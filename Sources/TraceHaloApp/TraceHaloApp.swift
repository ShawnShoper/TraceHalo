import AppKit
import SwiftUI
import TraceHaloCore

enum TraceHaloAppearanceMode: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    static let storageKey = "appearanceMode"
    static let defaultValue: Self = .system

    init(storedValue: String?) {
        self = storedValue.flatMap(Self.init(rawValue:)) ?? .defaultValue
    }

    var explicitAppearanceName: NSAppearance.Name? {
        switch self {
        case .system: nil
        case .light: .aqua
        case .dark: .darkAqua
        }
    }
}

@MainActor
enum TraceHaloAppearancePolicy {
    @discardableResult
    static func apply(_ mode: TraceHaloAppearanceMode, to window: NSWindow) -> Bool {
        let targetAppearance = windowAppearance(for: mode)
        guard !matches(window.appearance, targetAppearance) else { return false }
        window.appearance = targetAppearance
        window.contentView?.needsDisplay = true
        return true
    }

    @discardableResult
    static func apply(
        _ mode: TraceHaloAppearanceMode,
        to popover: NSPopover,
        systemAppearance: NSAppearance = NSApp.effectiveAppearance
    ) -> Bool {
        let targetAppearance = popoverAppearance(
            for: mode,
            systemAppearance: systemAppearance
        )
        var didChange = false

        if !matches(popover.appearance, targetAppearance) {
            popover.appearance = targetAppearance
            didChange = true
        }
        if let window = popover.contentViewController?.view.window,
           !matches(window.appearance, targetAppearance) {
            window.appearance = targetAppearance
            didChange = true
        }
        if didChange {
            popover.contentViewController?.view.needsDisplay = true
        }
        return didChange
    }

    static func windowAppearance(for mode: TraceHaloAppearanceMode) -> NSAppearance? {
        mode.explicitAppearanceName.flatMap(NSAppearance.init(named:))
    }

    static func popoverAppearance(
        for mode: TraceHaloAppearanceMode,
        systemAppearance: NSAppearance
    ) -> NSAppearance {
        windowAppearance(for: mode) ?? systemAppearance
    }

    private static func matches(_ current: NSAppearance?, _ target: NSAppearance?) -> Bool {
        current?.name == target?.name
    }
}

#if !SNAPSHOT_QA
@main
struct TraceHaloApp: App {
    @NSApplicationDelegateAdaptor(TraceHaloApplicationDelegate.self)
    private var appDelegate
    @AppStorage(TraceHaloAppearanceMode.storageKey)
    private var appearanceMode = TraceHaloAppearanceMode.defaultValue.rawValue
    @AppStorage(AppLanguagePreference.storageKey)
    private var appLanguagePreference = AppLanguagePreference.defaultValue.rawValue
    private let lockedCanvas: MainWindowLayoutPolicy.LockedCanvas

    init() {
        lockedCanvas = MainWindowLayoutPolicy.lockedCanvasAtLaunch(
            mainScreenVisibleFrame: NSScreen.main?.visibleFrame,
            fallbackScreenVisibleFrame: NSScreen.screens.first?.visibleFrame
        )
    }

