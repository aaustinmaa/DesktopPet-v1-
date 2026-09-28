import AppKit

// Matches SpeechBubbleWindow.xaml: 96 pt canvas, 14 pt corners,
// 1.5 pt jade outline, 12 pt semibold centered text and a 16 × 9 tail.
@MainActor final class SpeechBubbleView: NSView {
    private let label = NSTextField(wrappingLabelWithString: "")
    var tailX: CGFloat? { didSet { needsDisplay = true } }
    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = NSColor(red: 40/255, green: 72/255, blue: 82/255, alpha: 1)
        label.alignment = .center
        label.maximumNumberOfLines = 4
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setMessage(_ text: String) { label.stringValue = text; needsLayout = true; needsDisplay = true }
    private var textHeight: CGFloat {
        min(63, max(16, label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: max(1, bounds.width - 28), height: 63)).height ?? 16))
    }
    override func layout() {
        super.layout()
        label.frame = NSRect(x: 14, y: 18, width: max(1, bounds.width - 28), height: textHeight)
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let background = NSColor(red: 240/255, green: 246/255, blue: 245/255, alpha: 1)
        let outline = NSColor(red: 136/255, green: 191/255, blue: 184/255, alpha: 1)
        let card = NSBezierPath(roundedRect: NSRect(x: 3, y: 10, width: bounds.width - 6, height: min(83, textHeight + 16)), xRadius: 14, yRadius: 14)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(red: 40/255, green: 72/255, blue: 82/255, alpha: 0.16)
        shadow.shadowBlurRadius = 13
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        shadow.set()
        background.setFill(); card.fill()
        NSGraphicsContext.restoreGraphicsState()
        outline.setStroke(); card.lineWidth = 1.5; card.stroke()
        let x = min(bounds.width - 24, max(24, tailX ?? bounds.midX))
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: x - 8, y: 11))
        tail.line(to: NSPoint(x: x, y: 2))
        tail.line(to: NSPoint(x: x + 8, y: 11))
        tail.close()
        background.setFill(); tail.fill()
        outline.setStroke(); tail.lineWidth = 1.5; tail.stroke()
    }
}
