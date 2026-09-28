import AppKit
import QuartzCore
import ImageIO

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class PetView: NSView {
    let sprite = CALayer()
    let hammer = CALayer()
    private var sleepLayers: [CALayer] = []
    private var cache: [String: CGImage] = [:]
    private var generation = 0
    private var down = NSPoint.zero
    private var origin = NSPoint.zero
    private var dragged = false
    private var pendingClick: DispatchWorkItem?
    var onClick: ((Int) -> Void)?
    var onMove: (() -> Void)?
    var onInteractionStart: (() -> Void)?
    var onDragEnd: (() -> Void)?
    var makeMenu: (() -> NSMenu)?
    var onAnimationEnd: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(sprite)
        layer?.addSublayer(hammer)
        sprite.contentsGravity = .resizeAspect
        sprite.magnificationFilter = .nearest
        sprite.minificationFilter = .nearest
        hammer.magnificationFilter = .nearest
        for name in ["sleeping-z-small.png", "sleeping-z-medium.png", "sleeping-z-large.png"] {
            let z = CALayer()
            z.contents = load(name)
            z.magnificationFilter = .nearest
            z.opacity = 0
            layer?.addSublayer(z)
            sleepLayers.append(z)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let side = min(bounds.width, bounds.height)
        let square = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        sprite.frame = square
        let scale = bounds.width / 210
        hammer.frame = CGRect(x: bounds.midX + 14 - 45 * scale, y: bounds.height - 90 * scale, width: 90 * scale, height: 90 * scale)
        let coordinates: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(252, 72, 14, 17), (268, 49, 26, 31), (294, 4, 32, 40)]
        for (index, z) in sleepLayers.enumerated() {
            let (x, y, width, height) = coordinates[index]
            z.frame = CGRect(x: square.minX + x * side / 362, y: square.minY + (362 - y - height) * side / 362,
                             width: width * side / 362, height: height * side / 362)
        }
        CATransaction.commit()
    }
    private func load(_ name: String) -> CGImage? {
        if let existing = cache[name] { return existing }
        guard let source = CGImageSourceCreateWithURL(Resources.sprite(name) as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        cache[name] = image
        return image
    }
    func play(_ state: PetState, skin: String) {
        generation += 1
        let current = generation
        let spec = AnimationSpec.make(state, skin: skin)
        let images = spec.frames.compactMap(load)
        sprite.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.contents = images.first
        CATransaction.commit()
        if images.count > 1 {
            let animation = CAKeyframeAnimation(keyPath: "contents")
            animation.values = images
            animation.calculationMode = .discrete
            animation.duration = Double(images.count) * spec.interval
            animation.repeatCount = spec.once ? 1 : .infinity
            sprite.add(animation, forKey: "frames")
            if spec.once {
                DispatchQueue.main.asyncAfter(deadline: .now() + animation.duration) { [weak self] in
                    guard let self, self.generation == current else { return }
                    self.onAnimationEnd?()
                }
            }
        }
        for (index, z) in sleepLayers.enumerated() {
            z.removeAllAnimations()
            z.opacity = 0
            if state == .sleeping && skin == "suwudu" {
                // Same ten-second choreography as SpriteAnimator.StartSleepZAnimation.
                let specs: [[Double]] = [
                    [0.36, 0.424, 0.72, 0.72, 0.8, 1, 2.29, 0, 0, 51, -56.5],
                    [0.18, 0.244, 0.54, 0.54, 0.576, 0.54, 1.23, -22, 16, 29, -40.5],
                    [0, 0.064, 0.36, 0.36, 0.396, 0.43, 1, -51, 56.5, 0, 0]
                ]
                let s = specs[index]
                let factor = Double(min(bounds.width, bounds.height)) / 362
                let fade = CAKeyframeAnimation(keyPath: "opacity")
                fade.values = s[0] > 0 ? [0, 0, 1, 1, 0, 0] : [0, 1, 1, 0, 0]
                let fadeTimes = s[0] > 0 ? [0, s[0], s[1], s[3], s[4], 1] : [0, s[1], s[3], s[4], 1]
                fade.keyTimes = fadeTimes.map { NSNumber(value: $0) }
                fade.duration = 10
                func motion(_ path: String, _ start: Double, _ end: Double) -> CAKeyframeAnimation {
                    let animation = CAKeyframeAnimation(keyPath: path)
                    animation.values = s[0] > 0 ? [start, start, end, end] : [start, end, end]
                    let times = s[0] > 0 ? [0, s[0], s[2], 1] : [0, s[2], 1]
                    animation.keyTimes = times.map { NSNumber(value: $0) }
                    animation.duration = 10
                    return animation
                }
                let group = CAAnimationGroup()
                group.animations = [fade, motion("transform.scale", s[5], s[6]),
                                    motion("transform.translation.x", s[7] * factor, s[9] * factor),
                                    motion("transform.translation.y", -s[8] * factor, -s[10] * factor)]
                group.duration = 10
                group.repeatCount = .infinity
                z.add(group, forKey: "sleep")
            }
        }
    }
    func showHammer() {
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = AnimationSpec.sequence("hammer-v2", 9).compactMap(load)
        animation.calculationMode = .discrete
        animation.duration = 0.558
        hammer.contents = nil
        hammer.add(animation, forKey: "hammer")
        let scale = Double(bounds.width / 210)
        func motion(_ target: CALayer, _ path: String, _ values: [Double], _ times: [Double], _ duration: Double) {
            let animation = CAKeyframeAnimation(keyPath: path)
            animation.values = values
            animation.keyTimes = times.map { NSNumber(value: $0 / duration) }
            animation.duration = duration
            animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: values.count - 1)
            target.add(animation, forKey: path)
        }
        motion(hammer, "transform.rotation.z", [42.0, 28, -4, -58, -43].map { $0 * Double.pi / 180 }, [0, 0.12, 0.26, 0.43, 0.62], 0.62)
        motion(hammer, "transform.translation.x", [28, 18, -4, 0].map { $0 * scale }, [0, 0.18, 0.43, 0.62], 0.62)
        motion(hammer, "transform.translation.y", [34, 26, -14, -7].map { $0 * scale }, [0, 0.18, 0.43, 0.62], 0.62)
        motion(sprite, "transform.translation.y", [0, 0, -3 * scale, 0], [0, 0.36, 0.43, 0.65], 0.65)
        motion(sprite, "transform.scale.x", [1, 1, 1.018, 1], [0, 0.36, 0.43, 0.65], 0.65)
        motion(sprite, "transform.scale.y", [1, 1, 0.975, 1], [0, 0.36, 0.43, 0.65], 0.65)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        pendingClick?.cancel()
        onInteractionStart?()
        down = NSEvent.mouseLocation
        origin = window?.frame.origin ?? .zero
        dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        let current = NSEvent.mouseLocation
        let dx = current.x - down.x, dy = current.y - down.y
        if abs(dx) + abs(dy) > 3 { dragged = true }
        if dragged { window?.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy)); onMove?() }
    }
    override func mouseUp(with event: NSEvent) {
        guard !dragged else { onDragEnd?(); return }
        let count = event.clickCount
        // Windows responds to the first strike immediately; only defer the double
        // click so a third click can open chat without starting/pausing focus.
        if count == 1 { onClick?(1); return }
        if count == 3 { onClick?(3); return }
        guard count == 2 else { return }
        let pending = DispatchWorkItem { [weak self] in self?.onClick?(count) }
        pendingClick = pending
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval + 0.075, execute: pending)
    }
    override func rightMouseDown(with event: NSEvent) {
        pendingClick?.cancel()
        onInteractionStart?()
        if let menu = makeMenu?() { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }
}

