// Shared visual language for the dashboard: restrained macOS surfaces, compact
// status treatment, and one calm accent.
import SwiftUI

enum DashboardSection: String, CaseIterable, Identifiable {
    case agents, suggestions, manager, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .agents: return "Agents"
        case .suggestions: return "Suggestions"
        case .manager: return "Manager"
        case .settings: return "Settings"
        }
    }

    var subtitle: String {
        switch self {
        case .agents: return "Configure the pets that watch your workspace."
        case .suggestions: return "Review observations before anything is acted on."
        case .manager: return "Ask the manager to reason through a task."
        case .settings: return "Choose models, keys, and system behavior."
        }
    }

    var icon: String {
        switch self {
        case .agents: return "person.3.fill"
        case .suggestions: return "lightbulb.fill"
        case .manager: return "bubble.left.and.bubble.right.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

extension Brand {
    static let sidebar = Color(red: 0x16/255, green: 0x17/255, blue: 0x1A/255)
    static let panel = Color.white.opacity(0.055)
    static let panelRaised = Color.white.opacity(0.085)
    static let hairline = Color.white.opacity(0.095)
    static let glassStroke = Color.white.opacity(0.16)
    static let muted = Color.white.opacity(0.58)
    static let strongText = Color.white.opacity(0.92)
    static let accentGradient = LinearGradient(
        colors: [Brand.teal, Brand.blue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing)
}

struct Panel: ViewModifier {
    var padding: CGFloat = 16
    var raised = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(raised ? Brand.panelRaised : Brand.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Brand.hairline, lineWidth: 1)
            )
    }
}

struct GlassPanel: ViewModifier {
    var padding: CGFloat = 16
    var raised = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(
                LinearGradient(
                    colors: [
                        Color.white.opacity(raised ? 0.16 : 0.10),
                        Color.white.opacity(0.035)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(raised ? 0.32 : 0.20),
                                Brand.teal.opacity(raised ? 0.30 : 0.16),
                                Color.white.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(raised ? 0.28 : 0.16), radius: raised ? 16 : 8, x: 0, y: raised ? 10 : 5)
    }
}

extension View {
    func petPanel(padding: CGFloat = 16, raised: Bool = false) -> some View {
        modifier(Panel(padding: padding, raised: raised))
    }

    func glassPanel(padding: CGFloat = 16, raised: Bool = false) -> some View {
        modifier(GlassPanel(padding: padding, raised: raised))
    }

    func petCard() -> some View { petPanel() }
}

struct Pill: View {
    let text: String
    var color: Color = Brand.teal
    var icon: String?

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .imageScale(.small)
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15), in: Capsule())
        .foregroundStyle(color)
    }
}

struct StatusDot: View {
    var color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
    }
}

struct MetricBlock: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.strongText)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Brand.muted)
        }
        .frame(minWidth: 62, alignment: .trailing)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Brand.accentGradient)
            Text(title)
                .font(.headline)
                .foregroundStyle(Brand.strongText)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(Brand.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

func activityIcon(for phase: String) -> String {
    switch phase {
    case "reading_files": return "doc.text.magnifyingglass"
    case "checking_editor": return "macwindow"
    case "researching_web": return "globe"
    case "thinking": return "ellipsis.bubble.fill"
    case "sharing_context": return "arrow.triangle.branch"
    case "suggestion_found": return "lightbulb.fill"
    case "work_started": return "play.circle.fill"
    case "work_complete": return "checkmark.seal.fill"
    case "error": return "exclamationmark.triangle.fill"
    case "waiting": return "checkmark.circle.fill"
    default: return "waveform.path.ecg"
    }
}

func activityColor(for phase: String) -> Color {
    switch phase {
    case "suggestion_found": return .yellow
    case "work_started": return Brand.blue
    case "work_complete": return .green
    case "error": return .red
    case "waiting": return .secondary
    default: return Brand.teal
    }
}

func relativeTime(_ timestamp: Double) -> String {
    let delta = max(0, Date().timeIntervalSince1970 - timestamp)
    if delta < 60 { return "Just now" }
    if delta < 3600 { return "\(Int(delta / 60))m ago" }
    if delta < 86400 { return "\(Int(delta / 3600))h ago" }
    return "\(Int(delta / 86400))d ago"
}
