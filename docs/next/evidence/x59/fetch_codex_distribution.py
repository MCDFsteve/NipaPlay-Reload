"""Inspect public release metadata and archive headers; never install or run assets."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from hashlib import sha256
import json
from pathlib import Path
import re
import tarfile
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent
VERSION = "0.144.1"
TAG = "rust-v" + VERSION
HEADERS = {"User-Agent": "NipaPlay-X59-Research"}


def read_public(url):
    with urlopen(Request(url, headers=HEADERS), timeout=40) as response:
        return response.read()


def save_public(label, url):
    body = read_public(url)
    path = ROOT / "distribution" / label
    path.write_bytes(body)
    return {"path": str(path.relative_to(ROOT)), "url": url,
            "sha256": sha256(body).hexdigest(), "bytes": len(body)}


def route_meta(route):
    suffix, target = route
    url = "https://registry.npmjs.org/@openai/codex/" + VERSION + "-" + suffix
    raw = read_public(url)
    meta = json.loads(raw)
    tarball = meta["dist"]["tarball"]
    with urlopen(Request(tarball, headers=HEADERS, method="HEAD"), timeout=40) as response:
        length = response.headers.get("Content-Length")
    if length is not None:
        compressed = int(length)
    else:
        # Some proxy/CDN responses use chunked transfer even for HEAD.
        # Count public compressed bytes without writing the package to disk.
        compressed = 0
        with urlopen(Request(tarball, headers=HEADERS), timeout=40) as response:
            while chunk := response.read(1024 * 1024):
                compressed += len(chunk)
    artifact_name = "codex-" + target + (".exe" if "windows" in target else ".tar.gz")
    asset = ASSETS[artifact_name]
    binary_size = asset["size"] if "windows" in target else None
    header_members = []
    if binary_size is None:
        # Only read enough compressed bytes for tar headers. No binary is saved,
        # executed, installed, or claimed to have a verified archive digest.
        with urlopen(Request(asset["browser_download_url"], headers=HEADERS), timeout=40) as response:
            with tarfile.open(fileobj=response, mode="r|gz") as archive:
                for member in archive:
                    header_members.append({"name": member.name, "bytes": member.size})
                    if member.isfile() and Path(member.name).name in ("codex", "codex-" + target):
                        binary_size = member.size
                        break
                    if len(header_members) > 10:
                        raise ValueError("No Codex binary in initial archive headers")
    row = {"platformPackage": "@openai/codex@" + meta["version"],
           "target": target, "npmMetadataUrl": url, "npmTarballUrl": tarball,
           "npmUnpackedBytes": meta["dist"]["unpackedSize"],
           "npmCompressedBytes": compressed, "npmFileCount": meta["dist"]["fileCount"],
           "npmIntegrity": meta["dist"]["integrity"],
           "binaryBytes": binary_size,
           "releaseBinaryUrl": asset["browser_download_url"],
           "releaseAssetBytes": asset["size"], "releasePublishedDigest": asset.get("digest"),
           "archiveHeaderMembers": header_members,
           "archiveDigestVerified": False}
    (ROOT / "distribution" / (suffix + ".json")).write_bytes(raw)
    return row


if __name__ == "__main__":
    (ROOT / "distribution").mkdir(exist_ok=True)
    release_url = "https://api.github.com/repos/openai/codex/releases/tags/" + TAG
    release_raw = read_public(release_url)
    release = json.loads(release_raw)
    ASSETS = {a["name"]: a for a in release["assets"]}
    (ROOT / "distribution" / "release.json").write_bytes(release_raw)
    sources = []
    for label, relative in [
        ("LICENSE", "LICENSE"), ("NOTICE", "NOTICE"),
        ("cli-main.rs", "codex-rs/cli/src/main.rs"),
        ("config.schema.json", "codex-rs/core/config.schema.json"),
    ]:
        sources.append(save_public(label, "https://raw.githubusercontent.com/openai/codex/" + TAG + "/" + relative))
    routes = [
        ("darwin-arm64", "aarch64-apple-darwin"),
        ("darwin-x64", "x86_64-apple-darwin"),
        ("linux-x64", "x86_64-unknown-linux-musl"),
        ("win32-x64", "x86_64-pc-windows-msvc"),
    ]
    with ThreadPoolExecutor(max_workers=4) as pool:
        rows = list(pool.map(route_meta, routes))
    local = Path("/opt/homebrew/lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-arm64/vendor")
    local_files = [{"path": str(p.relative_to(local)), "bytes": p.stat().st_size}
                   for p in sorted(local.rglob("*")) if p.is_file()]
    report = {"retrievedAt": datetime.now(timezone.utc).isoformat(), "version": VERSION,
              "tag": TAG, "releaseUrl": release["html_url"],
              "releaseMetadataUrl": release_url, "releasePublishedAt": release["published_at"],
              "releaseMetadataSha256": sha256(release_raw).hexdigest(),
              "sources": sources, "platforms": rows,
              "localMacVendorFiles": local_files,
              "localMacVendorTotalBytes": sum(p["bytes"] for p in local_files),
              "executedDownloadedBinaries": 0, "modelCalls": 0,
              "sizeCaveat": "Compressed npm payload and unpacked platform package are actual sizes; final NipaPlay installer delta requires a later packaging build."}
    (ROOT / "codex-distribution.json").write_text(json.dumps(report, indent=2, ensure_ascii=False))
    for row in rows:
        print(row["target"], "binary", row["binaryBytes"], "native-package", row["npmUnpackedBytes"], "compressed", row["npmCompressedBytes"])
