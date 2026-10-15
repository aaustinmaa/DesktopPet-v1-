import AppKit

@MainActor private final class CloseVeto: NSObject, NSWindowDelegate {
    var allowed = false
    func windowShouldClose(_ sender: NSWindow) -> Bool { allowed }
}

/// Run in a real AppKit application, since a Swift Testing host does not own main-window focus.
@MainActor private final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private var pages: [AppPageWindow] = []
    private var cover: Process?
    private var textField: NSTextField?
    private let veto = CloseVeto()
    private let mode = CommandLine.arguments[1]
    private let readyFile = CommandLine.arguments[3]
    private var initialFrames: [NSRect] = []
    private var batchRestored = false
    private var batchObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        for (index, title) in ["Journal", "Launcher", "Settings"].enumerated() {
            let rect = index == 2 ? NSRect(x: 700, y: 150, width: 260, height: 180)
                : NSRect(x: 100 + index * 50, y: 100 + index * 50, width: 220, height: 150)
            let page = AppPageWindow(contentRect: rect, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                     backing: .buffered, defer: false)
            page.title = "Window lifecycle test · \(title)"
            page.isReleasedWhenClosed = false
            pages.append(page)
            if index < 2 { page.present() }
        }
        let field = NSTextField(string: "draft")
        field.frame = NSRect(x: 20, y: 30, width: 200, height: 28)
        pages[2].contentView?.addSubview(field)
        pages[2].delegate = veto
        textField = field
        initialFrames = pages.map(\.frame)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.startCover() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 22) { self.finish("Timed out waiting for AppKit", code: 2) }
    }

    private func startCover() {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[2])
        child.arguments = [readyFile, String(ProcessInfo.processInfo.processIdentifier)]
        cover = child
        do { try child.run() }
        catch { finish("Could not start synthetic foreground app: \(error)", code: 2) }
        awaitCover(remaining: 50)
    }
    private func awaitCover(remaining: Int) {
        guard remaining > 0, cover?.isRunning == true else {
            finish("Foreground-cover precondition failed", code: 2)
        }
        if FileManager.default.fileExists(atPath: readyFile), !NSRunningApplication.current.isActive {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.openSettings() }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.awaitCover(remaining: remaining - 1) }
        }
    }
    private func require(_ condition: Bool, _ message: String) {
        if !condition { finish(message, code: 1) }
    }
    private func openSettings() {
        require(pages[1].isVisible && !pages[1].occlusionState.contains(.visible), "Launcher must start covered")
        pages[2].present()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.editAndDismiss() }
    }
    private func editAndDismiss(remaining: Int = 50) {
        let settings = pages[2]
        if !(settings.isKeyWindow && settings.isMainWindow), remaining > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.editAndDismiss(remaining: remaining - 1) }
            return
        }
        if !NSRunningApplication.current.isActive, settings.canBecomeKey {
            finish("Activation precondition failed: macOS declined the synthetic app's initial focus request", code: 2)
        }
        require(settings.isKeyWindow && settings.isMainWindow, "Settings did not acquire key/main focus after activation")
        require(!pages[1].occlusionState.contains(.visible), "Opening settings raised the covered launcher")
        require(settings.makeFirstResponder(textField), "Page cannot focus editable text")
        guard let editor = settings.firstResponder as? NSTextView else { finish("Missing field editor", code: 1) }
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                    windowNumber: settings.windowNumber, context: nil, characters: "x",
                                    charactersIgnoringModifiers: "x", isARepeat: false, keyCode: 7)!
        settings.sendEvent(event)
        require(editor.string == "draftx", "Keyboard editing stopped working")
        settings.makeFirstResponder(nil)
        require(textField?.stringValue == "draftx", "Edited content did not commit to the control")
        settings.performClose(nil)
        require(settings.isVisible && settings.isKeyWindow, "Close veto was ignored")
        veto.allowed = true
        // Authorize our helper to supply a fresh synthetic user-activation context
        // after the dismissal assertions; a timer alone may not activate macOS apps.
        if let pid = cover?.processIdentifier, let app = NSRunningApplication(processIdentifier: pid) {
            NSApp.yieldActivation(to: app)
        }
        switch mode {
        case "close": settings.close()
        case "perform-close": settings.performClose(nil)
        case "minimize": settings.miniaturize(nil); settings.miniaturize(nil)
        case "perform-minimize": settings.performMiniaturize(nil); settings.performMiniaturize(nil)
        default: finish("Unknown mode: \(mode)", code: 2)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.checkDismissal() }
    }
    private func checkDismissal() {
        require(NSApp.keyWindow == nil && NSApp.mainWindow == nil, "Dismissing settings promoted another page")
        require(pages[0].isVisible && pages[1].isVisible, "Another page was hidden")
        require(!pages[1].occlusionState.contains(.visible), "Covered launcher came forward")
        require(pages.map(\.frame) == initialFrames, "A page moved or resized")
        require(pages.allSatisfy(\.canBecomeKey), "Dismissal left a stale focus gate")
        let settings = pages[2]
        require(!settings.isVisible, "Settings did not disappear")
        require(settings.isMiniaturized == mode.contains("minimize"), "Wrong settings dismissal state")
        // Repeated/no-op calls must not leak a pending-minimization gate.
        settings.miniaturize(nil)
        require(pages.allSatisfy(\.canBecomeKey), "No-op minimize left a focus gate")
        do { try Data("activate".utf8).write(to: URL(fileURLWithPath: readyFile + ".activate")) }
        catch { finish("Could not request synthetic activation: \(error)", code: 2) }
        awaitRestoreContext(remaining: 50)
    }
    private func awaitRestoreContext(remaining: Int) {
        guard remaining > 0, cover?.isRunning == true else {
            finish("Synthetic restore-activation precondition failed", code: 2)
        }
        if FileManager.default.fileExists(atPath: readyFile + ".restore"), !NSRunningApplication.current.isActive {
            pages[2].present()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.checkRestore() }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.awaitRestoreContext(remaining: remaining - 1) }
        }
    }
    private func checkRestore(remaining: Int = 50) {
        let settings = pages[2]
        let restored = settings.isVisible && !settings.isMiniaturized && settings.isKeyWindow && settings.isMainWindow
        if !restored, remaining > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.checkRestore(remaining: remaining - 1) }
            return
        }
        if !restored, !NSRunningApplication.current.isActive, settings.canBecomeKey {
            finish("Activation precondition failed: macOS declined the synthetic app's restore focus request", code: 2)
        }
        require(restored, "Explicit reopen did not restore key/main focus after activation")
        require(textField?.stringValue == "draftx" && settings.frame == initialFrames[2], "Reopening changed draft/frame")
        require(!pages[1].occlusionState.contains(.visible), "Reopening settings raised the launcher")
        if mode != "perform-minimize" { finish("PASS \(mode): dismissal, editing, close veto, restore") }
        settings.miniaturize(nil)
        settings.miniaturize(nil)
        settings.present() // This request must run after the animation, without losing the draft.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.require(settings.isVisible && !settings.isMiniaturized && settings.isKeyWindow,
                         "Present during minimization was lost")
            self.require(self.pages.allSatisfy(\.canBecomeKey), "Queued present leaked a gate")
            self.batchObserver = NotificationCenter.default.addObserver(forName: NSWindow.didDeminiaturizeNotification,
                                                                         object: self.pages[1], queue: .main) { [weak probe = self] _ in
                MainActor.assumeIsolated { probe?.batchRestored = true }
            }
            self.pages[1].miniaturize(nil)
            AppPageWindow.presentTogether([settings, self.pages[1]])
            self.awaitBatchRestore(settings, remaining: 50)
        }
    }
    private func awaitBatchRestore(_ settings: AppPageWindow, remaining: Int) {
        let restored = batchRestored && settings.isKeyWindow && settings.isMainWindow
            && pages[1].isVisible && !pages[1].isMiniaturized && pages.allSatisfy(\.canBecomeKey)
        if !restored {
            require(remaining > 0, "Show All did not settle on its intended front page within 5 seconds")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.awaitBatchRestore(settings, remaining: remaining - 1) }
            return
        }
        if let observer = batchObserver { NotificationCenter.default.removeObserver(observer); batchObserver = nil }
        // A stable checkpoint catches a late native restore taking focus back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.require(settings.isKeyWindow && settings.isMainWindow, "Show All reordered pages after settling")
            settings.miniaturize(nil)
            settings.close()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.require(!settings.isVisible && self.pages.allSatisfy(\.canBecomeKey), "Close during minimize leaked a gate")
                self.require(NSApp.keyWindow == nil && NSApp.mainWindow == nil, "Close during minimize promoted a page")
                self.finish("PASS \(self.mode): dismissal, editing, veto, restore, queued present, Show All, close during animation")
            }
        }
    }
    private func finish(_ message: String, code: Int32 = 0) -> Never {
        let status = code == 2 ? "BLOCKED" : "FAIL"
        print(code == 0 ? message : "\(status) \(mode): \(message)")
        fflush(stdout)
        if cover?.isRunning == true { cover?.terminate(); cover?.waitUntilExit() }
        try? FileManager.default.removeItem(atPath: readyFile)
        exit(code)
    }
}

@main private struct ProbeMain {
    @MainActor static func main() {
        guard CommandLine.arguments.count == 4 else { exit(2) }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = ProbeDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