    var body: some Scene {
        Window("TraceHalo", id: "main") {
            FixedWindowCanvasRoot(contentSize: lockedCanvas.contentSize) {
                RootView()
                    .environment(model)
                    .environment(navigationRouter)
                    .traceHaloLanguageEnvironment()
            }
                .background(
                    TraceHaloWindowConfigurator(
                        contentSize: lockedCanvas.contentSize,
                        appearanceMode: TraceHaloAppearanceMode(storedValue: appearanceMode)
                    )
                )
                .background(
                    MenuBarWindowActionBridge(
                        controller: appDelegate.menuBarController
                    )
                )
                .traceHaloFocusAppearance()
        }
        .defaultSize(
            width: lockedCanvas.contentSize.width,
            height: lockedCanvas.contentSize.height
        )
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .toolbar) {
                Button(localizedCommand("刷新状态")) {
                    Task { await model.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(replacing: .appTermination) {
                Button(localizedCommand("退出主界面")) {
                    appDelegate.enterMenuBarMode()
                }
                .keyboardShortcut("q", modifiers: .command)

                Divider()

                Button(localizedCommand("彻底退出 TraceHalo")) {
                    appDelegate.terminateApplication()
                }
            }
        }

        Settings {
            FixedWindowCanvasRoot(contentSize: lockedCanvas.contentSize) {
                SettingsView(isStandalone: true)
                    .environment(model)
                    .traceHaloLanguageEnvironment()
            }
                .background(
                    TraceHaloWindowConfigurator(
                        kind: .settings,
                        contentSize: lockedCanvas.contentSize,
                        appearanceMode: TraceHaloAppearanceMode(storedValue: appearanceMode)
                    )
                )
                .traceHaloFocusAppearance()
        }
        .defaultSize(
            width: lockedCanvas.contentSize.width,
            height: lockedCanvas.contentSize.height
        )
        .windowResizability(.contentSize)
    }

    private func localizedCommand(_ key: String) -> String {
        _ = appLanguagePreference
        return AppLocalization.currentString(key)
    }

    private var model: AppModel {
        appDelegate.model
    }

    private var navigationRouter: AppNavigationRouter {
        appDelegate.navigationRouter
    }

}

struct FixedWindowCanvasRoot<Content: View>: View {
    let contentSize: CGSize
    private let content: Content

    init(contentSize: CGSize, @ViewBuilder content: () -> Content) {
        self.contentSize = contentSize
        self.content = content()
    }

    var body: some View {
        content.frame(width: contentSize.width, height: contentSize.height)
    }
}

private struct MenuBarWindowActionBridge: View {
    let controller: MenuBarStatusItemController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                controller.setOpenMainWindowAction {
                    openWindow(id: "main")
                }
            }
            .accessibilityHidden(true)
    }
}

enum MainWindowLayoutPolicy {
    struct LockedCanvas: Equatable {
        let contentSize: CGSize
    }

    static let preferredContentSize = CGSize(width: 1_320, height: 840)
    static let compactContentSize = CGSize(width: 1_180, height: 750)
    static let resizeGestureSuppressionWidth: CGFloat = 8
    static let horizontalScreenAllowance: CGFloat = 24
    static let verticalScreenAllowance: CGFloat = 56

    static func contentSize(for visibleFrame: CGRect?) -> CGSize {
        guard let visibleFrame else { return preferredContentSize }

        let supportsPreferredCanvas =
            visibleFrame.width >= preferredContentSize.width + horizontalScreenAllowance
            && visibleFrame.height >= preferredContentSize.height + verticalScreenAllowance
        if supportsPreferredCanvas {
            return preferredContentSize
        }

        let supportsCompactCanvas =
            visibleFrame.width >= compactContentSize.width + horizontalScreenAllowance
            && visibleFrame.height >= compactContentSize.height + verticalScreenAllowance
        if supportsCompactCanvas {
            return compactContentSize
        }

        // Keep a single fixed canvas even on unusually small displays. The
        // fitted tier is calculated once for the current screen, then locked by
        // equal min/max constraints instead of following transient SwiftUI
        // fitting proposals.
        return CGSize(
            width: max(1, floor(min(
                compactContentSize.width,
                visibleFrame.width - horizontalScreenAllowance
            ))),
            height: max(1, floor(min(
                compactContentSize.height,
                visibleFrame.height - verticalScreenAllowance
            )))
        )
    }

    static func lockedCanvasAtLaunch(
        mainScreenVisibleFrame: CGRect?,
        fallbackScreenVisibleFrame: CGRect?
    ) -> LockedCanvas {
        LockedCanvas(
            contentSize: contentSize(
                for: mainScreenVisibleFrame ?? fallbackScreenVisibleFrame
            )
        )
    }

