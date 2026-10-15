import Foundation
import Testing
@testable import SuWuDu

struct FocusAllocationTests {
    private let half = [FocusTaskAllocation(taskID: "a", share: 0.5), FocusTaskAllocation(taskID: "b", share: 0.5)]
    private let quarter = [FocusTaskAllocation(taskID: "a", share: 0.25), FocusTaskAllocation(taskID: "b", share: 0.75)]

    private func state(sessions: [FocusSession]) -> AppData {
        var result = AppData()
        result.tasks = [FocusTask(id: "a", title: "课程"), FocusTask(id: "b", title: "网站")]
        result.journal = [JournalDay(date: "2026-10-14", sessions: sessions)]
        return result
    }

    private func setStoredAllocations(_ allocations: [FocusTaskAllocation], at location: String, in data: inout AppData) {
        switch location {
        case "current": data.currentTaskAllocations = allocations
        case "run": data.focus?.taskAllocations = allocations
        default: data.journal[0].sessions[0].taskAllocations = allocations
        }
    }

    @Test func oldSingleTaskAssignmentsMigrateAndNewVectorsRoundTrip() throws {
        var original = state(sessions: [FocusSession(id: "old", taskID: "a")])
        original.currentTaskID = "a"
        original.focus = FocusRun(startedAt: Date(), planned: 25, remaining: 100, taskID: "b")
        var object = try #require(JSONSerialization.jsonObject(with: DataStore.encoder.encode(original)) as? [String: Any])
        object.removeValue(forKey: "currentTaskAllocations")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        var migrated = try DataStore.decoder.decode(AppData.self, from: legacy)
        #expect(migrated.currentAllocations == [.init(taskID: "a", share: 1)])
        #expect(migrated.focus?.allocations == [.init(taskID: "b", share: 1)])
        #expect(migrated.journal[0].sessions[0].allocations == [.init(taskID: "a", share: 1)])

        migrated.currentAllocations = half
        migrated.focus?.allocations = quarter
        migrated.journal[0].sessions[0].allocations = quarter
        let restored = try DataStore.decoder.decode(AppData.self, from: DataStore.encoder.encode(migrated))
        #expect(restored.currentTaskID == nil)
        #expect(restored.focus?.taskID == nil)
        #expect(restored.journal[0].sessions[0].taskID == nil)
        #expect(restored.currentAllocations == half)
        #expect(restored.focus?.allocations == quarter)
        #expect(restored.journal[0].sessions[0].allocations == quarter)

        migrated.currentAllocations = [.init(taskID: "b", share: 1)]
        #expect(migrated.currentTaskID == "b")
        migrated.journal[0].sessions[0].allocations = []
        #expect(migrated.journal[0].sessions[0].taskID == nil)
        #expect(migrated.journal[0].sessions[0].allocations.isEmpty)
    }

    @Test func equalSharesAreStableAndOnlyRoundingToleranceIsNormalized() throws {
        let thirds = FocusTaskAllocationRules.equal(["c", "a", "b", "a"])
        #expect(thirds.map(\.taskID) == ["a", "b", "c"])
        #expect(thirds.allSatisfy { $0.share == 1.0 / 3.0 })
        let rounded = try FocusTaskAllocationRules.normalized([
            .init(taskID: "b", share: 0.6666667), .init(taskID: "a", share: 0.3333334)
        ])
        #expect(rounded.map(\.taskID) == ["a", "b"])
        #expect(abs(rounded.reduce(0) { $0 + $1.share } - 1) < 1e-12)
        #expect(FocusTaskAllocationRules.same(half, Array(half.reversed())))
        #expect(!FocusTaskAllocationRules.same(half, quarter))
        #expect(try FocusTaskAllocationRules.normalized([]).isEmpty)
        let invalidSets: [[FocusTaskAllocation]] = [
            [.init(taskID: "a", share: 1), .init(taskID: "a", share: 1)],
            [.init(taskID: "a", share: 0.6), .init(taskID: "b", share: 0.6)],
            [.init(taskID: "a", share: 0), .init(taskID: "b", share: 1)],
            [.init(taskID: "a", share: -0.1), .init(taskID: "b", share: 1.1)],
            [.init(taskID: " ", share: 1)], [.init(taskID: "a", share: .nan)],
            [.init(taskID: "a", share: .infinity)]
        ]
        for invalid in invalidSets {
            #expect(throws: FocusAssignmentError.invalidAllocations) { try FocusTaskAllocationRules.normalized(invalid) }
        }
    }

