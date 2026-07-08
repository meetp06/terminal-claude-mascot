// Codable models mirroring shared/protocol.md. Kept intentionally lenient
// (optionals + defaults) so a protocol tweak on the sidecar never crashes the app.
import Foundation

struct Skill: Codable, Identifiable, Hashable {
    var id: String
    var agentId: String
    var name: String
    var trigger: String
    var tools: [String]
    var prompt: String
}

struct Agent: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var role: String        // manager | worker
    var type: String        // files | news | editor | custom
    var rank: String        // newbie | senior
    var status: String      // alive | sleeping | working | paused
    var visible: Bool
    var skills: [Skill]

    var isManager: Bool { role == "manager" }
    var isNewbie: Bool { rank == "newbie" }
}

struct Suggestion: Codable, Identifiable, Hashable {
    var id: String
    var agentId: String
    var title: String
    var body: String
    var proposedAction: String
    var score: Double
    var status: String
    var createdAt: Double
}

struct WorkItem: Codable, Identifiable, Hashable {
    var id: String
    var suggestionId: String
    var agentId: String
    var title: String
    var objective: String
    var status: String
    var result: String
    var createdAt: Double
    var updatedAt: Double
}

struct SharedMemory: Codable, Identifiable, Hashable {
    var id: String
    var sourceAgentId: String
    var targetAgentId: String
    var topic: String
    var title: String
    var summary: String
    var kind: String
    var tokenEstimate: Int
    var createdAt: Double
}

struct AgentActivity: Codable, Identifiable, Hashable {
    var id: String { "\(agentId)-\(phase)-\(createdAt)" }
    var agentId: String
    var phase: String
    var title: String
    var detail: String
    var createdAt: Double
}

struct ChatMessage: Codable, Identifiable, Hashable {
    var id: String
    var sender: String      // user | manager
    var text: String
    var createdAt: Double
}

struct Settings: Codable, Hashable {
    var provider: String
    var model: String
    var safe_mode: String
    var launch_at_login: String
    var keys: [String: Bool]?

    static let empty = Settings(provider: "ollama", model: "llama3.2",
                                safe_mode: "readonly", launch_at_login: "false",
                                keys: [:])
}
