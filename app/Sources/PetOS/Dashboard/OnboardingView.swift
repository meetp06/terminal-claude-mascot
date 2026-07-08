// First-launch onboarding: explain the read-only promise, pick a model
// provider, and choose which pets appear on screen. Shown until the user
// finishes; the choice is remembered in @AppStorage.
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    var onDone: () -> Void

    @State private var provider = "ollama"
    @State private var apiKey = ""
    @State private var enabled: [String: Bool] = [:]
    @AppStorage("petos.focus.mode") private var focusMode = "quiet"
    @AppStorage("petos.mascot.mode") private var mascotMode = "minimal"
    @AppStorage("petos.mascot.bubbles") private var mascotBubbles = "important"

    private let providers = ["ollama", "openai", "gemini", "groq"]
    private let focusModes = ["quiet", "work", "research", "dnd"]
    private let mascotModes = ["off", "minimal", "active"]
    private let bubbleModes = ["important", "all"]

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                if let logo = Brand.logo {
                    logo.resizable()
                        .scaledToFit()
                        .frame(width: 78, height: 78)
                } else {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(Brand.accentGradient)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("PetOS")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.accentGradient)
                    Text("A quiet control center for desktop pets that observe, suggest, and stay read-only.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Label("Read-only: your pets observe and suggest. They never edit or run anything.",
                      systemImage: "lock.shield.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.green)

                Spacer()

                Text("Configure once. You can change provider, keys, and visible pets any time in Settings.")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(28)
            .frame(width: 330)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(Brand.sidebar)

            VStack(alignment: .leading, spacing: 16) {
                setupPanel(title: "Model provider", icon: "cpu") {
                    Picker("Provider", selection: $provider) {
                        ForEach(providers, id: \.self) { Text($0.capitalized) }
                    }
                    .pickerStyle(.segmented)

                    if provider == "ollama" {
                        Label("Runs fully local via Ollama. No key required.", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        SecureField("\(provider.capitalized) API key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                        Label("Stored in your macOS Keychain.", systemImage: "key.fill")
                            .font(.caption)
                            .foregroundStyle(Brand.muted)
                    }
                }

                setupPanel(title: "Visible pets", icon: "eye.fill") {
                    ForEach(model.agents.filter { $0.role == "worker" }) { a in
                        Toggle(isOn: binding(for: a.id)) {
                            HStack {
                                Text(a.name)
                                    .font(.callout.weight(.medium))
                                Spacer()
                                Pill(text: a.type.capitalized, color: Brand.blue)
                            }
                        }
                    }
                    if model.agents.isEmpty {
                        Label("Connecting to the agent runtime...", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.callout)
                            .foregroundStyle(Brand.muted)
                    }
                }

                setupPanel(title: "Desktop behavior", icon: "pawprint.fill") {
                    settingPicker("Focus", selection: $focusMode, options: focusModes)
                    settingPicker("Mascot", selection: $mascotMode, options: mascotModes)
                    settingPicker("Bubbles", selection: $mascotBubbles, options: bubbleModes)
                    Text("Recommended: Quiet focus, minimal mascot, important bubbles.")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                }

                Button(action: finish) {
                    Label("Get started", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Brand.bg,
                    Color(red: 0x17/255, green: 0x19/255, blue: 0x1C/255)
                ],
                startPoint: .top,
                endPoint: .bottom)
        )
        .tint(Brand.teal)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(get: { enabled[id] ?? true }, set: { enabled[id] = $0 })
    }

    private func finish() {
        model.updateSettings(["provider": provider])
        if provider != "ollama", !apiKey.isEmpty {
            model.setApiKey(provider: provider, key: apiKey)
        }
        for a in model.agents where a.role == "worker" {
            model.setVisible(a.id, enabled[a.id] ?? true)
        }
        model.updateMascotPreferences(
            mode: mascotMode,
            size: UserDefaults.standard.string(forKey: "petos.mascot.size") ?? "small",
            bubbles: mascotBubbles,
            position: UserDefaults.standard.string(forKey: "petos.mascot.position") ?? "bottomRight")
        model.applyFocusMode(focusMode)
        onDone()
    }

    private func settingPicker(_ label: String, selection: Binding<String>, options: [String]) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .frame(width: 68, alignment: .leading)
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

    private func labelText(_ value: String) -> String {
        switch value {
        case "dnd": return "Do not disturb"
        case "important": return "Important"
        default: return value.capitalized
        }
    }

    private func setupPanel<Content: View>(
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
        .petPanel(padding: 16, raised: true)
    }
}
