import Foundation
import Testing
@testable import SuWuDu

struct FocusTasksTests {
    private var toronto: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    @Test func oldAppStateAndActiveFocusDecodeWithoutTaskFields() throws {
        var state = AppData()
        state.journal = [JournalDay(date: "2026-10-14", sessions: [FocusSession()])]
        state.focus = FocusRun(startedAt: Date(), planned: 25, remaining: 100)
        let encoded = try DataStore.encoder.encode(state)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for key in ["tasks", "currentTaskID", "taskMemos"] { object.removeValue(forKey: key) }
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try DataStore.decoder.decode(AppData.self, from: legacy)
        #expect(decoded.tasks == nil)
        #expect(decoded.currentTaskID == nil)
        #expect(decoded.focus?.taskID == nil)
        #expect(decoded.journal[0].sessions[0].taskID == nil)
        #expect(decoded.journal[0].sessions[0].assignmentRevision == nil)
        #expect(decoded.journal[0].sessions[0].actualMinutes == nil)
        #expect(decoded.journal[0].sessions[0].completedPomodoro == nil)
    }

    @Test func dateOnlyDeadlineRemainsDueAfterJournalRollover() {
        let task = FocusTask(title: "课程作业", dueDate: date("2026-10-14T12:00:00-04:00"))
        let late = date("2026-10-14T22:00:00-04:00")
        #expect(FocusAccounting.key(late, calendar: toronto) == "2026-10-15")
        #expect(!task.isOverdue(at: late, calendar: toronto))
        #expect(task.isOverdue(at: date("2026-10-15T00:00:00-04:00"), calendar: toronto))
        var timed = task
        timed.dueHasTime = true
        #expect(timed.isOverdue(at: late, calendar: toronto))
        timed.isCompleted = true
        #expect(!timed.isOverdue(at: late, calendar: toronto))
    }

    @Test func importPreviewKeepsCourseNumbersAndRecognizesSeparateBudgetLines() {
        let tasks = FocusTaskImport.preview("CS370 补课 预计15\n个人网站\n20\n备忘：周五 14:30\nCS370")
        #expect(tasks.map(\.title) == ["CS370 补课", "个人网站", "备忘：周五 14:30", "CS370"])
        #expect(tasks.map(\.estimatedPomodoros) == [15, 20, nil, nil])
    }

