# Mac validation record

## Fixed memo-extraction contract (2026-10-14)

- The AI request uses dedicated fixed instructions, memo text, local reference
  date/timezone and strict JSON Schema for both ChatGPT/Codex and OpenAI API.
  Every task returns the same six required keys: `title`, `estimatedPomodoros`,
  `dueDate`, `dueTime`, `notes` and `sourceExcerpt`.
- Estimates are integers from 0 to 10000 or null. Dates/times use valid local
  `YYYY-MM-DD` / `HH:mm` values or null; a time requires a date. Original source
  excerpts must match the memo. Local checks validate this normalized contract,
  rather than parsing memo notation or resolving a deadline-word whitelist.
- The instructions explicitly explain dash budgets, a following numeric line,
  separate named-child `+N` budgets, course identifiers and tasks with no estimate.
  AI performs this interpretation and deadline normalization; there are no
  `estimateText` or `deadlineText` fields.
- The 21 targeted tests in `FocusMemoExtractionTests` and
  `MemoBudgetNotationTests` passed. They cover the seven canonical tasks from the
  screenshot, the complete prompt example, varied input notation with the same
  response contract, nullable values, invalid types/extra keys, normalized dates,
  DST validation, source integrity and atomic/stale import handling. These are
  fixture-based contract checks, not a live-model semantic accuracy test.
- The required development build checks passed all 104 tests in 19 suites,
  followed by production compilation and strict signature verification. The
  updated Apple Silicon development app is `output/arm64/SuWuDu.app`. No real AI
  request was submitted. The older results below describe their original versions.
- This request remains scoped to the Mac development app; Windows and the DMG
  are outside the update.

## Focus panel copy cleanup (2026-10-14)

- Removed persistent instructional sentences and duplicate labels in the panel,
  matching/memo/task dialogs, journal editors, export and bulk target dialog.
  User Notes, task metrics and error/loading/unsaved states remain available.
- Native renders at 1120 × 820 and 760 × 820, the memo preview at 600 × 580 and
  bulk target dialog at 480 × 330 were visually checked with isolated sample data.
  Instructions now live in hover help and the existing built-in help page.
- This changes presentation only. No new unit tests were added; the temporary
  native rendering harness was removed after inspection. No real user data,
  account requests or running app state were changed by these checks.
- The development script's required 97 tests passed, followed by production
  compilation and strict signature verification. Updated the Mac development
  `.app` only; no DMG or Windows output was rebuilt.

## Compact records, memo extraction and history (2026-10-14)

- Added 14 focused tests for explicit memo-source evidence, budgets/deadlines,
  ambiguous or truncated date/time wording, duplicate/stale preview rejection,
  atomic edited imports, persistence failure, request cancellation, and
  completion timestamps with backward-compatible legacy tasks. All passed.
- Native renders used 24 sample pomodoros at 1120 × 820 and 760 × 820, including
  the scrolled record area. Rows are approximately 30 points high, retain aligned
  columns and show one-line Notes with full-text tooltips and expanded editing.
  The native memo preview (600-point width) and history detail at sidebar width
  were also visually checked. Temporary rendering tests were removed afterward.
- The checks used isolated sample data and a silent sound provider. No real user
  data or running app was changed, and no real ChatGPT/OpenAI request was sent.
  The original memo remains intact when selected proposals are imported.
- The development build completed with **97 Swift Testing tests in 18 suites**
  passing, a successful production executable build, and strict verification of
  app/nested component signatures. Updated `output/arm64/SuWuDu.app` only; no
  DMG, Windows source, Windows development output or installer was updated.

## Tasks and focus development update (2026-10-14)

- Added tests for backward-compatible task persistence, deadlines, conservative
  task import, task accounting, partial-session day boundaries, minute-conversion
  exclusions, assignment validation, batch undo, and Windows import preservation.
- Matching tests cover request limits, local time/chronological ordering, strict
  JSON parsing, unknown/duplicate IDs, stale snapshots, and conservative local
  note suggestions. Model tests cover task continuity, persistence failure,
  cancellation, AI preview/apply/undo, and editor merge behavior.
- Native SwiftUI panel renders were visually inspected at 1120 × 820 and
  760 × 820 with isolated sample tasks and sessions. The task list, timer,
  journal totals, collapsed goal/matching tools, and session records remain
  usable at both widths and follow the existing celadon theme.
- `scripts/build.sh` completed using the macOS 26.5 SDK. Its required suite
  passed all **83 Swift Testing tests in 17 suites**; the production executable
  built and the app/nested components passed strict signature verification.
- Updated development output: `output/arm64/SuWuDu.app`. No DMG, Windows source,
  Windows development output, or Windows installer was changed. The running app
  and real user data were not modified by the UI rendering checks.
- No real ChatGPT or OpenAI API matching request was submitted. The Google Doc
  remains a source for manual paste/import; automatic synchronization is not
  part of this feature.

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

## Mac installer refresh (2026-09-29)

- Rebuilt the current workspace as version **1.0.1 (build 2)** using
  `bash Mac/scripts/build.sh --dmg --sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`.
- Apple Silicon installer: `output/arm64/SuWuDu-macOS-arm64.dmg`.
  Open it and drag `SuWuDu.app` to Applications; quit the development app before
  launching the installed copy. User data remains in Application Support.
- All 42 Swift tests passed. The app and nested helper signatures verified.
  `hdiutil verify` passed; the DMG was mounted read-only and all 358 app files/links
  matched the rebuilt bundle, including file contents and executable permissions.
  The `/Applications` shortcut and packaged version were verified, then unmounted.
- DMG SHA-256: `32449d90ead77543c5b49b3c48fee90821d91d7457acf240b7bab19bc4da86d2`.
- Sparkle 2.10.0 remains bundled. Automatic updates remain disabled: no Mac
  appcast URL or public update-signing key is configured. No update was published
  or end-to-end update installation tested. See README's signed distribution
  instructions for enabling a hosted feed.
- This is an ad-hoc signed local installer, not a notarized distribution release;
  no Developer ID signing identity is available on this Mac. Intel packaging and
  Windows outputs were outside this refresh. The running app was not restarted
  and no copy was installed into Applications by this task.