    @Test func taskTotalsUseSharesWithoutRoundingAndIgnoreConversionRows() {
        let full = FocusSession(id: "full", minutes: 25, taskAllocations: quarter,
            actualMinutes: 25, completedPomodoro: true)
        let partial = FocusSession(id: "partial", source: "partial", minutes: 10, countsTowardGoal: false,
            taskAllocations: half, actualMinutes: 10, completedPomodoro: false)
        let conversion = FocusSession(id: "conversion", source: "manual", minutes: 25,
            taskAllocations: half, actualMinutes: 0, completedPomodoro: true)
        let summaries = state(sessions: [full, partial, conversion]).taskSummaries()
        #expect(summaries.first { $0.taskID == "a" }?.completedPomodoros == 0.25)
        #expect(summaries.first { $0.taskID == "b" }?.completedPomodoros == 0.75)
        #expect(summaries.first { $0.taskID == "a" }?.minutes == 11.25)
        #expect(summaries.first { $0.taskID == "b" }?.minutes == 23.75)
        #expect(summaries.reduce(0) { $0 + $1.completedPomodoros } == 1)
        #expect(summaries.reduce(0) { $0 + $1.minutes } == 35)
    }

    @Test func activeAllocationsCarryIntoCompletedAndPartialRecordsAcrossRollover() {
        let start = Calendar.current.date(bySettingHour: 20, minute: 50, second: 0, of: Date())!
        let end = start.addingTimeInterval(1500)
        var completed = state(sessions: [])
        FocusAccounting.record(segments: [.init(start: start, end: end)], planned: 25, completed: true,
            startedAt: start, endedAt: end, taskAllocations: quarter, journal: &completed.journal)
        let completedRows = completed.journal.flatMap(\.sessions).filter(\.isCompletedPomodoro)
        #expect(completedRows.count == 1)
        #expect(completedRows.first?.allocations == quarter)
        #expect(completed.taskSummaries().reduce(0) { $0 + $1.completedPomodoros } == 1)
        #expect(completed.taskSummaries().reduce(0) { $0 + $1.minutes } == 25)

        var partial = state(sessions: [])
        FocusAccounting.record(segments: [.init(start: start, end: end)], planned: 30, completed: false,
            startedAt: start, endedAt: end, taskAllocations: half, journal: &partial.journal)
        let partialRows = partial.journal.flatMap(\.sessions).filter(\.isPartial)
        #expect(partialRows.count == 2)
        #expect(partialRows.allSatisfy { $0.allocations == half && $0.taskID == nil })
        #expect(partial.taskSummaries().reduce(0) { $0 + $1.completedPomodoros } == 0)
        #expect(partial.taskSummaries().reduce(0) { $0 + $1.minutes } == 25)
    }

    @Test func batchApplyAndUndoRestoreEveryShareAndKeepRevisionsMonotonic() throws {
        let first = FocusSession(id: "one", taskAllocations: quarter, assignmentSource: "current", assignmentRevision: 3)
        let second = FocusSession(id: "two", taskID: "a")
        var data = state(sessions: [first, second])
        let plan = FocusMatchingPlan(changes: [
            .init(session: first, targetAllocations: half), .init(session: second, targetAllocations: [])
        ], source: "manual")
        let transaction = try data.applyAssignments(plan)
        #expect(data.journal[0].sessions[0].allocations == half)
        #expect(data.journal[0].sessions[0].assignmentRevision == 4)
        #expect(data.journal[0].sessions[1].allocations.isEmpty)
        try data.undoAssignments(transaction)
        #expect(data.journal[0].sessions[0].allocations == quarter)
        #expect(data.journal[0].sessions[0].assignmentSource == "current")
        #expect(data.journal[0].sessions[0].assignmentRevision == 5)
        #expect(data.journal[0].sessions[1].allocations == [.init(taskID: "a", share: 1)])
        #expect(throws: FocusAssignmentError.staleSession) { try data.applyAssignments(plan) }
    }

    @Test func invalidAllocationInAnyChangeRejectsWholeBatch() {
        let first = FocusSession(id: "one", taskID: "a")
        let second = FocusSession(id: "two", taskAllocations: half)
        var data = state(sessions: [first, second])
        let plan = FocusMatchingPlan(changes: [
            .init(session: first, targetAllocations: quarter),
            .init(session: second, targetAllocations: [.init(taskID: "a", share: 0.8), .init(taskID: "b", share: 0.4)])
        ])
        #expect(throws: FocusAssignmentError.invalidAllocations) { try data.applyAssignments(plan) }
        #expect(data.journal[0].sessions == [first, second])
    }

