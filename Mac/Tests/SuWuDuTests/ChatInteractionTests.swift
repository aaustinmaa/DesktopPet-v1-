import AppKit
import Testing
import WebKit
@testable import SuWuDu

@MainActor private final class WheelEvent: NSEvent {
    var target: NSWindow?
    var point = NSPoint(x: 40, y: 40)
    var dx: CGFloat = 0
    var dy: CGFloat = -12
    var finger: NSEvent.Phase = []
    var momentum: NSEvent.Phase = []
    override var type: NSEvent.EventType { .scrollWheel }
    override var window: NSWindow? { target }
    override var locationInWindow: NSPoint { point }
    override var scrollingDeltaX: CGFloat { dx }
    override var scrollingDeltaY: CGFloat { dy }
    override var phase: NSEvent.Phase { finger }
    override var momentumPhase: NSEvent.Phase { momentum }
    override var hasPreciseScrollingDeltas: Bool { true }
}

@MainActor private final class ChatScrollRecorder: NSScrollView {
    var events: [NSEvent] = []
    override func scrollWheel(with event: NSEvent) { events.append(event) }
}

struct ChatInteractionTests {
    @Test @MainActor func bubbleForwardsVerticalAndMomentumButKeepsHorizontalGestures() throws {
        let scroll = ChatScrollRecorder(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let document = NSView(frame: scroll.bounds)
        let bubble = ChatBubbleWebView(frame: NSRect(x: 10, y: 10, width: 300, height: 200), configuration: WKWebViewConfiguration())
        document.addSubview(bubble)
        scroll.documentView = document
        let window = NSWindow(contentRect: scroll.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = scroll
        defer { window.contentView = nil }
        let event = WheelEvent()
        event.target = window
        event.point = bubble.convert(NSPoint(x: 30, y: 30), to: nil)
        #expect(bubble.forwardVerticalScroll(event))
        #expect(scroll.events.last === event)

        event.finger = .began
        #expect(bubble.forwardVerticalScroll(event))
        event.finger = .ended
        event.dy = 0
        #expect(bubble.forwardVerticalScroll(event))
        event.finger = []
        event.momentum = .began
        event.dy = -8
        #expect(bubble.forwardVerticalScroll(event))
        event.momentum = .ended
        event.dy = 0
        #expect(bubble.forwardVerticalScroll(event))
        #expect(scroll.events.count == 5)

        event.momentum = []
        event.finger = .began
        event.dx = 20
        event.dy = 1
        #expect(!bubble.forwardVerticalScroll(event))
        event.finger = .changed
        event.dx = 0
        event.dy = 2
        #expect(!bubble.forwardVerticalScroll(event))
        #expect(scroll.events.count == 5)

        event.finger = .began
        event.dx = 0
        event.dy = 10
        event.point = NSPoint(x: -100, y: -100)
        #expect(!bubble.forwardVerticalScroll(event))
        event.point = bubble.convert(NSPoint(x: 30, y: 30), to: nil)
        event.target = nil
        #expect(!bubble.forwardVerticalScroll(event))
        event.target = window
        bubble.isHidden = true
        #expect(!bubble.forwardVerticalScroll(event))
        #expect(scroll.events.count == 5)
    }
}
