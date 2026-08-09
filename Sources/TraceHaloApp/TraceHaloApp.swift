import AppKit
import SwiftUI
import TraceHaloCore

#if !SNAPSHOT_QA
@main
struct TraceHaloApp: App {
    @NSApplicationDelegateAdaptor(TraceHaloApplicationDelegate.self)
    private var appDelegate
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage(AppLanguagePreference.storageKey)
    private var appLanguagePreference = AppLanguagePreference.defaultValue.rawValue

    var body: some Scene {
        Window("TraceHalo", id: "main") {
            RootView()
                .environment(model)
                .environment(navigationRouter)
                .traceHaloLanguageEnvironment()
                .preferredColorScheme(preferredColorScheme)
                .background(
                    TraceHaloWindowConfigurator()
                )
                .background(
                    MenuBarWindowActionBridge(
                        controller: appDelegate.menuBarController
                    )
                )
                .traceHaloFocusAppearance()
        }
        .defaultSize(width: 1_320, height: 840)
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
            SettingsView(isStandalone: true)
                .environment(model)
                .traceHaloLanguageEnvironment()
                .preferredColorScheme(preferredColorScheme)
                .frame(width: 640, height: 560)
                .traceHaloFocusAppearance()
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": .light
        case "dark": .dark
        default: nil
        }
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
    static let preferredContentSize = CGSize(width: 1_320, height: 840)
    static let compactContentSize = CGSize(width: 1_180, height: 750)
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

    static func resolvedVisibleFrame(
        windowScreen: CGRect?,
        mainScreen: CGRect?
    ) -> CGRect? {
        windowScreen ?? mainScreen
    }

    @MainActor
    static func applyFixedCanvas(_ contentSize: CGSize, to window: NSWindow) {
        // AppKit automatically uses the screen-sized content rect while the
        // window is in native full screen. These equal content constraints only
        // govern the normal window and restore its exact canvas on exit.
        // A previous implementation used aspectRatio to prevent compression.
        // Clear that legacy constraint explicitly before installing the one
        // authoritative fixed content size.
        // A fixed-size window must not also advertise native live resizing.
        // On macOS 26 that contradictory state can enter AppKit's resize event
        // path and trap while the frame's invalidation region is updated.
        window.styleMask.remove(.resizable)
        window.aspectRatio = .zero

        if window.contentView?.bounds.size != contentSize {
            window.setContentSize(contentSize)
        }
        if window.contentMinSize != contentSize {
            window.contentMinSize = contentSize
        }
        if window.contentMaxSize != contentSize {
            window.contentMaxSize = contentSize
        }
    }

    static func shouldApplyFixedCanvas(
        isFullScreen: Bool,
        isInLiveResize: Bool
    ) -> Bool {
        !isFullScreen && !isInLiveResize
    }
}

private struct TraceHaloWindowConfigurator: NSViewRepresentable {

    final class Coordinator {
        weak var configuredWindow: NSWindow?
        var screenChangeObserver: NSObjectProtocol?
        var fullScreenExitObserver: NSObjectProtocol?

        deinit {
            if let screenChangeObserver {
                NotificationCenter.default.removeObserver(screenChangeObserver)
            }
            if let fullScreenExitObserver {
                NotificationCenter.default.removeObserver(fullScreenExitObserver)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view.window, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(nsView.window, coordinator: context.coordinator)
        }
    }

    private func configure(_ window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }
        guard coordinator.configuredWindow !== window else { return }
        coordinator.configuredWindow = window

        window.identifier = TraceHaloWindowIdentity.main
        window.styleMask.insert(.titled)
        window.styleMask.remove(.resizable)
        window.styleMask.remove(.fullSizeContentView)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.title = "TraceHalo"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .line
        MainWindowLayoutPolicy.applyFixedCanvas(
            MainWindowLayoutPolicy.contentSize(for: resolvedVisibleFrame(for: window)),
            to: window
        )
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
        window.center()
    }

    @MainActor
    private func reapplyFixedCanvasIfSafe(to window: NSWindow) {
        guard MainWindowLayoutPolicy.shouldApplyFixedCanvas(
            isFullScreen: window.styleMask.contains(.fullScreen),
            isInLiveResize: window.inLiveResize
        ) else { return }
        MainWindowLayoutPolicy.applyFixedCanvas(
            MainWindowLayoutPolicy.contentSize(for: resolvedVisibleFrame(for: window)),
            to: window
        )
    }

    @MainActor
    private func resolvedVisibleFrame(for window: NSWindow) -> CGRect? {
        MainWindowLayoutPolicy.resolvedVisibleFrame(
            windowScreen: window.screen?.visibleFrame,
            mainScreen: NSScreen.main?.visibleFrame
        )
    }
}
#endif
