import Foundation
import AppKit
import SwiftUI
import Testing
@testable import SuWuDu

struct AuditRegressionTests {
    @Test @MainActor func journalMergePreservesAutomaticChangesToExistingSessions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(store: try DataStore(directory: directory), loaded: AppData())
        let editor = JournalEditor(model: model)
        var day = editor.day
        day.sessions = [FocusSession(minutes: 25)]
        model.saveDay(day)
        day.notes = "editing"
        editor.edit(day)
        var live = model.data.journalDay(editor.dateKey)
        live.adjustment = -10
        model.saveDay(live)
        #expect(model.data.journalDay(editor.dateKey).total == 15)
        editor.save()
        #expect(model.data.journalDay(editor.dateKey).total == 15)
        #expect(model.data.journalDay(editor.dateKey).count == 0)
        #expect(model.data.journalDay(editor.dateKey).notes == "editing")
    }

    @Test @MainActor func failedSaveKeepsDraftAndDate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(store: try DataStore(directory: directory), loaded: AppData())
        let editor = JournalEditor(model: model)
        var day = editor.day
        day.notes = "keep unsaved"
        editor.edit(day)
        try FileManager.default.removeItem(at: directory)
        try Data().write(to: directory) // Deterministic write failure, including when run as root.
        let old = editor.date
        editor.navigate(old.addingTimeInterval(86400))
        #expect(editor.draft?.notes == "keep unsaved")
        #expect(editor.date == old)
        #expect(model.data.journal.isEmpty)
    }

    @Test func missingPrimaryRecoversBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DataStore(directory: directory)
        var data = AppData()
        data.facts = ["saved"]
        try store.save(data)
        try store.save(data)
        try FileManager.default.removeItem(at: store.file)
        let (loaded, warning) = try store.load()
        #expect(loaded.facts == ["saved"])
        #expect(warning != nil)
        #expect(FileManager.default.fileExists(atPath: store.file.path))
    }

    @Test func rejectsNonexistentAndNoncanonicalDates() {
        for invalid in ["2026-02-30", "2026-13-01", "2026-00-10", "2026-2-01", "2026-02-01-extra"] {
            #expect(FocusAccounting.date(from: invalid) == nil)
        }
        #expect(FocusAccounting.date(from: "2024-02-29") != nil)
    }
}

extension AuditRegressionTests {
    @Test func numericEditingPreservesEmptyAndRejectsInvalidInput() {
        var input = IntegerInput(text: "1")
        #expect(input.accept("", range: 0...999) == 0)
        input.synchronize(0, editing: true)
        #expect(input.text.isEmpty)
        input.synchronize(0, editing: false)
        #expect(input.text == "0")
        #expect(input.accept("12", range: 0...999) == 12)
        #expect(input.accept("abc", range: 0...999) == nil)
        #expect(input.text == "12")
        #expect(input.accept(String(repeating: "9", count: 50), range: 0...999) == nil)
        #expect(input.text == "12")
        #expect(input.accept("1000", range: 0...999) == 999)
        #expect(input.text == "999")
        #expect(input.accept("-", range: -10000...10000) == 0)
        #expect(input.text == "-")
        #expect(input.accept("-12", range: -10000...10000) == -12)
        input.synchronize(-11, editing: true) // Stepper/external change while focused.
        #expect(input.text == "-11")
    }

