import Foundation
import Testing
@testable import SuWuDu

struct JournalEditorTests {
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
