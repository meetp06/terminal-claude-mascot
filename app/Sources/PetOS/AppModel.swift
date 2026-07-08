// The single source of truth the SwiftUI dashboard binds to. Owns the sidecar,
// the WebSocket, and the on-screen overlay, translating protocol messages into
// published state and UI actions into protocol commands.
import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var connected = false
    @Published var agents: [Agent] = []
    @Published var suggestions: [Suggestion] = []
    @Published var workItems: [WorkItem] = []
    @Published var agentMemory: [SharedMemory] = []
    @Published var messages: [ChatMessage] = []
    @Published var settings: Settings = .empty
    @Published var ollamaModels: [String] = []
    @Published var safeMode: String = "readonly"
    @Published var tools: [String] = []
    @Published var activities: [String: AgentActivity] = [:]
    @Published var activityTimeline: [AgentActivity] = []
    @Published var log: [String] = []

    let overlay = OverlayController()
    private let sidecar = SidecarManager()
    private let ws = WSClient()
    private var appliedFocusModeAfterSnapshot = false

    var aliveCount: Int { agents.filter { $0.status != "paused" }.count }
    var visibleCount: Int { agents.filter { $0.visible }.count }

    func start() {
        applyMascotPreferences()
        overlay.start()
        ws.onConnected = { [weak self] c in self?.connected = c }
        ws.onMessage = { [weak self] msg in self?.handle(msg) }
        sidecar.start { [weak self] url in
            self?.ws.connect(urlString: url)
        }
    }

    func stop() {
        ws.stop()
        sidecar.stop()
    }

    // MARK: - Inbound

    private func handle(_ msg: [String: Any]) {
        guard let type = msg["type"] as? String else { return }
        switch type {
        case "snapshot":
            if let a = decodeArray(msg["agents"], as: Agent.self) {
                agents = a
                overlay.sync(a)
                applyFocusModeAfterSnapshotIfNeeded()
            }
            if let s = decodeArray(msg["suggestions"], as: Suggestion.self) { suggestions = s }
            if let w = decodeArray(msg["workItems"], as: WorkItem.self) { workItems = w }
            if let m = decodeArray(msg["agentMemory"], as: SharedMemory.self) { agentMemory = m }
            if let m = decodeArray(msg["messages"], as: ChatMessage.self) { messages = m }
            if let set = decode(msg["settings"], as: Settings.self) { settings = set }
            if let sm = msg["safeMode"] as? String { safeMode = sm }
            if let t = msg["tools"] as? [String] { tools = t }
        case "agents":
            if let a = decodeArray(msg["agents"], as: Agent.self) { agents = a; overlay.sync(a) }
        case "agent_update":
            if let a = decode(msg["agent"], as: Agent.self) { upsertAgent(a) }
        case "agent_activity":
            if let a = decode(msg["activity"], as: AgentActivity.self) { updateActivity(a) }
        case "agent_memory":
            if let m = decode(msg["memory"], as: SharedMemory.self) { addMemory(m) }
        case "work_item":
            if let w = decode(msg["workItem"], as: WorkItem.self) { upsertWorkItem(w) }
        case "work_item_update":
            if let w = decode(msg["workItem"], as: WorkItem.self) { upsertWorkItem(w) }
        case "suggestion":
            if let s = decode(msg["suggestion"], as: Suggestion.self) { addSuggestion(s) }
        case "suggestion_update":
            if let s = decode(msg["suggestion"], as: Suggestion.self) { updateSuggestion(s) }
        case "chat":
            if let m = decode(msg["message"], as: ChatMessage.self) { messages.append(m) }
        case "settings":
            if let set = decode(msg["settings"], as: Settings.self) { settings = set }
        case "ollama_models":
            if let m = msg["models"] as? [String] { ollamaModels = m }
        case "log":
            let text = (msg["text"] as? String) ?? ""
            log.append(text); if log.count > 200 { log.removeFirst(log.count - 200) }
        case "error":
            log.append("error: " + ((msg["text"] as? String) ?? ""))
        default:
            break
        }
    }

    private func upsertAgent(_ a: Agent) {
        if let i = agents.firstIndex(where: { $0.id == a.id }) { agents[i] = a }
        else { agents.append(a) }
        overlay.sync(agents)
    }

    private func addSuggestion(_ s: Suggestion) {
        suggestions.insert(s, at: 0)
        overlay.showSuggestion(agentId: s.agentId, text: s.title)
    }

    private func updateActivity(_ activity: AgentActivity) {
        activities[activity.agentId] = activity
        activityTimeline.insert(activity, at: 0)
        if activityTimeline.count > 200 {
            activityTimeline.removeLast(activityTimeline.count - 200)
        }
        overlay.showActivity(activity)
    }

    private func updateSuggestion(_ s: Suggestion) {
        if s.status != "new" {
            suggestions.removeAll { $0.id == s.id }
        } else if let i = suggestions.firstIndex(where: { $0.id == s.id }) {
            suggestions[i] = s
        }
    }

    private func upsertWorkItem(_ item: WorkItem) {
        if let i = workItems.firstIndex(where: { $0.id == item.id }) {
            workItems[i] = item
        } else {
            workItems.insert(item, at: 0)
        }
        workItems.sort { $0.updatedAt > $1.updatedAt }
        if workItems.count > 80 {
            workItems.removeLast(workItems.count - 80)
        }
    }

    private func addMemory(_ memory: SharedMemory) {
        if let i = agentMemory.firstIndex(where: { $0.id == memory.id }) {
            agentMemory[i] = memory
        } else {
            agentMemory.insert(memory, at: 0)
        }
        if agentMemory.count > 150 {
            agentMemory.removeLast(agentMemory.count - 150)
        }
    }

    // MARK: - Outbound commands

    func createAgent(name: String, type: String) {
        ws.send(["type": "create_agent",
                 "agent": ["name": name, "role": "worker", "type": type, "rank": "newbie"]])
    }
    func deleteAgent(_ id: String) { ws.send(["type": "delete_agent", "id": id]) }
    func setVisible(_ id: String, _ visible: Bool) {
        ws.send(["type": "update_agent", "id": id, "patch": ["visible": visible]])
    }
    func setPaused(_ id: String, _ paused: Bool) {
        ws.send(["type": "update_agent", "id": id, "patch": ["status": paused ? "paused" : "sleeping"]])
    }
    func rename(_ id: String, _ name: String) {
        ws.send(["type": "update_agent", "id": id, "patch": ["name": name]])
    }
    func addSkill(agentId: String, name: String, trigger: String, tools: [String]) {
        ws.send(["type": "add_skill", "agentId": agentId,
                 "skill": ["name": name, "trigger": trigger, "tools": tools, "prompt": ""]])
    }
    func removeSkill(_ skillId: String) { ws.send(["type": "remove_skill", "skillId": skillId]) }
    func chat(_ text: String) {
        messages.append(ChatMessage(id: UUID().uuidString, sender: "user", text: text,
                                    createdAt: Date().timeIntervalSince1970))
        ws.send(["type": "chat", "text": text])
    }
    func act(on suggestion: Suggestion, approve: Bool) {
        ws.send(["type": "suggestion_action", "id": suggestion.id,
                 "action": approve ? "approve" : "dismiss"])
        suggestions.removeAll { $0.id == suggestion.id }
    }
    func updateSettings(_ patch: [String: Any]) {
        ws.send(["type": "update_settings", "patch": patch])
    }
    func setApiKey(provider: String, key: String) {
        ws.send(["type": "set_api_key", "provider": provider, "key": key])
    }
    func refreshOllamaModels() { ws.send(["type": "list_ollama_models"]) }
    func sendFrontmost(app: String?, bundleId: String?) {
        ws.send(["type": "frontmost", "app": app ?? "", "bundleId": bundleId ?? ""])
    }
    func sendSystem(_ state: String) { ws.send(["type": "system", "state": state]) }

    func applyFocusMode(_ mode: String) {
        switch mode {
        case "quiet":
            updateMascotPreferences(mode: "minimal", size: mascotSize, bubbles: "important", position: mascotPosition)
        case "work":
            updateMascotPreferences(mode: "minimal", size: mascotSize, bubbles: "important", position: mascotPosition)
            for agent in agents where agent.role == "worker" {
                let active = agent.type == "files" || agent.type == "editor" || agent.type == "custom"
                setPaused(agent.id, !active)
                setVisible(agent.id, active)
            }
        case "research":
            updateMascotPreferences(mode: "minimal", size: mascotSize, bubbles: "all", position: mascotPosition)
            for agent in agents where agent.role == "worker" {
                let active = agent.type == "news" || agent.type == "custom"
                setPaused(agent.id, !active)
                setVisible(agent.id, active)
            }
        case "dnd":
            updateMascotPreferences(mode: "off", size: mascotSize, bubbles: "important", position: mascotPosition)
            for agent in agents where agent.role == "worker" {
                setPaused(agent.id, true)
            }
        default:
            updateMascotPreferences(mode: "minimal", size: mascotSize, bubbles: "important", position: mascotPosition)
        }
    }

    func applyMascotPreferences() {
        let d = UserDefaults.standard
        overlay.configure(
            mode: d.string(forKey: "petos.mascot.mode") ?? "minimal",
            size: d.string(forKey: "petos.mascot.size") ?? "small",
            bubbles: d.string(forKey: "petos.mascot.bubbles") ?? "important",
            position: d.string(forKey: "petos.mascot.position") ?? "bottomRight")
    }

    func updateMascotPreferences(mode: String, size: String, bubbles: String, position: String) {
        let d = UserDefaults.standard
        d.set(mode, forKey: "petos.mascot.mode")
        d.set(size, forKey: "petos.mascot.size")
        d.set(bubbles, forKey: "petos.mascot.bubbles")
        d.set(position, forKey: "petos.mascot.position")
        overlay.configure(mode: mode, size: size, bubbles: bubbles, position: position)
    }

    private var mascotSize: String {
        UserDefaults.standard.string(forKey: "petos.mascot.size") ?? "small"
    }

    private var mascotPosition: String {
        UserDefaults.standard.string(forKey: "petos.mascot.position") ?? "bottomRight"
    }

    private func applyFocusModeAfterSnapshotIfNeeded() {
        guard !appliedFocusModeAfterSnapshot else { return }
        appliedFocusModeAfterSnapshot = true
        let focusMode = UserDefaults.standard.string(forKey: "petos.focus.mode") ?? "quiet"
        if focusMode != "quiet" {
            applyFocusMode(focusMode)
        }
    }

    // MARK: - Decoding helpers

    private func decode<T: Decodable>(_ any: Any?, as: T.Type) -> T? {
        guard let any = any,
              let data = try? JSONSerialization.data(withJSONObject: any) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    private func decodeArray<T: Decodable>(_ any: Any?, as: T.Type) -> [T]? {
        guard let arr = any as? [Any] else { return nil }
        return arr.compactMap { decode($0, as: T.self) }
    }
}
