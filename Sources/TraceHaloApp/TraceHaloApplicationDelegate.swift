import AppKit
import Darwin

final class TraceHaloSingleInstanceGuard {
    enum Acquisition: Equatable {
        case primary
        case secondary
        case unavailable
    }

    private(set) var acquisition: Acquisition = .unavailable
    private var fileDescriptor: Int32 = -1

    init(lockFileURL: URL = TraceHaloSingleInstanceGuard.defaultLockFileURL()) {
        do {
            try FileManager.default.createDirectory(
                at: lockFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            return
        }

        let descriptor = Darwin.open(
            lockFileURL.path,
            O_CREAT | O_RDWR | O_EXLOCK | O_NONBLOCK,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            acquisition = errno == EACCES || errno == EAGAIN
                ? .secondary
                : .unavailable
            return
        }

        fileDescriptor = descriptor
        acquisition = .primary
    }

    deinit {
        guard fileDescriptor >= 0 else { return }
        Darwin.close(fileDescriptor)
    }

    static func defaultLockFileURL(
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.tseai.tracehalo"
    ) -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return applicationSupport
            .appendingPathComponent("TraceHalo", isDirectory: true)
            .appendingPathComponent("Instances", isDirectory: true)
            .appendingPathComponent("\(bundleIdentifier).lock", isDirectory: false)
    }
}

enum TraceHaloWindowIdentity {
    static let main = NSUserInterfaceItemIdentifier("TraceHalo.main")
}

@MainActor
final class TraceHaloApplicationDelegate: NSObject, NSApplicationDelegate {
    private static let activateExistingInstanceNotification = Notification.Name(
        "com.tseai.tracehalo.activate-existing-instance"
    )

    let model: AppModel
    let navigationRouter: AppNavigationRouter
    let menuBarController: MenuBarStatusItemController
    private let preferencesController: PreferencesPersistenceController
    private let singleInstanceGuard: TraceHaloSingleInstanceGuard

    override init() {
        singleInstanceGuard = TraceHaloSingleInstanceGuard()
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

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard singleInstanceGuard.acquisition != .secondary else {
            Self.requestExistingInstanceActivation()
            (notification.object as? NSApplication)?.terminate(nil)
            return
        }

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleExistingInstanceActivation),
            name: Self.activateExistingInstanceNotification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard singleInstanceGuard.acquisition != .secondary else { return }
        preferencesController.start()
        model.startMonitoring()
        menuBarController.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: Self.activateExistingInstanceNotification,
            object: nil
        )
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

    @objc
    private func handleExistingInstanceActivation() {
        menuBarController.activateMainWindowPreservingDestination()
    }

    private static func requestExistingInstanceActivation() {
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            )
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }?
            .activate(options: [.activateAllWindows])
        }

        DistributedNotificationCenter.default().postNotificationName(
            activateExistingInstanceNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}
