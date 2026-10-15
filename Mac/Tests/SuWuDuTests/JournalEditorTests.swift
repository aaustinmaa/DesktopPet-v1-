import Foundation
import Testing
@testable import SuWuDu

struct JournalEditorTests {
    @Test @MainActor func zeroMinuteEditsPreserveRecordingSourcesAfterSavingAndExporting() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DataStore(directory: directory)
        let model = AppModel(store: store, loaded: AppData())
        let editor = JournalEditor(model: model)
        var original = editor.day
        original.sessions = [
            FocusSession(id: "automatic", actualMinutes: 25, completedPomodoro: true),
            FocusSession(id: "manual", source: "manual", actualMinutes: 25, completedPomodoro: true),
            FocusSession(id: "conversion", source: "manual", actualMinutes: 0, completedPomodoro: false),
            FocusSession(id: "partial", source: "partial", minutes: 0, countsTowardGoal: false,
                         actualMinutes: 0, completedPomodoro: false)
        ]
        #expect(model.saveDay(original))
        var edited = editor.day
        edited.sessions[0].minutes = 0
        edited.sessions[1].minutes = 0
        editor.edit(edited)
        #expect(editor.save())

        let saved = try #require(store.load().0.journal.first)
        #expect(saved.sessions.map(\.recordingSourceLabel) == ["自动", "手动", "分钟换算", "提前结束"])
        #expect(saved.sessions.map(\.isMinuteConversion) == [false, false, true, false])
        #expect(saved.sessions.prefix(2).allSatisfy { $0.actualMinutes == 0 })
        let exported = JournalExport.markdown([saved])
        #expect(exported.contains("0 分钟 · 自动"))
        #expect(exported.contains("0 分钟 · 手动"))
        #expect(exported.contains("25 分钟 · 分钟换算"))
        #expect(exported.contains("0 分钟 · 提前结束"))
    }

    @Test @MainActor func saveMergesAutomaticSessionsWhileKeepingUserEdits() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(store: try DataStore(directory: directory), loaded: AppData())
        let editor = JournalEditor(model: model)
        var edited = editor.day
        edited.target = 5
        edited.notes = "local draft"
        editor.edit(edited)
        #expect(model.data.journal.isEmpty)
        var live = JournalDay(date: editor.dateKey)
        live.sessions.append(FocusSession())
        model.saveDay(live)
        editor.save()
        let saved = try #require(model.data.journal.first)
        #expect(saved.target == 5)
        #expect(saved.notes == "local draft")
        #expect(saved.sessions.count == 1)
        #expect(editor.draft == nil)
    }
    @Test @MainActor func navigationSavesPendingDayBeforeLoadingAnother() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(store: try DataStore(directory: directory), loaded: AppData())
        let editor = JournalEditor(model: model)
        var edited = editor.day
        edited.sessions.append(FocusSession(source: "manual", minutes: 10, countsTowardGoal: false))
        editor.edit(edited)
        editor.navigate(editor.date.addingTimeInterval(86400))
        #expect(editor.day.sessions.isEmpty)
        let saved = try #require(model.data.journal.first)
        #expect(saved.sessions.count == 1)
        #expect(saved.count == 0)
    }
}
