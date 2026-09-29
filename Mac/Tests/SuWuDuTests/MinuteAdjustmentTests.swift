import Foundation
import Testing
@testable import SuWuDu

struct MinuteAdjustmentTests {
    @Test @MainActor func additionsAndSubtractionsAccumulateAndPersistAfterSettlement() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DataStore(directory: directory)
        let model = AppModel(store: store, loaded: AppData())
        let editor = JournalEditor(model: model)
        var day = editor.day
        day.adjustment = 8
        day.notes = "retain notes"
        editor.edit(day)
        #expect(editor.adjustMinutes(by: 30))
        #expect(editor.day.adjustment == 38)
        #expect(editor.save())
        #expect(editor.day.total == 38)
        #expect(editor.adjustMinutes(by: -15))
        #expect(editor.save())
        #expect(editor.day.total == 23)
        #expect(editor.adjustMinutes(by: -30))
        #expect(editor.save())
        #expect(editor.day.total == -7)
        let saved = try #require(store.load().0.journal.first)
        #expect(saved.total == -7)
        #expect(saved.notes == "retain notes")
    }

    @Test @MainActor func invalidDeltaDoesNotPartiallyApplyOrCreateDraft() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(store: try DataStore(directory: directory), loaded: AppData())
        let editor = JournalEditor(model: model)
        #expect(!editor.adjustMinutes(by: 0))
        #expect(editor.draft == nil)
        #expect(editor.adjustMinutes(by: 9999))
        #expect(!editor.adjustMinutes(by: 2))
        #expect(!editor.adjustMinutes(by: Int.max))
        #expect(editor.day.adjustment == 9999)
        #expect(editor.adjustMinutes(by: -19999))
        #expect(editor.day.adjustment == -10000)
    }

    @Test @MainActor func failedSaveKeepsDeltaForRetryWithoutApplyingItAgain() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(store: try DataStore(directory: directory), loaded: AppData())
        let editor = JournalEditor(model: model)
        try FileManager.default.removeItem(at: directory)
        try Data().write(to: directory)
        #expect(editor.adjustMinutes(by: 10))
        #expect(!editor.save())
        #expect(editor.day.adjustment == 10)
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #expect(editor.save())
        #expect(editor.day.total == 10)
    }
}
