// One borderless, transparent, click-through window per on-screen agent.
// Draws a compact sprite and an optional activity bubble that fades out.
import AppKit

final class AgentOverlayWindow {
    let agentId: String
    let window: NSWindow
    private let container: NSView
    private let sprite: AgentSpriteView
    private let bubble: SpeechBubbleView
    private var bubbleHideAt: Date?

    private let scale: CGFloat
    private let lane = 22
    private let bubbleHeight: CGFloat

    init(agent: Agent, origin: NSPoint, scale: CGFloat = 2.5) {
        self.agentId = agent.id
        self.scale = scale
        bubbleHeight = scale > 2.7 ? 46 : 40
        let tint = AgentOverlayWindow.tint(for: agent)
        sprite = AgentSpriteView(tint: tint, scale: scale, lane: lane)

        let spriteW = sprite.frame.width
        let spriteH = sprite.frame.height
        let width = max(spriteW, scale > 2.7 ? 190 : 160)
        let height = spriteH + 4 + bubbleHeight
        container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        // layout bottom -> top: sprite, temporary bubble
        sprite.frame.origin = NSPoint(x: (width - spriteW) / 2, y: 0)

        bubble = SpeechBubbleView(frame: NSRect(x: 0, y: spriteH + 4,
                                                width: width, height: bubbleHeight))
        bubble.isHidden = true
        bubble.accent = tint

        container.addSubview(bubble)
        container.addSubview(sprite)

        window = NSWindow(contentRect: NSRect(origin: origin, size: container.frame.size),
                          styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .floating
        window.ignoresMouseEvents = true          // click-through
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = container
    }

    static func tint(for agent: Agent) -> NSColor {
        if agent.isManager {
            return NSColor(srgbRed: 217/255, green: 119/255, blue: 87/255, alpha: 1) // warm orange
        }
        if agent.isNewbie {
            return NSColor(srgbRed: 120/255, green: 210/255, blue: 120/255, alpha: 1) // green newbie
        }
        return NSColor(srgbRed: 100/255, green: 180/255, blue: 240/255, alpha: 1)     // senior blue
    }

    var contentSize: NSSize { container.frame.size }

    func show() { window.orderFrontRegardless() }
    func hide() { window.orderOut(nil) }

    func setState(_ s: PetState) { sprite.setState(s) }
    func faceLeft(_ left: Bool) { sprite.facingLeft = left }

    func setTint(for agent: Agent) {
        let t = AgentOverlayWindow.tint(for: agent)
        sprite.tint = t
    }

    func say(_ text: String) {
        bubble.text = text
        bubble.accent = NSColor(srgbRed: 250/255, green: 204/255, blue: 80/255, alpha: 1)
        bubble.isHidden = false
        bubbleHideAt = Date().addingTimeInterval(9)
    }

    func showActivity(_ activity: AgentActivity) {
        let cleanDetail = activity.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = short(cleanDetail, limit: 54)
        bubble.text = detail.isEmpty ? activity.title : "\(activity.title)\n\(detail)"
        bubble.accent = accent(for: activity.phase)
        bubble.isHidden = false
        bubbleHideAt = Date().addingTimeInterval(ttl(for: activity.phase))
    }

    func hideActivity() {
        bubble.isHidden = true
        bubbleHideAt = nil
    }

    func tick() {
        sprite.tick()
        if let t = bubbleHideAt, Date() > t {
            bubble.isHidden = true
            bubbleHideAt = nil
        }
    }

    func setPosition(_ p: NSPoint) { window.setFrameOrigin(p) }

    private func ttl(for phase: String) -> TimeInterval {
        switch phase {
        case "waiting": return 4
        case "suggestion_found", "work_started", "work_complete", "error": return 10
        default: return 7
        }
    }

    private func accent(for phase: String) -> NSColor {
        switch phase {
        case "suggestion_found":
            return NSColor(srgbRed: 250/255, green: 204/255, blue: 80/255, alpha: 1)
        case "work_started":
            return NSColor(srgbRed: 101/255, green: 146/255, blue: 177/255, alpha: 1)
        case "work_complete":
            return NSColor(srgbRed: 80/255, green: 220/255, blue: 112/255, alpha: 1)
        case "error":
            return NSColor(srgbRed: 245/255, green: 90/255, blue: 84/255, alpha: 1)
        case "researching_web":
            return NSColor(srgbRed: 101/255, green: 146/255, blue: 177/255, alpha: 1)
        default:
            return AgentOverlayWindow.tint(forPhaseFallback: sprite.tint)
        }
    }

    private func short(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(max(0, limit - 3))) + "..."
    }

    private static func tint(forPhaseFallback color: NSColor) -> NSColor { color }
}
