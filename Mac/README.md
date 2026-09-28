# 苏无度 · 沈青 for macOS

Native Swift/AppKit/SwiftUI implementation, targeting **macOS 14+**. The Windows
application and Windows installers are independent and are not changed by this
project. Both implementations use the repository's existing PNG sprites and WAV
recordings; Mac builds copy only runtime assets.

## Build and use on your MacBook

1. Copy or clone the **whole repository** onto the Mac. `Mac/` alone does not
   contain the shared artwork and sounds.
2. Install Xcode 16 or later, or compatible Command Line Tools with Swift 6 and
   Swift Testing, and ensure `xcode-select -p` points to the intended developer
   directory. Python 3 and internet access are needed for the initial
   runtime/dependency download.
3. From Terminal, in the repository's `Mac` directory:

   ```bash
   bash scripts/build.sh --dmg
   ```

   Alternatively run `bash "Build Mac App.command"` from that directory. A Git
   checkout made on Windows may not preserve the executable bit; explicitly
   running it with Bash works without changing permissions.

4. The build runs Swift tests, creates an app bundle, and creates a drag-to-install
   DMG in `Mac/output/arm64/` (Apple Silicon) or `Mac/output/x86_64/` (Intel).
   Open the DMG, drag `SuWuDu.app` to Applications, and launch it. Its heart menu-bar
   icon remains available when other windows are closed.

The installed application does not need Xcode, Python, or a separately installed
Codex CLI. Full builds bundle a pinned native Codex runtime. A deliberately smaller
build is available using `bash scripts/build.sh --without-codex`; its ChatGPT login
mode reports the missing component, while offline and API modes remain available.

`--arch=arm64` and `--arch=x86_64` select separate architecture builds. Build and
test each on a matching Mac (Intel tests on an Apple Silicon host require Rosetta).
These are separate native bundles, not a universal binary.

On the MacBook validated on 2026-09-27, the default macOS 27 SDK requires a
SwiftUI macro plugin absent from its Command Line Tools. The installed macOS 26.5
SDK works. Reproduce that build with:

```bash
bash scripts/build.sh --dmg --sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
open output/arm64/SuWuDu.app
```

`--sdk=/absolute/path/to/SDK` (or `SDKROOT`) applies to both compilation and tests.
The script uses SwiftPM's native build engine and supplies the CLT Swift Testing
framework path; the resulting application does not depend on that test framework.
Cached Codex binaries copied from Windows have their executable permissions
restored after checksum verification.

## Features implemented

- Both characters, all 12 states, PNG frame sequences, nearest-neighbor rendering,
  layered sleep effects, hammer interaction, scaling, wandering, and idle sleep.
- Transparent nonactivating pet and separate click-through speech bubble panels.
- Drag, single/double/triple-click, two separate wake-up hits, right-click menus,
  menu-bar recovery, and Control–Option–P recovery.
- Multiple displays, screen reconnection clamping, all-Spaces toggle, topmost and
  mouse-through options, login-item registration, single-instance recall.
- Focus/pause/resume/stop/restart, configurable breaks, random microbreaks,
  selectable/previewable sounds, hydration reminders, and optional notifications.
- Paused recovery after restart/sleep; partial-minute settlement; the 21:00 local
  journal boundary and largest-remainder cross-day allocation. Recovery state and
  journal changes are committed in the same atomic JSON document.
- Daily targets, minute adjustments, manual sessions, session deletion, daily and
  session Notes, daily clipboard copy, and date-range Markdown export.
- ChatGPT login via Codex app-server, dynamic model/effort discovery, API-key mode,
  offline replies, conversations, archives, bounded local context and 50 facts.
- Enter-to-send / Shift–Enter newline, per-message copy, screen attachment toggle,
  multi-display screenshot composition excluding the chat window, and temporary
  screenshot cleanup on success, error, startup, and shutdown.
- Windows JSON import with a pre-import backup, and external `command.json` input.
- Sparkle updater integration, activated only in releases with a real Mac appcast
  URL and public update-signing key. No Windows release URL is used as a Mac feed.

## Data and permissions

Application data is stored in:

