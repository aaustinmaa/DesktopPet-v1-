# Mac validation record

## Follow-up: obvious focus/interaction bugs

- Confirmed Windows plays the selected start cue on resume; Mac omitted that
  call. Added it to the shared resume path used by double-click and the launcher.
- Added pause feedback and resumed countdown feedback; new messages cancel the
  old countdown so it cannot overwrite a stop/pause/reminder bubble.
- First-click hammer feedback is immediate; only double-click is deferred for
  triple-click detection. Four or more clicks do not open additional chats.
  The pet accepts the first click when the application is inactive.
- Microbreak delays use random seconds, only schedule if the break finishes
  before focus ends, and show the reminder for the whole microbreak.
- Mouse interaction cancels pending wandering; drag completion clamps and saves.
- Playback preparation/start failures now log and use a system-sound fallback.
- Five focused regression tests passed: selected/muted resume cues, recovered
  focus resume, audio decoding of all generated and imported sounds, triple-click
  cancellation/fourth-click suppression, and microbreak end boundaries. The
  development build's required suite passed all 21 Swift tests.
- No claim of a complete physical-input or audible-output acceptance pass.
  This follow-up updates the development `.app` only, not the existing DMG.

## Verified in the Windows authoring environment

- Swift source parses with tree-sitter-swift. This is syntax validation, not an
  Apple SDK compiler or Swift type checker.
- All 215 referenced sprite frames and all four imported WAV recordings exist.
- Info.plist structure and Python helper syntax pass portable checks.
- Both Bash launch/build scripts pass `bash -n`.
- Four offline Python runtime-extraction tests pass. Windows sandbox restrictions
  initially blocked their temporary directories; the isolated rerun outside that
  sandbox passed.
- Official Codex 0.144.4 asset names and SHA-256 values for arm64/x86_64 and the
  Sparkle 2.10.0 release were verified against upstream release metadata.
- The Apple Silicon Codex fetcher completed download, checksum verification and
  extraction of the CLI and code-mode-host binaries. Mac binaries were not run
  on Windows.

## Verified on this MacBook — 2026-09-27

- Host: Apple Silicon, macOS 26.6 (25G72), Swift 6.4 Command Line Tools.
- Build: `bash scripts/build.sh --dmg --sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`.
- Sixteen Swift Testing tests passed, including three new app-model tests for
  paused recovery/resume, preventing duplicate settlement, and offline chat with
  persisted memory. Existing accounting, import, recovery and asset assertions
  were migrated from XCTest because this CLT does not include XCTest.
- Five offline Python tests passed, including a regression test for executable
  permission restoration on checksum-verified caches copied from Windows.
- All 215 referenced sprite frames, four WAV assets and Info.plist passed checks.
- Full arm64 app and DMG built. Nested Sparkle/Codex and outer app signatures
  passed deep/strict validation with local ad-hoc signing.
- App launched from `output/arm64/SuWuDu.app`. Both character sprites displayed;
  switching characters persisted through relaunch. Settings, launcher, chat and
  journal windows opened, and the pet right-click menu worked.
- Focus started at 25:00, paused at 24:56, and remained paused at 24:56 after
  quitting/relaunching. Resume, restart to 25:00 and stop worked. These short
  sessions correctly left the journal at zero minutes.
- Chinese offline messages sent with Return and received the expected reply.
  The app is left in offline mode with the default SuWuDu character. One local
  test conversation remains; no real AI request or screen attachment was sent.
- Bundled Codex startup and `account/read` succeeded through “Refresh account
  and models”, showing “not signed in” after fixing Unix executable permissions.
- Click-through/recovery and dragging were attempted through automation, but
  panel-coordinate persistence was not observed; these are not a complete
  physical-input acceptance pass and remain on the manual checklist.

Environment notes: the default macOS 27 SDK could not resolve SwiftUIMacros with
this CLT; selecting the installed 26.5 SDK resolved application compilation.
The native SwiftPM engine plus explicit CLT Testing framework paths resolved
test compilation. Initial Sparkle URLSession download stalled; downloading the
same official archive with curl, checking its pinned SHA-256, and placing it in
SwiftPM's artifact cache allowed the build to proceed.

## Remaining acceptance before release

The smoke checks above are complete. The broader scenarios below remain release
acceptance requirements; no Intel, notarization or authenticated AI pass is claimed.

1. Run `bash scripts/build.sh --dmg` on Apple Silicon; repeat on Intel if shipping
   Intel support. Confirm Swift compilation, Swift Testing, embedded framework paths,
   nested signatures, and app launch from Applications.
