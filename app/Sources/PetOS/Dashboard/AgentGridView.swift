// Admin view: create custom agents, and per-agent controls for visibility,
// pause/resume, rename, delete, and skills.
import SwiftUI

struct AgentGridView: View {
    @EnvironmentObject var model: AppModel
    @State private var newName = ""
    @State private var newType = "custom"
    @State private var selectedAgentId: String?
    @AppStorage("petos.ui.inspectorVisible") private var inspectorVisible = false

    private let types = ["custom", "files", "news", "editor"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            createBar
            if model.agents.isEmpty {
                EmptyStateView(
                    icon: "person.3.sequence.fill",
                    title: "Waiting for agents",
                    subtitle: "The local runtime will populate this workspace as soon as it connects.")
            } else {
                HStack(alignment: .top, spacing: 14) {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 8) {
                            ForEach(model.agents) { agent in
                                AgentRow(
                                    agent: agent,
                                    selected: inspectorVisible && selectedAgentId == agent.id,
                                    onInspect: {
                                        selectedAgentId = agent.id
                                        inspectorVisible = true
                                    }
                                )
                            }
                        }
                        .padding(.vertical, 2)
                        .padding(.bottom, 18)
                    }

                    if inspectorVisible, let selectedAgent {
                        AgentInspector(agent: selectedAgent)
                            .frame(width: 310)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: inspectorVisible)
            }
        }
        .onAppear {
            if selectedAgentId == nil {
                selectedAgentId = model.agents.first?.id
            }
        }
        .onChange(of: model.agents) { agents in
            if let selectedAgentId, agents.contains(where: { $0.id == selectedAgentId }) {
                return
            }
            selectedAgentId = agents.first?.id
        }
    }

    private var createBar: some View {
        HStack(spacing: 10) {
            Label("New agent", systemImage: "plus.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.strongText)
                .frame(width: 108, alignment: .leading)
            TextField("New agent name", text: $newName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
            Picker("", selection: $newType) {
                ForEach(types, id: \.self) { Text($0.capitalized) }
            }
            .frame(width: 130)
            Button {
                let name = newName.isEmpty ? "Newbie" : newName
                model.createAgent(name: name, type: newType)
                newName = ""
            } label: { Label("Create", systemImage: "plus") }
            .buttonStyle(.borderedProminent)
            Spacer()
            Button {
                if selectedAgentId == nil {
                    selectedAgentId = model.agents.first?.id
                }
                inspectorVisible.toggle()
            } label: {
                Label(inspectorVisible ? "Hide details" : "Show details",
                      systemImage: inspectorVisible ? "sidebar.right" : "sidebar.right")
            }
            .buttonStyle(.bordered)
            .disabled(model.agents.isEmpty)
        }
        .controlSize(.regular)
        .glassPanel(padding: 12, raised: true)
    }

    private var selectedAgent: Agent? {
        model.agents.first { $0.id == selectedAgentId } ?? model.agents.first
    }
}

private struct AgentRow: View {
    @EnvironmentObject var model: AppModel
    let agent: Agent
    let selected: Bool
    let onInspect: () -> Void
    @State private var skillName = ""
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                identityColumn
                activityColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
                controlsColumn
            }

            HStack(alignment: .center, spacing: 12) {
                modeColumn
                Divider()
                    .frame(height: 24)
                    .overlay(Brand.hairline)
                skillsColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(padding: 12, raised: hovering)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Brand.teal.opacity(0.65) : Color.clear, lineWidth: 1)
        )
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: hovering || selected)
    }

    private var identityColumn: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: agent.isManager ? "sparkles" : "pawprint.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(agent.name)
                        .font(.headline)
                        .foregroundStyle(Brand.strongText)
                        .lineLimit(1)
                    badge
                }
                HStack(spacing: 7) {
                    StatusDot(color: statusColor)
                    Text(agent.status.capitalized)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(statusColor)
                }
            }
        }
        .frame(minWidth: 210, alignment: .leading)
    }

    private var modeColumn: some View {
        HStack(spacing: 6) {
            Pill(text: agent.type.capitalized, color: Brand.blue)
            if agent.visible {
                Pill(text: "Visible", color: .green, icon: "eye.fill")
            } else {
                Pill(text: "Hidden", color: .secondary, icon: "eye.slash.fill")
            }
        }
    }

    private var activityColumn: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: rowActivityIcon)
                .font(.caption)
                .foregroundStyle(rowActivityColor)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(activityTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.strongText)
                    .lineLimit(1)
                Text(activityDetail)
                    .font(.caption2)
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
            }
        }
    }

    private var skillsColumn: some View {
        HStack(spacing: 8) {
            if let first = agent.skills.first {
                HStack(spacing: 7) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                        .foregroundStyle(Brand.teal)
                    Text(first.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    if agent.skills.count > 1 {
                        Text("+\(agent.skills.count - 1)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Brand.muted)
                    }
                    Spacer(minLength: 2)
                    Button {
                        model.removeSkill(first.id)
                    } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .help("Remove skill")
                }
            } else {
                Text("No skills")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
            }

            HStack(spacing: 6) {
                TextField("Add skill", text: $skillName)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(maxWidth: 180)
                Button {
                    guard !skillName.isEmpty else { return }
                    model.addSkill(agentId: agent.id, name: skillName,
                                   trigger: "schedule", tools: model.tools)
                    skillName = ""
                } label: { Image(systemName: "plus.circle") }
                .buttonStyle(.borderless)
                .help("Add skill")
            }
        }
    }

    private var controlsColumn: some View {
        HStack(spacing: 10) {
            Button(action: onInspect) {
                Image(systemName: "info.circle")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Show agent details")

            Toggle("Show", isOn: Binding(
                get: { agent.visible },
                set: { model.setVisible(agent.id, $0) }))
            .toggleStyle(.switch)

            Toggle("Pause", isOn: Binding(
                get: { agent.status == "paused" },
                set: { model.setPaused(agent.id, $0) }))
            .toggleStyle(.switch)

            if !agent.isManager {
                Button(role: .destructive) {
                    model.deleteAgent(agent.id)
                } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Delete agent")
            }
        }
        .font(.caption)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var color: Color {
        if agent.isManager { return .orange }
        if agent.isNewbie { return .green }
        return .blue
    }
    private var statusColor: Color {
        switch agent.status {
        case "working": return .blue
        case "paused": return .secondary
        default: return .green
        }
    }
    private var badge: some View {
        Pill(text: agent.isManager ? "MANAGER" : agent.rank.uppercased(), color: color)
    }

    private var activityTitle: String {
        model.activities[agent.id]?.title ?? (agent.status == "paused" ? "Paused" : "Standing by")
    }

    private var activityDetail: String {
        if let activity = model.activities[agent.id], !activity.detail.isEmpty {
            return activity.detail
        }
        return agent.visible ? "Ready to observe on the next scan." : "Hidden from the desktop overlay."
    }

    private var rowActivityIcon: String {
        guard let activity = model.activities[agent.id] else {
            return agent.status == "paused" ? "pause.circle.fill" : "circle.dotted"
        }
        return activityIcon(for: activity.phase)
    }

    private var rowActivityColor: Color {
        guard let activity = model.activities[agent.id] else {
            return agent.status == "paused" ? .secondary : Brand.teal
        }
        return activityColor(for: activity.phase)
    }
}

private struct AgentInspector: View {
    @EnvironmentObject var model: AppModel
    let agent: Agent

    private var timeline: [AgentActivity] {
        Array(model.activityTimeline.filter { $0.agentId == agent.id }.prefix(8))
    }

    private var suggestions: [Suggestion] {
        Array(model.suggestions.filter { $0.agentId == agent.id }.prefix(4))
    }

    private var memories: [SharedMemory] {
        Array(model.agentMemory.filter { memory in
            memory.sourceAgentId == agent.id ||
            memory.targetAgentId == agent.id ||
            memory.targetAgentId.isEmpty
        }.prefix(5))
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(agentColor.opacity(0.18))
                            .frame(width: 42, height: 42)
                        Image(systemName: agent.isManager ? "sparkles" : "pawprint.fill")
                            .foregroundStyle(agentColor)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(agent.name)
                            .font(.headline)
                            .foregroundStyle(Brand.strongText)
                        Text("\(agent.type.capitalized) agent")
                            .font(.caption)
                            .foregroundStyle(Brand.muted)
                    }
                    Spacer()
                }

                HStack(spacing: 8) {
                    Pill(text: agent.status.capitalized, color: statusColor)
                    Pill(text: agent.visible ? "Visible" : "Hidden",
                         color: agent.visible ? .green : .secondary,
                         icon: agent.visible ? "eye.fill" : "eye.slash.fill")
                }

                inspectorSection("Last activity", icon: "waveform.path.ecg") {
                    if let activity = model.activities[agent.id] {
                        activityLine(activity)
                    } else {
                        mutedText(agent.status == "paused" ? "Paused by user." : "No live activity yet.")
                    }
                }

                inspectorSection("Timeline", icon: "clock.arrow.circlepath") {
                    if timeline.isEmpty {
                        mutedText("Activity will appear here as this agent observes.")
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(timeline) { activity in
                                activityLine(activity)
                            }
                        }
                    }
                }

                inspectorSection("Suggestions", icon: "lightbulb.fill") {
                    if suggestions.isEmpty {
                        mutedText("No pending suggestions from this agent.")
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(suggestions) { suggestion in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(suggestion.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Brand.strongText)
                                        .lineLimit(1)
                                    Text(String(format: "%.0f%% confidence", suggestion.score * 100))
                                        .font(.caption2)
                                        .foregroundStyle(Brand.muted)
                                }
                            }
                        }
                    }
                }

                inspectorSection("Shared memory", icon: "arrow.triangle.branch") {
                    if memories.isEmpty {
                        mutedText("Compact handoffs will appear here after scans or approved work.")
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(memories) { memory in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(memory.title)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Brand.strongText)
                                            .lineLimit(1)
                                        Text("~\(memory.tokenEstimate)t")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(Brand.muted)
                                    }
                                    Text(memory.summary)
                                        .font(.caption2)
                                        .foregroundStyle(Brand.muted)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }

                inspectorSection("Allowed tools", icon: "lock.shield.fill") {
                    if agent.skills.isEmpty {
                        mutedText(model.tools.isEmpty ? "Runtime tools will appear after connect." : model.tools.joined(separator: ", "))
                    } else {
                        Text(agent.skills.flatMap(\.tools).isEmpty ? "No tools assigned." : agent.skills.flatMap(\.tools).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(Brand.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .glassPanel(padding: 14, raised: true)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .topTrailing) {
            Text("Details")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Brand.muted)
                .padding(10)
        }
    }

    private func inspectorSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(Brand.strongText)
            content()
        }
        .padding(.top, 2)
    }

    private func activityLine(_ activity: AgentActivity) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: activityIcon(for: activity.phase))
                .font(.caption2)
                .foregroundStyle(activityColor(for: activity.phase))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(activity.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.strongText)
                        .lineLimit(1)
                    Text(relativeTime(activity.createdAt))
                        .font(.caption2)
                        .foregroundStyle(Brand.muted)
                }
                if !activity.detail.isEmpty {
                    Text(activity.detail)
                        .font(.caption2)
                        .foregroundStyle(Brand.muted)
                        .lineLimit(2)
                }
            }
        }
    }

    private func mutedText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Brand.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var agentColor: Color {
        if agent.isManager { return .orange }
        if agent.isNewbie { return .green }
        return .blue
    }

    private var statusColor: Color {
        switch agent.status {
        case "working": return .blue
        case "paused": return .secondary
        default: return .green
        }
    }
}
