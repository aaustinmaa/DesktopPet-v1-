"""Exercise app replacement with fake build/sign tools, without touching real outputs."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/build.sh"


@unittest.skipUnless(os.uname().sysname == "Darwin", "Mac build script")
class BuildReplacementTests(unittest.TestCase):
    def run_build(self, fail_signing, with_claude=False):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            mac = root / "Mac"
            tools = root / "tools"
            tools.mkdir()
            for name in ["scripts", "Support", "output/arm64/SuWuDu.app", ".build/artifacts/mock/macos/Sparkle.framework", "bin/SuWuDuMac_SuWuDu.bundle"]:
                (mac / name).mkdir(parents=True)
            shutil.copyfile(SCRIPT, mac / "scripts/build.sh")
            for name in ["Sprites", "Sounds"]:
                (root / "Assets" / name).mkdir(parents=True)
            (root / "OPENAI-CODEX-LICENSE.txt").write_text("license")
            for name in ["Info.plist", "ThirdPartyNotices.txt", "AppIcon.png"]:
                (mac / "Support" / name).write_text("fixture")
            (mac / "bin/SuWuDu").write_text("new executable")
            if with_claude:
                runtime = mac / "runtime/claude/arm64"
                runtime.mkdir(parents=True)
                (runtime / "claude").write_text("original Anthropic-signed executable")
                (runtime / "runtime-manifest.json").write_text("fixture manifest")
            old = mac / "output/arm64/SuWuDu.app/old-marker"
            old.write_text("working previous app")
            commands = {
                "uname": 'if [ "$1" = -s ]; then echo Darwin; else echo arm64; fi',
                "xcrun": "exit 0",
                "swift": 'case " $* " in *" --show-bin-path "*) echo "$FAKE_MAC/bin";; esac',
                "sips": "exit 0",
                "iconutil": "exit 0",
                "ditto": 'cp -R "$1" "$2"',
                "codesign": "exit 1" if fail_signing else "exit 0",
            }
            if with_claude:
                commands["python3"] = 'echo "$*" >> "$FAKE_MAC/runtime-checks"'
                commands["file"] = 'echo "Mach-O 64-bit executable arm64"'
                commands["codesign"] = 'echo "$*" >> "$FAKE_MAC/signing-commands"'
            for name, body in commands.items():
                path = tools / name
                path.write_text("#!/bin/sh\n" + body + "\n")
                path.chmod(0o755)
            env = {key: value for key, value in os.environ.items() if key not in ["NOTARY_PROFILE", "SIGNING_IDENTITY", "UPDATE_FEED_URL", "UPDATE_PUBLIC_KEY", "SDKROOT"]}
            env.update(PATH=str(tools) + os.pathsep + env["PATH"], FAKE_MAC=str(mac))
            args = ["bash", str(mac / "scripts/build.sh"), "--without-codex"]
            if not with_claude:
                args.append("--without-claude")
            result = subprocess.run(args, env=env, capture_output=True, text=True)
            if fail_signing:
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(old.read_text(), "working previous app")
            else:
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(old.exists())
                self.assertEqual((old.parent / "Contents/MacOS/SuWuDu").read_text(), "new executable")
                if with_claude:
                    self.assertEqual((old.parent / "Contents/Helpers/Claude/claude").read_text(), "original Anthropic-signed executable")
                    self.assertNotIn("Contents/Helpers/Claude/claude", (mac / "signing-commands").read_text())
                    checks = (mac / "runtime-checks").read_text().splitlines()
                    self.assertEqual(len(checks), 2)
                    self.assertEqual(checks[0], "scripts/fetch-claude-runtime.py --arch arm64")
                    self.assertIn("--verify-only ", checks[1])
                    self.assertTrue(checks[1].endswith("/Contents/Helpers/Claude/claude"))
            self.assertEqual(list((mac / "output/arm64").glob(".dev-build.*")), [])

    def test_signing_failure_keeps_previous_app(self):
        self.run_build(True)

    def test_success_replaces_app_after_verification(self):
        self.run_build(False)

    def test_claude_keeps_original_signature_and_is_verified_after_app_signing(self):
        self.run_build(False, with_claude=True)


if __name__ == "__main__":
    unittest.main()
