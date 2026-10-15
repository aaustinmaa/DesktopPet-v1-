#!/usr/bin/env python3
"""Fetch the pinned, unmodified official Claude Code macOS executable."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
VERSION = "2.1.300"  # Supports disabling automatic @file expansion (requires 2.1.299+).
BASE_URL = "https://downloads.claude.ai/claude-code-releases"
PLATFORMS = {
    "arm64": ("darwin-arm64", "475517caa611e3318a2f298fa071287ec98955538df78c58f709ecc01e5ae2d3", 249556880),
    "x86_64": ("darwin-x64", "5824fc36863e70bbd070491bb9359e217d3f17b38c45697c085b31a3a67356b3", 259416272),
}
SIGNING_REQUIREMENT = ('anchor apple generic and certificate leaf[subject.OU] = "Q6L2SF6YDW" '
                       'and identifier "com.anthropic.claude-code"')


def request(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers={
        "User-Agent": "SuWuDu-Mac-build",
    }), timeout=120)


def fetch_manifest():
    with request(f"{BASE_URL}/{VERSION}/manifest.json") as response:
        data = response.read(1024 * 1024 + 1)
    if len(data) > 1024 * 1024:
        raise RuntimeError("Claude release manifest is unexpectedly large")
    return json.loads(data)


def validate_manifest(manifest, arch):
    platform, digest, size = PLATFORMS[arch]
    entry = manifest.get("platforms", {}).get(platform, {})
    if (manifest.get("version") != VERSION or entry.get("binary") != "claude"
            or entry.get("checksum") != digest or entry.get("size") != size):
        raise RuntimeError(f"Official manifest changed for pinned Claude {VERSION} {platform}")


def download(destination, arch):
    platform, _, size = PLATFORMS[arch]
    received = 0
    with request(f"{BASE_URL}/{VERSION}/{platform}/claude") as response, destination.open("wb") as output:
        while chunk := response.read(1024 * 1024):
            received += len(chunk)
            if received > size:
                raise RuntimeError("Claude download exceeds the pinned binary size")
            output.write(chunk)
    if received != size:
        raise RuntimeError("Claude download is incomplete")
    destination.chmod(0o755)


def verify_binary(binary, arch):
    _, digest, size = PLATFORMS[arch]
    if binary.is_symlink() or not binary.is_file() or binary.stat().st_size != size:
        raise RuntimeError("Claude runtime is missing or has an unexpected size")
    checksum = hashlib.sha256()
    with binary.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            checksum.update(chunk)
    if checksum.hexdigest() != digest:
        raise RuntimeError("Claude runtime SHA-256 does not match the pinned official binary")
    # Never replace Anthropic's signature with the application's signature.
    subprocess.run(["/usr/bin/codesign", "--verify", "--strict", "-R=" + SIGNING_REQUIREMENT,
                    str(binary)], check=True, capture_output=True, text=True)


def ensure_runtime(arch):
    platform, digest, _ = PLATFORMS[arch]
    output = ROOT / "runtime" / "claude" / arch
    binary = output / "claude"
    manifest = {
        "version": VERSION,
        "target": platform,
        "source": f"{BASE_URL}/{VERSION}/{platform}/claude",
        "signingTeam": "Q6L2SF6YDW",
        "files": {"claude": digest},
    }
    # The pinned digest, rather than editable cache metadata, is the trust anchor.
    if binary.exists():
        try:
            verify_binary(binary, arch)
        except (RuntimeError, OSError, subprocess.CalledProcessError):
            pass
        else:
            binary.chmod(0o755)
            (output / "runtime-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
            print(f"Verified cached Claude Code {VERSION}: {output}")
            return
    validate_manifest(fetch_manifest(), arch)
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="fetch-", dir=output) as temporary:
        staging = Path(temporary)
        download(staging / "claude", arch)
        verify_binary(staging / "claude", arch)
        (staging / "runtime-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        # Keep any previous runtime until the whole replacement has been verified.
        os.replace(staging / "claude", binary)
        os.replace(staging / "runtime-manifest.json", output / "runtime-manifest.json")
    print(f"Verified Claude Code {VERSION} for {platform}: {output}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--arch", choices=sorted(PLATFORMS), required=True)
    parser.add_argument("--verify-only", type=Path, help="Verify a copied bundle binary without downloading or changing it")
    args = parser.parse_args()
    if args.verify_only:
        verify_binary(args.verify_only, args.arch)
        print(f"Verified original Claude Code {VERSION} signature and bytes: {args.verify_only}")
    else:
        ensure_runtime(args.arch)


if __name__ == "__main__":
    main()
