// Settings: pick the LLM provider/model (Ollama local by default, or a cloud
// provider via an API key stored in the Keychain), toggle launch-at-login, and
// review the read-only safety posture.
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var keyDrafts: [String: String] = [:]
    @AppStorage("petos.mascot.mode") private var mascotMode = "minimal"
    @AppStorage("petos.mascot.size") private var mascotSize = "small"
    @AppStorage("petos.mascot.bubbles") private var mascotBubbles = "important"
    @AppStorage("petos.mascot.position") private var mascotPosition = "bottomRight"
    @AppStorage("petos.focus.mode") private var focusMode = "quiet"
    @AppStorage("petos.ui.sidebarVisible") private var sidebarVisible = true
    @AppStorage("petos.ui.inspectorVisible") private var inspectorVisible = false

    private let providers = ["ollama", "openai", "gemini", "groq"]
    private let cloud = ["openai", "gemini", "groq"]
    private let focusModes = ["quiet", "work", "research", "dnd"]
    private let mascotModes = ["off", "minimal", "active"]
    private let mascotSizes = ["small", "medium"]
    private let bubbleModes = ["important", "all"]
    private let mascotPositions = ["bottomRight", "bottomLeft"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                settingsGroup(title: "Model provider", icon: "cpu") {
                    Picker("Provider", selection: providerBinding) {
                        ForEach(providers, id: \.self) { Text($0.capitalized) }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 10) {
                        Text("Model")
                            .frame(width: 92, alignment: .leading)
                            .foregroundStyle(Brand.muted)
                        TextField("Model", text: modelBinding)
                            .textFieldStyle(.roundedBorder)
                        if model.settings.provider == "ollama" {
                            Button { model.refreshOllamaModels() } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                        }
                    }
                    if model.settings.provider == "ollama", !model.ollamaModels.isEmpty {
                        HStack(spacing: 10) {
                            Text("Installed")
                                .frame(width: 92, alignment: .leading)
                                .foregroundStyle(Brand.muted)
                            Picker("Installed", selection: modelBinding) {
                                ForEach(model.ollamaModels, id: \.self) { Text($0) }
                            }
                            .labelsHidden()
                        }
                    }
                }

                settingsGroup(title: "API keys", icon: "key.fill") {
                    ForEach(cloud, id: \.self) { provider in
                        HStack(spacing: 10) {
                            HStack(spacing: 8) {
                                Text(provider.capitalized)
                                    .frame(width: 76, alignment: .leading)
                                if hasKey(provider) {
                                    Pill(text: "Saved", color: .green, icon: "checkmark.circle.fill")
                                }
                            }
                            SecureField(hasKey(provider) ? "Key saved in Keychain" : "Paste key",
                                        text: Binding(
                                            get: { keyDrafts[provider] ?? "" },
                                            set: { keyDrafts[provider] = $0 }))
                            .textFieldStyle(.roundedBorder)
                            Button {
                                let k = keyDrafts[provider] ?? ""
                                guard !k.isEmpty else { return }
                                model.setApiKey(provider: provider, key: k)
                                keyDrafts[provider] = ""
                            } label: {
                                Label("Save", systemImage: "square.and.arrow.down")
                            }
                            .disabled((keyDrafts[provider] ?? "").isEmpty)
                        }
                    }
                }

                settingsGroup(title: "System", icon: "gearshape.fill") {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { newVal in
                            LoginItem.setEnabled(newVal)
                            model.updateSettings(["launch_at_login": newVal ? "true" : "false"])
                        }
                }

                settingsGroup(title: "Interface", icon: "rectangle.split.3x1") {
                    Toggle("Show navigation sidebar", isOn: $sidebarVisible)
                    Toggle("Show agent details panel", isOn: $inspectorVisible)
                    Text("Hide panels when you want the workspace to feel lighter and scrolling to stay vertical.")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                settingsGroup(title: "Focus mode", icon: "moon.zzz.fill") {
                    settingPicker("Mode", selection: $focusMode, options: focusModes)
                    Text(focusDescription)
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .onChange(of: focusMode) { newValue in model.applyFocusMode(newValue) }

                settingsGroup(title: "Mascot", icon: "pawprint.fill") {
                    settingPicker("Mascot", selection: $mascotMode, options: mascotModes)
                    settingPicker("Size", selection: $mascotSize, options: mascotSizes)
                    settingPicker("Bubbles", selection: $mascotBubbles, options: bubbleModes)
                    settingPicker("Position", selection: $mascotPosition, options: mascotPositions)
                }
                .onChange(of: mascotMode) { _ in applyMascotPrefs() }
                .onChange(of: mascotSize) { _ in applyMascotPrefs() }
                .onChange(of: mascotBubbles) { _ in applyMascotPrefs() }
                .onChange(of: mascotPosition) { _ in applyMascotPrefs() }

                settingsGroup(title: "Safety", icon: "lock.shield.fill") {
                    Label("Read-only: agents can observe but never edit or run anything.",
                          systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    Text(model.tools.isEmpty ? "Allowed tools will appear after the runtime connects." : "Allowed tools: " + model.tools.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 18)
        }
        .onAppear {
            model.refreshOllamaModels()
            applyMascotPrefs()
        }
    }

    private func hasKey(_ p: String) -> Bool { model.settings.keys?[p] ?? false }

    private var providerBinding: Binding<String> {
        Binding(get: { model.settings.provider },
                set: { model.updateSettings(["provider": $0]) })
    }
    private var modelBinding: Binding<String> {
        Binding(get: { model.settings.model },
                set: { model.updateSettings(["model": $0]) })
    }

    private func settingPicker(_ label: String, selection: Binding<String>, options: [String]) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .frame(width: 92, alignment: .leading)
                .foregroundStyle(Brand.muted)
            Picker(label, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(labelText(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func applyMascotPrefs() {
        model.updateMascotPreferences(
            mode: mascotMode,
            size: mascotSize,
            bubbles: mascotBubbles,
            position: mascotPosition)
    }

    private func labelText(_ value: String) -> String {
        switch value {
        case "bottomRight": return "Bottom right"
        case "bottomLeft": return "Bottom left"
        case "important": return "Important"
        case "dnd": return "Do not disturb"
        default: return value.capitalized
        }
    }

    private var focusDescription: String {
        switch focusMode {
        case "work":
            return "Editor and file agents stay active; research agents pause."
        case "research":
            return "Research agents stay active with more activity bubbles."
        case "dnd":
            return "Mascot hides and worker agents pause until you change modes."
        default:
            return "Recommended default: minimal mascot, important bubbles, agents stay calm."
        }
    }

    private func settingsGroup<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(Brand.strongText)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
        }
        .petPanel(padding: 14)
    }
}
