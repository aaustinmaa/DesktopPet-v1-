# Continue on the MacBook

The native Mac source implementation is in `Mac/`. No Windows source, Windows
development output, or Windows installer was modified. The user explicitly chose
to continue Mac compilation and runtime work on their MacBook.

## Multiple tasks per pomodoro and fixed matching contract — 2026-10-14

Records and active runs now retain task allocation vectors. The user-facing editor
uses minutes, with equal allocation by default: a 25-minute record can be split
12.5/12.5 or edited to 10/15. Fractions remain internal; the latter allocation
contributes 0.4/0.6 completed pomodoros and 10/15 task minutes. Interrupted rows
contribute actual task minutes only; minute-conversion rows do not duplicate
task effort. Current/next-run task selection accepts multiple tasks and captures
their complete allocation when the run begins.

Single-record editing, batch editing, grouping, completed history and exports
show allocated task minutes. Equal-duration batches use minutes per record with
a **每条 … 分钟** footer: 10/15 means 10/15 in every selected 25-minute record.
Mixed-duration batches use combined actual minutes with a **合计 … 分钟** footer,
then apply the resulting proportions to each record. Existing single-task IDs
decode as a full share. `FocusTaskAllocationRules`
checks positive, finite, unique shares totaling 1; `DataStore` validates new vectors
on load/save and retains its corrupt-file preservation and backup recovery path.
Assignments and undo store full old/new vectors and use monotonic revisions.

`FocusTaskMatching` now supplies a fixed contract to both configured AI providers:
`{"matches":[{"sessionID":"…","allocations":[{"taskID":"…","share":1}],"reason":"…"}]}`.
All keys are required, extras are rejected, IDs must exist in the bounded snapshot,
and every allocation is a complete final state. Dedicated instructions explain
add/remove/replace/clear, default equal shares, minutes-to-share conversion and
ambiguous cases. An explicit empty allocation clears the record; an omitted record
is unchanged. Unknown or ambiguous work is omitted. The snapshot includes actual
minutes, current allocations, chronological ordinals and local timestamps/timezone.
Local code checks the contract instead of parsing the user's sentence. Preview,
apply and undo protect complete allocations against later changes.

The development build passed all 133 tests in 22 suites, production compilation
and strict signature verification, producing `output/arm64/SuWuDu.app`. Native
render checks at 1120 and 760 pixels confirmed compact rows and visible per-task
minutes; the allocation editor was also checked. No live AI request was submitted.
See `VALIDATION.md` for details.
This update targets the Mac development `.app`; Windows parity
and installer work remain pending/out of scope.

## Fixed memo-extraction contract — 2026-10-14

`AIService.extractMemoTasks` sends dedicated fixed instructions plus the memo,
local reference date/timezone and strict JSON Schema to both the Codex and OpenAI
API providers. Regardless of input notation, the response is `{"tasks": [...]}`.
Every task has exactly six required keys: `title` (string), `estimatedPomodoros`
(integer 0–10000 or null), `dueDate` (`YYYY-MM-DD` or null), `dueTime` (`HH:mm` or
null), `notes` (string) and `sourceExcerpt` (exact original substring). A non-null
time requires a date; invalid calendar dates or times are rejected.

AI interprets the user's dash budgets, following standalone numeric lines and
named child `+N` budgets. Parent and child budgets remain separate: the CS370
example produces 15 and 5, not 20. Course identifiers are not estimates; a task
without a budget remains present with null. AI normalizes explicit deadlines
using the supplied date/timezone; uncertain values remain null. Local code only
validates the contract, types, ranges, normalized dates/times and source integrity.
It no longer parses memo notation or resolves a whitelist of deadline expressions;
`estimateText` and `deadlineText` are absent from the new schema.

Preview/edit/selected import, duplicate handling, stale-request rejection and
original memo preservation remain in place. Windows extraction is still pending.
The 21 targeted contract/import tests passed. The required development build
passed 104 tests in 19 suites and strict signature verification, producing
`output/arm64/SuWuDu.app`. No live-model extraction pass is claimed. See the current
entry in `VALIDATION.md`.

## Focus panel copy cleanup — 2026-10-14

Removed persistent instructional captions, taglines and duplicate explanations
from the task/focus panel and its dialogs. Controls use short labels; rules live
in control hover help and `HelpView`. Task/user Notes and relevant error, stale,
loading and unsaved states remain visible. Memo source excerpts are expandable.
The default timer/footer no longer show instructional prose, and normal session
Notes no longer repeat the automatic/manual source on every row.
Native layout checks and the development build passed; the build's required
97-test suite and strict app signature verification passed. Only the development
`.app` was rebuilt.

## Compact records, memo extraction and task history — 2026-10-14

The journal now uses 30-point single-line session rows with aligned time/minute/
task/Notes columns; full text remains available through tooltips and row expansion.
Selection, task grouping and existing edit actions remain connected to the journal.
The same task list switches between active tasks and completed history. Completion
time and memo-source excerpts persist on tasks; legacy missing completion dates
stay unknown. Historical tasks retain their associated sessions and can navigate
to the record day through `JournalEditor.navigate`, which saves pending edits.

`FocusMemoExtraction.swift` validates AI task proposals and original-source
integrity; the current normalized contract is described above.
`AppModelMemoTasks.swift` handles cancellation, stale memo
snapshots and atomic selected imports. `AIService.extractMemoTasks` uses the
existing Codex/OpenAI providers. The UI allows editing proposals before import,
preserves the memo and original excerpts, and excludes duplicate titles by default.
Only the Mac development app is updated; Windows parity remains pending.

The updated developer build passed all 97 Swift Testing tests and strict app
signature verification. Native checks used 24 sample sessions at 1120 × 820 and
760 × 820, plus memo preview and history detail renders. No real AI request was
sent. Development output remains `output/arm64/SuWuDu.app`; the DMG is unchanged.

## Tasks and focus — 2026-10-14

The Mac journal is now the **任务与专注** panel. It combines the existing timer,
daily goals, bulk targets, minute adjustments, manual/ignored/deleted sessions,
Notes and exports with a unified task list, optional deadlines, local memos,
paste/import preview, task selection and retrospective batch matching.
`FocusTasks.swift` contains persistence-compatible domain logic and atomic
association/undo validation; `AppModelFocusTasks.swift` coordinates persistence
and asynchronous matching. `FocusTaskMatching.swift` isolates AI snapshots from
chat context and provides explicit-title offline suggestions. The matching UI
previews changes and refuses stale results.

Current-run task IDs are captured when starting; changing current selection affects
the next run. Partial records expose real minutes already counted in daily
adjustment; conversion records contribute zero duplicate task minutes. Keep
that distinction when changing journal accounting. Only the Mac development app
is updated for this feature; Windows work is listed in `WINDOWS_PARITY.md`.
User instructions in `HelpView` and `Mac/README.md` describe the current workflow.
Build without `--dmg` when only updating development output. Validation for further
work must stay scoped to the new request, rather than repeating previous checks.

The development build completed with all 83 Swift Testing tests passing and
strict signature verification passing for `output/arm64/SuWuDu.app`. Native
panel renders at 1120 × 820 and 760 × 820 were visually checked using isolated
sample data. Matching payload/response validation was tested without submitting
a real AI request. See the dated entry in `VALIDATION.md` for the scope.

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