    @Test @MainActor func bulkSaveFailureKeepsPreviousTargets() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(store: try DataStore(directory: directory), loaded: AppData())
        #expect(model.setTargets(from: "2026-10-01", through: nil, target: 4))
        try FileManager.default.removeItem(at: directory)
        try Data().write(to: directory)
        #expect(!model.setTargets(from: "2026-10-01", through: nil, target: 8))
        #expect(model.data.journalDay("2026-10-01").target == 4)
    }

    @Test @MainActor func importFlushesDraftAndUsesLatestData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DataStore(directory: directory)
        let folder = directory.appendingPathComponent("import")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let model = AppModel(store: store, loaded: AppData())
        let editor = JournalEditor(model: model)
        var day = editor.day
        day.notes = "old draft"
        editor.edit(day)
        let source: [String: Any] = ["Days": [["Date": day.date, "DailyNotes": "imported", "Sessions": []]]]
        try JSONSerialization.data(withJSONObject: source).write(to: folder.appendingPathComponent("focus-journal.json"))
        model.prepareForImport = {
            model.data.facts.append("latest")
            return editor.save()
        }
        try model.importWindows(folder)
        #expect(editor.draft == nil)
        #expect(editor.day.notes == "imported")
        editor.save() // Closing after import must not put back the old draft.
        #expect(try store.load().0.journal.first?.notes == "imported")
        #expect(model.data.facts == ["latest"])
        let backup = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("before-import-") })
        let saved = try DataStore.decoder.decode(AppData.self, from: Data(contentsOf: backup))
        #expect(saved.journal.first?.notes == "old draft")
    }

    @Test @MainActor func importRechecksBusyAndFocusBeforeReading() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(store: try DataStore(directory: directory), loaded: AppData())
        model.busy = true
        #expect(throws: (any Error).self) { try model.importWindows(directory) }
        model.busy = false
        model.data.focus = FocusRun(startedAt: Date(), planned: 25, remaining: 1500)
        #expect(throws: (any Error).self) { try model.importWindows(directory) }
        #expect(model.data.focus?.remaining == 1500)
    }

    @Test @MainActor func immediateCancelPreventsSendAndDuplicateSubmission() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var data = AppData()
        data.settings.provider = "offline"
        let model = AppModel(store: try DataStore(directory: directory), loaded: data)
        let id = model.newChat()
        #expect(model.beginSend("first", threadID: id))
        #expect(model.busy)
        #expect(!model.beginSend("duplicate", threadID: id))
        model.cancelReply()
        for _ in 0..<50 where model.busy { await Task.yield() }
        #expect(!model.busy)
        #expect(model.data.threads.first?.messages.isEmpty == true)
        #expect(model.error == nil)
    }

    @Test @MainActor func cancellationDuringCapturePreventsReplyAndDeletesImage() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }
        var captureStarted = false
        var release: CheckedContinuation<Void, Never>?
        let task = Task {
            try await ChatScreenCapture.reply(enabled: true, capture: {
                captureStarted = true
                await withCheckedContinuation { release = $0 }
                return path
            }) { _, _ in
                Issue.record("A cancelled capture must not send any network request")
                return CompanionReply(text: "unexpected")
            }
        }
        while !captureStarted { await Task.yield() }
        task.cancel()
        release?.resume()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch { #expect(error is CancellationError) }
        #expect(!FileManager.default.fileExists(atPath: path.path))
    }
}


extension AuditRegressionTests {
    @Test @MainActor func nextDraftRemainsEditableAndSurvivesReplyCompletion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(store: try DataStore(directory: directory), loaded: AppData())
        let id = model.newChat()
        model.busy = true
        let host = NSHostingView(rootView: ChatView(model: model, selected: id, settings: {}, resizeSidebar: { _ in }))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 480), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        func findEditor(_ view: NSView) -> SendTextView? {
            if let editor = view as? SendTextView { return editor }
            for child in view.subviews { if let editor = findEditor(child) { return editor } }
            return nil
        }
        for _ in 0..<50 {
            host.layoutSubtreeIfNeeded()
            if findEditor(host) != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let editor = try #require(findEditor(host))
        #expect(editor.isEditable)
        editor.insertText("下一条草稿", replacementRange: NSRange(location: 0, length: 0))
        model.busy = false
        for _ in 0..<5 { try await Task.sleep(for: .milliseconds(10)); host.layoutSubtreeIfNeeded() }
        #expect(editor.string == "下一条草稿")
        #expect(editor.isEditable)
    }
}
