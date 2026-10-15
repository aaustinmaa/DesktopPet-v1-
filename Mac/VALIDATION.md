# Mac validation record

## Desktop quick menu preserves other windows (2026-10-15)

- The desktop quick menu no longer activates the whole application. Root and
  submenu panels are created as nonactivating panels, retaining keyboard focus
  while other application windows remain at their existing stacking positions.
  Explicit menu commands that open chat/settings still use their existing window
  activation paths.
- Two targeted tests passed for nonactivating root/submenu panels, keyboard
  navigation and action selection, Escape dismissal and other window state.
- A separate two-process AppKit comparison used only isolated test windows:
  before the fix, opening the menu activated the owning process and exposed its
  covered panel; after the fix, root and submenu received keyboard focus while
  the owning process stayed in the background and the other panel stayed covered.
  AppKit's `NSApp.isActive` can be true for keyboard event routing even when
  `NSRunningApplication.current.isActive` remains false; verification uses the
  process activation state and actual window occlusion.
- Release compilation with the macOS 26.5 SDK passed. The new executable is in
  `output/arm64/SuWuDu.app`; strict/deep signature verification passed, retaining
  existing runtime assets and nested helpers. The running user app was not
  restarted, and no Windows output, installer or DMG was changed.

## Shen Qing sleeping ZZZ placement (2026-10-15)

- Applied the approved preview offset to Shen Qing only: 20 pixels left and
  30 pixels down on the 362-by-362 canvas. SuWuDu retains its original placement;
  all glyph sizes, travel, opacity and ten-second timing remain unchanged.
- Two targeted sleeping tests passed, including the new position and restoring
  SuWuDu's original position after changing characters. Preview registration was
  checked against the approved offset and all visible glyphs remain in bounds.
- Release compilation with the macOS 26.5 SDK passed. The development app at
  `output/arm64/SuWuDu.app` received the new executable and current runtime sprites;
  strict/deep signature verification passed and nested helpers were preserved.
  No running app was restarted. No installer or DMG was rebuilt.
- Windows source has the matching placement adjustment. Windows binaries were
  not rebuilt on this Mac.

## Minute details and disclosure hit targets (2026-10-15)

- The pomodoro table now shows counted, non-partial records, including converted
  units. Early-ended work remains in **目标与分钟调整 → 分钟明细**; excluded
  ordinary records remain editable/restorable in **未计入记录**. Existing data,
  task effort, export details and minute-conversion accounting are retained.
- Table selection, grouping and batch/AI matching use the same visible scope;
  conversions cannot be matched. Saved records are rechecked before matching or
  batch assignment, while individual minute details still allow task allocation.
- Two new isolated regression tests passed: 10 + 15 interrupted minutes produce
  one converted unit while preserving 25 task minutes once; editing, saving,
  reloading, excluding/restoring and deleting records preserve the correct scopes,
  totals and exported detail. Earlier functional suites were not rerun.
- Shared disclosure headings now have full-width 32-point hit targets, including
  trailing whitespace. A temporary native AppKit harness passed nine mouse-event
  clicks across three label sizes (title open, trailing-space close/open). The
  expanded render was inspected, and the harness was removed. Compact record
  rows keep their 30-point height and expand through the combined Notes/arrow area.
- Release compilation with the macOS 26.5 SDK and strict/deep app signature
  verification passed. `output/arm64/SuWuDu.app` was refreshed without restarting
  the running app or changing user data. Windows and installers were not changed.

## Visible recording sources (2026-10-15)

- Compact rows now show **自动 / 手动 / 提前结束 / 分钟换算** in the existing
  **来源 · Notes** column, preserving row height and table width. Recording
  sources remain stored separately from task-assignment sources.
- Source inspection and a read-only check of the reported local records confirmed
  the manual flags were retained. Manual additions create independent records;
  overlapping displayed times are not a deduplication key. No user records were
  edited, deleted or merged.
- Fixed a related classification bug: editing ordinary manual/automatic records
  to zero minutes no longer labels them as minute conversions. Table, hover help
  and Markdown export share the same source classification.
- The new isolated regression test passed through edit, save, reload and export
  for automatic, manual, partial and converted records. Earlier functional suites
  were not rerun for this change.
- Release compilation with the macOS 26.5 SDK and strict/deep signature verification
  passed. The development app at `output/arm64/SuWuDu.app` was updated without
  restarting the user's app. Windows and installers were not changed.

## Claude resolved model labels (2026-10-15)

