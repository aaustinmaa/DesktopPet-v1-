import AppKit

/// A page is brought forward explicitly, never as a side effect of dismissing another page.
@MainActor final class AppPageWindow: NSWindow {
    private static var dismissalDepth = 0
    private var presentationDepth = 0
    private var minimizationID: UUID?
    private var minimizationObserver: NSObjectProtocol?
    private var presentAfterMinimizing = false
    private var afterMinimizing: [() -> Void] = []
    private var restorationID: UUID?
    private var restorationObserver: NSObjectProtocol?
    private var afterRestoring: [() -> Void] = []
    private var closeAfterTransition = false

    private var acceptsFocus: Bool {
        if Self.dismissalDepth == 0 || presentationDepth > 0 { return true }
        // An actual click on a page is still an explicit request during another
        // page's minimize animation; AppKit's automatic successor is not.
        guard let event = NSApp.currentEvent, event.window === self else { return false }
        return event.type == .leftMouseDown || event.type == .rightMouseDown
    }
    override var canBecomeKey: Bool { acceptsFocus && super.canBecomeKey }
    override var canBecomeMain: Bool { acceptsFocus && super.canBecomeMain }

    static func presentTogether(_ windows: [AppPageWindow]) {
        // Finish in-flight animations before restoring a batch, otherwise a
        // delayed background page could steal focus back from the intended first.
        if let pending = windows.first(where: { $0.minimizationID != nil }) {
            pending.afterMinimizing.append { presentTogether(windows) }
            return
        }
        if let restoring = windows.first(where: { $0.restorationID != nil || $0.isMiniaturized }) {
            restoring.restore { presentTogether(windows) }
            return
        }
        for window in windows.reversed() where window.isVisible || window.isMiniaturized {
            window.present()
        }
    }

    func present() {
        closeAfterTransition = false
        if minimizationID != nil {
            presentAfterMinimizing = true
            return
        }
        if restorationID != nil || isMiniaturized {
            restore { [weak self] in
                guard let self, self.isVisible else { return }
                self.present()
            }
            return
        }
        presentationDepth += 1
        defer { presentationDepth -= 1 }
        // Activation raises the current key/main windows. Select this page first
        // so a previously used page behind another app is not raised along with it.
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func close() {
        if minimizationID != nil || restorationID != nil {
            // Closing does not cancel AppKit's in-flight animation or its later
            // focus handoff. Keep the gate until completion, then close safely.
            closeAfterTransition = true
            presentAfterMinimizing = false
            return
        }
        withoutAutomaticSuccessor {
            presentAfterMinimizing = false
            super.close()
        }
    }

    override func miniaturize(_ sender: Any?) {
        guard minimizationID == nil else { return }
        guard isVisible, !isMiniaturized, styleMask.contains(.miniaturizable),
              !styleMask.contains(.fullScreen), attachedSheet == nil,
              standardWindowButton(.miniaturizeButton)?.isEnabled != false else { return }
        let id = UUID()
        minimizationID = id
        Self.dismissalDepth += 1
        minimizationObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMiniaturizeNotification, object: self, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.minimizationID == id else { return }
                // Both will/did notifications can arrive after miniaturize()
                // returns. The successor is chosen after did; gate through it.
                DispatchQueue.main.async { [weak self] in
                    guard self?.minimizationID == id else { return }
                    self?.finishMinimization()
                }
            }
        }
        super.miniaturize(sender)
    }

    private func finishMinimization() {
        guard minimizationID != nil else { return }
        minimizationID = nil
        if let observer = minimizationObserver { NotificationCenter.default.removeObserver(observer) }
        minimizationObserver = nil
        Self.dismissalDepth -= 1
        if closeAfterTransition {
            closeAfterTransition = false
            close()
        } else if presentAfterMinimizing {
            presentAfterMinimizing = false
            present()
        }
        let completions = afterMinimizing
        afterMinimizing.removeAll()
        // Recheck which pages from a Show All request are still open after any
        // close deferred until the animation ended.
        if !completions.isEmpty { DispatchQueue.main.async { completions.forEach { $0() } } }
    }

    private func restore(then completion: @escaping () -> Void) {
        afterRestoring.append(completion)
        guard restorationID == nil else { return }
        let id = UUID()
        restorationID = id
        restorationObserver = NotificationCenter.default.addObserver(forName: NSWindow.didDeminiaturizeNotification, object: self, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard self?.restorationID == id else { return }
                self?.finishRestoration()
            }
        }
        // Restoring can select this window asynchronously. A batch chooses its
        // final front page only after every restore has actually completed.
        deminiaturize(nil)
    }

    private func finishRestoration() {
        guard restorationID != nil else { return }
        restorationID = nil
        if let observer = restorationObserver { NotificationCenter.default.removeObserver(observer) }
        restorationObserver = nil
        if closeAfterTransition {
            closeAfterTransition = false
            close()
        }
        let completions = afterRestoring
        afterRestoring.removeAll()
        if !completions.isEmpty { DispatchQueue.main.async { completions.forEach { $0() } } }
    }

    deinit {
        if let observer = minimizationObserver { NotificationCenter.default.removeObserver(observer) }
        if let observer = restorationObserver { NotificationCenter.default.removeObserver(observer) }
        if minimizationID != nil {
            Task { @MainActor in AppPageWindow.dismissalDepth -= 1 }
        }
    }

    private func withoutAutomaticSuccessor(_ dismiss: () -> Void) {
        // AppKit otherwise promotes another eligible page when its key/main
        // window disappears, even if that page was covered by another app.
        Self.dismissalDepth += 1
        defer { Self.dismissalDepth -= 1 }
        dismiss()
    }
}
