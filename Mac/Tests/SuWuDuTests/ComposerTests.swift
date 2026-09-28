import AppKit
import SwiftUI
import Testing
@testable import SuWuDu

struct ComposerTests {
    @Test @MainActor func refreshPreservesPinyinUntilCandidateIsCommitted() {
        let editor = SendTextView()
        editor.string = "你好"
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        editor.setMarkedText("shi", selectedRange: NSRange(location: 3, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        let markedRange = editor.markedRange()
        let selection = editor.selectedRange()
        #expect(editor.hasMarkedText())

        // A model/timer refresh still carries the draft from before composition.
        for _ in 0..<3 { editor.synchronizeDraft("你好") }
        #expect(editor.string == "你好shi")
        #expect(editor.markedRange() == markedRange)
        #expect(editor.selectedRange() == selection)

        var draft = "你好"
        let coordinator = Composer(text: Binding(get: { draft }, set: { draft = $0 }), send: {}).makeCoordinator()
        editor.delegate = coordinator
        editor.insertText("世界", replacementRange: editor.markedRange())
        #expect(!editor.hasMarkedText())
        #expect(draft == "你好世界")
        editor.synchronizeDraft(draft)
        #expect(editor.string == "你好世界")

        // Sending or changing chats must still clear a committed draft.
        editor.synchronizeDraft("")
        #expect(editor.string.isEmpty)
    }

    @Test @MainActor func returnSendsCommittedTextAndShiftReturnInsertsNewline() throws {
        let editor = SendTextView()
        var sends = 0
        editor.send = { sends += 1 }
        editor.string = "你好"
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        func enter(_ modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
                characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        }
        editor.keyDown(with: try enter(.shift))
        #expect(sends == 0)
        #expect(editor.string == "你好\n")
        editor.keyDown(with: try enter([]))
        #expect(sends == 1)
    }
}