- Model picker labels now include the official `resolvedModel` ID, including
  the automatic/default choice. Missing metadata keeps the existing name;
  selection IDs and inference behavior are unchanged.
- An isolated, signed-out initialize-only metadata request confirmed that the
  bundled CLI supplies full IDs for default, Opus, Sonnet and Haiku. No user
  credentials or inference were used. Release compilation with the macOS 26.5
  SDK passed, and `output/arm64/SuWuDu.app` was refreshed and signature-verified.
- This display-only change did not rerun the earlier functional test suites,
  restart the user's app, or update installers or Windows outputs.

## Claude model and effort selection (2026-10-14)

- Claude settings now match ChatGPT's **模型** / **推理强度** picker layout and
  **刷新账号和模型** action. Independent saved settings reach chat, memo extraction
  and pomodoro matching. Changing models resets effort; missing saved choices
  remain visible and requests reject unsupported selections before inference.
- Official CLI 2.1.300's initialize-only control protocol was checked with an
  isolated HOME/config directory, no credentials or user turn. Runtime models
  and their effort capabilities populate the pickers. Default selections also
  require an allowed catalog entry; Fable/paid variants cannot bypass this check
  through the default alias. No model or API fallback was added.
- **37 targeted permanent tests passed**: 12 model/protocol, 5 settings, 8 provider
  and 12 client/process tests. Coverage includes metadata parsing and failures,
  selected/default arguments, unavailable defaults, independent preferences and
  legacy settings, and all three feature routes forwarding the saved choices.
- One additional temporary native render test passed. The actual Claude settings
  component was visually checked at 620 points with fake account/model metadata,
  showing Opus/high, the shared celadon style and no extra captions/buttons. The
  temporary harness was removed before the development build.
- Release compilation with the macOS 26.5 SDK passed. The executable was updated
  in `output/arm64/SuWuDu.app`, preserving the existing runtime components; the
  refreshed app passed strict/deep signature verification. The running user app
  was not restarted.
- No live-account model inference was performed; tests use isolated protocol
  responses and do not establish the user's account entitlement. Windows and
  installers remain outside this change.

## Claude login presentation (2026-10-14)

- The picker now says **Claude 登录**. Account controls use the ChatGPT button
  style and spacing, with **连接我的 Claude**, **刷新账号** and **退出登录**.
  The subscription caption and extra usage button were removed; status wording
  and current instructions/documentation were updated to match.
- Release compilation with the macOS 26.5 SDK passed. The development executable
  was refreshed in `output/arm64/SuWuDu.app` and the app signature was verified.
  Existing runtime components were retained. No live login, full test suite,
  installer build or unrelated feature verification was performed for this
  presentation-only change.

## Claude subscription integration (2026-10-14)

- Mac settings provide official Claude browser login, status, refresh, disconnect
  and cancellation. Chat, optional screen images, memo extraction and pomodoro
  matching route through the same Claude client. Built-in instructions and both
  READMEs document connection and the billing boundary; Windows remains pending.
- **19 targeted permanent Swift tests passed**: 12 client/process tests and 7
  provider integration tests. They cover official subscription login arguments,
  clean environments, account-method/provider rejection, auth rechecking, input
  images, fixed instructions/schemas, invalid structured output, local memo and
  matching validation, quota failures without fallback, settings compatibility,
  bounded process output, timeout, cancellation and private-error redaction.
- **11 targeted Python tests passed** (8 runtime, 3 build). Runtime tests cover
  pinned manifest/hash checks, verified cache, failed-download preservation and
  a version floor supporting disabled file mentions. Build tests cover preserving
  the previous app on failure and retaining Claude's original signature/bytes.
- Official **Claude Code 2.1.300 arm64** was downloaded from Anthropic and checked
  against its pinned SHA-256 and Developer ID signature (`Q6L2SF6YDW`). Isolated
  actual CLI checks confirmed version, supported arguments, subscription login
  help and not-signed-in status. No real login, credentials or inference was used.
  The x86_64 manifest hash is pinned; that binary was not executed on this Mac.
- Native renders of the actual Claude settings component verified disconnected
  and connected states at the settings panel's 620-point width, with the shared
  Pet theme. The isolated host did not expose a usable Connect button through its
  accessibility/native-button tree, so pending/cancel UI interaction is not claimed
  as verified. Its client cancellation is covered by tests and the view lifecycle
  was reviewed in source. The temporary render harness was removed.