    @Test func importPreviewOnlyExtractsExplicitBudgetsAndPreservesCompoundPlans() {
        let lines = ["Mod 10", "CS 370", "A7 前两题", "备忘：周五 14:30", "截止 2026-10-20",
                     "CS341 - 8", "课程 - 15", "论文 预计7", "复习 5个番茄", "代码 3 🍅",
                     "CS479 -25, catchup cheat sheet + 7", "CS479 -25, cheat sheet 7个番茄", "CS-370", "任务 15"]
        let tasks = FocusTaskImport.preview(lines.joined(separator: "\n"))
        #expect(tasks.map(\.title) == ["Mod 10", "CS 370", "A7 前两题", "备忘：周五 14:30", "截止 2026-10-20",
                                      "CS341", "课程", "论文", "复习", "代码",
                                      "CS479 -25, catchup cheat sheet + 7", "CS479 -25, cheat sheet 7个番茄", "CS-370", "任务 15"])
        #expect(tasks.map(\.estimatedPomodoros) == [nil, nil, nil, nil, nil, 8, 15, 7, 5, 3, nil, nil, nil, nil])
    }

    @Test func partialRunsKeepSeparateTaskMinutesWithoutAssigningConvertedPomodoro() {
        var state = AppData()
        state.tasks = [FocusTask(id: "a", title: "补课"), FocusTask(id: "b", title: "网站")]
        let start = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        FocusAccounting.record(segments: [.init(start: start, end: start.addingTimeInterval(600))],
            planned: 25, completed: false, startedAt: start, endedAt: start.addingTimeInterval(600),
            taskID: "a", journal: &state.journal)
        FocusAccounting.record(segments: [.init(start: start.addingTimeInterval(1200), end: start.addingTimeInterval(2100))],
            planned: 25, completed: false, startedAt: start.addingTimeInterval(1200), endedAt: start.addingTimeInterval(2100),
            taskID: "b", journal: &state.journal)
        #expect(state.journal.reduce(0) { $0 + $1.total } == 25)
        #expect(state.journal.reduce(0) { $0 + $1.count } == 1)
        #expect(state.taskSummaries().first { $0.taskID == "a" }?.minutes == 10)
        #expect(state.taskSummaries().first { $0.taskID == "b" }?.minutes == 15)
        #expect(state.taskSummaries().reduce(0) { $0 + $1.completedPomodoros } == 0)
        let conversion = state.journal.flatMap(\.sessions).first { $0.source == "manual" }!
        #expect(conversion.actualMinutes == 0)
        #expect(conversion.taskID == nil)
    }

    @Test func editingOrDeletingPartialDetailsReconcilesAccountingOnce() {
        let partial = FocusSession(source: "partial", minutes: 10, countsTowardGoal: false,
            taskID: "a", actualMinutes: 10, completedPomodoro: false)
        let original = JournalDay(date: "2026-10-14", adjustment: 10, sessions: [partial])
        var edited = original
        edited.sessions[0].minutes = 12
        edited.reconcilePartialWorkEdits(previous: original)
        #expect(edited.total == 12)
        #expect(edited.sessions[0].taskMinutes == 12)
        var deleted = edited
        deleted.sessions.removeAll()
        deleted.reconcilePartialWorkEdits(previous: edited)
        #expect(deleted.total == 0)
        let full = FocusSession(minutes: 25, actualMinutes: 25, completedPomodoro: true)
        let fullDay = JournalDay(date: "2026-10-14", sessions: [full])
        var corrected = fullDay
        corrected.sessions[0].minutes = 20
        corrected.reconcilePartialWorkEdits(previous: fullDay)
        #expect(corrected.sessions[0].taskMinutes == 20)
    }

    @Test func completedRunAcrossRolloverRemainsOneRealPomodoro() {
        var state = AppData()
        state.tasks = [FocusTask(id: "a", title: "补课")]
        let start = Calendar.current.date(bySettingHour: 20, minute: 50, second: 0, of: Date())!
        let end = start.addingTimeInterval(1500)
        FocusAccounting.record(segments: [.init(start: start, end: end)], planned: 25, completed: true,
            startedAt: start, endedAt: end, taskID: "a", journal: &state.journal)
        #expect(state.journal.reduce(0) { $0 + $1.total } == 25)
        #expect(state.taskSummaries().first?.minutes == 25)
        #expect(state.taskSummaries().first?.completedPomodoros == 1)
    }

    @Test func partialRowsAcrossRolloverUseClippedWorkingTimesAndExcludePauseMinutes() throws {
        var state = AppData()
        state.tasks = [FocusTask(id: "a", title: "补课")]
        let start = Calendar.current.date(bySettingHour: 20, minute: 45, second: 0, of: Date())!
        let boundary = start.addingTimeInterval(15 * 60)
        let segments = [FocusSegment(start: start, end: start.addingTimeInterval(5 * 60)),
                        FocusSegment(start: start.addingTimeInterval(13 * 60), end: start.addingTimeInterval(17 * 60)),
                        FocusSegment(start: start.addingTimeInterval(23 * 60), end: start.addingTimeInterval(28 * 60))]
        FocusAccounting.record(segments: segments, planned: 25, completed: false,
            startedAt: start.addingTimeInterval(-5 * 60), endedAt: start.addingTimeInterval(31 * 60),
            taskID: "a", journal: &state.journal)
        #expect(state.journal.count == 2)
        let before = try #require(state.journal.first { $0.date == FocusAccounting.key(start) }?.sessions.first)
        let after = try #require(state.journal.first { $0.date == FocusAccounting.key(boundary) }?.sessions.first)
        #expect(before.startedAt == start)
        #expect(before.completedAt == boundary)
        #expect(after.startedAt == boundary)
        #expect(after.completedAt == segments.last?.end)
        #expect(before.minutes == 7)
        #expect(after.minutes == 7)
        for day in state.journal {
            for session in day.sessions {
                #expect(FocusAccounting.key(session.startedAt) == day.date)
                #expect(FocusAccounting.key(session.completedAt.addingTimeInterval(-1)) == day.date)
                #expect(session.taskID == "a")
                #expect(!session.countsTowardGoal)
            }
        }
        #expect(state.journal.reduce(0) { $0 + $1.total } == 14)
        #expect(state.taskSummaries().first?.minutes == 14)
        #expect(state.taskSummaries().first?.completedPomodoros == 0)
    }

    @Test func importPreservesTasksAndSameSessionAnnotations() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var state = AppData()
        state.tasks = [FocusTask(id: "a", title: "补课", dueDate: Date())]
        state.currentTaskID = "a"
        state.taskMemos = "保留备忘"
        state.journal = [JournalDay(date: "2026-10-14", sessions: [FocusSession(id: "one", taskID: "a",
            assignmentSource: "manual", assignmentRevision: 4, actualMinutes: 25, completedPomodoro: true)])]
        let bytes = try JSONSerialization.data(withJSONObject: ["Days": [["Date": "2026-10-14", "Sessions": [
            ["Id": "one", "PlannedMinutes": 20, "CountsTowardGoal": true]
        ]]]])
        try bytes.write(to: folder.appendingPathComponent("focus-journal.json"))
        let imported = try WindowsImport.read(folder, into: state)
        #expect(imported.tasks == state.tasks)
        #expect(imported.currentTaskID == "a")
        #expect(imported.taskMemos == "保留备忘")
        #expect(imported.journal[0].sessions[0].taskID == "a")
        #expect(imported.journal[0].sessions[0].assignmentRevision == 4)
        #expect(imported.journal[0].sessions[0].actualMinutes == 20)
    }

    @Test func batchApplyAndUndoUseStableIDsAndLeaveNewRecordsUntouched() throws {
        var state = AppData()
        state.tasks = [FocusTask(id: "a", title: "补课"), FocusTask(id: "b", title: "网站")]
        let first = FocusSession(id: "1", taskID: "a", assignmentSource: "current")
        let second = FocusSession(id: "2")
        state.journal = [JournalDay(date: "2026-10-14", sessions: [first, second])]
        let plan = FocusMatchingPlan(changes: [.init(session: first, targetTaskID: "b"), .init(session: second, targetTaskID: "a")], source: "manual")
        state.journal[0].sessions.insert(FocusSession(id: "new"), at: 0)
        let transaction = try state.applyAssignments(plan)
        #expect(state.journal[0].sessions.first?.taskID == nil)
        #expect(state.journal[0].sessions.first { $0.id == "1" }?.taskID == "b")
        try state.undoAssignments(transaction)
        #expect(state.journal[0].sessions.first { $0.id == "1" }?.taskID == "a")
        #expect(state.journal[0].sessions.first { $0.id == "1" }?.assignmentSource == "current")
        #expect(state.journal[0].sessions.first { $0.id == "2" }?.taskID == nil)
        #expect(throws: FocusAssignmentError.staleSession) { try state.applyAssignments(plan) }
    }

    @Test func invalidOrStalePlansApplyNoPartialChanges() throws {
        var state = AppData()
        state.tasks = [FocusTask(id: "a", title: "补课")]
        let first = FocusSession(id: "1")
        let second = FocusSession(id: "2", notes: "原备注")
        state.journal = [JournalDay(date: "2026-10-14", sessions: [first, second])]
        let stale = FocusMatchingPlan(changes: [.init(session: first, targetTaskID: "a"), .init(session: second, targetTaskID: "a")])
        state.journal[0].sessions[1].notes = "已修改"
        #expect(throws: FocusAssignmentError.staleSession) { try state.applyAssignments(stale) }
        #expect(state.journal[0].sessions.allSatisfy { $0.taskID == nil })
        let missing = FocusMatchingPlan(changes: [.init(session: first, targetTaskID: "absent")])
        #expect(throws: FocusAssignmentError.missingTask) { try state.applyAssignments(missing) }
        let repeated = FocusMatchingPlan(changes: [.init(session: first, targetTaskID: "a"), .init(session: first, targetTaskID: "a")])
        #expect(throws: FocusAssignmentError.duplicateSession) { try state.applyAssignments(repeated) }
    }

    @Test func concurrentReassignmentBlocksWholeUndoWithoutOverwriting() throws {
        var state = AppData()
        state.tasks = [FocusTask(id: "a", title: "补课"), FocusTask(id: "b", title: "网站")]
        state.journal = [JournalDay(date: "2026-10-14", sessions: [FocusSession(id: "1"), FocusSession(id: "2")])]
        let plan = FocusMatchingPlan(changes: state.journal[0].sessions.map { .init(session: $0, targetTaskID: "a") })
        let transaction = try state.applyAssignments(plan)
        let concurrent = FocusMatchingPlan(changes: [.init(session: state.journal[0].sessions[1], targetTaskID: "b")])
        try state.applyAssignments(concurrent)
        #expect(throws: FocusAssignmentError.staleSession) { try state.undoAssignments(transaction) }
        #expect(state.journal[0].sessions[0].taskID == "a")
        #expect(state.journal[0].sessions[1].taskID == "b")
    }
}
