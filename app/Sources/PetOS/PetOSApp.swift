// PetOS entry point. Runs as a menu-bar accessory (no Dock icon): the pets live
// on-screen and a control-center window opens on demand.
import AppKit
import SwiftUI

extension AppModel {
    static let shared = AppModel()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var lifecycle: LifecycleObserver?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)     // show in Dock AND menu bar
        AppModel.shared.start()
        let lc = LifecycleObserver(model: .shared)
        lc.start()
        lifecycle = lc

        // Bring the Control Center window to the front on launch. Overlay pet
        // windows are borderless (canBecomeMain == false) so they're skipped.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            NSApp.activate(ignoringOtherApps: true)
            for w in NSApp.windows where w.canBecomeMain {
                w.makeKeyAndOrderFront(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.stop()
    }
}

@main
struct PetOSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        Window("PetOS Control Center", id: "dashboard") {
            DashboardView()
                .environmentObject(model)
                .frame(minWidth: 820, minHeight: 560)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(model)
        } label: {
            if let flake = Brand.flakeNSImage {
                Image(nsImage: flake)
            } else {
                Image(systemName: "snowflake")
            }
        }
        .menuBarExtraStyle(.window)   // allow a rich glanceable popover
    }
}

private struct MenuBarContent: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let logo = Brand.logo {
                    logo.resizable().scaledToFit().frame(width: 20, height: 20)
                }
                Text("PetOS").font(.headline)
                Spacer()
                Circle().fill(model.connected ? .green : .orange).frame(width: 8, height: 8)
                Text(model.connected ? "\(model.aliveCount) alive" : "connecting")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            ForEach(model.agents) { a in
                HStack(spacing: 8) {
                    Circle().fill(dot(a)).frame(width: 7, height: 7)
                    Text(a.name).font(.callout)
                    Spacer()
                    Text(a.status).font(.caption2).foregroundStyle(.secondary)
                }
            }

            Divider()

            if let s = model.suggestions.first {
                Text("Latest suggestion").font(.caption).foregroundStyle(.secondary)
                Text(s.title).font(.callout.bold())
                Text(s.body).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            } else {
                Text("No suggestions yet").font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            Button {
                openWindow(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
            } label: { Label("Open Control Center", systemImage: "square.grid.2x2") }

            Button(role: .destructive) { NSApp.terminate(nil) } label: {
                Label("Quit PetOS", systemImage: "power")
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private func dot(_ a: Agent) -> Color {
        switch a.status {
        case "working": return .blue
        case "paused":  return .gray
        default:        return a.isManager ? .orange : .green
        }
    }
}
