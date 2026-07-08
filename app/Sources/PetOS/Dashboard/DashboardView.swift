// Control center shell: a status header plus tabs for agents, suggestions,
// the manager chat, and settings.
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("petos.onboarded") private var onboarded = false
    @AppStorage("petos.ui.sidebarVisible") private var sidebarVisible = true
    @State private var selected: DashboardSection = .agents

    var body: some View {
        Group {
            if onboarded {
                main
            } else {
                OnboardingView(onDone: { onboarded = true })
            }
        }
        .background(Brand.bg)
        .preferredColorScheme(.dark)
        .tint(Brand.teal)
    }

    private var main: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                sidebar
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Rectangle()
                    .fill(Brand.hairline)
                    .frame(width: 1)
            }
            VStack(spacing: 0) {
                header
                Rectangle()
                    .fill(Brand.hairline)
                    .frame(height: 1)
                workspace
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Brand.bg,
                    Color(red: 0x17/255, green: 0x19/255, blue: 0x1C/255)
                ],
                startPoint: .top,
                endPoint: .bottom)
        )
        .animation(.easeInOut(duration: 0.18), value: sidebarVisible)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                if let logo = Brand.logo {
                    logo.resizable()
                        .scaledToFit()
                        .frame(width: 34, height: 34)
                } else {
                    Image(systemName: "pawprint.fill")
                        .font(.title2)
                        .foregroundStyle(Brand.accentGradient)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("PetOS")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Brand.strongText)
                    Text("Control Center")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                }
            }
            .padding(.top, 2)

            VStack(spacing: 4) {
                ForEach(DashboardSection.allCases) { section in
                    sidebarButton(section)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    StatusDot(color: model.connected ? .green : .orange)
                    Text(model.connected ? "Runtime connected" : "Runtime connecting")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Brand.strongText)
                }
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(.green)
                    Text(model.safeMode.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                }
                Text("\(model.settings.provider.capitalized) / \(model.settings.model)")
                    .font(.caption2)
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
            }
            .padding(.top, 12)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Brand.hairline)
                    .frame(height: 1)
            }
        }
        .padding(16)
        .frame(width: 230)
        .background(Brand.sidebar)
    }

    private func sidebarButton(_ section: DashboardSection) -> some View {
        let active = selected == section
        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                selected = section
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 22)
                Text(section.title)
                    .font(.callout.weight(active ? .semibold : .medium))
                Spacer()
            }
            .foregroundStyle(active ? Brand.strongText : Brand.muted)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(active ? Color.white.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .leading) {
                if active {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Brand.teal)
                        .frame(width: 3, height: 18)
                        .padding(.leading, 2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var workspace: some View {
        Group {
            switch selected {
            case .agents:
                AgentGridView()
            case .suggestions:
                SuggestionsView()
            case .manager:
                ChatView()
            case .settings:
                SettingsView()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            Button {
                sidebarVisible.toggle()
            } label: {
                Image(systemName: sidebarVisible ? "sidebar.left" : "sidebar.left")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .help(sidebarVisible ? "Hide navigation" : "Show navigation")

            if !sidebarVisible {
                Menu {
                    ForEach(DashboardSection.allCases) { section in
                        Button {
                            selected = section
                        } label: {
                            Label(section.title, systemImage: section.icon)
                        }
                    }
                } label: {
                    Image(systemName: selected.icon)
                        .frame(width: 26, height: 26)
                }
                .menuStyle(.borderlessButton)
                .help("Change section")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(selected.title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Brand.strongText)
                Text(selected.subtitle)
                    .font(.callout)
                    .foregroundStyle(Brand.muted)
            }
            Spacer()
            HStack(spacing: 14) {
                connectionBadge
                MetricBlock(title: "Alive", value: "\(model.aliveCount)")
                MetricBlock(title: "On screen", value: "\(model.visibleCount)")
                Pill(text: model.safeMode.uppercased(), color: .green, icon: "lock.shield.fill")
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(Color.black.opacity(0.12))
    }

    private var connectionBadge: some View {
        HStack(spacing: 8) {
            StatusDot(color: model.connected ? .green : .orange)
            Text(model.connected ? "Connected" : "Connecting")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Brand.strongText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.06), in: Capsule())
    }
}
