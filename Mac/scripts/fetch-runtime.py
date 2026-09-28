#!/usr/bin/env python3
"""Fetch only pinned official Darwin binaries, checking GitHub's SHA-256 digest."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
VERSION = "0.144.4"  # Matches the Windows integration's pinned protocol generation.
ARCHIVE_HASHES = {
    "codex-aarch64-apple-darwin.tar.gz": "77c8969a481302f9db1d9ea2a6c21c083abae3f1a8fc8a7275dc38323699391e",
    "codex-code-mode-host-aarch64-apple-darwin.tar.gz": "a3429ba6a6d65a4ca6f32c292d35f0da067651fc0f8333dcfa42a7c3b6b5d7d9",
    "codex-x86_64-apple-darwin.tar.gz": "274ea4931246621d477ad61d61ea3303527878e77fa910087df52153f5e6188e",
    "codex-code-mode-host-x86_64-apple-darwin.tar.gz": "4b49e838ab1d66dd4fecfc803411a6b635225ba4bf8fe2648d3151385512980d",
}


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "SuWuDu-Mac-build", "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


def unpack_binary(archive, destination, basename):
    with tarfile.open(archive, "r:gz") as bundle:
        candidates = [m for m in bundle.getmembers() if m.isfile() and
                      (Path(m.name).name == basename or Path(m.name).name.startswith(basename + "-"))]
        if len(candidates) != 1:
            raise RuntimeError(f"Expected one {basename} executable in {archive.name}, found {len(candidates)}")
        # Extract just the selected regular file; never trust archive paths or symlinks.
        with bundle.extractfile(candidates[0]) as source, destination.open("wb") as output:
            shutil.copyfileobj(source, output)
        destination.chmod(0o755)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--arch", choices=["arm64", "x86_64"], required=True)
    args = parser.parse_args()
    target = "aarch64-apple-darwin" if args.arch == "arm64" else "x86_64-apple-darwin"
    output = ROOT / "runtime" / args.arch
    cached_path = output / "runtime-manifest.json"
    if cached_path.exists():
        cached = json.loads(cached_path.read_text(encoding="utf-8"))
        if cached.get("version") == VERSION and cached.get("target") == target and set(cached.get("files", {})) == {"codex", "codex-code-mode-host"}:
            if all((output / name).is_file() and hashlib.sha256((output / name).read_bytes()).hexdigest() == digest for name, digest in cached["files"].items()):
                # Windows copies/ZIP tools can discard Unix modes without changing bytes.
                for name in cached["files"]:
                    (output / name).chmod(0o755)
                print(f"Verified cached Codex {VERSION}: {output}")
                return
    release = json.loads(fetch(f"https://api.github.com/repos/openai/codex/releases/tags/rust-v{VERSION}"))
    if release.get("tag_name") != f"rust-v{VERSION}" or release.get("draft"):
        raise RuntimeError("Unexpected Codex release metadata")
    assets = {asset["name"]: asset for asset in release["assets"]}
    output.mkdir(parents=True, exist_ok=True)
    manifest = {"version": VERSION, "target": target, "files": {}}
    with tempfile.TemporaryDirectory(prefix="fetch-", dir=output) as temporary:
        staging = Path(temporary)
        for binary in ["codex", "codex-code-mode-host"]:
            name = f"{binary}-{target}.tar.gz"
            asset = assets.get(name)
            if not asset:
                raise RuntimeError(f"Official release is missing {name}; refusing an incomplete runtime")
            digest = asset.get("digest", "")
            if not digest.startswith("sha256:") or len(digest) != 71:
                raise RuntimeError(f"No SHA-256 digest published for {name}; refusing an unverified runtime")
            if digest[7:] != ARCHIVE_HASHES[name]:
                raise RuntimeError(f"Published digest changed for pinned asset {name}")
            url = asset["browser_download_url"]
            if not url.startswith(f"https://github.com/openai/codex/releases/download/rust-v{VERSION}/"):
                raise RuntimeError("Unexpected download host or release path")
            data = fetch(url)
            if hashlib.sha256(data).hexdigest() != digest[7:]:
                raise RuntimeError(f"SHA-256 mismatch: {name}")
            archive = staging / name
            archive.write_bytes(data)
            unpack_binary(archive, staging / binary, binary)
            manifest["files"][binary] = hashlib.sha256((staging / binary).read_bytes()).hexdigest()
        # Commit only after every required binary has been verified.
        for binary in manifest["files"]:
            os.replace(staging / binary, output / binary)
        (output / "runtime-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Verified Codex {VERSION} for {target}: {output}")


if __name__ == "__main__":
    main()
