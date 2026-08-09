import ServiceManagement
import TraceHaloCore

@MainActor
enum LaunchAtLoginController {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard RuntimeSafetyMode.current == .live else {
            throw SafetyViolation.deniedInSafeTestMode(.launchAtLogin)
        }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
