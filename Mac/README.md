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

The app also appears in the Dock and Command–Tab. Click its Dock icon to recall
the pet and open the control panel. To pin it, secondary-click its Dock icon and
choose Options → Keep in Dock. Closing a control window leaves the pet running;
use Quit to exit the app.

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

## Tasks and focus

Open **任务与专注** from the launcher, Dock menu, menu bar or pet context menu.
The existing journal and timer controls share one panel with a unified task list;
there is no separate today/task-library hierarchy. The panel uses the existing
celadon theme and shared controls.
The panel keeps controls, task/session data and relevant states visible; operating
rules are in hover help and the built-in instructions. Memo source text is expandable.

- Create or edit tasks with optional estimated pomodoros, a date-only or timed
  deadline, notes and a completion flag. Estimates measure a budget, not completion.
  Deadlines follow the local calendar, independently of the journal's 21:00 boundary.
- Paste a list and review/select the detected tasks before import; edit them after
  import. Explicit budget markers and separate numeric child lines are recognized;
  course numbers, dates, times and compound plans are preserved for manual review. Freeform memos
  remain editable locally and can be turned into a task. **AI 提取** proposes
  actionable items from the memo; select and edit the proposed names, budgets,
  deadlines and notes before importing the batch. Each proposal retains its source
  excerpt, and the original memo stays intact. Only explicit budgets/deadlines are
  extracted; ambiguous information stays empty. AI understands the memo shorthand
  described below; the manual paste importer retains its conservative behavior.
  Google Docs sync is not included.
- Select one or more tasks for upcoming runs. The editor uses task minutes: a
  25-minute pomodoro with two tasks defaults to 12.5 minutes each and can be
  changed to 10 and 15 minutes. Starting a run captures the complete allocation;
  changing the selection during a run affects the next run. Pause/recovery keeps
  the captured allocation.
- Edit a record's task minutes directly, or use Shift/multiple selection to
  allocate a batch. When all selected records have the same actual duration, the
  editor uses minutes per record and shows **每条 25 分钟**, for example; entering
  10/15 applies that split to every 25-minute record. When durations differ, the
  editor uses their combined actual minutes, shows **合计 … 分钟**, and applies
  the resulting proportions to each record. Clear associations or undo the most
  recent whole batch.
  Compact table rows show time, minutes, tasks and a single-line note; hover to
  read the full note or expand one row to edit. Task grouping and history show
  each task's allocated minutes without counting the whole record for every task.
- The task list's **完成历史** view retains completed tasks, their completion time,
  estimated/actual effort, notes and source excerpt. Expand a task to inspect its
  associated sessions and jump to a record day. Older completed tasks with no
  stored completion time show it as unknown. Reopen a task to continue working.
- **AI 匹配** and **AI 建议** use the configured ChatGPT/Codex or
  OpenAI API provider. **Notes 匹配** runs locally and requires a unique, explicit
  full task name in the note. Review old/new task minutes and reasons before
  applying. AI returns a fixed allocation contract described below; the application
  rejects unknown IDs, invalid shares and stale snapshots. Automatic suggestions
  preserve existing associations. Offline mode does not run a natural-language parser.
- Task effort uses the stored proportion: a 10/15 split of one 25-minute completed
  pomodoro contributes 0.4/0.6 completed pomodoros and 10/15 minutes. Interrupted
  runs contribute only their allocated actual minutes. Minute-conversion records
  still serve daily goals, with no duplicate task minutes or completed pomodoros.
  Manual sessions can still be added and assigned directly.

Daily goals, bulk target schedules, signed minute adjustments, manual sessions,
ignore/delete, daily/session Notes, save-on-navigation, clipboard copy and Markdown
range export are retained. Exports include time, task names and allocated minutes.

Matching sends task IDs/titles/descriptions and the selected journal range's
timestamps, chronological ordinals, actual minutes, current allocations, session
Notes and timezone to the selected provider. Memo extraction sends the memo
being extracted plus local date/timezone context. Neither operation sends chat
history or screen images, and neither modifies Google Docs. Both use the configured
ChatGPT/Codex or OpenAI API provider; memo extraction requires AI connectivity.
Tasks, memos and associations are persisted in `app-state.json`; old files remain
readable, and a legacy single-task association means 100% of that record.
The Windows implementation is still pending; see [WINDOWS_PARITY.md](WINDOWS_PARITY.md).

### Matching AI contract

Both ChatGPT/Codex and OpenAI API receive dedicated matching instructions and a
strict JSON Schema. Every response uses this structure, regardless of how the
user describes the work:

```json
{"matches":[{"sessionID":"session-1","allocations":[{"taskID":"task-a","share":0.4},{"taskID":"task-b","share":0.6}],"reason":"A 10 分钟，B 15 分钟"}]}
```

