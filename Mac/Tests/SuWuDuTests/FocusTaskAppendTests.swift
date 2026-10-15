import Foundation
import Testing
@testable import SuWuDu

@MainActor private final class AppendSilentSound: SoundPlaying {
    func play(_ id: String, complete: Bool) {}
    func stop() {}
}

struct FocusTaskAppendTests {
    private let instant = Date(timeIntervalSince1970: 1_792_000_000)

    private func session(_ id: String, tasks: [String] = []) -> FocusSession {
        FocusSession(id: id, startedAt: instant, completedAt: instant.addingTimeInterval(1500),
                     minutes: 25, notes: "备注 \(id)", taskAllocations: FocusTaskAllocationRules.equal(tasks),
                     actualMinutes: 25, completedPomodoro: true)
    }

    @MainActor private func fixture(_ sessions: [FocusSession]) throws -> (URL, DataStore, AppModel) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try DataStore(directory: directory)
        var data = AppData()
        data.tasks = [FocusTask(id: "a", title: "补课"), FocusTask(id: "b", title: "网站"), FocusTask(id: "c", title: "笔记")]
        data.journal = [JournalDay(date: "2026-10-14", adjustment: 7, notes: "当天备注", sessions: sessions)]
        return (directory, store, AppModel(store: store, loaded: data, sound: AppendSilentSound()))
    }

    @Test @MainActor func appendPreservesEachRecordsOwnTasksAndUndoesTheWholeBatch() throws {
        var first = session("one", tasks: ["a"]); first.countsTowardGoal = false
        let originals = [first, session("two", tasks: ["b"]), session("three")]
        let (directory, store, model) = try fixture(originals)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(model.appendFocusSessions(originals, taskIDs: ["c"]))
        let saved = try store.load().0
        #expect(saved.journal[0].sessions[0].allocations == FocusTaskAllocationRules.equal(["a", "c"]))
        #expect(saved.journal[0].sessions[1].allocations == FocusTaskAllocationRules.equal(["b", "c"]))
        #expect(saved.journal[0].sessions[2].allocations == FocusTaskAllocationRules.equal(["c"]))
        #expect(saved.taskSummaries().first { $0.taskID == "a" }?.minutes == 12.5)
        #expect(saved.taskSummaries().first { $0.taskID == "b" }?.minutes == 12.5)
        #expect(saved.taskSummaries().first { $0.taskID == "c" }?.minutes == 50)
        for (before, after) in zip(originals, saved.journal[0].sessions) {
            #expect(before.notes == after.notes && before.minutes == after.minutes)
            #expect(before.startedAt == after.startedAt && before.completedAt == after.completedAt)
            #expect(before.countsTowardGoal == after.countsTowardGoal && before.actualMinutes == after.actualMinutes)
        }
        #expect(saved.journal[0].adjustment == 7 && saved.journal[0].notes == "当天备注")
        #expect(model.undoFocusAssignments())
        for (before, after) in zip(originals, model.data.journal[0].sessions) {
            #expect(before.allocations == after.allocations)
            #expect(before.assignmentSource == after.assignmentSource)
        }
    }

    @Test @MainActor func repeatedAddPreservesCustomMinutesRevisionAndExistingUndo() throws {
        let original = session("one")
        let (directory, store, model) = try fixture([original])
        defer { try? FileManager.default.removeItem(at: directory) }
        let uneven = [FocusTaskAllocation(taskID: "a", share: 0.4), FocusTaskAllocation(taskID: "b", share: 0.6)]
        #expect(model.assignFocusSessions([original], allocations: uneven))
        let before = model.data.journal[0].sessions
        let persistedBefore = try store.load().0.journal[0].sessions

        #expect(model.appendFocusSessions(before, taskIDs: ["a", "b", "a"]))
        #expect(model.data.journal[0].sessions == before)
        #expect(try store.load().0.journal[0].sessions == persistedBefore)
        #expect(model.canUndoFocusAssignments)
        #expect(model.undoFocusAssignments())
        #expect(model.data.journal[0].sessions[0].allocations.isEmpty)
    }

    @Test @MainActor func multipleAdditionsDeduplicateAndEqualizeOnlyChangedRecords() throws {
        var first = session("one", tasks: ["a", "b"])
        first.allocations = [FocusTaskAllocation(taskID: "a", share: 0.4), FocusTaskAllocation(taskID: "b", share: 0.6)]
        var second = session("two", tasks: ["b", "c"])
        second.allocations = [FocusTaskAllocation(taskID: "b", share: 0.3), FocusTaskAllocation(taskID: "c", share: 0.7)]
        let originals = [first, second]
        let (directory, _, model) = try fixture(originals)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(model.appendFocusSessions(originals, taskIDs: ["b", "c", "c"]))
        #expect(model.data.journal[0].sessions[0].allocations == FocusTaskAllocationRules.equal(["a", "b", "c"]))
        #expect(model.data.journal[0].sessions[1] == second)
        #expect(model.focusAssignmentUndo?.entries.count == 1)
        #expect(model.undoFocusAssignments())
        #expect(model.data.journal[0].sessions[0].allocations == first.allocations)
        #expect(model.data.journal[0].sessions[1] == second)
    }

    @Test @MainActor func staleAlreadyAssociatedRecordRejectsOtherAdditionsAtomically() throws {
        let originals = [session("one", tasks: ["a", "c"]), session("two", tasks: ["b"])]
        let (directory, store, model) = try fixture(originals)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(model.assignFocusSessions([originals[0]], allocations: [
            FocusTaskAllocation(taskID: "a", share: 0.2), FocusTaskAllocation(taskID: "c", share: 0.8)
        ]))
        let before = model.data.journal[0].sessions
        let persistedBefore = try store.load().0.journal[0].sessions

        #expect(!model.appendFocusSessions(originals, taskIDs: ["c"]))
        #expect(model.data.journal[0].sessions == before)
        #expect(try store.load().0.journal[0].sessions == persistedBefore)
        #expect(model.undoFocusAssignments())
        #expect(model.data.journal[0].sessions[0].allocations == originals[0].allocations)
    }

    @Test @MainActor func unknownTaskAndDuplicateRecordRejectTheEntireBatch() throws {
        let originals = [session("one", tasks: ["a"]), session("two", tasks: ["b"])]
        let (directory, _, model) = try fixture(originals)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(!model.appendFocusSessions(originals, taskIDs: ["c", "missing"]))
        #expect(model.data.journal[0].sessions == originals)
        #expect(!model.appendFocusSessions(originals + [originals[0]], taskIDs: ["c"]))
        #expect(model.data.journal[0].sessions == originals)
        #expect(!model.canUndoFocusAssignments)
    }

    @Test @MainActor func persistenceFailureRollsBackAdditionAndPreservesPreviousUndo() throws {
        let original = session("one")
        let (directory, _, model) = try fixture([original])
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(model.assignFocusSessions([original], to: "a"))
        let before = model.data.journal[0].sessions
        try FileManager.default.removeItem(at: directory)
        try Data().write(to: directory)

        #expect(!model.appendFocusSessions(before, taskIDs: ["b"]))
        #expect(model.data.journal[0].sessions == before)
        #expect(model.canUndoFocusAssignments)
        #expect(model.focusAssignmentUndo?.entries.first?.appliedAllocations == FocusTaskAllocationRules.equal(["a"]))
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #expect(model.undoFocusAssignments())
        #expect(model.data.journal[0].sessions[0].allocations.isEmpty)
    }

    @Test @MainActor func conversionRecordsAreExcludedFromAppendAndUndo() throws {
        let conversion = FocusSession(id: "converted", minutes: 25, actualMinutes: 0, completedPomodoro: false)
        let originals = [session("one", tasks: ["a"]), conversion]
        let (directory, _, model) = try fixture(originals)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(model.appendFocusSessions(originals, taskIDs: ["b"]))
        #expect(model.data.journal[0].sessions[1] == conversion)
        #expect(model.focusAssignmentUndo?.entries.count == 1)
        #expect(model.undoFocusAssignments())
        #expect(model.data.journal[0].sessions[0].allocations == originals[0].allocations)
        #expect(model.data.journal[0].sessions[1] == conversion)
    }
}
