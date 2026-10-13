"""Fetch only public documentation; no provider or credential requests."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from hashlib import sha256
from html.parser import HTMLParser
import json
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.parse import quote

ROOT = Path(__file__).resolve().parent
URLS = {
    "deepseek-first-call": "https://api-docs.deepseek.com/",
    "deepseek-anthropic": "https://api-docs.deepseek.com/guides/anthropic_api/",
    "deepseek-claude": "https://api-docs.deepseek.com/quick_start/agent_integrations/claude_code/",
    "deepseek-codex": "https://api-docs.deepseek.com/quick_start/agent_integrations/codex/",
    "deepseek-pricing": "https://api-docs.deepseek.com/quick_start/pricing/",
    "deepseek-thinking": "https://api-docs.deepseek.com/guides/thinking_mode/",
    "deepseek-caching": "https://api-docs.deepseek.com/guides/kv_cache/",
    "deepseek-flash-release": "https://api-docs.deepseek.com/news/news260910/",
    "bigmodel-index": "https://docs.bigmodel.cn/llms.txt",
    "bigmodel-claude": "https://docs.bigmodel.cn/cn/guide/develop/claude/introduction.md",
    "bigmodel-claude-code": "https://docs.bigmodel.cn/cn/coding-plan/tool/claude.md",
    "zai-index": "https://docs.z.ai/llms.txt",
    "zai-claude-code": "https://docs.z.ai/devpack/tool/claude.md",
    "glm-flash-model-card": "https://huggingface.co/zai-org/GLM-5.3-Flash/raw/main/README.md",
    "bigmodel-responses": "https://docs.bigmodel.cn/cn/guide/develop/responses/introduction.md",
    "bigmodel-flash": "https://docs.bigmodel.cn/cn/guide/models/vlm/glm-5.3-flash.md",
    "bigmodel-cache": "https://docs.bigmodel.cn/cn/guide/capabilities/cache.md",
    "bigmodel-models": "https://docs.bigmodel.cn/cn/guide/start/model-overview.md",
    "zai-flash": "https://docs.z.ai/guides/vlm/glm-5.3-flash.md",
    "zai-cache": "https://docs.z.ai/guides/capabilities/cache.md",
    "deepseek-response-api": "https://api-docs.deepseek.com/api/create-response/",
    "deepseek-responses-guide": "https://api-docs.deepseek.com/guides/responses_api/",
    "bigmodel-response-schema": "https://docs.bigmodel.cn/api-reference/response/创建-response.md",
    "bigmodel-response-openapi": "https://docs.bigmodel.cn/openapi/openapi-responses.json",
    "openclaw-session-control": "https://docs.openclaw.ai/gateway/protocol/rpc-session-control.md",
}


class ReadableHTML(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []
        self.hidden = 0

    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style"):
            self.hidden += 1
        if tag in ("p", "div", "tr", "li", "h1", "h2", "h3", "pre", "br"):
            self.parts.append("\n")

    def handle_endtag(self, tag):
        if tag in ("script", "style") and self.hidden:
            self.hidden -= 1
        if tag in ("p", "div", "tr", "li", "h1", "h2", "h3", "pre"):
            self.parts.append("\n")

    def handle_data(self, data):
        if not self.hidden:
            self.parts.append(data)


def fetch(pair):
    label, url = pair
    try:
        request = Request(quote(url, safe=":/?=&%"), headers={"User-Agent": "NipaPlay-X59-Research"})
        with urlopen(request, timeout=40) as response:
            data = response.read()
            resolved = response.url
            kind = response.headers.get("content-type", "")
        text = data.decode("utf-8")
        if "text/html" in kind:
            parser = ReadableHTML()
            parser.feed(text)
            text = "\n".join(line.strip() for line in "".join(parser.parts).splitlines() if line.strip())
        path = ROOT / "official" / (label + ".md")
        path.write_text(text)
        return {"id": label, "url": url, "resolvedUrl": resolved,
                "contentType": kind, "sha256Response": sha256(data).hexdigest(),
                "sha256Evidence": sha256(path.read_bytes()).hexdigest(),
                "retrievedAt": datetime.now(timezone.utc).isoformat(), "bytes": len(data)}
    except Exception as error:
        return {"id": label, "url": url, "error": str(error)}


if __name__ == "__main__":
    import sys
    selected = URLS if len(sys.argv) == 1 else {key: URLS[key] for key in sys.argv[1:]}
    with ThreadPoolExecutor(max_workers=5) as executor:
        results = list(executor.map(fetch, selected.items()))
    manifest = ROOT / "sources-models.json"
    previous = json.loads(manifest.read_text()) if manifest.exists() else []
    merged = {row["id"]: row for row in previous}
    merged.update({row["id"]: row for row in results})
    manifest.write_text(json.dumps(list(merged.values()), indent=2, ensure_ascii=False))
    for row in results:
        print(row["id"], row.get("bytes", row.get("error")))