The IDs must come from the supplied snapshot. Every object has exactly the keys
shown; all are required, with no extra keys, Markdown or prose. `share` is a
positive JSON number at most 1; nonempty allocations contain unique task IDs and
sum to 1. These fractions are the storage/AI protocol; the user edits and reviews
minutes. A record appears at most once, and `reason` is a nonempty string.

Each allocation array describes the complete final state. AI resolves requests
to add, remove or replace tasks using the current allocation; unspecified shares
default to equal allocation. Explicit clearing returns `allocations: []`;
omitting a record keeps it unchanged. Unknown tasks, ambiguous record references
and contradictory durations are omitted rather than guessed. AI converts stated
minutes or ratios into shares using the snapshot's actual minutes, which exclude
pauses; wall-clock elapsed time is not used as task time. Multiple-record totals
are not repeated on every record or divided without a clear instruction.

Local code validates the normalized result and does not reinterpret the user's
sentence. Preview, application and undo compare the complete allocation vectors
and revisions; a later edit cannot be overwritten by an older preview. Invalid
responses reject the entire batch before any records are modified. Stored
allocation vectors are also validated on load/save; corrupt state follows the
existing backup recovery path.

### Memo AI contract

`AIService.extractMemoTasks` sends dedicated fixed instructions, the current memo,
the local reference date and timezone, and a strict JSON Schema through either
ChatGPT/Codex or OpenAI API. Input notation does not change the output structure:
the response is always `{"tasks": [...]}`, and every task has exactly six required
keys:

- `title`: a nonempty task-name string, at most 300 characters.
- `estimatedPomodoros`: an integer from 0 to 10000, or `null`.
- `dueDate`: a valid local calendar date in `YYYY-MM-DD`, or `null`.
- `dueTime`: a valid local 24-hour time in `HH:mm`, or `null`; a time requires a date.
- `notes`: a string, at most 10000 characters; empty when no extra details are supplied.
- `sourceExcerpt`: a nonblank exact original substring, at most 8000 characters,
  containing the task and its context.

AI interprets the memo's meaning: `CS341 - 8` means eight expected pomodoros;
`Build personal website` followed by a standalone `20` means twenty. A named child
budget stays separate: `Cs370 - 15, catchup cheat sheet +5` becomes a course task
with 15 and a course-scoped cheat-sheet task with 5, rather than one task with 20.
Course codes are not budgets, and `Nexo project` remains a task with a `null`
estimate. Unclear estimates/deadlines stay empty. AI resolves explicit relative
deadlines using the supplied reference date and timezone.

The local app checks only the response contract, types, ranges, normalized date/
time validity and original-source integrity. It does not parse memo budget notation
or use a deadline-word whitelist to reinterpret the model's result. There are no
`estimateText` or `deadlineText` response fields. Proposals are still editable and
selected by the user before import.
The array contains at most 100 tasks; an empty array is valid when no planned work
is present. All six keys are required even when their values are null. Additional
keys, Markdown fences and explanatory text are outside the response contract.

For the Mac **development app only**, build without `--dmg`:

```bash
bash scripts/build.sh --sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
open output/arm64/SuWuDu.app
```

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
  app-state.json           settings, journal, tasks, memos, recovery, chats, facts
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

**Current multi-task/matching validation (2026-10-14):** The Mac development build
passed all 133 tests in 22 suites, production compilation and strict signature
verification, producing `output/arm64/SuWuDu.app`. Native renders checked the
compact table at 1120/760 pixels and the minute-allocation editor. No live AI
matching request has been submitted.
See [`VALIDATION.md`](VALIDATION.md) for the current record.

**Previous extraction-contract validation (2026-10-14):** All 21 targeted tests
passed. The updated development build passed its required 104 tests in 19 suites,
production compilation and strict signature verification, producing
`output/arm64/SuWuDu.app`. No real AI request was submitted; the checks verify the
fixed contract and import behavior rather than live-model semantic accuracy.
See [`VALIDATION.md`](VALIDATION.md) for the current record.

**Previous verification (2026-10-14):** The compact records, memo extraction and
task history development build passed 97 Swift Testing tests and produced an ad-hoc signed Apple Silicon app at
`output/arm64/SuWuDu.app`. The merged panel was rendered and visually checked at
1120 × 820 and 760 × 820 using 24 isolated sample sessions; memo extraction
preview and history details were also checked at their native widths. The required build checks
and strict app signature verification passed. This feature update did not rebuild
the DMG or Windows outputs, and no real AI request was submitted. Release
signing/notarization and hardware/account-dependent acceptance cases remain
outstanding. See
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
