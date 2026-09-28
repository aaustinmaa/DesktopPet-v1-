import SwiftUI
import WebKit

/// WebKit's content view consumes wheel events before they reach the SwiftUI scroll view.
/// Intercept only events over this bubble, and keep horizontal gestures inside WebKit.
final class ChatBubbleWebView: WKWebView {
    private var scrollMonitor: Any?
    private var verticalGesture: Bool?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoringScroll()
        guard window != nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.forwardVerticalScroll(event) else { return event }
            return nil
        }
    }

    func stopMonitoringScroll() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        verticalGesture = nil
    }

    deinit {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
    }

    @discardableResult
    func forwardVerticalScroll(_ event: NSEvent) -> Bool {
        guard event.type == .scrollWheel, let window, event.window === window,
              !isHiddenOrHasHiddenAncestor,
              visibleRect.contains(convert(event.locationInWindow, from: nil)),
              let scrollView = enclosingScrollView else { return false }
        let phased = !event.phase.isEmpty || !event.momentumPhase.isEmpty
        if event.phase.contains(.began) || !phased { verticalGesture = nil }
        if verticalGesture == nil && (event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0) {
            verticalGesture = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
        }
        let forward = verticalGesture == true
        // Keep the axis through finger-up and momentum, including zero-delta end events.
        if event.phase.contains(.cancelled) || event.momentumPhase.contains(.ended) || !phased {
            verticalGesture = nil
        }
        guard forward else { return false }
        scrollView.scrollWheel(with: event)
        return true
    }
}

struct ChatThreadButtonStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        ChatThreadButtonSurface(configuration: configuration, selected: selected)
    }
}

private struct ChatThreadButtonSurface: View {
    let configuration: ButtonStyle.Configuration
    let selected: Bool
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var active: Bool { enabled && (hovered || configuration.isPressed) }
    private var fill: Color {
        if active {
            return selected ? Color(red: 178/255, green: 210/255, blue: 204/255)
                : Color(red: 217/255, green: 233/255, blue: 230/255)
        }
        return selected ? PetTheme.soft : .clear
    }
    var body: some View {
        configuration.label
            .padding(9)
            .background(fill, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .opacity(enabled ? 1 : 0.42)
            .animation(reduceMotion ? nil : .easeOut(duration: active ? 0.14 : 0.12), value: active)
            .onHover { hovered = $0 }
    }
}
