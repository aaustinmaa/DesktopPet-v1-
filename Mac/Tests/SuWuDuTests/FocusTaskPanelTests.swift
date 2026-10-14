import Foundation
import Testing
@testable import SuWuDu

@MainActor private final class FocusPanelSilentSound: SoundPlaying {
    func play(_ id: String, complete: Bool) {}
    func stop() {}
}

struct FocusTaskPanelTests {
    @Test @MainActor func changingSelectionAppliesToNextRunAndRecoveryKeepsCapturedTask() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DataStore(directory: directory)
        var data = AppData()
        data.settings.microbreaks = false
        data.tasks = [FocusTask(id: "a", title: "补课"), FocusTask(id: "b", title: "网站")]
        data.currentTaskID = "a"
        let model = AppModel(store: store, loaded: data, sound: FocusPanelSilentSound())
        model.startFocus()
        #expect(model.data.focus?.taskID == "a")
        #expect(model.selectFocusTask("b"))
        #expect(model.data.focus?.taskID == "a")
        model.pause()
        let restored = AppModel(store: store, loaded: try store.load().0, sound: FocusPanelSilentSound())
        #expect(restored.paused)
        #expect(restored.data.currentTaskID == "b")
        #expect(restored.data.focus?.taskID == "a")
        restored.resume()
        restored.pause()
        #expect(restored.data.focus?.taskID == "a")
        restored.stopFocus()
        restored.startFocus()
        #expect(restored.data.focus?.taskID == "b")
        #expect(try store.load().0.focus?.taskID == "b")
    }

    @Test @MainActor func manualAssignmentPreviewApplyAndUndoPersistWithoutChangingJournalFields() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DataStore(directory: directory)
        var data = AppData()
        data.tasks = [FocusTask(id: "a", title: "补课"), FocusTask(id: "b", title: "网站")]
        let sessions = [FocusSession(id: "one", minutes: 25, countsTowardGoal: false, notes: "第一页\n推导",
                                    actualMinutes: 25, completedPomodoro: true),
                        FocusSession(id: "two", source: "manual", minutes: 12, notes: "保留说明")]
        data.journal = [JournalDay(date: "2026-10-14", adjustment: 3, notes: "每日备忘", sessions: sessions)]
        let model = AppModel(store: store, loaded: data, sound: FocusPanelSilentSound())
        #expect(model.assignFocusSessions(sessions, to: "a"))
        #expect(try store.load().0.journal[0].sessions.allSatisfy { $0.taskID == "a" })
        model.matchingPlan = FocusMatchingPlan(changes: model.data.journal[0].sessions.map {
            FocusAssignmentChange(session: $0, targetTaskID: "b", reason: "整体回顾")
        })
        #expect(model.applyFocusMatch())
        #expect(try store.load().0.journal[0].sessions.allSatisfy { $0.taskID == "b" })
        #expect(model.undoFocusAssignments())
        let saved = try store.load().0.journal[0]
        #expect(saved.sessions.allSatisfy { $0.taskID == "a" && $0.assignmentSource == "manual" })
        #expect(saved.sessions.map(\.notes) == sessions.map(\.notes))
        #expect(saved.sessions.map(\.minutes) == sessions.map(\.minutes))
        #expect(saved.sessions.map(\.countsTowardGoal) == sessions.map(\.countsTowardGoal))
        #expect(saved.notes == "每日备忘")
        #expect(saved.adjustment == 3)
        #expect(!model.canUndoFocusAssignments)
    }

    @Test @MainActor func draftNotesMergeWithExternalTaskAssignmentAndNewAutomaticRecord() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DataStore(directory: directory)
        var data = AppData()
        data.tasks = [FocusTask(id: "a", title: "补课")]
        let original = FocusSession(id: "one", notes: "原备注", actualMinutes: 25, completedPomodoro: true)
        data.journal = [JournalDay(date: FocusAccounting.key(Date()), sessions: [original])]
        let model = AppModel(store: store, loaded: data, sound: FocusPanelSilentSound())
        let editor = JournalEditor(model: model)
        var draft = editor.day
        draft.notes = "编辑中的每日笔记"
        draft.sessions[0].notes = "新进展"
        draft.sessions[0].minutes = 20
        editor.edit(draft)
        #expect(model.assignFocusSessions([original], to: "a"))
        var live = model.data.journalDay(editor.dateKey)
        live.sessions.append(FocusSession(id: "automatic-new", notes: "计时完成", actualMinutes: 25, completedPomodoro: true))
        #expect(model.saveDay(live))
        #expect(editor.save())
        let saved = try store.load().0.journalDay(editor.dateKey)
        #expect(saved.notes == "编辑中的每日笔记")
        #expect(saved.sessions.count == 2)
        let merged = try #require(saved.sessions.first { $0.id == "one" })
        #expect(merged.notes == "新进展")
        #expect(merged.taskID == "a")
        #expect(merged.assignmentRevision == 1)
        #expect(merged.minutes == 20)
        #expect(merged.actualMinutes == 20)
        #expect(saved.sessions.first { $0.id == "automatic-new" }?.notes == "计时完成")
        #expect(editor.draft == nil)
    }

    @Test @MainActor func repeatedSaveOfEditedAndDeletedPartialDetailChangesAccountingOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DataStore(directory: directory)
        var data = AppData()
        data.tasks = [FocusTask(id: "a", title: "补课"), FocusTask(id: "b", title: "网站")]
        data.journal = [JournalDay(date: "2026-10-14", sessions: [
            FocusSession(id: "partial-a", source: "partial", minutes: 10, countsTowardGoal: false,
                         taskID: "a", actualMinutes: 10, completedPomodoro: false),
            FocusSession(id: "partial-b", source: "partial", minutes: 15, countsTowardGoal: false,
                         taskID: "b", actualMinutes: 15, completedPomodoro: false),
            FocusSession(id: "conversion", source: "manual", minutes: 25, actualMinutes: 0, completedPomodoro: false)
        ])]
        let model = AppModel(store: store, loaded: data, sound: FocusPanelSilentSound())
        var edited = model.data.journal[0]
        edited.sessions[0].minutes = 12
        #expect(model.saveDay(edited))
        #expect(model.data.journal[0].total == 27)
        #expect(model.data.taskSummaries().first { $0.taskID == "a" }?.minutes == 12)
        #expect(model.saveDay(model.data.journal[0]))
        #expect(model.data.journal[0].total == 27)
        var deleted = model.data.journal[0]
        deleted.sessions.removeAll { $0.id == "partial-a" }
        #expect(model.saveDay(deleted))
        #expect(model.data.journal[0].total == 15)
        #expect(model.saveDay(model.data.journal[0]))
        let restored = try store.load().0
        #expect(restored.journal[0].total == 15)
        #expect(restored.taskSummaries().first { $0.taskID == "a" }?.minutes == 0)
        #expect(restored.taskSummaries().first { $0.taskID == "b" }?.minutes == 15)
    }

    @Test @MainActor func failedPersistenceRollsBackAssignmentUndoTaskAndPartialEdits() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DataStore(directory: directory)
        var data = AppData()
        data.tasks = [FocusTask(id: "a", title: "补课"), FocusTask(id: "b", title: "网站")]
        data.journal = [JournalDay(date: "2026-10-14", adjustment: 10, sessions: [
            FocusSession(id: "full", notes: "保留", actualMinutes: 25, completedPomodoro: true),
            FocusSession(id: "partial", source: "partial", minutes: 10, countsTowardGoal: false,
                         actualMinutes: 10, completedPomodoro: false)
        ])]
        let model = AppModel(store: store, loaded: data, sound: FocusPanelSilentSound())
        #expect(model.assignFocusSessions([data.journal[0].sessions[0]], to: "a"))
        let committed = model.data.journal[0]
        try FileManager.default.removeItem(at: directory)
        try Data().write(to: directory)
        #expect(!model.undoFocusAssignments())
        #expect(model.canUndoFocusAssignments)
        #expect(model.data.journal[0].sessions == committed.sessions)
        #expect(!model.assignFocusSessions([committed.sessions[0]], to: "b"))
        #expect(model.data.journal[0].sessions == committed.sessions)
        #expect(!model.saveFocusTask(FocusTask(id: "new", title: "新增任务")))
        #expect(model.data.tasks?.map(\.id) == ["a", "b"])
        var edited = committed
        edited.sessions[1].minutes = 12
        #expect(!model.saveDay(edited))
        #expect(model.data.journal[0].sessions == committed.sessions)
        #expect(model.data.journal[0].total == committed.total)
        #expect(model.error != nil)
    }
}
