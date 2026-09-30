import AppKit
import SwiftUI

/// Let AppKit own the input-method composition and put spacing inside the text view.
@MainActor struct NotesEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        let editor = NotesTextView()
        editor.isRichText = false
        editor.allowsUndo = true
        editor.font = .systemFont(ofSize: NSFont.systemFontSize)
        editor.textColor = .textColor
        editor.backgroundColor = .textBackgroundColor
        editor.textContainerInset = NSSize(width: 8, height: 8)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        editor.synchronize(text)
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) {
        context.coordinator.parent = self
        (view.documentView as? NotesTextView)?.synchronize(text)
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NotesEditor
        init(_ parent: NotesEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView, !editor.hasMarkedText() else { return }
            if parent.text != editor.string { parent.text = editor.string }
        }
    }
}

final class NotesTextView: NSTextView {
    func synchronize(_ text: String) {
        // Timer and journal updates must not replace the marked pinyin or reset its selection.
        guard !hasMarkedText(), string != text else { return }
        string = text
    }
}
