import AppKit

/// A separate, disposable app supplies a real foreground window. No user app is inspected.
@MainActor private final class CoverDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 540, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Window lifecycle test · foreground cover"
        window.isReleasedWhenClosed = false
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard NSRunningApplication.current.isActive, window.isKeyWindow else { exit(2) }
            do { try Data("ready".utf8).write(to: URL(fileURLWithPath: CommandLine.arguments[1])) }
            catch { exit(3) }
            self.yieldToProbe()
        }
        // A failed or interrupted parent must not leave a synthetic window behind.
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { exit(4) }
    }
    private func yieldToProbe() {
        guard let pid = Int32(CommandLine.arguments[2]),
              let parent = NSRunningApplication(processIdentifier: pid), !parent.isTerminated else { exit(0) }
        let request = CommandLine.arguments[1] + ".activate"
        if FileManager.default.fileExists(atPath: request) {
            try? FileManager.default.removeItem(atPath: request)
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard NSRunningApplication.current.isActive, self.window?.isKeyWindow == true else { exit(5) }
                NSApp.yieldActivation(to: parent)
                do { try Data("ready".utf8).write(to: URL(fileURLWithPath: CommandLine.arguments[1] + ".restore")) }
                catch { exit(3) }
            }
        }
        // Model an explicit user request to open the test app, without input automation.
        NSApp.yieldActivation(to: parent)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.yieldToProbe() }
    }
}

@main private struct CoverMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = CoverDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
