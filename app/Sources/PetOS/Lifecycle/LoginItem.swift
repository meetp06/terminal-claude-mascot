// Launch-at-login toggle using SMAppService (macOS 13+). No-ops gracefully when
// running as a bare `swift run` binary (unregistered main app), so it never
// crashes the dev workflow.
import Foundation
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("PetOS: login item toggle failed: \(error)")
            return false
        }
    }
}