    @MainActor
    @discardableResult
    static func applyFixedCanvas(_ contentSize: CGSize, to window: NSWindow) -> Bool {
        guard shouldApplyFixedCanvas(
            isFullScreen: window.styleMask.contains(.fullScreen),
            isInLiveResize: window.inLiveResize
        ) else {
            return false
        }

        // Keep one authoritative fixed canvas. In particular, never combine
        // equal content constraints with AppKit's native live-resize path: on
        // macOS 26 that contradictory state can trap while AppKit invalidates
        // the resized frame.
        window.styleMask.insert([.titled, .closable, .miniaturizable])
        window.styleMask.remove([.resizable, .fullSizeContentView])
        window.collectionBehavior.remove([
            .fullScreenPrimary,
            .fullScreenAuxiliary,
            .fullScreenAllowsTiling,
        ])
        window.collectionBehavior.insert([
            .fullScreenNone,
            .fullScreenDisallowsTiling,
        ])
        // Disable every AppKit/NSHostingView automatic movement path. The
        // event monitor handles only verified titlebar drags by changing the
        // frame origin itself, without re-enabling native movement.
        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.isRestorable = false
        window.disableSnapshotRestoration()
        _ = window.setFrameAutosaveName("")
        window.aspectRatio = .zero

        if window.contentView?.bounds.size != contentSize {
            let contentRect = CGRect(origin: .zero, size: contentSize)
            let targetFrameSize = window.frameRect(forContentRect: contentRect).size
            let targetFrame = CGRect(origin: window.frame.origin, size: targetFrameSize)
            window.setFrame(targetFrame, display: true, animate: false)
        }
        if window.contentMinSize != contentSize {
            window.contentMinSize = contentSize
        }
        if window.contentMaxSize != contentSize {
            window.contentMaxSize = contentSize
        }
        if let zoomButton = window.standardWindowButton(.zoomButton) {
            // Accessibility can still invoke a disabled standard zoom button
            // when it retains AppKit's target/action. Remove the affordance and
            // its dispatch path entirely so key-window timing cannot maximize
            // or enter full screen.
            zoomButton.isEnabled = false
            zoomButton.isHidden = true
            zoomButton.target = nil
            zoomButton.action = nil
            zoomButton.setAccessibilityElement(false)
        }
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = true
        window.standardWindowButton(.closeButton)?.isEnabled = true
        return true
    }

    static func shouldApplyFixedCanvas(
        isFullScreen: Bool,
        isInLiveResize: Bool
    ) -> Bool {
        !isFullScreen && !isInLiveResize
    }

    static func shouldSuppressTitlebarDoubleClickMouseUp(
        eventBelongsToManagedWindow: Bool,
        clickCount: Int,
        locationInWindow: CGPoint,
        contentLayoutRect: CGRect,
        windowFrameSize: CGSize
    ) -> Bool {
        guard eventBelongsToManagedWindow, clickCount >= 2 else { return false }
        let windowBounds = CGRect(origin: .zero, size: windowFrameSize)
        guard windowBounds.contains(locationInWindow) else { return false }
        return locationInWindow.y >= contentLayoutRect.maxY
    }

    static func shouldSuppressResizeMouseDown(
        eventBelongsToManagedWindow: Bool,
        locationInWindow: CGPoint,
        windowFrameSize: CGSize,
        suppressionWidth: CGFloat = resizeGestureSuppressionWidth
    ) -> Bool {
        guard eventBelongsToManagedWindow,
              suppressionWidth > 0,
              windowFrameSize.width > suppressionWidth * 2,
              windowFrameSize.height > suppressionWidth * 2
        else {
            return false
        }

        let windowBounds = CGRect(origin: .zero, size: windowFrameSize)
        let outerHitBounds = windowBounds.insetBy(
            dx: -suppressionWidth,
            dy: -suppressionWidth
        )
        guard outerHitBounds.contains(locationInWindow) else { return false }
        let safeInterior = windowBounds.insetBy(
            dx: suppressionWidth,
            dy: suppressionWidth
        )
        return !safeInterior.contains(locationInWindow)
    }

