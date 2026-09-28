"""Offline tests for the Mac runtime archive extraction boundary."""
import importlib.util
import io
import hashlib
import json
import os
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("fetch_runtime", ROOT / "scripts/fetch-runtime.py")
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        (ROOT / ".build").mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(dir=ROOT / ".build")
        self.directory = Path(self.temporary.name)

    def tearDown(self):
        self.temporary.cleanup()

    def archive(self, members):
        path = self.directory / "runtime.tar.gz"
        with tarfile.open(path, "w:gz") as bundle:
            for name, kind in members:
                entry = tarfile.TarInfo(name)
                if kind == "symlink":
                    entry.type = tarfile.SYMTYPE
                    entry.linkname = "../../outside"
                    bundle.addfile(entry)
                else:
                    entry.size = 4
                    bundle.addfile(entry, io.BytesIO(b"test"))
        return path

    def test_archive_path_cannot_escape_destination(self):
        archive = self.archive([("../../codex", "file")])
        destination = self.directory / "codex"
        runtime.unpack_binary(archive, destination, "codex")
        self.assertEqual(destination.read_bytes(), b"test")
        self.assertEqual(sorted(p.name for p in self.directory.iterdir()), ["codex", "runtime.tar.gz"])

    def test_symlink_is_never_extracted(self):
        archive = self.archive([("codex", "symlink")])
        with self.assertRaises(RuntimeError):
            runtime.unpack_binary(archive, self.directory / "codex", "codex")
        self.assertFalse((self.directory / "codex").exists())

    def test_ambiguous_archive_is_rejected(self):
        archive = self.archive([("codex", "file"), ("codex-other", "file")])
        with self.assertRaises(RuntimeError):
            runtime.unpack_binary(archive, self.directory / "codex", "codex")

    def test_both_architectures_have_pinned_hashes(self):
        for target in ["aarch64-apple-darwin", "x86_64-apple-darwin"]:
            for binary in ["codex", "codex-code-mode-host"]:
                digest = runtime.ARCHIVE_HASHES[f"{binary}-{target}.tar.gz"]
                self.assertEqual(len(bytes.fromhex(digest)), 32)

    @unittest.skipIf(os.name == "nt", "Unix executable permissions")
    def test_verified_windows_cache_restores_executable_permissions(self):
        output = self.directory / "runtime" / "arm64"
        output.mkdir(parents=True)
        hashes = {}
        for name in ["codex", "codex-code-mode-host"]:
            binary = output / name
            binary.write_bytes(b"cached binary")
            binary.chmod(0o644)
            hashes[name] = hashlib.sha256(binary.read_bytes()).hexdigest()
        (output / "runtime-manifest.json").write_text(json.dumps({
            "version": runtime.VERSION, "target": "aarch64-apple-darwin", "files": hashes
        }))
        with patch.object(runtime, "ROOT", self.directory), patch("sys.argv", ["fetch-runtime.py", "--arch", "arm64"]), patch.object(runtime, "fetch") as fetch:
            runtime.main()
            fetch.assert_not_called()
        for name in hashes:
            self.assertEqual((output / name).stat().st_mode & 0o777, 0o755)
            self.assertEqual(hashlib.sha256((output / name).read_bytes()).hexdigest(), hashes[name])


if __name__ == "__main__":
    unittest.main()