- The Mac development build passed **159 tests in 25 suites**, production
  compilation and strict/deep app signature verification. The post-signing check
  reconfirmed the original Claude SHA-256 and Anthropic identity. Output:
  `output/arm64/SuWuDu.app`. No live user app was restarted by this task.
- Live-account acceptance remains: complete browser authorization, check one chat
  (and optional screen attachment), extract a memo, preview matching changes, and
  try login cancellation/quota errors. Tests above use isolated fake protocol
  responses; they do not establish live model semantic accuracy or account access.
  The app never falls back to API credentials. Claude account-level usage credits
  / extra usage remain controlled by the user's Claude settings.
- This change does not build or inspect DMGs or Windows installers.

## Batch association appends existing task sets (2026-10-14)

- Both the task-card shortcut and the main selected-record action append tasks.
  **追加任务…** opens a task-selection sheet; allocation minutes are edited through
  the existing record editor or explicit **重新分配用时…** action. The more menu
  also retains **清空任务关联**.
- Each record combines only its own existing IDs with the selected additions.
  Adding new IDs defaults its final task set to equal shares; already associated
  IDs are not duplicated. Duplicate-only additions preserve exact custom minutes,
  and a wholly duplicate action preserves the previous undo transaction.
  Unassigned records split their minutes equally among the selected tasks.
- All 7 targeted `FocusTaskAppendTests` passed, covering different prior tasks,
  mixed assigned/unassigned selections, duplicate-only additions, stale snapshots,
  unknown tasks, duplicate records, conversion records, persistence rollback and
  whole-batch undo.
- Native renders verified the append sheet with one selected task and the task-card
  shortcuts. The append sheet displays task selection without misleading minute
  fields. The isolated Journal host did not expose accessible controls for a
  selected-toolbar render; that routing was checked in source. The temporary render
  harness was removed.
- The required development build passed **140 tests in 23 suites**, production
  compilation and strict signature verification, producing `output/arm64/SuWuDu.app`.
  Earlier entries retain their original results.
- Windows implementation is unchanged and pending; installers are outside scope.

## Multiple task allocations and fixed matching contract (2026-10-14)

- Current change: one pomodoro can allocate actual minutes to multiple tasks,
  defaulting to equal shares. A 25-minute 10/15 allocation contributes 0.4/0.6
  completed pomodoros. Partial rows contribute only real allocated minutes;
  minute-conversion rows do not duplicate task effort.
- Current/next-run selection captures a full allocation for each run. Individual
  and batch editors use minutes. Equal-duration batches edit minutes per record;
  mixed-duration batches edit combined actual minutes and apply the resulting
  proportions to each record. The footer identifies per-record or combined time.
  Grouping, history and exports show task minutes. Legacy single IDs remain
  readable as full shares.
- Matching has a fixed strict response contract: `matches` contains objects with
  `sessionID`, `allocations` and `reason`; each allocation contains `taskID` and
  numeric `share`. All keys are required, extra keys/unknown IDs/duplicate IDs and
  invalid shares are rejected. Nonempty shares must be positive and total 1.
- The prompt specifies full final-state add/remove/replace/clear operations,
  input minute/ratio conversion, explicit clearing versus omitted unchanged
  records, and omission for ambiguity. The snapshot supplies actual minutes,
  current allocations, stable chronological ordinals and local timestamps/timezone.
  Contract parsing does not run local natural-language rules.
- Focused checks cover legacy migration, equal allocation, weighted totals,
  partial/conversion accounting, full-vector atomic apply/undo, stale ratios,
  persistence failure/backup recovery, import preservation and matching contracts.
  Editor checks cover 12.5/12.5 defaults, 10/15 edits, exact thirds, remaining-time
  redistribution, invalid drafts and saving the still-focused minute field.
- The required Mac development build passed all **133 tests in 22 suites**,
  production compilation and strict signature verification, producing
  `output/arm64/SuWuDu.app`. Two new integration fixtures were corrected to compare
  live versus persisted snapshots consistently across timestamp serialization;
  the stale-record protections remain unchanged.
- Native view rendering at 1120 and 760 pixels verified the compact 30-pixel
  record rows, multiple visible task-minute values, narrow stacked layout and
  the 10/15-minute allocation editor. Long task names truncate individually while
  minute values remain visible; full labels are available on hover. Rendering
  used isolated test data, and the temporary render harness was removed.
- No live ChatGPT/OpenAI matching request has been submitted. The older results
  below describe their original versions. This request updates the Mac development
  app only; Windows development output and both platforms' installers are outside
  scope.

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
