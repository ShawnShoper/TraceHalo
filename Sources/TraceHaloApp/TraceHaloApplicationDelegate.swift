import AppKit

enum TraceHaloWindowIdentity {
    static let main = NSUserInterfaceItemIdentifier("TraceHalo.main")
}

@MainActor
final class TraceHaloApplicationDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    let navigationRouter: AppNavigationRouter
    let menuBarController: MenuBarStatusItemController
    private let preferencesController: PreferencesPersistenceController

    override convenience init() {
        self.init(preferenceMigration: LegacyPreferencesMigration.performIfNeeded)
    }

    /// Internal injection point keeps lifecycle tests independent from the
    /// process preference domain while production performs the Bundle ID
    /// compatibility migration before constructing `AppModel`.
    init(preferenceMigration: () -> Void) {
        preferenceMigration()
        let configuredModel = AppModel.configured()
        let router = AppNavigationRouter()
        model = configuredModel
        navigationRouter = router
        menuBarController = MenuBarStatusItemController(
            model: configuredModel,
            navigationRouter: router
        )
        preferencesController = PreferencesPersistenceController(model: configuredModel)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        preferencesController.start()
        model.startMonitoring()
        menuBarController.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarController.stop()
        model.stopMonitoring()
        preferencesController.stop(flushPendingChanges: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows _: Bool
    ) -> Bool {
        let hasVisibleMainWindow = sender.windows.contains {
            $0.identifier == TraceHaloWindowIdentity.main && $0.isVisible
        }
        guard !hasVisibleMainWindow else { return true }
        menuBarController.showMainWindow()
        return false
    }

    /// `Command-Q` is intentionally a "menu-bar mode" command for TraceHalo.
    /// Monitoring and the status item remain owned by the application delegate.
    func enterMenuBarMode() {
        menuBarController.closePopover()
        guard menuBarController.prepareForMenuBarMode() else { return }
        guard NSApplication.shared.setActivationPolicy(.accessory) else { return }
        for window in NSApplication.shared.windows where window.isVisible {
            window.orderOut(nil)
        }
    }

    func terminateApplication() {
        NSApplication.shared.terminate(nil)
    }
}