```text
~/Library/Application Support/SuWuDu/
  app-state.json           settings, journal, recovery, chats, facts
  app-state.json.backup    previous successful state
  before-import-*.json     explicit Windows import backups
  Codex/                  app-specific Codex state
  CompanionWorkspace/     isolated chat working directory
  ScreenCaptures/         temporary screenshot attachments
  command.json            optional external one-shot command
```

API keys use macOS Keychain. Codex is configured to use its keyring credential
store, with its own `CODEX_HOME`; it does not reuse the developer's CLI home.
The app does not sync data to Windows, iCloud, or ChatGPT Memory.

Enable system notifications with **Settings → Focus → Allow notifications**.
Screen capture requests macOS Screen Recording permission on first use. If macOS
requires a restart after granting permission, relaunch the app. Text chat works
with screen vision disabled; offline mode never captures or sends a screenshot.

Windows import accepts `settings.json`, `focus-journal.json`, `chat-memory.json`,
and `active-focus.json` from a copied `%LocalAppData%\PixelHeartDesktopPet`
directory. Matching journal dates/chat IDs are replaced only after an explicit
import confirmation. Other records are retained. Windows coordinates and DPAPI
secrets are not imported; re-enter the API key or sign in on the Mac. Imported
focus state is paused. End a current Mac focus session before importing.

## Development and validation

Open `Package.swift` in Xcode to edit and build the package. Use the bundled app
produced by `scripts/build.sh` to exercise desktop integration: an unpackaged
`swift run` lacks the app resources, helper runtime, Info.plist and identity needed
for permissions and login items.

```bash
swift test --disable-xctest
python3 scripts/check-source.py
python3 -m unittest discover -s Tests -p 'test_*.py'
```

Optional portable syntax parsing uses `tree-sitter` and `tree-sitter-swift`:

```bash
python3 -m pip install --target .build/validation tree-sitter tree-sitter-swift
python3 scripts/check-source.py --swift-syntax
```

Swift tests cover the 21:00 boundary, daylight-saving transitions, paused gaps,
rounding, positive/negative minute settlement, interrupted/completed sessions,
atomic recovery, corruption backup recovery, memory opt-out, Windows import, and
animation asset references. App-model tests also exercise paused restart/resume,
duplicate settlement prevention, and offline chat persistence. Python tests cover
archive path/symlink handling and executable permission restoration for a cache
copied from Windows. Neither suite submits real AI requests. For Command Line
Tools, use the build script above to include the required test framework paths.

**Verification status:** The Apple Silicon application now compiles on macOS,
passes 21 Swift Testing tests, with five Python tests passed during the initial
Mac validation, and produces an ad-hoc signed
app and DMG. The launcher and focus start/pause have been exercised on the Mac.
This is a local development build; release signing/notarization and the remaining
hardware/account-dependent acceptance cases are still outstanding. See
[`VALIDATION.md`](VALIDATION.md) for the acceptance cases and recorded checks.

## Signed distribution and updates

Local builds are ad-hoc signed. To distribute a normally trusted downloaded app,
use your Developer ID Application identity and an existing notarytool Keychain
profile. Do not put credentials in this repository:

```bash
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='your-notary-profile' \
bash scripts/build.sh --dmg
```

The script signs nested binaries/bundles inside-out, notarizes a ZIP of the app,
staples the app ticket, and then creates the DMG. It does not upload or publish a
release. Signing/notarization cannot be completed without your Apple credentials.

For Sparkle, additionally set `UPDATE_FEED_URL` (a real HTTPS Mac appcast) and
`UPDATE_PUBLIC_KEY` (the public EdDSA key). Keep the private signing key outside the
repository. Publish signed app archives and a valid appcast before enabling the
feed. These values are intentionally absent from local builds, where “Check for
Updates” is disabled. Bump the Mac Info.plist version/build for each release.

The runtime fetcher pins Codex 0.144.4 and SHA-256 hashes for both Darwin
architectures, checks official release metadata, downloads and verifies both
required binaries, and caches them under ignored `Mac/runtime/`. Sparkle 2.10.0
is pinned in Package.swift. License notices are included in the application.
