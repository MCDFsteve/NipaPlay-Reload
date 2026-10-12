"""Boundary checks for public acquisition, with a disposable loopback fixture."""
import http.server
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading

workspace = Path(__file__).resolve().parents[4]
sys.dont_write_bytecode = True
sys.path.insert(0, str(workspace / "assets/next/harness/tools"))
import public_http
import mikan
import discovery
import danmaku

checks = []


def rejects(label, fn):
    try:
        fn()
    except (ValueError, RuntimeError):
        checks.append(label)
    else:
        raise AssertionError(label)


for value in ["https://user:example@provider.invalid/", "https://provider.invalid/?passkey=example", "file:///tmp/file", "http://remote.invalid/"]:
    rejects("public URL boundary", lambda: public_http.public_url(value))
rejects("redirect host boundary", lambda: public_http.public_url("https://other.invalid/", {"provider.invalid"}))
for parser in [mikan.parse_rss, discovery.parse_nyaa_rss, discovery.parse_at_rss]:
    rejects("challenge is a failure", lambda: parser("<html>challenge</html>", "https://example.invalid/"))
    rejects("XML declarations rejected", lambda: parser("<!DOCTYPE rss><rss><channel/></rss>", "https://example.invalid/"))
rejects("mismatched torrent identity", lambda: mikan.release("Title", "/Home/Episode/" + "a"*40, "/Download/20261012/" + "b"*40 + ".torrent"))
safe = public_http.sanitize({"https://example.invalid/?passkey=one": 1, "https://example.invalid/?passkey=two": 2, "token": "example"})
assert len(safe) == 3 and list(safe.values()) == [1, 2, "[redacted]"]
checks.append("redaction preserves multiple entries")


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.endswith("format=xml"):
            body = '<i><d p="1.25,1,25,16777215,0,0,0,0">hello &amp; world</d></i>'.encode()
        else:
            body = json.dumps({"animes": [{"animeId": 7, "animeTitle": "fixture"}]}).encode()
        self.send_response(200)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
base = f"http://127.0.0.1:{server.server_port}/prefix"
try:
    assert "/prefix/api/" in danmaku.api_url(base, "api/v2/bangumi/7")
    with tempfile.TemporaryDirectory() as temp:
        path = Path(temp) / "episode.xml"
        result = danmaku.main(["fetch", "9", "--base", base, "--out", str(path)])
        assert result["comments"] == 1 and danmaku.xml_comments(path.read_bytes()) == 1
        original = path.read_bytes()
        try:
            danmaku.main(["fetch", "9", "--base", base, "--out", str(path)])
        except FileExistsError:
            assert path.read_bytes() == original
        else:
            raise AssertionError("Existing evidence was overwritten")
        checks.extend(["XML exact bytes and comment count", "existing output preserved", "base path prefix preserved"])
    for tool in ["mikan", "discovery", "api", "danmaku"]:
        result = subprocess.run([sys.executable, "-B", str(workspace / f"assets/next/harness/tools/{tool}.py"), "--help"], capture_output=True)
        assert result.returncode == 0
    checks.append("four directly runnable CLIs")
finally:
    server.shutdown()
    server.server_close()
value = {"checks": len(checks), "passed": checks, "thirdPartyDependencies": 0}
(Path(__file__).parent / "verification.json").write_text(json.dumps(value, ensure_ascii=False, indent=2))
print(json.dumps(value, ensure_ascii=False))
