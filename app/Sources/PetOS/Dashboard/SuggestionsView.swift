// Suggestions inbox: what the agents observed, ranked by score. Approval starts
// a managed read-only work item and saves the result as shared agent memory.
import SwiftUI

struct SuggestionsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            queueHeader
            if !recentWork.isEmpty {
                workSection
            }
            if model.suggestions.isEmpty && recentWork.isEmpty {
                EmptyStateView(
                    icon: "tray",
                    title: "No suggestions yet",
                    subtitle: "Agents observe every ~45s. Try focusing a code editor or a messy Downloads folder.")
            } else if model.suggestions.isEmpty {
                EmptyStateView(
                    icon: "checkmark.seal",
                    title: "Queue is clear",
                    subtitle: "Approved work stays visible above while agents finish and share local context.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.suggestions) { s in
                            SuggestionRow(suggestion: s, agentName: name(for: s.agentId))
                        }
                    }
                    .padding(.bottom, 18)
                }
            }
        }
    }

    private var queueHeader: some View {
        HStack(spacing: 14) {
            queueMetric("Pending", "\(model.suggestions.count)", .yellow)
            queueMetric("Working", "\(workingCount)", Brand.blue)
            queueMetric("Read-only", model.safeMode.uppercased(), .green)
            queueMetric("Tools", "\(model.tools.count)", Brand.teal)
            Spacer()
            Label("Approvals start managed read-only work.", systemImage: "play.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
        }
        .glassPanel(padding: 12, raised: true)
    }

    private var workSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Active work", systemImage: "checklist.checked")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.strongText)
                Spacer()
                Text("\(model.agentMemory.reduce(0) { $0 + $1.tokenEstimate }) local context tokens")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Brand.muted)
            }
            VStack(spacing: 8) {
                ForEach(recentWork) { item in
                    WorkItemRow(item: item, agentName: name(for: item.agentId))
                }
            }
        }
        .glassPanel(padding: 12, raised: true)
    }

    private func queueMetric(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Brand.muted)
        }
        .frame(minWidth: 72, alignment: .leading)
    }

    private func name(for id: String) -> String {
        model.agents.first { $0.id == id }?.name ?? "Agent"
    }

    private var workingCount: Int {
        model.workItems.filter { $0.status == "queued" || $0.status == "working" }.count
    }

    private var recentWork: [WorkItem] {
        Array(model.workItems.prefix(4))
    }
}

private struct SuggestionRow: View {
    @EnvironmentObject var model: AppModel
    let suggestion: Suggestion
    let agentName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 4) {
                    Image(systemName: "lightbulb.fill")
                        .font(.headline)
                        .foregroundStyle(Brand.teal)
                    Text(String(format: "%.0f%%", suggestion.score * 100))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Brand.muted)
                }
                .frame(width: 44)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(suggestion.title)
                            .font(.headline)
                            .foregroundStyle(Brand.strongText)
                            .lineLimit(2)
                        Pill(text: agentName, color: Brand.blue)
                        Pill(text: "Needs approval", color: .yellow, icon: "hand.raised.fill")
                        Spacer()
                    }
                    Text(suggestion.body)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                }

                VStack(spacing: 8) {
                    Button { model.act(on: suggestion, approve: true) } label: {
                        Label("Start", systemImage: "play.fill")
                            .frame(width: 96)
                    }
                    .buttonStyle(.borderedProminent)
                    Button { model.act(on: suggestion, approve: false) } label: {
                        Label("Dismiss", systemImage: "xmark")
                            .frame(width: 96)
                    }
                    .buttonStyle(.bordered)
                }
                .font(.caption)
            }

            HStack(alignment: .top, spacing: 10) {
                evidenceBlock("Why", suggestion.body, "text.magnifyingglass")
                evidenceBlock("Proposed", proposedText, "arrow.right.circle")
                evidenceBlock("Safety", "Read-only work starts after approval; result is saved as compact local context.", "lock.shield")
            }
        }
        .glassPanel(padding: 14)
    }

    private func evidenceBlock(_ title: String, _ text: String, _ icon: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(Brand.teal)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Brand.strongText)
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(Brand.muted)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var proposedText: String {
        suggestion.proposedAction.isEmpty ? "No direct action proposed." : suggestion.proposedAction
    }
}

private struct WorkItemRow: View {
    let item: WorkItem
    let agentName: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.strongText)
                        .lineLimit(1)
                    Pill(text: agentName, color: Brand.blue)
                    Pill(text: item.status.capitalized, color: color)
                    Spacer()
                }
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(Brand.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(9)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var detail: String {
        item.result.isEmpty ? item.objective : item.result
    }

    private var icon: String {
        switch item.status {
        case "queued": return "clock"
        case "working": return "play.circle.fill"
        case "completed": return "checkmark.seal.fill"
        case "failed": return "exclamationmark.triangle.fill"
        default: return "circle"
        }
    }

    private var color: Color {
        switch item.status {
        case "queued": return .yellow
        case "working": return Brand.blue
        case "completed": return .green
        case "failed": return .red
        default: return Brand.teal
        }
    }
}

/// Small back-compat stand-in for ContentUnavailableView on older SDKs.
struct ContentUnavailableCompat: View {
    let title: String
    let subtitle: String
    var body: some View {
        EmptyStateView(icon: "tray", title: title, subtitle: subtitle)
    }
}
