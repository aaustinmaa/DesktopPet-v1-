import AppKit
import SwiftUI
import Combine
import Sparkle

@main enum SuWuDuMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class MenuAction: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, checked: Bool = false, enabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
        isEnabled = enabled
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { handler() }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var model: AppModel!
    private var desktop: DesktopController!
    private var status: NSStatusItem!
    private var shortcut: RecoveryHotKey?
    private var windows: [String: NSWindow] = [:]
    private var subscriptions: Set<AnyCancellable> = []
    private var updater: SPUStandardUpdaterController?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var showingError = false
    private var journalEditor: JournalEditor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let identifier = Bundle.main.bundleIdentifier ?? "com.suwudu.desktop-pet.mac"
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            DistributedNotificationCenter.default().postNotificationName(Notification.Name("\(identifier).recall"), object: nil, userInfo: nil, deliverImmediately: true)
            running.activate(options: [])
            NSApp.terminate(nil)
            return
        }
        do {
            let store = try DataStore()
            let (loaded, warning) = try store.load()
            model = AppModel(store: store, loaded: loaded)
            desktop = DesktopController(model: model)
            desktop.makeMenu = { [weak self] in self?.makeMenu(forPet: true) ?? NSMenu() }
            desktop.onChat = { [weak self] in self?.openChat() }
            setupMenuBar()
            setupMainMenu()
            do { shortcut = try RecoveryHotKey { [weak self] in self?.desktop.recover() } }
            catch { model.error = error.localizedDescription }
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(recall), name: Notification.Name("\(identifier).recall"), object: nil)
            let center = NSWorkspace.shared.notificationCenter
            workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.model.sleep() }
            })
            workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.model.wake() }
            })
            NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
            model.$error.compactMap { $0 }.receive(on: RunLoop.main).sink { [weak self] text in self?.showError(text) }.store(in: &subscriptions)
            if let warning { model.error = warning }
            ScreenCapture.cleanup()
            if let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String, !feed.isEmpty,
               let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String, !key.isEmpty {
                updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            }
            model.start()
            if loaded.settings.firstRun {
                openLauncher()
                model.changeSettings { $0.firstRun = false }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法启动苏无度"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard desktop != nil else { return true }
        recall()
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        guard model != nil else { return }
        journalEditor?.save()
        model.pause()
        model.ai.codex.shutdown()
        ScreenCapture.cleanup()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
    @objc private func recall() { desktop.recover(); openLauncher() }
    @objc private func screenChanged() { desktop.clamp(); desktop.applySettings() }
    private func setupMenuBar() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "heart.fill", accessibilityDescription: "苏无度桌宠")
        let menu = makeMenu()
        menu.delegate = self
        status.menu = menu
    }
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let updated = makeMenu()
        for item in updated.items { updated.removeItem(item); menu.addItem(item) }
    }
    private func setupMainMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(MenuAction("启动面板") { [weak self] in self?.openLauncher() })
        appMenu.addItem(MenuAction("和她聊聊") { [weak self] in self?.openChat() })
        appMenu.addItem(MenuAction("专注记录") { [weak self] in self?.openJournal() })
        appMenu.addItem(MenuAction("设置…") { [weak self] in self?.openSettings() })
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "退出苏无度", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        bar.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        for (title, selector, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: NSSelectorFromString(selector), keyEquivalent: key)
        }
        editItem.submenu = editMenu
        bar.addItem(editItem)
        NSApp.mainMenu = bar
    }
    private func makeMenu(forPet: Bool = false) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ title: String, checked: Bool = false, enabled: Bool = true, _ action: @escaping () -> Void) {
            menu.addItem(MenuAction(title, checked: checked, enabled: enabled, handler: action))
        }
        if !forPet { add("叫回桌宠（⌃⌥P）") { [weak self] in self?.desktop.recover() } }
        add("💬 和我聊聊") { [weak self] in self?.openChat() }
        add("💚 给我一点鼓励") { [weak self] in self?.model.animate(.heart); self?.model.say("慢慢来，我会一直陪着你。") }
        let actions = NSMenu()
        for (title, state) in [("💚 比心", PetState.heart), ("😉 眨眼", .blink), ("👋 挥手", .waving)] {
            actions.addItem(MenuAction(title) { [weak self] in self?.model.animate(state) })
        }
        let actionsItem = NSMenuItem(title: "🎭 命令她做动作", action: nil, keyEquivalent: "")
        actionsItem.submenu = actions
        menu.addItem(actionsItem)
        menu.addItem(.separator())
        if !forPet { add(model.focusLabel, enabled: false) {} }
        add("💻 工作模式", checked: model.manualMode == .working) { [weak self] in self?.model.setMode(.working) }
        add("😴 睡眠模式", checked: model.manualMode == .sleeping) { [weak self] in self?.model.setMode(.sleeping) }
        add(model.breakRemaining > 0 ? "▶ 跳过休息并开始专注" : model.data.focus != nil ? "↻ 重新开始专注计时" : "⏱ 开始专注计时") { [weak self] in self?.model.startFocus() }
        add(model.paused ? "▶ 继续专注计时" : "⏸ 暂停专注计时", enabled: model.data.focus != nil) { [weak self] in self?.model.toggleFocus() }
        add(model.breakRemaining > 0 ? "■ 结束休息" : "■ 停止专注计时", enabled: model.data.focus != nil || model.breakRemaining > 0) { [weak self] in self?.model.stopFocus() }
        add("📊 今日专注记录") { [weak self] in self?.openJournal() }
        menu.addItem(.separator())
        add("🐾 自动漫游", checked: model.data.settings.wander) { [weak self] in self?.model.changeSettings { $0.wander.toggle() } }
        add("📌 始终置顶", checked: model.data.settings.topmost) { [weak self] in self?.model.changeSettings { $0.topmost.toggle() } }
        add("👻 鼠标穿透（⌃⌥P 恢复）", checked: model.clickThrough) { [weak self] in self?.desktop.toggleClickThrough() }
        menu.addItem(.separator())
        add("🏠 打开启动面板") { [weak self] in self?.openLauncher() }
        add("📖 使用说明书") { [weak self] in self?.show("help", title: "使用说明", view: HelpView(), size: NSSize(width: 640, height: 650)) }
        add("⬆ 检查更新", enabled: updater?.updater.canCheckForUpdates == true) { [weak self] in self?.updater?.checkForUpdates(nil) }
        add("⚙ 设置") { [weak self] in self?.openSettings() }
        add("🌙 收起来") { [weak self] in self?.desktop.hide() }
        add("✕ 退出") { NSApp.terminate(nil) }
        return menu
    }
    private func show<V: View>(_ id: String, title: String, view: V, size: NSSize, replace: Bool = false) {
        let window: NSWindow
        if let existing = windows[id] {
            window = existing
            if replace { window.contentView = NSHostingView(rootView: view) }
        } else {
            window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = title
            window.identifier = NSUserInterfaceItemIdentifier(id)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: view)
            window.center()
            windows[id] = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    private func openLauncher() {
        show("launcher", title: "苏无度 · 沈青", view: LauncherView(model: model, recover: { [weak self] in self?.desktop.recover() },
            chat: { [weak self] in self?.openChat() }, journal: { [weak self] in self?.openJournal() }, settings: { [weak self] in self?.openSettings() },
            help: { [weak self] in self?.show("help", title: "使用说明", view: HelpView(), size: NSSize(width: 640, height: 650)) },
            hide: { [weak self] in self?.desktop.hide() }), size: NSSize(width: 450, height: 565))
    }
    private func openSettings() {
        show("settings", title: "苏无度沈青设置", view: SettingsView(model: model, close: { [weak self] in self?.windows["settings"]?.close() }),
             size: NSSize(width: 620, height: 750), replace: windows["settings"]?.isVisible != true)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender.identifier?.rawValue == "journal" { journalEditor?.save() }
        return true
    }
    private func openJournal() {
        if journalEditor == nil { journalEditor = JournalEditor(model: model) }
        guard let editor = journalEditor else { return }
        show("journal", title: "专注记录", view: JournalView(model: model, editor: editor), size: NSSize(width: 730, height: 730))
    }
    private func openChat() {
        if model.busy, let window = windows["chat"] { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); return }
        if let window = windows["chat"] { window.setContentSize(NSSize(width: 440, height: 480)) }
        show("chat", title: "和我聊聊", view: ChatView(model: model, selected: model.newChat(), settings: { [weak self] in self?.openSettings() },
            resizeSidebar: { [weak self] expanded in
                guard let window = self?.windows["chat"] else { return }
                var frame = window.frame
                frame.size.width = max(expanded ? 660 : 440, frame.width + (expanded ? 219 : -219))
                window.setFrame(frame, display: true, animate: true)
            }), size: NSSize(width: 440, height: 480), replace: true)
    }
    private func showError(_ text: String) {
        guard !showingError else { return }
        showingError = true
        let alert = NSAlert()
        alert.messageText = "苏无度"
        alert.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        model.error = nil
        showingError = false
    }
}