@MainActor final class DesktopController {
    let model: AppModel
    let panel: PetPanel
    let view: PetView
    let bubble: PetPanel
    private let label = NSTextField(wrappingLabelWithString: "")
    private var movementGeneration = 0
    private var positionSave: DispatchWorkItem?
    var onChat: (() -> Void)?
    var makeMenu: (() -> NSMenu)?

    init(model: AppModel) {
        self.model = model
        let rect = NSRect(x: 0, y: 0, width: 300, height: 300)
        panel = PetPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        view = PetView(frame: rect)
        bubble = PetPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        for window in [panel, bubble] {
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.isExcludedFromWindowsMenu = true
            window.animationBehavior = .none
        }
        panel.contentView = view
        bubble.ignoresMouseEvents = true
        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        label.font = NSFont.systemFont(ofSize: 14)
        label.maximumNumberOfLines = 8
        label.lineBreakMode = .byTruncatingTail
        background.addSubview(label)
        bubble.contentView = background
        view.onClick = { [weak self] count in
            guard let self else { return }
            switch count {
            case 1:
                model.singleClick()
                self.view.showHammer()
            case 2: model.toggleFocus()
            default: self.onChat?()
            }
        }
        view.onMove = { [weak self] in self?.moved() }
        view.onInteractionStart = { [weak self] in self?.movementGeneration += 1 }
        view.onDragEnd = { [weak self] in self?.clamp(); self?.moved() }
        view.makeMenu = { [weak self] in self?.makeMenu?() ?? NSMenu() }
        view.onAnimationEnd = { [weak model] in model?.restoreAnimation() }
        model.onStateChanged = { [weak self] state in self?.view.play(state, skin: model.data.settings.skin) }
        model.onSettingsChanged = { [weak self] in self?.applySettings() }
        model.onBubble = { [weak self] text in self?.showBubble(text) }
        model.onWander = { [weak self] in self?.wander() }
        applySettings()
        if let x = model.data.settings.windowX, let y = model.data.settings.windowY { panel.setFrameOrigin(NSPoint(x: x, y: y)) }
        else if let screen = NSScreen.main { panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - panel.frame.width - 30, y: screen.visibleFrame.minY + 20)) }
        clamp()
        panel.orderFrontRegardless()
    }
    func applySettings() {
        movementGeneration += 1
        panel.setContentSize(NSSize(width: 210 * model.data.settings.scale, height: 238 * model.data.settings.scale))
        for window in [panel, bubble] {
            window.level = model.data.settings.topmost ? .floating : .normal
            window.collectionBehavior = model.data.settings.allSpaces ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.moveToActiveSpace, .fullScreenAuxiliary]
        }
        panel.ignoresMouseEvents = model.clickThrough
        view.play(model.state, skin: model.data.settings.skin)
        clamp()
        positionBubble()
    }
    func recover() {
        movementGeneration += 1
        model.clickThrough = false
        panel.ignoresMouseEvents = false
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - panel.frame.width - 30, y: screen.visibleFrame.minY + 20))
        }
        panel.orderFrontRegardless()
        moved()
    }
    func hide() { movementGeneration += 1; panel.orderOut(nil); bubble.orderOut(nil) }
    func toggleClickThrough() {
        model.clickThrough.toggle()
        panel.ignoresMouseEvents = model.clickThrough
        model.say(model.clickThrough ? "鼠标穿透已开启。按 ⌃⌥P 或使用菜单栏叫回。" : "鼠标穿透已关闭。")
    }
    func clamp() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let bounds = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: min(max(panel.frame.minX, bounds.minX), bounds.maxX - panel.frame.width),
                                     y: min(max(panel.frame.minY, bounds.minY), bounds.maxY - panel.frame.height)))
    }
    private func moved() {
        movementGeneration += 1
        positionBubble()
        model.data.settings.windowX = panel.frame.minX
        model.data.settings.windowY = panel.frame.minY
        positionSave?.cancel()
        let save = DispatchWorkItem { [weak model] in model?.persist() }
        positionSave = save
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: save)
    }
    private func showBubble(_ text: String) {
        guard !text.isEmpty, panel.isVisible else { bubble.orderOut(nil); return }
        label.stringValue = text
        let size = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: 260, height: 160)) ?? NSSize(width: 260, height: 60)
        let height = min(170, max(24, size.height))
        bubble.setContentSize(NSSize(width: 284, height: height + 24))
        label.frame = NSRect(x: 12, y: 12, width: 260, height: height)
        positionBubble()
        bubble.orderFrontRegardless()
    }
    private func positionBubble() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        let x = min(max(area.minX, panel.frame.midX - bubble.frame.width / 2), area.maxX - bubble.frame.width)
        let y = min(area.maxY - bubble.frame.height, panel.frame.maxY - panel.frame.height * 0.15)
        bubble.setFrameOrigin(NSPoint(x: x, y: max(area.minY, y)))
    }
    private func wander() {
        guard panel.isVisible, NSEvent.pressedMouseButtons == 0,
              let screen = panel.screen else { return }
        let bounds = screen.visibleFrame
        let x = min(max(bounds.minX, panel.frame.minX + CGFloat.random(in: -90...90)), bounds.maxX - panel.frame.width)
        let y = min(max(bounds.minY, panel.frame.minY + CGFloat.random(in: -25...25)), bounds.maxY - panel.frame.height)
        // Small discrete position steps avoid a permanent rendering loop when idle.
        let start = panel.frame.origin
        movementGeneration += 1
        let generation = movementGeneration
        for step in 1...20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.05) { [weak self] in
                guard let self, self.movementGeneration == generation else { return }
                guard NSEvent.pressedMouseButtons == 0, self.model.data.settings.wander, self.model.state == .idle else {
                    self.movementGeneration += 1
                    return
                }
                let t = CGFloat(step) / 20
                self.panel.setFrameOrigin(NSPoint(x: start.x + (x - start.x) * t, y: start.y + (y - start.y) * t))
                self.positionBubble()
                if step == 20 { self.moved() }
            }
        }
    }
}
