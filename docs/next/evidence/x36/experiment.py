"""X36 real chat in one disposable profile, using only the worktree build."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import tomllib
import urllib.parse

workspace = Path(__file__).resolve().parents[4]
evidence = Path(__file__).parent
suffix = "-recommendation" if sys.argv[1:] else ""
sys.dont_write_bytecode = True
sys.path.insert(0, str(workspace / "scripts/next"))
from x23_vm import LabVM

name = "x36-tools-" + str(os.getpid())
root = Path.home() / "Library/Application Support/NipaPlay/LabProfiles" / name
assert not root.exists()
root.mkdir(mode=0o700)
home = root / "codex-home"
home.mkdir(mode=0o700)
original = Path.home() / ".codex"
# Configuration and auth are copied without printing their contents.
config = (original / "config.toml").read_text()
config = re.sub(r'(?m)^model\s*=.*$', 'model = "deepseek-v4.1-flash"', config, count=1)
parsed = tomllib.loads(config)
(home / "config.toml").write_text(config)
(home / "config.toml").chmod(0o600)
if (original / "auth.json").exists():
    shutil.copy2(original / "auth.json", home / "auth.json")
if (original / "skills").exists():
    (home / "skills").symlink_to(original / "skills", target_is_directory=True)
ca = root / "system-ca.pem"
shutil.copyfile("/etc/ssl/cert.pem", ca)
provider = parsed["model_providers"][parsed["model_provider"]]
host = urllib.parse.urlsplit(provider["base_url"]).hostname
env = dict(os.environ, NIPAPLAY_PROFILE=name, CODEX_HOME=str(home),
           CODEX_CA_CERTIFICATE=str(ca), SSL_CERT_FILE=str(ca),
           NIPAPLAY_ENDPOINT_FILE=str(root / "endpoint.json"),
           NO_PROXY=f"{host},127.0.0.1,localhost,::1", no_proxy=f"{host},127.0.0.1,localhost,::1")
env.pop("NIPAPLAY_LAB_QUIET", None)
preferences = {
    "flutter.labs_enable_agent_endpoint": True,
    "flutter.nipaplay_scanned_folders": [],
    "flutter.skip_danmaku_matching": True,
    "flutter.danmaku_auto_load_strategy": "disabled",
    "flutter.downloader_enabled": False,
    "flutter.downloader_auto_scan_completed_tasks": False,
    "flutter.web_server_auto_start": False,
    "flutter.remote_control_receiver_enabled": False,
    "flutter.auto_check_update": False,
}
(root / "preferences.json").write_text(json.dumps(preferences))
sys.path.insert(0, str(workspace / "assets/next/harness/tools"))
from public_http import sanitize
secrets = []


def collect(value):
    if isinstance(value, dict):
        for key, item in value.items():
            if re.search(r"secret|token|password|api_key|apikey|authorization", key, re.I) and isinstance(item, str) and item:
                secrets.append(item)
            else:
                collect(item)
    elif isinstance(value, list):
        for item in value:
            collect(item)


collect(parsed)
if (home / "auth.json").exists():
    collect(json.loads((home / "auth.json").read_text()))


def clean(value):
    text = json.dumps(sanitize(value), ensure_ascii=False)
    for secret in secrets:
        text = text.replace(secret, "[redacted]")
    # Private VM service URLs and externally supplied authenticated links are omitted.
    text = re.sub(r"http://127\.0\.0\.1:\d+/[^\s\"\\]+", "[private-vm-url]", text)
    text = re.sub(r"\bip=(?:\d{1,3}\.){3}\d{1,3}", "ip=[redacted]", text)
    return json.loads(text)


records = []


def record(label, value):
    safe = clean(value)
    records.append({"label": label, "value": safe})
    (evidence / f"operations{suffix}.json").write_text(json.dumps(records, ensure_ascii=False, indent=2))
    print(label, json.dumps(safe, ensure_ascii=False), flush=True)


def call(action, inputs=None, verb="call"):
    cmd = [sys.executable, str(root / "harness/nipa"), verb, action]
    if verb != "describe":
        cmd.append(json.dumps(inputs or {}, ensure_ascii=False))
    result = subprocess.run(cmd, cwd=root / "harness", env=env, capture_output=True, text=True, timeout=75)
    value = json.loads(result.stdout or result.stderr)
    record(verb + " " + action, value)
    return value


app = None
vm = None
log = root / "app.log"
try:
    executable = workspace / "build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay"
    with log.open("w") as stream:
        app = subprocess.Popen([str(executable)], cwd=workspace, env=env, stdout=stream, stderr=subprocess.STDOUT)
    deadline = time.monotonic() + 90
    while not (root / "endpoint.json").exists():
        if app.poll() is not None:
            raise RuntimeError("Lab app exited before endpoint startup")
        if time.monotonic() > deadline:
            raise TimeoutError("Lab endpoint startup")
        time.sleep(.3)
    collect(json.loads((root / "endpoint.json").read_text()))
    vm = LabVM(log)
    assert vm.rpc("getVM")["pid"] == app.pid
    record("instance", {"profile": name, "pid": app.pid, "executable": str(executable), "quiet": True})
    record("seed-tools", sorted(p.name for p in (root / "harness/tools").iterdir()))
    call("media.library.roots.add", {"paths": ["/Volumes/Anime/躲在超市后门抽烟的两人"]})
    initial = {p.name: p.read_bytes() for p in (root / "harness/tools").glob("*.py")}
    prompts = sys.argv[1:] or ["无职转生第三季最近更新到第几集了？", "给《躲在超市后门抽烟的两人》补上弹幕"]
    for index, text in enumerate(prompts, 1):
        thread = vm.chat("start")
        record(f"chat-{index}-thread", {"header": vm.chat("status")["header"]})
        record(f"chat-{index}-prompt", text)
        record(f"chat-{index}-turn", vm.chat("turn", text=text))
        deadline = time.monotonic() + 720
        last_report = time.monotonic()
        while True:
            status = vm.chat("status")
            live = status["liveness"]
            if live["status"] not in {"starting", "inProgress"}:
                break
            if time.monotonic() - last_report > 30:
                print(f"chat-{index} working", json.dumps({k: live.get(k) for k in ["status", "elapsedMs", "eventCount", "latestError"]}), flush=True)
                last_report = time.monotonic()
            if time.monotonic() > deadline:
                record(f"chat-{index}-observation-limit", live)
                vm.chat("interrupt")
                break
            time.sleep(1)
        record(f"chat-{index}-status", {"header": status["header"], "liveness": live})
        thread_id = status["header"]["threadId"]
        history = vm.chat("read", threadId=thread_id)
        record(f"chat-{index}-history", history)
        call("chat.turn.process", {"threadId": thread_id, "turnId": live["turnId"]})
        changed = [p.name for p in (root / "harness/tools").glob("*.py") if initial.get(p.name) != p.read_bytes()]
        record(f"chat-{index}-tool-changes", changed)
        for filename in changed:
            value = clean((root / "harness/tools" / filename).read_text())
            (evidence / f"agent{suffix}-{index}-{filename}.txt").write_text(value)
    call("danmaku.tracks", verb="query")
    record("harness-git", subprocess.run(["git", "status", "--short"], cwd=root / "harness", capture_output=True, text=True).stdout)
except Exception as exc:
    record("experiment-error", {"type": type(exc).__name__, "message": str(exc)})
    raise
finally:
    if vm is not None:
        try:
            record("chat-close", vm.chat("close"))
        except Exception as exc:
            record("chat-close-error", type(exc).__name__)
    if app is not None and app.poll() is None:
        app.terminate()
        try:
            app.wait(timeout=15)
        except subprocess.TimeoutExpired:
            app.kill()
            app.wait()
    # Store a redacted log only after the process is stopped.
    if log.exists():
        (evidence / f"app-log{suffix}.txt").write_text(clean(log.read_text(errors="replace")))
    shutil.rmtree(root)
    record("cleanup", {"profileRemoved": not root.exists(), "appExited": app is None or app.poll() is not None})
