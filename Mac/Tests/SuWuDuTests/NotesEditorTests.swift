import AppKit
import SwiftUI
import Testing
@testable import SuWuDu

@MainActor private struct NotesHarness: View {
    @ObservedObject var editor: JournalEditor
    var sessionID: String
    var body: some View {
        NotesEditor(text: Binding(get: {
            editor.day.sessions.first { $0.id == sessionID }?.notes ?? ""
        }, set: { value in
            var day = editor.day
            if let index = day.sessions.firstIndex(where: { $0.id == sessionID }) {
                day.sessions[index].notes = value
                editor.edit(day)
            }
        })).frame(width: 400, height: 65)
    }
}

struct NotesEditorTests {
    @Test @MainActor func hostedNotesPreservePinyinDuringJournalRefreshAndSaveChinese() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try DataStore(directory: directory)
        let model = AppModel(store: store, loaded: AppData())
        let journal = JournalEditor(model: model)
        let session = FocusSession(notes: "你好")
        var day = journal.day
        day.sessions = [session]
        journal.edit(day)
        let host = NSHostingView(rootView: NotesHarness(editor: journal, sessionID: session.id))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 65), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        func find(_ view: NSView) -> NotesTextView? {
            if let text = view as? NotesTextView { return text }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        for _ in 0..<50 {
            host.layoutSubtreeIfNeeded()
            if find(host) != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let text = try #require(find(host))
        #expect(text.textContainerInset == NSSize(width: 8, height: 8))
        #expect(text.string == "你好")
        text.setSelectedRange(NSRange(location: 2, length: 0))
        text.setMarkedText("shi", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let marked = text.markedRange()
        let selected = text.selectedRange()
        for target in 1...3 {
            var updated = journal.day
            updated.target = target
            journal.edit(updated)
            try await Task.sleep(for: .milliseconds(20))
            host.layoutSubtreeIfNeeded()
            #expect(find(host) === text)
            #expect(text.hasMarkedText())
            #expect(text.string == "你好shi")
            #expect(text.markedRange() == marked)
            #expect(text.selectedRange() == selected)
        }
        text.insertText("世界", replacementRange: text.markedRange())
        #expect(!text.hasMarkedText())
        #expect(journal.day.sessions.first?.notes == "你好世界")
        text.insertText("\n第二行", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(journal.save())
        #expect(try store.load().0.journal.first?.sessions.first?.notes == "你好世界\n第二行")
    }

    @Test @MainActor func markedPinyinIsNotPublishedAsSavedNotes() {
        var notes = ""
        let parent = NotesEditor(text: Binding(get: { notes }, set: { notes = $0 }))
        let coordinator = parent.makeCoordinator()
        let text = NotesTextView()
        text.delegate = coordinator
        text.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: text))
        #expect(notes.isEmpty)
        text.synchronize(notes)
        #expect(text.hasMarkedText())
        text.insertText("中", replacementRange: text.markedRange())
        #expect(notes == "中")
        text.synchronize("")
        #expect(text.string.isEmpty)
    }
}
