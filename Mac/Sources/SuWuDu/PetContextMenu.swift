import AppKit
import SwiftUI

@MainActor private final class PetMenuPanel: NSPanel {
    var handleKey: ((UInt16) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           handleKey?(event.keyCode) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if handleKey?(event.keyCode) != true { super.keyDown(with: event) }
    }
}

@MainActor private final class PetMenuState: ObservableObject {
    let menu: NSMenu
    @Published var highlighted = -1
    var frames: [Int: CGRect] = [:]
    init(_ menu: NSMenu) { self.menu = menu }
    var enabledIndices: [Int] { menu.items.indices.filter { !menu.items[$0].isSeparatorItem && menu.items[$0].isEnabled } }
    func move(_ delta: Int) {
        let items = enabledIndices
        guard !items.isEmpty else { return }
        if let index = items.firstIndex(of: highlighted) { highlighted = items[(index + delta + items.count) % items.count] }
        else { highlighted = delta > 0 ? items[0] : items[items.count - 1] }
    }
}

// Desktop popup only: the system menu-bar menu stays native. Both menus use
// the same NSMenu commands, so checked/enabled state and actions cannot diverge.
@MainActor final class PetContextMenuController {
    private var panels: [PetMenuPanel] = []
    private var states: [PetMenuState] = []
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var deactivateObserver: NSObjectProtocol?
    private var parentItem: Int?
    var isVisible: Bool { panels.first?.isVisible == true }

    func show(_ menu: NSMenu, at point: NSPoint) {
        dismiss()
        let state = PetMenuState(menu)
        let panel = makePanel(state, level: 0)
        let area = (NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        panel.setFrameOrigin(NSPoint(x: min(max(area.minX, point.x), area.maxX - panel.frame.width),
                                     y: min(max(area.minY, point.y - panel.frame.height), area.maxY - panel.frame.height)))
        panels = [panel]; states = [state]
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self else { return event }
            if !self.panels.contains(where: { $0 === event.window }) { self.dismiss() }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in self?.dismiss() }
        deactivateObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }
    func dismiss() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let deactivateObserver { NotificationCenter.default.removeObserver(deactivateObserver) }
        localMonitor = nil; globalMonitor = nil; deactivateObserver = nil
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll(); states.removeAll(); parentItem = nil
    }
    private func makePanel(_ state: PetMenuState, level: Int) -> PetMenuPanel {
        let font = NSFont.systemFont(ofSize: 13)
        let width = max(240, state.menu.items.map { ($0.title as NSString).size(withAttributes: [.font: font]).width + 68 }.max() ?? 240)
        let naturalHeight = state.menu.items.reduce(CGFloat(14)) { $0 + ($1.isSeparatorItem ? 11 : 34) }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let height = min(naturalHeight, (screen?.visibleFrame.height ?? 800) - 12)
        let panel = PetMenuPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.title = level == 0 ? "桌宠菜单" : "命令她做动作"
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: PetMenuList(state: state, hover: { [weak self] index in self?.highlight(index, level: level) },
            choose: { [weak self] index in self?.choose(index, level: level) }))
        panel.handleKey = { [weak self] code in self?.key(code, level: level) ?? false }
        return panel
    }
    private func closeSubmenu() {
        if panels.count > 1 { panels.removeLast().orderOut(nil); states.removeLast() }
        parentItem = nil
    }
    private func highlight(_ index: Int, level: Int) {
        guard states.indices.contains(level) else { return }
        states[level].highlighted = index
        if level == 0 {
            if states[0].menu.items[index].submenu != nil { openSubmenu(index, focus: false) }
            else { closeSubmenu() }
        }
    }
    private func openSubmenu(_ index: Int, focus: Bool) {
        guard let root = panels.first, let state = states.first, let submenu = state.menu.items[index].submenu else { return }
        if parentItem != index {
            closeSubmenu()
            let childState = PetMenuState(submenu)
            let child = makePanel(childState, level: 1)
            let area = root.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
            let row = state.frames[index] ?? CGRect(x: 0, y: CGFloat(index * 34), width: root.frame.width, height: 34)
            let right = root.frame.maxX - 3
            let x = right + child.frame.width <= area.maxX ? right : root.frame.minX - child.frame.width + 3
            let y = root.frame.maxY - row.minY + 7 - child.frame.height
            child.setFrameOrigin(NSPoint(x: max(area.minX, x), y: min(max(area.minY, y), area.maxY - child.frame.height)))
            panels.append(child); states.append(childState); parentItem = index
            child.orderFrontRegardless()
        }
        if focus { states.last?.move(1); panels.last?.makeKeyAndOrderFront(nil) }
    }
    private func choose(_ index: Int, level: Int) {
        guard states.indices.contains(level), states[level].menu.items.indices.contains(index) else { return }
        let item = states[level].menu.items[index]
        guard item.isEnabled, !item.isSeparatorItem else { return }
        if item.submenu != nil { openSubmenu(index, focus: true); return }
        dismiss()
        if let action = item.action { NSApp.sendAction(action, to: item.target, from: item) }
    }
    private func key(_ code: UInt16, level: Int) -> Bool {
        guard states.indices.contains(level) else { return false }
        let state = states[level]
        switch code {
        case 53: dismiss()
        case 125, 126:
            if level == 0 { closeSubmenu() }
            state.move(code == 125 ? 1 : -1)
        case 124:
            if level == 0, state.highlighted >= 0 { openSubmenu(state.highlighted, focus: true) }
        case 123:
            if level == 1 { closeSubmenu(); panels.first?.makeKeyAndOrderFront(nil) }
        case 36, 76, 49: choose(state.highlighted, level: level)
        default: return false
        }
        return true
    }
}

@MainActor private struct PetMenuList: View {
    @ObservedObject var state: PetMenuState
    var hover: (Int) -> Void
    var choose: (Int) -> Void
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(state.menu.items.enumerated()), id: \.offset) { index, item in
                        if item.isSeparatorItem {
                            Rectangle().fill(PetTheme.border).frame(height: 1).padding(.horizontal, 12).padding(.vertical, 5)
                        } else {
                            Button { choose(index) } label: {
                                HStack(spacing: 0) {
                                    Text(item.state == .on ? "✓" : "").fontWeight(.bold).foregroundStyle(PetTheme.accent).frame(width: 20)
                                    Text(item.title).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(item.submenu == nil ? "" : "›").font(.system(size: 18)).frame(width: 18)
                                }.font(.system(size: 13)).padding(.horizontal, 10).frame(height: 32)
                                    .foregroundStyle(PetTheme.ink)
                                    .background(state.highlighted == index ? PetTheme.soft : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                                    .opacity(item.isEnabled ? 1 : 0.4).contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(!item.isEnabled)
                                .accessibilityLabel(item.title + (item.state == .on ? "，已选中" : ""))
                                .padding(1).id(index)
                                .onHover { inside in if inside { hover(index) } }
                                .background(GeometryReader { geometry in
                                    Color.clear.onAppear { state.frames[index] = geometry.frame(in: .named("petMenu")) }
                                        .onChange(of: geometry.frame(in: .named("petMenu"))) { _, frame in state.frames[index] = frame }
                                })
                        }
                    }
                }.padding(6)
            }.coordinateSpace(name: "petMenu")
                .onChange(of: state.highlighted) { _, index in proxy.scrollTo(index) }
        }.background(PetTheme.card, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(PetTheme.border))
            .clipShape(RoundedRectangle(cornerRadius: 8)).preferredColorScheme(.light)
    }
}
