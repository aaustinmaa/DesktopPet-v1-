import Foundation
import Testing
@testable import SuWuDu

@MainActor private final class MultiTaskSilentSound: SoundPlaying {
    func play(_ id: String, complete: Bool) {}
    func stop() {}
}

struct MultiTaskPanelTests {
    private let split = [FocusTaskAllocation(taskID: "a", share: 0.4), FocusTaskAllocation(taskID: "b", share: 0.6)]
    private var tasks: [FocusTask] {
        [FocusTask(id: "a", title: "补课"), FocusTask(id: "b", title: "网站"), FocusTask(id: "c", title: "笔记")]
    }

    @Test @MainActor func nextRoundSelectionDoesNotChangeCapturedMinutesAndRecovery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DataStore(directory: directory)
        var data = AppData(); data.settings.microbreaks = false; data.tasks = tasks
        let model = AppModel(store: store, loaded: data, sound: MultiTaskSilentSound())
        #expect(model.selectFocusTasks(split))
        model.startFocus()
        #expect(FocusTaskAllocationRules.same(try #require(model.data.focus).allocations, split))
        let next = FocusTaskAllocationRules.equal(["b", "c"])
        #expect(model.selectFocusTasks(next))
        model.pause()
        let restored = AppModel(store: store, loaded: try store.load().0, sound: MultiTaskSilentSound())
        #expect(restored.paused)
        #expect(FocusTaskAllocationRules.same(try #require(restored.data.focus).allocations, split))
        #expect(FocusTaskAllocationRules.same(restored.data.currentAllocations, next))
        restored.resume(); restored.pause()
        #expect(FocusTaskAllocationRules.same(try #require(restored.data.focus).allocations, split))
        restored.stopFocus(); restored.startFocus(); restored.pause()
        #expect(FocusTaskAllocationRules.same(try #require(store.load().0.focus).allocations, next))
    }

    @Test @MainActor func minutesAllocationPersistsFractionalTotalsAndRatioOnlyChangesUndo() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DataStore(directory: directory)
        var data = AppData(); data.tasks = tasks
        let original = FocusSession(id: "one", minutes: 25, countsTowardGoal: false, notes: "保留说明",
                                    actualMinutes: 25, completedPomodoro: true)
        data.journal = [JournalDay(date: "2026-10-14", adjustment: 2, notes: "当天笔记", sessions: [original])]
        let model = AppModel(store: store, loaded: data, sound: MultiTaskSilentSound())
        #expect(model.assignFocusSessions([original], allocations: split))
        let saved = try store.load().0
        #expect(saved.taskSummaries().first { $0.taskID == "a" }?.completedPomodoros == 0.4)
        #expect(saved.taskSummaries().first { $0.taskID == "b" }?.completedPomodoros == 0.6)
        #expect(saved.taskSummaries().first { $0.taskID == "a" }?.minutes == 10)
        #expect(saved.taskSummaries().first { $0.taskID == "b" }?.minutes == 15)
        let session = model.data.journal[0].sessions[0]
        model.matchingPlan = FocusMatchingPlan(changes: [FocusAssignmentChange(session: session,
            targetAllocations: FocusTaskAllocationRules.equal(["a", "b"]), reason: "这颗两个任务均分")])
        #expect(model.applyFocusMatch())
        #expect(model.data.taskSummaries().first { $0.taskID == "a" }?.minutes == 12.5)
        #expect(model.undoFocusAssignments())
        let undone = try store.load().0.journal[0]
        #expect(FocusTaskAllocationRules.same(undone.sessions[0].allocations, split))
        #expect(undone.sessions[0].assignmentRevision == 3)
        #expect(undone.sessions[0].minutes == original.minutes && undone.sessions[0].notes == original.notes)
        #expect(undone.sessions[0].countsTowardGoal == original.countsTowardGoal)
        #expect(undone.adjustment == 2 && undone.notes == "当天笔记")
    }

    @Test @MainActor func draftNotesAndMinuteChangesPreserveLiveTaskSplit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DataStore(directory: directory)
        var data = AppData(); data.tasks = tasks
        let original = FocusSession(id: "one", notes: "原备注", actualMinutes: 25, completedPomodoro: true)
        data.journal = [JournalDay(date: FocusAccounting.key(Date()), sessions: [original])]
        let model = AppModel(store: store, loaded: data, sound: MultiTaskSilentSound())
        let editor = JournalEditor(model: model)
        var draft = editor.day; draft.sessions[0].notes = "新的备注"; draft.sessions[0].minutes = 20
        editor.edit(draft)
        #expect(model.assignFocusSessions([original], allocations: split))
        #expect(editor.save())
        let saved = try store.load().0
        #expect(FocusTaskAllocationRules.same(saved.journal[0].sessions[0].allocations, split))
        #expect(saved.journal[0].sessions[0].notes == "新的备注")
        #expect(saved.taskSummaries().first { $0.taskID == "a" }?.minutes == 8)
        #expect(saved.taskSummaries().first { $0.taskID == "b" }?.minutes == 12)
        let exported = JournalExport.markdown(saved.journal, tasks: tasks)
        #expect(exported.contains("补课") && exported.contains("网站"))
        #expect(exported.contains("8") && exported.contains("12"))
        #expect(!exported.contains("%"))
    }

    @Test @MainActor func staleBatchAndMissingTasksDoNotPartiallyAssign() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DataStore(directory: directory)
        var data = AppData(); data.tasks = tasks
        let sessions = [FocusSession(id: "one"), FocusSession(id: "two")]
        data.journal = [JournalDay(date: "2026-10-14", sessions: sessions)]
        let model = AppModel(store: store, loaded: data, sound: MultiTaskSilentSound())
        #expect(model.assignFocusSessions([sessions[0]], allocations: split))
        let before = model.data.journal[0].sessions
        let persistedBefore = try store.load().0.journal[0].sessions
        #expect(!model.assignFocusSessions(sessions, allocations: FocusTaskAllocationRules.equal(["a", "b"])))
        #expect(model.data.journal[0].sessions == before)
        #expect(!model.assignFocusSessions(before, allocations: FocusTaskAllocationRules.equal(["a", "missing"])))
        #expect(try store.load().0.journal[0].sessions == persistedBefore)
        #expect(!model.deleteFocusTask("a"))
        #expect(!model.deleteFocusTask("b"))
    }

    @Test @MainActor func failedMinuteAllocationAndSelectionSaveRestorePreviousState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DataStore(directory: directory)
        var data = AppData(); data.tasks = tasks
        data.currentTaskID = "a"
        data.journal = [JournalDay(date: "2026-10-14", sessions: [FocusSession(id: "one")])]
        let model = AppModel(store: store, loaded: data, sound: MultiTaskSilentSound())
        #expect(model.assignFocusSessions(data.journal[0].sessions, allocations: split))
        let before = model.data.journal[0].sessions
        try FileManager.default.removeItem(at: directory); try Data().write(to: directory)
        #expect(!model.selectFocusTasks(split))
        #expect(model.data.currentAllocations == FocusTaskAllocationRules.equal(["a"]))
        #expect(!model.assignFocusSessions(before, allocations: FocusTaskAllocationRules.equal(["a", "b"])))
        #expect(model.data.journal[0].sessions == before)
        #expect(!model.undoFocusAssignments())
        #expect(model.canUndoFocusAssignments)
        #expect(model.data.journal[0].sessions == before)
    }
}
