import AppKit
import Testing
@testable import SuWuDu

@Suite(.serialized) @MainActor struct PetContextMenuTests {
    private func key(_ code: UInt16, in window: NSWindow) throws {
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: code))
        window.keyDown(with: event)
    }

    @Test func popupAndSubmenuStayNonactivatingWhileKeyboardActionsWork() throws {
        let app = NSApplication.shared
        // AppKit can report a key nonactivating panel as active for event routing;
        // the owning process must still retain its original activation state.
        let wasActive = NSRunningApplication.current.isActive
        let existingWindows = Set(app.windows.map(ObjectIdentifier.init))
        let controller = PetContextMenuController()
        defer { controller.dismiss() }
        var selected = 0
        let menu = NSMenu()
        let submenu = NSMenu()
        submenu.addItem(MenuAction("测试动作") { selected += 1 })
        let parent = NSMenuItem(title: "动作", action: nil, keyEquivalent: "")
        parent.submenu = submenu
        menu.addItem(parent)
        controller.show(menu, at: NSPoint(x: 300, y: 400))
        let root = try #require(app.windows.first {
            !existingWindows.contains(ObjectIdentifier($0)) && $0.title == "桌宠菜单"
        })
        #expect(controller.isVisible)
        #expect(root.styleMask.contains(.nonactivatingPanel))
        #expect(root.canBecomeKey)
        #expect(!root.canBecomeMain)
        #expect(NSRunningApplication.current.isActive == wasActive)

        try key(125, in: root) // Down highlights the first item.
        try key(124, in: root) // Right opens its submenu.
        let child = try #require(app.windows.first {
            !existingWindows.contains(ObjectIdentifier($0)) && $0.title == "命令她做动作" && $0.isVisible
        })
        #expect(child.styleMask.contains(.nonactivatingPanel))
        #expect(child.canBecomeKey)
        #expect(!child.canBecomeMain)
        #expect(NSRunningApplication.current.isActive == wasActive)
        try key(123, in: child) // Left returns to the root.
        #expect(!child.isVisible)
        #expect(controller.isVisible)
        try key(124, in: root)
        let reopened = try #require(app.windows.first {
            !existingWindows.contains(ObjectIdentifier($0)) && $0.title == "命令她做动作" && $0.isVisible
        })
        try key(36, in: reopened) // Return invokes the action and dismisses both panels.
        #expect(selected == 1)
        #expect(!controller.isVisible)
        #expect(!root.isVisible)
        #expect(!reopened.isVisible)
    }

    @Test func escapeDismissesWithoutChangingOtherWindows() throws {
        let app = NSApplication.shared
        let existingWindows = Set(app.windows.map(ObjectIdentifier.init))
        let other = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 240, height: 160),
                             styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        other.orderBack(nil)
        let originalFrame = other.frame
        let originalVisibility = other.isVisible
        let controller = PetContextMenuController()
        defer { controller.dismiss(); other.close() }
        let menu = NSMenu()
        menu.addItem(MenuAction("测试动作") {})
        controller.show(menu, at: NSPoint(x: 300, y: 400))
        let popup = try #require(app.windows.first {
            !existingWindows.contains(ObjectIdentifier($0)) && $0.title == "桌宠菜单"
        })
        #expect(other.frame == originalFrame)
        #expect(other.isVisible == originalVisibility)
        #expect(!other.isKeyWindow)
        try key(53, in: popup)
        #expect(!controller.isVisible)
        #expect(other.frame == originalFrame)
        #expect(other.isVisible == originalVisibility)
    }
}