2. Check both characters and every state. Verify the pixel edges, frame order,
   hammer position, sleep layers, single/double/triple-click timing, dragging and
   the two separate wake-up hits. Verify idle and active battery/CPU use.
3. Toggle click-through and recover with both Control–Option–P and the menu bar.
   Test shortcut conflict, hiding/reopening, second launch, topmost, Spaces,
   Mission Control, Stage Manager, full-screen apps, and hiding the Dock.
4. Move between mixed-Retina displays; disconnect the current monitor, restart,
   and confirm the pet/bubble stay on a usable screen. Drag during wandering and
   confirm there is no jump back to an old movement target.
5. Run/pause/resume/stop/restart focus; close the app and sleep/wake the Mac during
   focus. Confirm offline time is excluded and recovery is paused. Exercise
   cross-21:00 sessions, sub-minute interruptions, random microbreaks and normal
   breaks. Confirm journal totals survive restarts without duplication.
6. Test all sound choices, mute, notification permission denial, daily targets,
   positive/negative adjustments, session notes/deletion, clipboard and exports.
7. Import copies of real Windows JSON data. Compare dates, notes, session counts,
   archived conversations, facts and paused remaining time; retain originals.
8. Test ChatGPT OAuth success/cancel/logout, model/effort refresh, child-process
   failure, reply timeout, cancellation, API invalid-key/model errors, and offline
   replies. No real account integration was exercised on Windows.
9. Deny/allow/revoke screen-recording permission; test all displays and chat-window
   exclusion. Inspect request attachments and ensure temporary JPEGs are removed
   after success/error/cancellation and relaunch.
10. With real release credentials/feed: notarize and launch a downloaded app on a
    clean Mac, enable login at startup, verify signed Sparkle update/relaunch and
    retention of local data. No feed or signing identity is fabricated here.

## Windows-style UI alignment (2026-09-27)

- Rebuilt the local Apple Silicon development app (no DMG update). All 25 Swift
  tests passed, including four new settings-draft and journal-editor tests.
- Launcher, settings, chat, journal and help share the Windows celadon palette,
  bordered cards and primary/secondary buttons. Launcher follows the Windows
  quick-action/management grid; Finder reveal replaces the Windows shortcut action.
- Settings use one scrolling page and a fixed Cancel/Save footer. Draft edits do
  not change running settings until Save; only edited fields are merged, preserving
  live pet position/menu changes. Login, data import and key deletion remain explicit
  immediate actions. UI check: change name, Cancel, reopen => original name retained.
- Chat uses the compact default window, collapsible conversation list, settings
  action, contrasting message bubbles, visible Copy controls, and composer-side
  Send / screen toggle. Verified expand/collapse, existing conversation selection,
  message layout, and opening settings from the chat header; no AI messages sent.
- Journal uses summary cards, date navigation, expandable session editing and a
  fixed Copy/Export/Save footer. Drafts save on navigation/close/export; automatic
  sessions received during editing are merged. Verified journal layout and the
  date-range export sheet; save/merge/navigation covered by isolated tests.
- Native macOS title bars, pickers, steppers, file dialogs and login controls remain.
  This pass compares the checked-in Windows XAML; no live Windows screenshot
  or pixel-perfect cross-platform claim is made.

## UI detail parity and settings categories (2026-09-27)

- Buttons now reproduce the Windows 0.3-second (0.25, 0, 0.3, 1) hover curve:
  outline expands from 0.7 to 1 while the fill shrinks from 1 to 0.7; labels and
  hit areas stay fixed. Reduce Motion disables the interpolation.
- SpeechBubbleView reproduces the 96-point canvas, minimum 184-point width,
  12-point semibold centered text, 14-point corners, 1.5-point pale-jade outline,
  shadow and 16 × 9 tail from SpeechBubbleWindow.xaml. A local AppKit render was
  visually inspected; the bubble stays click-through and follows the pet.
- Desktop secondary-click uses a custom celadon menu with Windows item ordering,
  separators, checkmarks and a side submenu. Native menu-bar commands stay native.
  UI checks passed for opening the desktop menu, keyboard submenu navigation,
  Escape dismissal and dispatching the encouragement command. Global/local outside
  clicks and app deactivation dismiss the popup. Control-click has a regression
  test covering modifier release before mouse-up without a pet interaction.
- Settings retain the new palette and Save/Cancel draft behavior, but restore four
  category buttons: appearance, focus, AI/memory and local data. All four category
  switches were checked in the running app; only the selected section is displayed.
- Final development build and all 26 Swift tests passed. No DMG or Windows output
  was rebuilt. Physical hover timing and trackpad gestures remain user acceptance
  checks; the animation parameters match the checked-in Windows source.