    @Test func changedPercentagesWithoutRevisionStillBlockApplyAndUndoAtomically() throws {
        let first = FocusSession(id: "one", taskAllocations: half)
        let second = FocusSession(id: "two", taskAllocations: half)
        var data = state(sessions: [first, second])
        let preview = FocusMatchingPlan(changes: [FocusAssignmentChange(sessionID: "one", targetAllocations: [],
            expectedAllocations: half, expectedNotes: "")])
        data.journal[0].sessions[0].allocations = quarter
        #expect(throws: FocusAssignmentError.staleSession) { try data.applyAssignments(preview) }
        let transaction = try data.applyAssignments(.init(changes: data.journal[0].sessions.map {
            .init(session: $0, targetAllocations: quarter)
        }))
        data.journal[0].sessions[1].allocations = half
        #expect(throws: FocusAssignmentError.staleSession) { try data.undoAssignments(transaction) }
        #expect(data.journal[0].sessions[0].allocations == quarter)
        #expect(data.journal[0].sessions[1].allocations == half)
        #expect(data.journal[0].sessions[0].assignmentRevision == 1)
    }

    @Test func windowsImportPreservesExistingMultiTaskSharesAndSelection() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var original = state(sessions: [FocusSession(id: "one", taskAllocations: quarter,
            assignmentSource: "manual", assignmentRevision: 2, actualMinutes: 25, completedPomodoro: true)])
        original.currentAllocations = half
        let bytes = try JSONSerialization.data(withJSONObject: ["Days": [["Date": "2026-10-14", "Sessions": [
            ["Id": "one", "PlannedMinutes": 20, "CountsTowardGoal": true]
        ]]]])
        try bytes.write(to: folder.appendingPathComponent("focus-journal.json"))
        let imported = try WindowsImport.read(folder, into: original)
        #expect(imported.currentAllocations == half)
        #expect(imported.journal[0].sessions[0].allocations == quarter)
        #expect(imported.journal[0].sessions[0].taskID == nil)
        #expect(imported.journal[0].sessions[0].assignmentRevision == 2)
        #expect(imported.taskSummaries().first { $0.taskID == "a" }?.minutes == 5)
        #expect(imported.taskSummaries().first { $0.taskID == "b" }?.minutes == 15)
    }

    @Test(arguments: ["current", "run", "session"])
    func invalidPersistedAllocationVectorRecoversValidBackup(location: String) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try DataStore(directory: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        var original = state(sessions: [FocusSession(id: "legacy", taskID: "removed-task")])
        original.currentTaskID = "removed-task"
        original.focus = FocusRun(startedAt: Date(), planned: 25, remaining: 100, taskID: "removed-task")
        try store.save(original)
        try store.save(original)
        let validBytes = try Data(contentsOf: store.file)
        var corrupted = original
        setStoredAllocations([.init(taskID: "a", share: 0.8), .init(taskID: "b", share: 0.4)], at: location, in: &corrupted)
        let corruptBytes = try DataStore.encoder.encode(corrupted)
        try corruptBytes.write(to: store.file)

        let (restored, warning) = try store.load()
        #expect(warning?.contains("备份") == true)
        #expect(restored.currentAllocations == [.init(taskID: "removed-task", share: 1)])
        #expect(restored.focus?.allocations == [.init(taskID: "removed-task", share: 1)])
        #expect(restored.journal[0].sessions[0].allocations == [.init(taskID: "removed-task", share: 1)])
        #expect(try Data(contentsOf: store.file) == validBytes)
        let preserved = try #require(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.hasPrefix("app-state-corrupt-") })
        #expect(try Data(contentsOf: preserved) == corruptBytes)
    }

    @Test func invalidAllocationSaveLeavesPrimaryAndBackupUntouched() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try DataStore(directory: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        var original = state(sessions: [FocusSession(id: "one", taskAllocations: quarter)])
        original.focus = FocusRun(startedAt: Date(), planned: 25, remaining: 100, taskAllocations: half)
        original.currentAllocations = [.init(taskID: "removed-task", share: 1)]
        try store.save(original)
        original.taskMemos = "第二个有效版本"
        try store.save(original)
        let primary = try Data(contentsOf: store.file)
        let backupURL = store.file.appendingPathExtension("backup")
        let backup = try Data(contentsOf: backupURL)
        let invalidVectors: [[FocusTaskAllocation]] = [
            [.init(taskID: "a", share: 0.8), .init(taskID: "b", share: 0.4)],
            [.init(taskID: "a", share: 0.5), .init(taskID: "a", share: 0.5)],
            [.init(taskID: "a", share: -0.5), .init(taskID: "b", share: 1.5)],
            [.init(taskID: "a", share: .nan)]
        ]
        for location in ["current", "run", "session"] {
            for allocations in invalidVectors {
                var invalid = original
                setStoredAllocations(allocations, at: location, in: &invalid)
                #expect(throws: FocusAssignmentError.invalidAllocations) { try store.save(invalid) }
                #expect(try Data(contentsOf: store.file) == primary)
                #expect(try Data(contentsOf: backupURL) == backup)
            }
        }
        #expect(try store.load().0.currentAllocations == original.currentAllocations)
    }
}