    static func shouldPerformManagedTitlebarDragMouseDown(
        eventBelongsToManagedWindow: Bool,
        clickCount: Int,
        locationInWindow: CGPoint,
        contentLayoutRect: CGRect,
        windowFrameSize: CGSize,
        excludedControlFrames: [CGRect]
    ) -> Bool {
        guard eventBelongsToManagedWindow, clickCount == 1 else { return false }
        let windowBounds = CGRect(origin: .zero, size: windowFrameSize)
        guard windowBounds.contains(locationInWindow),
              locationInWindow.y >= contentLayoutRect.maxY,
              !shouldSuppressResizeMouseDown(
                  eventBelongsToManagedWindow: true,
                  locationInWindow: locationInWindow,
                  windowFrameSize: windowFrameSize
              ),
              !excludedControlFrames.contains(where: { $0.contains(locationInWindow) })
        else {
            return false
        }
        return true
    }

    struct ManagedTitlebarDragState: Equatable {
        let initialMouseLocation: CGPoint
        let initialWindowOrigin: CGPoint

        func windowOrigin(for mouseLocation: CGPoint) -> CGPoint {
            CGPoint(
                x: initialWindowOrigin.x
                    + mouseLocation.x
                    - initialMouseLocation.x,
                y: initialWindowOrigin.y
                    + mouseLocation.y
                    - initialMouseLocation.y
            )
        }
    }

    enum ManagedMouseEventPhase {
        case down
        case dragged
        case up
    }

    enum ManagedMouseEventAction: Sendable {
        case passThrough
        case suppress
        case moveManagedWindow(to: CGPoint)
    }

    static func shouldSuppressManagedMouseEvent(
        phase: ManagedMouseEventPhase,
        eventBelongsToManagedWindow: Bool,
        clickCount: Int,
        locationInWindow: CGPoint,
        contentLayoutRect: CGRect,
        windowFrameSize: CGSize,
        isSuppressingResizeGesture: inout Bool
    ) -> Bool {
        switch phase {
        case .down:
            // Every new mouse sequence starts clean, even if a previous event
            // stream was interrupted before AppKit delivered its mouse-up.
            isSuppressingResizeGesture = false
            let beginsResizeGesture = shouldSuppressResizeMouseDown(
                eventBelongsToManagedWindow: eventBelongsToManagedWindow,
                locationInWindow: locationInWindow,
                windowFrameSize: windowFrameSize
            )
            isSuppressingResizeGesture = beginsResizeGesture
            return beginsResizeGesture
        case .dragged:
            return isSuppressingResizeGesture
        case .up:
            // Clear first. The same event may also be a titlebar double-click,
            // but no later suppression decision may leave resize state behind.
            let wasSuppressingResizeGesture = isSuppressingResizeGesture
            isSuppressingResizeGesture = false
            if wasSuppressingResizeGesture {
                return true
            }
            return shouldSuppressTitlebarDoubleClickMouseUp(
                eventBelongsToManagedWindow: eventBelongsToManagedWindow,
                clickCount: clickCount,
                locationInWindow: locationInWindow,
                contentLayoutRect: contentLayoutRect,
                windowFrameSize: windowFrameSize
            )
        }
    }
}

private struct TraceHaloWindowConfigurator: NSViewRepresentable {
    enum Kind {
        case main
        case settings

        var identifier: NSUserInterfaceItemIdentifier {
            switch self {
            case .main: TraceHaloWindowIdentity.main
            case .settings: NSUserInterfaceItemIdentifier("TraceHalo.settings")
            }
        }

    }

    let kind: Kind
    let contentSize: CGSize
    let appearanceMode: TraceHaloAppearanceMode

