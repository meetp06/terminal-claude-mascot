// Bridges macOS lifecycle into the sidecar:
//  - system sleep/wake  -> pause/resume agents (so they idle while the lid is shut)
//  - frontmost app change -> feeds the editor worker its read-only signal
import AppKit

@MainActor
final class LifecycleObserver {
    private weak var model: AppModel?
    private let wsnc = NSWorkspace.shared.notificationCenter

    init(model: AppModel) { self.model = model }

    func start() {
        wsnc.addObserver(self, selector: #selector(willSleep),
                         name: NSWorkspace.willSleepNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(didWake),
                         name: NSWorkspace.didWakeNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(didActivateApp),
                         name: NSWorkspace.didActivateApplicationNotification, object: nil)
        reportFrontmost()
    }

    @objc private func willSleep() { model?.sendSystem("sleep") }
    @objc private func didWake() { model?.sendSystem("wake") }

    @objc private func didActivateApp(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
        model?.sendFrontmost(app: app.localizedName, bundleId: app.bundleIdentifier)
    }

    private func reportFrontmost() {
        if let app = NSWorkspace.shared.frontmostApplication {
            model?.sendFrontmost(app: app.localizedName, bundleId: app.bundleIdentifier)
        }
    }
}
