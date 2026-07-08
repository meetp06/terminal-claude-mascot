// Owns the on-screen agent windows and keeps them in sync with the sidecar.
// Visible agents stay anchored near a screen corner. Motion is reserved for
// meaningful state changes: scan turns, focused poses, and suggestion hops.
import AppKit

@MainActor
final class OverlayController {
    private struct LiveActivity {
        var phase: String
        var title: String
        var detail: String
        var expiresAt: Date
    }

    private enum Mode: String { case off, minimal, active }
    private enum Size: String { case small, medium }
    private enum BubblePolicy: String { case important, all }
    private enum Position: String { case bottomRight, bottomLeft }

    private var windows: [String: AgentOverlayWindow] = [:]
    private var baseState: [String: PetState] = [:]
    private var activities: [String: LiveActivity] = [:]
    private var agents: [Agent] = []
    private var timer: Timer?
    private var mode: Mode = .minimal
    private var size: Size = .small
    private var bubblePolicy: BubblePolicy = .important
    private var position: Position = .bottomRight

    private func state(for agent: Agent) -> PetState {
        switch agent.status {
        case "paused":  return .sleep
        case "working": return .work
        default:        return .wander
        }
    }

    private func state(for activity: LiveActivity) -> PetState {
        switch activity.phase {
        case "observing": return .scan
        case "reading_files": return .readFiles
        case "checking_editor": return .scan
        case "researching_web": return .research
        case "thinking": return .think
        case "sharing_context": return .think
        case "suggestion_found": return .found
        case "work_started": return .work
        case "work_complete": return .found
        case "error": return .alert
        default: return .wander
        }
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.06, target: self,     // ~16 fps for smooth motion
                      selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func configure(mode: String, size: String, bubbles: String, position: String) {
        let nextMode = Mode(rawValue: mode) ?? .minimal
        let nextSize = Size(rawValue: size) ?? .small
        let nextBubbles = BubblePolicy(rawValue: bubbles) ?? .important
        let nextPosition = Position(rawValue: position) ?? .bottomRight
        let sizeChanged = self.size != nextSize

        self.mode = nextMode
        self.size = nextSize
        self.bubblePolicy = nextBubbles
        self.position = nextPosition

        if sizeChanged {
            hideAndClearWindows()
        }
        sync(agents)
    }

    func sync(_ agents: [Agent]) {
        self.agents = agents
        let ids = Set(agents.map { $0.id })
        for id in Array(windows.keys) where !ids.contains(id) {
            windows[id]?.hide()
            windows.removeValue(forKey: id)
            baseState.removeValue(forKey: id)
            activities.removeValue(forKey: id)
        }

        guard let screen = NSScreen.main else { return }
        let vis = screen.visibleFrame

        if mode == .off {
            for win in windows.values { win.hide() }
            return
        }

        var visibleIndex = 0
        for agent in agents {
            let win: AgentOverlayWindow
            if let existing = windows[agent.id] {
                win = existing
                win.setTint(for: agent)
            } else {
                win = AgentOverlayWindow(agent: agent, origin: .zero, scale: scale)
                windows[agent.id] = win
            }
            baseState[agent.id] = state(for: agent)

            if shouldDisplay(agent) {
                win.show()
                win.faceLeft(position == .bottomRight)
                win.setPosition(anchor(for: win, in: vis, index: visibleIndex))
                visibleIndex += 1
            } else {
                win.hide()
            }
        }
    }

    @objc private func tick() {
        for (id, win) in windows {
            if let live = activities[id], live.expiresAt <= Date() {
                activities.removeValue(forKey: id)
            }
            if let agent = agents.first(where: { $0.id == id }), !shouldDisplay(agent) {
                win.hide()
                continue
            }
            let s = activities[id].map(state(for:)) ?? baseState[id] ?? .wander
            win.setState(s)
            win.tick()
        }
    }

    func showSuggestion(agentId: String, text: String) {
        guard mode != .off else { return }
        windows[agentId]?.say(text)
    }

    func showActivity(_ activity: AgentActivity) {
        guard mode != .off else { return }
        if activity.phase == "waiting" {
            activities.removeValue(forKey: activity.agentId)
            windows[activity.agentId]?.hideActivity()
            sync(agents)
            return
        }

        if bubblePolicy == .important && !isImportant(activity.phase) {
            activities[activity.agentId] = LiveActivity(
                phase: activity.phase,
                title: activity.title,
                detail: activity.detail,
                expiresAt: Date().addingTimeInterval(ttl(for: activity.phase))
            )
            sync(agents)
            return
        }

        activities[activity.agentId] = LiveActivity(
            phase: activity.phase,
            title: activity.title,
            detail: activity.detail,
            expiresAt: Date().addingTimeInterval(ttl(for: activity.phase))
        )
        sync(agents)
        windows[activity.agentId]?.showActivity(activity)
    }

    private func ttl(for phase: String) -> TimeInterval {
        switch phase {
        case "waiting": return 4
        case "suggestion_found", "work_started", "work_complete", "error": return 10
        default: return 7
        }
    }

    private var scale: CGFloat {
        switch size {
        case .small: return 2.5
        case .medium: return 3.25
        }
    }

    private func anchor(for win: AgentOverlayWindow, in vis: NSRect, index: Int) -> NSPoint {
        let marginX: CGFloat = 28
        let marginY: CGFloat = 42
        let gap: CGFloat = 10
        let size = win.contentSize
        let x: CGFloat
        switch position {
        case .bottomRight:
            x = vis.maxX - size.width - marginX
        case .bottomLeft:
            x = vis.minX + marginX
        }
        let y = vis.minY + marginY + CGFloat(index) * (size.height + gap)
        return NSPoint(x: x, y: min(y, vis.maxY - size.height - marginY))
    }

    private func hideAndClearWindows() {
        for win in windows.values { win.hide() }
        windows.removeAll()
        activities.removeAll()
        baseState.removeAll()
    }

    private func isImportant(_ phase: String) -> Bool {
        switch phase {
        case "suggestion_found", "work_started", "work_complete", "error":
            return true
        default:
            return false
        }
    }

    private func shouldDisplay(_ agent: Agent) -> Bool {
        guard agent.visible else { return false }
        switch mode {
        case .off:
            return false
        case .active:
            return true
        case .minimal:
            return agent.isManager || agent.status == "working" || activities[agent.id] != nil
        }
    }
}