    init(
        kind: Kind = .main,
        contentSize: CGSize,
        appearanceMode: TraceHaloAppearanceMode = .defaultValue
    ) {
        self.kind = kind
        self.contentSize = contentSize
        self.appearanceMode = appearanceMode
    }

    final class Coordinator: @unchecked Sendable {
        weak var configuredWindow: NSWindow?
        var desiredAppearanceMode = TraceHaloAppearanceMode.defaultValue
        var screenChangeObserver: NSObjectProtocol?
        var didBecomeKeyObserver: NSObjectProtocol?
        var didResignKeyObserver: NSObjectProtocol?
        var fullScreenExitObserver: NSObjectProtocol?
        var liveResizeExitObserver: NSObjectProtocol?
        var resizeObserver: NSObjectProtocol?
        var managedMouseEventMonitor: Any?
        var isSuppressingResizeGesture = false
        var managedTitlebarDragState: MainWindowLayoutPolicy.ManagedTitlebarDragState?

        @MainActor
        func resetManagedMouseState() {
            isSuppressingResizeGesture = false
            managedTitlebarDragState = nil
        }

        deinit {
            if let screenChangeObserver {
                NotificationCenter.default.removeObserver(screenChangeObserver)
            }
            if let didBecomeKeyObserver {
                NotificationCenter.default.removeObserver(didBecomeKeyObserver)
            }
            if let didResignKeyObserver {
                NotificationCenter.default.removeObserver(didResignKeyObserver)
            }
            if let fullScreenExitObserver {
                NotificationCenter.default.removeObserver(fullScreenExitObserver)
            }
            if let liveResizeExitObserver {
                NotificationCenter.default.removeObserver(liveResizeExitObserver)
            }
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
            }
            if let managedMouseEventMonitor {
                NSEvent.removeMonitor(managedMouseEventMonitor)
            }
        }
    }

    final class ConfigurationView: NSView {
        var windowDidChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            windowDidChange?(window)
        }
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.desiredAppearanceMode = appearanceMode
        return coordinator
    }

    func makeNSView(context: Context) -> ConfigurationView {
        let view = ConfigurationView()
        let coordinator = context.coordinator
        coordinator.desiredAppearanceMode = appearanceMode
        view.windowDidChange = { window in
            configure(window, coordinator: coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: ConfigurationView, context: Context) {
        context.coordinator.desiredAppearanceMode = appearanceMode
        // Close the current style-mask window immediately, then reassert once
        // more after SwiftUI finishes the surrounding scene update.
        configure(nsView.window, coordinator: context.coordinator)
        DispatchQueue.main.async {
            configure(nsView.window, coordinator: context.coordinator)
        }
    }

    private func configure(_ window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }
        // SwiftUI can retain the previous presentation appearance when a
        // non-nil preferred color scheme is cleared. Keep the AppKit window
        // authoritative so light/dark -> system takes effect without a focus
        // or key-window transition.
        TraceHaloAppearancePolicy.apply(coordinator.desiredAppearanceMode, to: window)
        // SwiftUI may replace or reconfigure the hosting window independently
        // of an AppKit mouse-up. Never carry a partially observed gesture into
        // the next configuration pass.
        coordinator.resetManagedMouseState()
        let isNewWindow = coordinator.configuredWindow !== window
        if isNewWindow {
            coordinator.configuredWindow = window
            window.identifier = kind.identifier
            if kind == .main {
                window.title = "TraceHalo"
                window.titleVisibility = .visible
                window.titlebarAppearsTransparent = false
                window.titlebarSeparatorStyle = .line
            }

            installObservers(for: window, coordinator: coordinator)
        }

        // SwiftUI can update the same NSWindow after this representable first
        // appears. Reassert the policy on every update instead of treating the
        // first configuration as permanently authoritative.
        let didApplyFixedCanvas = reapplyFixedCanvasIfSafe(to: window)

        if isNewWindow, kind == .main, didApplyFixedCanvas {
            window.center()
        }
    }

    private func installObservers(for window: NSWindow, coordinator: Coordinator) {
        if let managedMouseEventMonitor = coordinator.managedMouseEventMonitor {
            NSEvent.removeMonitor(managedMouseEventMonitor)
        }
        coordinator.resetManagedMouseState()
        coordinator.managedMouseEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak window, weak coordinator] event in
            guard let window, let coordinator else { return event }
            let action = MainActor.assumeIsolated {
                let phase: MainWindowLayoutPolicy.ManagedMouseEventPhase
                switch event.type {
                case .leftMouseDown:
                    phase = .down
                case .leftMouseDragged:
                    phase = .dragged
                case .leftMouseUp:
                    phase = .up
                default:
                    return MainWindowLayoutPolicy.ManagedMouseEventAction.passThrough
                }
                let belongsToManagedWindow = event.window === window
                    || event.windowNumber == window.windowNumber

                switch phase {
                case .down:
                    // A new sequence always invalidates an interrupted titlebar
                    // drag, including clicks in app content or another window.
                    coordinator.managedTitlebarDragState = nil
                    let suppressesResize = MainWindowLayoutPolicy.shouldSuppressManagedMouseEvent(
                        phase: .down,
                        eventBelongsToManagedWindow: belongsToManagedWindow,
                        clickCount: event.clickCount,
                        locationInWindow: event.locationInWindow,
                        contentLayoutRect: window.contentLayoutRect,
                        windowFrameSize: window.frame.size,
                        isSuppressingResizeGesture: &coordinator.isSuppressingResizeGesture
                    )
                    // Edge/corner suppression has priority over every movement
                    // path and consumes the full mouse sequence.
                    if suppressesResize {
                        return MainWindowLayoutPolicy.ManagedMouseEventAction.suppress
                    }

                    let excludedControlFrames = [
                        window.standardWindowButton(.closeButton),
                        window.standardWindowButton(.miniaturizeButton),
                    ].compactMap { button -> CGRect? in
                        guard let button else { return nil }
                        return button.convert(button.bounds, to: nil)
                    }
                    guard MainWindowLayoutPolicy.shouldPerformManagedTitlebarDragMouseDown(
                        eventBelongsToManagedWindow: belongsToManagedWindow,
                        clickCount: event.clickCount,
                        locationInWindow: event.locationInWindow,
                        contentLayoutRect: window.contentLayoutRect,
                        windowFrameSize: window.frame.size,
                        excludedControlFrames: excludedControlFrames
                    ) else {
                        return MainWindowLayoutPolicy.ManagedMouseEventAction.passThrough
                    }
                    coordinator.managedTitlebarDragState = .init(
                        initialMouseLocation: window.convertPoint(
                            toScreen: event.locationInWindow
                        ),
                        initialWindowOrigin: window.frame.origin
                    )
                    return MainWindowLayoutPolicy.ManagedMouseEventAction.suppress

                case .dragged:
                    let suppressesResize = MainWindowLayoutPolicy.shouldSuppressManagedMouseEvent(
                        phase: .dragged,
                        eventBelongsToManagedWindow: belongsToManagedWindow,
                        clickCount: event.clickCount,
                        locationInWindow: event.locationInWindow,
                        contentLayoutRect: window.contentLayoutRect,
                        windowFrameSize: window.frame.size,
                        isSuppressingResizeGesture: &coordinator.isSuppressingResizeGesture
                    )
                    if suppressesResize {
                        return MainWindowLayoutPolicy.ManagedMouseEventAction.suppress
                    }
                    guard let dragState = coordinator.managedTitlebarDragState else {
                        return MainWindowLayoutPolicy.ManagedMouseEventAction.passThrough
                    }
                    return MainWindowLayoutPolicy.ManagedMouseEventAction.moveManagedWindow(
                        to: dragState.windowOrigin(
                            for: window.convertPoint(
                                toScreen: event.locationInWindow
                            )
                        )
                    )

                case .up:
                    let wasManagingTitlebarDrag = coordinator.managedTitlebarDragState != nil
                    coordinator.managedTitlebarDragState = nil
                    let shouldSuppress = MainWindowLayoutPolicy.shouldSuppressManagedMouseEvent(
                        phase: .up,
                        eventBelongsToManagedWindow: belongsToManagedWindow,
                        clickCount: event.clickCount,
                        locationInWindow: event.locationInWindow,
                        contentLayoutRect: window.contentLayoutRect,
                        windowFrameSize: window.frame.size,
                        isSuppressingResizeGesture: &coordinator.isSuppressingResizeGesture
                    )
                    return shouldSuppress || wasManagingTitlebarDrag
                        ? MainWindowLayoutPolicy.ManagedMouseEventAction.suppress
                        : MainWindowLayoutPolicy.ManagedMouseEventAction.passThrough
                }
            }
            switch action {
            case .passThrough:
                return event
            case .suppress:
                return nil
            case let .moveManagedWindow(origin):
                MainActor.assumeIsolated {
                    // Programmatic origin movement remains valid while native
                    // resizing and automatic NSWindow movement stay disabled.
                    window.setFrameOrigin(origin)
                }
                return nil
            }
        }

        if let screenChangeObserver = coordinator.screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }
        coordinator.screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: window,
            queue: .main
        ) { [weak window] _ in
            guard let window else { return }
            Task { @MainActor in
                reapplyFixedCanvasIfSafe(to: window)
            }
        }
        if let didBecomeKeyObserver = coordinator.didBecomeKeyObserver {
            NotificationCenter.default.removeObserver(didBecomeKeyObserver)
        }
        coordinator.didBecomeKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak window] _ in
            guard let window else { return }
            _ = MainActor.assumeIsolated {
                reapplyFixedCanvasIfSafe(to: window)
            }
        }
        if let didResignKeyObserver = coordinator.didResignKeyObserver {
            NotificationCenter.default.removeObserver(didResignKeyObserver)
        }
        coordinator.didResignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak window, weak coordinator] _ in
            guard let window, let coordinator else { return }
            MainActor.assumeIsolated {
                coordinator.resetManagedMouseState()
                _ = reapplyFixedCanvasIfSafe(to: window)
            }
        }
        if let fullScreenExitObserver = coordinator.fullScreenExitObserver {
            NotificationCenter.default.removeObserver(fullScreenExitObserver)
        }
        coordinator.fullScreenExitObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification,
            object: window,
            queue: .main
        ) { [weak window] _ in
            guard let window else { return }
            Task { @MainActor in
                reapplyFixedCanvasIfSafe(to: window)
            }
        }
        if let liveResizeExitObserver = coordinator.liveResizeExitObserver {
            NotificationCenter.default.removeObserver(liveResizeExitObserver)
        }
        coordinator.liveResizeExitObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification,
            object: window,
            queue: .main
        ) { [weak window] _ in
            guard let window else { return }
            Task { @MainActor in
                reapplyFixedCanvasIfSafe(to: window)
            }
        }
        if let resizeObserver = coordinator.resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
        }
        coordinator.resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak window] _ in
            // Do not call setContentSize reentrantly from AppKit's frame update.
            // Recover any programmatic/zoom size drift on the next main turn.
            DispatchQueue.main.async { [weak window] in
                guard let window, !window.inLiveResize else { return }
                reapplyFixedCanvasIfSafe(to: window)
            }
        }
    }

    @MainActor
    @discardableResult
    private func reapplyFixedCanvasIfSafe(to window: NSWindow) -> Bool {
        MainWindowLayoutPolicy.applyFixedCanvas(
            contentSize,
            to: window
        )
    }
}
#endif
