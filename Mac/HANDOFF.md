# Continue on the MacBook

The native Mac source implementation is in `Mac/`. No Windows source, Windows
development output, or Windows installer was modified. The user explicitly chose
to continue Mac compilation and runtime work on their MacBook.

## MacBook progress — 2026-09-27

The Apple Silicon app now builds and launches on this MacBook (macOS 26.6,
Swift 6.4 Command Line Tools, macOS 26.5 SDK). Local outputs are:

- `output/arm64/SuWuDu.app`
- `output/arm64/SuWuDu-macOS-arm64.dmg`

Twenty-one Swift Testing tests pass after the focus/interaction fixes below;
five Python tests passed during the initial Mac build. The app and nested
components pass `codesign --verify --deep --strict`. Desktop smoke checks cover
both character displays, settings persistence, right-click menu, focus
start/pause/resume/restart/stop, paused recovery after quitting/relaunching,
journal display, Chinese offline chat, and bundled Codex account-status reads
(returns “not signed in”). No account login or real AI request was performed.

Follow-up fixes: resume now plays the selected start cue, pause/resume bubbles
match the timer state, new messages cancel stale countdown overlays, first-click
feedback is immediate, a fourth click does not reopen chat, and microbreak
scheduling uses seconds and avoids the end of a focus session. Mouse interaction
cancels an in-flight wander, and completed drags clamp/persist the position.
Audio playback failures fall back to the system sound. Five regression tests
cover these focus/audio/click scheduling changes. Only the development `.app`
was rebuilt for this follow-up; the existing DMG predates these fixes.

Fixed during Mac validation: explicit SDK selection; Swift Testing support in
Command Line Tools; app signing order; moving the Codex cache manifest out of
the Helpers code directory; restoring executable permissions on verified
runtime caches copied from Windows. Tests now require Swift 6 / Xcode 16+.

The current CLT defaults to a macOS 27 SDK missing its SwiftUI macro plugin.
Use the installed 26.5 SDK explicitly below. SwiftPM's default build engine also
failed to resolve Testing macros; the script uses the native engine and adds
the CLT Testing framework paths only to the test build.

## Rebuild on this MacBook

Run from `Mac/`:

```bash
bash scripts/build.sh --dmg --sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
```

This builds for the current Mac architecture, runs Swift tests, assembles the app,
and creates a DMG under `Mac/output/<architecture>/`. The first run downloads
Sparkle and checksum-pinned official Codex Mac components. If an AI-runtime
download blocks UI development, use `bash scripts/build.sh --without-codex` and
select offline chat. The API mode also works without Codex.

If continuing with a coding agent, use this prompt:

> Continue the macOS port in Mac/. Read Mac/HANDOFF.md and Mac/README.md first.
> Re-read current files before changing them. Build on this Mac with
> the SDK-specific build command above, fix actual runtime failures, and verify
> the native desktop behavior against Mac/VALIDATION.md. Keep changes scoped to
> the Mac port; do not modify or build Windows outputs or installers. Read the
> current validation record before choosing further checks. Remaining desktop,
> hardware, permission and authenticated AI checks are listed in VALIDATION.md.
> Do not publish releases or assume signing credentials are configured.

## Current state

- Swift/AppKit pet and bubble panels; SwiftUI launcher, settings, journal, chat,
  and help; core focus/accounting/memory/import services; Mac integrations and
  build/distribution scripts are implemented.
- PNG animation mapping, timing, pet dimensions, sleep choreography and generated
  sound formulas were taken from the current Windows source. Native easing,
  display scaling and window interactions still need visual comparison.
- Portable validation passed: 11 Swift files parsed; 215 sprite frames and four
  WAVs resolved; Info.plist, Python and Bash syntax checked; four Python archive
  tests passed. Apple Silicon Codex runtime download/checksum/extraction passed.
- **Still not verified:** full animation/gesture acceptance, physical sleep/wake,
  mixed-display/Spaces behavior, permissions, authenticated AI, Developer ID
  signing, notarization, and updater delivery. The app is locally ad-hoc signed.
- Swift tests are in `Tests/SuWuDuTests/`; native acceptance cases
  are in `VALIDATION.md`.
- Sparkle integration is present but disabled until an actual Mac appcast and
  EdDSA public key are supplied. No fake update feed or credentials are included.
- SwiftUI windows intentionally use native Mac controls; this is not a literal
  pixel-for-pixel copy of WPF controls. Full-screen/Spaces behavior is subject to
  macOS and requires desktop verification.

## Source archive

`SuWuDu-Mac-source.zip` contains the Mac project, required shared runtime PNG/WAV
assets, and the Codex license. It excludes Windows binaries, personal application
data, local build caches, and downloaded helper binaries. Extract it on the Mac
and work from its `Mac/` directory. The fetcher restores helpers during build.

See `README.md` for local data locations, Windows import, signing and architecture
options. Keep local Keychain credentials and release keys out of source control.

## UI alignment follow-up (2026-09-27)

The development app now follows the Windows control-panel grid, single-page
settings with Save/Cancel, compact chat with a collapsible list, and card-based
journal with editable sessions and Save/Copy/Export actions. `Theme.swift` holds
the matching celadon palette and shared controls. Settings drafts preserve unrelated
live settings; journal drafts merge new automatic sessions before saving. See the
UI alignment section in `VALIDATION.md` for the 25-test build and native UI checks.
The existing DMG was not rebuilt for this change.

## UI details and categorized settings (2026-09-27)

Settings now use four category buttons while retaining celadon cards and Save/Cancel.
Button hover scaling/timing matches Windows. `SpeechBubbleView.swift` replaces the
native material bubble with the Windows outline, tail, text and sizing.
`PetContextMenu.swift` supplies a matching desktop popup and side submenu with
keyboard navigation/dismissal; command actions are shared with the native menu bar.
The final local development build passes 26 Swift tests. See `VALIDATION.md` for
UI checks and the remaining physical-hover/trackpad acceptance limits.
