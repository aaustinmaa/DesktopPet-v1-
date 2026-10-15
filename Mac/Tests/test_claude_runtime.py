"""Offline checks for pinned Claude downloads and preservation of vendor signing."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("fetch_claude_runtime", ROOT / "scripts/fetch-claude-runtime.py")
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class ClaudeRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.binary = b"official signed binary fixture"
        self.digest = hashlib.sha256(self.binary).hexdigest()
        self.platforms = {"arm64": ("darwin-arm64", self.digest, len(self.binary))}
        self.output = self.root / "runtime/claude/arm64"
        self.output.mkdir(parents=True)
        self.manifest = {"version": runtime.VERSION, "platforms": {"darwin-arm64": {
            "binary": "claude", "checksum": self.digest, "size": len(self.binary),
        }}}

    def tearDown(self):
        self.temporary.cleanup()

    def test_both_architectures_have_pinned_official_hashes(self):
        self.assertGreaterEqual(tuple(map(int, runtime.VERSION.split("."))), (2, 1, 299))
        self.assertEqual(set(runtime.PLATFORMS), {"arm64", "x86_64"})
        for platform, digest, size in runtime.PLATFORMS.values():
            self.assertTrue(platform.startswith("darwin-"))
            self.assertEqual(len(bytes.fromhex(digest)), 32)
            self.assertGreater(size, 100_000_000)

    def test_manifest_must_match_pinned_version_hash_size_and_filename(self):
        with patch.object(runtime, "PLATFORMS", self.platforms):
            runtime.validate_manifest(self.manifest, "arm64")
            for key, value in [("binary", "other"), ("checksum", "0" * 64), ("size", 1)]:
                changed = json.loads(json.dumps(self.manifest))
                changed["platforms"]["darwin-arm64"][key] = value
                with self.assertRaises(RuntimeError):
                    runtime.validate_manifest(changed, "arm64")
            with self.assertRaises(RuntimeError):
                runtime.validate_manifest(dict(self.manifest, version="future"), "arm64")

    def test_verified_cache_uses_pinned_hash_and_restores_executable_mode(self):
        binary = self.output / "claude"
        binary.write_bytes(self.binary)
        binary.chmod(0o644)
        with patch.object(runtime, "ROOT", self.root), patch.object(runtime, "PLATFORMS", self.platforms), \
                patch.object(runtime, "fetch_manifest") as fetch, patch.object(runtime.subprocess, "run") as verify:
            runtime.ensure_runtime("arm64")
            fetch.assert_not_called()
            verify.assert_called_once_with([
                "/usr/bin/codesign", "--verify", "--strict", "-R=" + runtime.SIGNING_REQUIREMENT,
                str(binary),
            ], check=True, capture_output=True, text=True)
        self.assertEqual(binary.stat().st_mode & 0o777, 0o755)
        self.assertEqual(binary.read_bytes(), self.binary)
        self.assertEqual(json.loads((self.output / "runtime-manifest.json").read_text())["files"], {"claude": self.digest})

    def test_forged_cache_manifest_cannot_authorize_changed_bytes(self):
        changed = b"x" * len(self.binary)
        (self.output / "claude").write_bytes(changed)
        (self.output / "runtime-manifest.json").write_text(json.dumps({
            "version": runtime.VERSION, "files": {"claude": hashlib.sha256(changed).hexdigest()},
        }))
        with patch.object(runtime, "ROOT", self.root), patch.object(runtime, "PLATFORMS", self.platforms), \
                patch.object(runtime, "fetch_manifest", side_effect=OSError("offline")) as fetch, \
                patch.object(runtime.subprocess, "run") as verify:
            with self.assertRaises(OSError):
                runtime.ensure_runtime("arm64")
            fetch.assert_called_once()
            verify.assert_not_called()
        self.assertEqual((self.output / "claude").read_bytes(), changed)

    def test_download_is_committed_only_after_checksum_and_signature_succeed(self):
        with patch.object(runtime, "ROOT", self.root), patch.object(runtime, "PLATFORMS", self.platforms), \
                patch.object(runtime, "fetch_manifest", return_value=self.manifest), \
                patch.object(runtime, "request", return_value=io.BytesIO(self.binary)), \
                patch.object(runtime.subprocess, "run") as verify:
            runtime.ensure_runtime("arm64")
            verify.assert_called_once()
        self.assertEqual((self.output / "claude").read_bytes(), self.binary)
        self.assertEqual(sorted(p.name for p in self.output.iterdir()), ["claude", "runtime-manifest.json"])

    def test_failed_download_or_signature_preserves_previous_runtime(self):
        previous = b"previous runtime"
        (self.output / "claude").write_bytes(previous)
        for data, signature_error in [(b"x" * len(self.binary), None),
                                      (self.binary, subprocess.CalledProcessError(1, "codesign"))]:
            with self.subTest(signature_error=signature_error), patch.object(runtime, "ROOT", self.root), \
                    patch.object(runtime, "PLATFORMS", self.platforms), \
                    patch.object(runtime, "fetch_manifest", return_value=self.manifest), \
                    patch.object(runtime, "request", return_value=io.BytesIO(data)), \
                    patch.object(runtime.subprocess, "run", side_effect=signature_error):
                with self.assertRaises((RuntimeError, subprocess.CalledProcessError)):
                    runtime.ensure_runtime("arm64")
                self.assertEqual((self.output / "claude").read_bytes(), previous)
                self.assertEqual(list(self.output.glob("fetch-*")), [])

    def test_truncated_and_oversized_downloads_are_rejected(self):
        for data in [self.binary[:-1], self.binary + b"extra"]:
            with patch.object(runtime, "PLATFORMS", self.platforms), \
                    patch.object(runtime, "request", return_value=io.BytesIO(data)):
                with self.assertRaises(RuntimeError):
                    runtime.download(self.output / "partial", "arm64")

    def test_symlinks_are_rejected_even_when_target_has_pinned_bytes(self):
        target = self.root / "elsewhere"
        target.write_bytes(self.binary)
        binary = self.output / "claude"
        binary.symlink_to(target)
        with patch.object(runtime, "PLATFORMS", self.platforms), patch.object(runtime.subprocess, "run") as verify:
            with self.assertRaises(RuntimeError):
                runtime.verify_binary(binary, "arm64")
            verify.assert_not_called()


if __name__ == "__main__":
    unittest.main()
