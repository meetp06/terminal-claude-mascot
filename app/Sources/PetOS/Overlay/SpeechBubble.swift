// A tiny rounded speech bubble drawn above an agent.
import AppKit

final class SpeechBubbleView: NSView {
    var text: String = "" { didSet { needsDisplay = true } }
    var accent: NSColor = NSColor(srgbRed: 112/255, green: 185/255, blue: 176/255, alpha: 1) {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty else { return }
        let inset: CGFloat = 5
        let rect = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor(white: 0.06, alpha: 0.84).setFill()
        path.fill()
        accent.withAlphaComponent(0.62).setStroke()
        path.lineWidth = 1
        path.stroke()

        let accentRect = NSRect(x: rect.minX + 6, y: rect.maxY - 6, width: rect.width - 12, height: 2)
        let accentPath = NSBezierPath(roundedRect: accentRect, xRadius: 1, yRadius: 1)
        accent.withAlphaComponent(0.75).setFill()
        accentPath.fill()

        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: style,
        ]
        let textRect = rect.insetBy(dx: inset, dy: inset + 1)
        (text as NSString).draw(in: textRect, withAttributes: attrs)
    }
}
