import AppKit
import Observation
import os
import SwiftUI
import TraceHaloCore

@MainActor
final class MenuBarStatusItemController: NSObject, NSPopoverDelegate {
    private static let signposter = OSSignposter(
        subsystem: TraceHaloBundleIdentifiers.application,
        category: "MenuBarPopover"
    )

    private let model: AppModel
    private let navigationRouter: AppNavigationRouter
    private let popover = NSPopover()
    private let visualState = MenuBarStatusVisualState()
    private let popoverLayoutState = MenuBarPopoverLayoutState(
        maximumColumnHeight: MenuBarPopoverSizingPolicy.maximumColumnHeight
    )

    private var statusItem: NSStatusItem?
    private weak var popoverAnchorOverride: NSButton?
    private var statusHostingView: PassthroughHostingView?
    private var popoverHostingView: MenuBarPopoverHostingView?
    private var openMainWindowAction: (() -> Void)?
    private var isStarted = false
    private var observationGeneration = 0
    private var popoverPresentation = MenuBarPopoverPresentation()
    private var popoverColumnHeight = MenuBarPopoverSizingPolicy.layout(
        availableHeight: NSScreen.main?.visibleFrame.height
    ).columnHeight
    private var pendingPresentationMeasurement: PendingPopoverPresentationMeasurement?
    private var completedPresentationCount = 0
    private var totalPopoverContentSizeChangeCount = 0
    private var presentationSizeChangeStartCount = 0
    private var lastOpeningLatencyMilliseconds: Double?
    private var lastOpeningContentSizeChangeCount: Int?
    private var lastOpeningWasCold: Bool?
    private var languagePreferenceObserver: NSObjectProtocol?
    private var systemLocaleObserver: NSObjectProtocol?

    init(
        model: AppModel,
        navigationRouter: AppNavigationRouter,
        popoverAnchorOverride: NSButton? = nil
    ) {
        self.model = model
        self.navigationRouter = navigationRouter
        self.popoverAnchorOverride = popoverAnchorOverride
        super.init()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        if popoverAnchorOverride == nil {
            installStatusItem()
            guard statusItem != nil else {
                isStarted = false
                return
            }
        }
        installPopover()
        synchronizeFromModel()
        observeLanguagePreference()
        observePresentationPreferences()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        observationGeneration += 1
        popover.performClose(nil)
        finishPendingPresentationMeasurement(didShow: false)
        releasePopoverContent()
        popoverPresentation = MenuBarPopoverPresentation()
        visualState.isHighlighted = false
        statusHostingView?.removeFromSuperview()
        statusHostingView = nil
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        stopObservingLanguagePreference()
    }

    func setOpenMainWindowAction(_ action: @escaping () -> Void) {
        openMainWindowAction = action
    }

    /// Ensures Command-Q cannot leave TraceHalo running without any way back
    /// into the app. Entering menu-bar mode is refused if AppKit cannot create
    /// the status item.
    func prepareForMenuBarMode() -> Bool {
        if !isStarted {
            start()
        }
        guard let statusItem else { return false }
        if !model.showMenuBarSummary {
            model.showMenuBarSummary = true
        }
        synchronizeFromModel()
        statusItem.isVisible = true
        return statusItem.isVisible
    }

    private func installStatusItem() {
        let initialWidth = MenuBarStatusLayout.estimatedStatusItemWidth(
            for: model.monitorConfiguration
        )
        let item = NSStatusBar.system.statusItem(withLength: initialWidth)
        guard let button = item.button else {
            NSStatusBar.system.removeStatusItem(item)
            return
        }

        statusItem = item
        button.title = ""
        button.image = nil
        button.imagePosition = .noImage
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: MenuBarStatusInteractionPolicy.actionEventMask)
        refreshLocalizedStatusButtonText()
        TraceHaloFocusAppearance.configureStatusButton(button)

        let hostedContent = MenuBarStatusHostingRoot(
            model: model,
            visualState: visualState,
            onContentSizeChange: { [weak self] size in
                self?.applyStatusContentSize(size)
            }
        )
        let hostingView = PassthroughHostingView(rootView: AnyView(hostedContent))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.setContentHuggingPriority(.required, for: .horizontal)
        hostingView.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.addSubview(hostingView)

        let inset = MenuBarStatusLayout.statusItemHorizontalInset
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: inset),
            hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -inset),
            hostingView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            hostingView.heightAnchor.constraint(equalToConstant: 22)
        ])
        statusHostingView = hostingView
    }

    private func observeLanguagePreference() {
        guard languagePreferenceObserver == nil,
              systemLocaleObserver == nil else { return }
        languagePreferenceObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshLanguagePresentation()
            }
        }
        systemLocaleObserver = NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshLanguagePresentation()
            }
        }
    }

    private func stopObservingLanguagePreference() {
        if let languagePreferenceObserver {
            NotificationCenter.default.removeObserver(languagePreferenceObserver)
            self.languagePreferenceObserver = nil
        }
        if let systemLocaleObserver {
            NotificationCenter.default.removeObserver(systemLocaleObserver)
            self.systemLocaleObserver = nil
        }
    }

    private func refreshLocalizedStatusButtonText() {
        guard let button = statusItem?.button else { return }
        let localizedText = MenuBarStatusItemLocalizedText.resolve(
            locale: AppLocalization.currentLocale
        )
        button.toolTip = localizedText.toolTip
        button.setAccessibilityLabel(localizedText.accessibilityLabel)
    }

    private func refreshLanguagePresentation() {
        refreshLocalizedStatusButtonText()
        statusHostingView?.needsLayout = true
        statusItem?.button?.needsLayout = true
        // Localized default labels can have different intrinsic widths. Reuse
        // the same measurement path as a configuration change so the real
        // NSStatusItem, not only the settings preview, updates immediately.
        synchronizeFromModel()
    }

    private func installPopover() {
        popover.behavior = .transient
        // The system animation magnifies first-frame layout work and makes a
        // status item feel delayed even when the content is ready.
        popover.animates = false
        popover.delegate = self
        let initialLayout = MenuBarPopoverSizingPolicy.layout(
            availableHeight: NSScreen.main?.visibleFrame.height
        )
        popoverColumnHeight = initialLayout.columnHeight
        applyPopoverContentSize(initialLayout.contentSize)
    }

    private func synchronizeFromModel() {
        guard let statusItem else { return }
        statusItem.isVisible = model.showMenuBarSummary
        if !model.showMenuBarSummary,
           popover.isShown || popoverPresentation.isPresented {
            closePopover()
        }

        let fallbackWidth = MenuBarStatusLayout.estimatedStatusItemWidth(
            for: model.monitorConfiguration
        )
        applyStatusItemWidth(fallbackWidth)

        DispatchQueue.main.async { [weak self] in
            self?.measureAndApplyStatusWidth()
        }
    }

    private func observePresentationPreferences() {
        guard isStarted else { return }
        let generation = observationGeneration
        withObservationTracking {
            _ = model.monitorConfiguration
            _ = model.showMenuBarSummary
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      self.isStarted,
                      self.observationGeneration == generation else { return }
                self.synchronizeFromModel()
                self.observePresentationPreferences()
            }
        }
    }

    private func measureAndApplyStatusWidth() {
        guard let statusHostingView else { return }
        statusHostingView.invalidateIntrinsicContentSize()
        statusHostingView.layoutSubtreeIfNeeded()
        applyStatusContentSize(statusHostingView.fittingSize)
    }

    private func applyStatusContentSize(_ size: CGSize) {
        guard size.width.isFinite, size.width > 0 else { return }
        let estimatedContentWidth = MenuBarStatusLayout.estimatedContentWidth(
            for: model.monitorConfiguration
        )
        let measuredContentWidth = max(ceil(size.width), ceil(estimatedContentWidth))
        let requiredWidth = max(
            MenuBarStatusLayout.minimumStatusItemWidth,
            measuredContentWidth + MenuBarStatusLayout.statusItemHorizontalInset * 2
        )
        applyStatusItemWidth(requiredWidth)
    }

    private func applyStatusItemWidth(_ width: CGFloat) {
        guard let statusItem else { return }
        let normalizedWidth = max(MenuBarStatusLayout.minimumStatusItemWidth, ceil(width))
        guard abs(statusItem.length - normalizedWidth) > 0.5 else { return }
        statusItem.length = normalizedWidth
        statusItem.button?.needsLayout = true
    }

    @discardableResult
    private func applyPopoverContentSize(_ size: CGSize) -> Bool {
        guard size.width.isFinite, size.height.isFinite else { return false }
        let normalized = CGSize(
            width: MenuBarPopoverSizingPolicy.normalizedContentWidth(
                preferredWidth: size.width
            ),
            height: ceil(size.height)
        )
        guard MenuBarPopoverSizingPolicy.needsUpdate(
            current: popover.contentSize,
            target: normalized
        ) else { return false }
        popover.contentSize = normalized
        totalPopoverContentSizeChangeCount += 1
        Self.signposter.emitEvent(
            "MenuBarPopoverContentSizeChanged",
            "count: \(self.totalPopoverContentSizeChangeCount, privacy: .public), width: \(normalized.width, privacy: .public), height: \(normalized.height, privacy: .public)"
        )
        return true
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        if popover.isShown || popoverPresentation.isPresented {
            closePopover(sender)
        } else {
            showPopover()
        }
    }

    /// Presents the popover without exposing AppKit implementation details to
    /// integration tests. Repeated calls while visible are idempotent.
    @discardableResult
    func showPopover() -> Bool {
        guard isStarted, let button = popoverAnchorButton else { return false }
        if popover.isShown {
            if !popoverPresentation.isPresented {
                popoverPresentation.present()
            }
            popoverHostingView?.activatePreferredContentSizeMeasurements(
                for: popoverPresentation.presentationID
            )
            return true
        }
        if popoverPresentation.isPresented {
            finishPopoverDismissal()
        }

        beginPresentationMeasurement()
        let layout = updatePopoverLayout(for: button.window?.screen)
        guard popoverPresentation.present() else {
            finishPendingPresentationMeasurement(didShow: popover.isShown)
            return popover.isShown
        }
        presentationSizeChangeStartCount = totalPopoverContentSizeChangeCount
        mountPopoverContentIfNeeded(contentSize: layout.contentSize)
        popoverHostingView?.activatePreferredContentSizeMeasurements(
            for: popoverPresentation.presentationID
        )
        // The first mount may change AppKit's provisional size. Applying the
        // policy here is harmless on warm opens and keeps one size authority.
        applyPopoverContentSize(layout.contentSize)

        visualState.isHighlighted = true
        button.highlight(true)
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )

        guard popover.isShown else {
            finishPendingPresentationMeasurement(didShow: false)
            finishPopoverDismissal()
            return false
        }
        popover.contentViewController?.view.window?.makeKey()
        popoverHostingView?.requestPreferredContentSizeMeasurement()
        return true
    }

    @discardableResult
    private func updatePopoverLayout(for screen: NSScreen?) -> MenuBarPopoverLayout {
        let availableHeight = screen?.visibleFrame.height
            ?? NSScreen.main?.visibleFrame.height
        let layout = MenuBarPopoverSizingPolicy.layout(availableHeight: availableHeight)
        if MenuBarPopoverSizingPolicy.needsUpdate(
            current: popoverColumnHeight,
            target: layout.columnHeight
        ) {
            popoverColumnHeight = layout.columnHeight
            popoverLayoutState.maximumColumnHeight = layout.columnHeight
        }
        return layout
    }

    private func mountPopoverContentIfNeeded(contentSize: CGSize) {
        // Once mounted, AppKit owns the hosting view's frame inside the
        // popover chrome. Replacing the entire frame on a warm open resets the
        // system-provided origin to zero, which shifts the dashboard underneath
        // the popover border and clips both horizontal edges. Content size and
        // the autoresizing mask below remain the single source of truth for
        // subsequent collapsed/expanded size changes.
        guard popoverHostingView == nil else { return }
        let root = MenuBarPopoverHostingRoot(
            model: model,
            navigationRouter: navigationRouter,
            layoutState: popoverLayoutState,
            openMainWindowAction: { [weak self] in
                self?.showMainWindow()
            },
            quitApplicationAction: {
                NSApplication.shared.terminate(nil)
            }
        )
        let hostingView = MenuBarPopoverHostingView(rootView: AnyView(root))
        hostingView.frame = CGRect(origin: .zero, size: contentSize)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.onPreferredContentSizeChange = { [weak self] size, presentationID in
            self?.applyPopoverPreferredContentSize(
                size,
                presentationID: presentationID
            )
        }
        let viewController = NSViewController()
        viewController.view = hostingView
        popoverHostingView = hostingView
        popover.contentViewController = viewController
    }

    private func releasePopoverContent() {
        popoverHostingView?.deactivatePreferredContentSizeMeasurements()
        popoverHostingView?.onPreferredContentSizeChange = nil
        popoverHostingView = nil
        popover.contentViewController = nil
    }

    private func applyPopoverPreferredContentSize(
        _ preferredSize: CGSize,
        presentationID: UInt64
    ) {
        guard popoverPresentation.isPresented,
              popoverPresentation.presentationID == presentationID
        else { return }
        let normalized = MenuBarPopoverSizingPolicy.contentSize(
            preferredWidth: preferredSize.width,
            columnHeight: popoverColumnHeight
        )
        applyPopoverContentSize(normalized)
    }

    private func beginPresentationMeasurement() {
        finishPendingPresentationMeasurement(didShow: false)
        let isCold = completedPresentationCount == 0
        let phase = isCold ? "cold" : "warm"
        let intervalState = Self.signposter.beginInterval(
            "MenuBarPopoverOpen",
            "phase: \(phase, privacy: .public)"
        )
        pendingPresentationMeasurement = PendingPopoverPresentationMeasurement(
            intervalState: intervalState,
            startedAt: ProcessInfo.processInfo.systemUptime,
            contentSizeChangeCountAtStart: totalPopoverContentSizeChangeCount,
            wasCold: isCold
        )
    }

    private func finishPendingPresentationMeasurement(didShow: Bool) {
        guard let measurement = pendingPresentationMeasurement else { return }
        pendingPresentationMeasurement = nil
        let latencyMilliseconds = max(
            0,
            (ProcessInfo.processInfo.systemUptime - measurement.startedAt) * 1_000
        )
        let sizeChangeCount = totalPopoverContentSizeChangeCount
            - measurement.contentSizeChangeCountAtStart
        Self.signposter.endInterval(
            "MenuBarPopoverOpen",
            measurement.intervalState,
            "shown: \(didShow, privacy: .public), cold: \(measurement.wasCold, privacy: .public), latency_ms: \(latencyMilliseconds, privacy: .public), size_changes: \(sizeChangeCount, privacy: .public)"
        )
        guard didShow else { return }
        completedPresentationCount += 1
        lastOpeningLatencyMilliseconds = latencyMilliseconds
        lastOpeningContentSizeChangeCount = sizeChangeCount
        lastOpeningWasCold = measurement.wasCold
    }

    func showMainWindow() {
        closePopover()
        NSApplication.shared.setActivationPolicy(.regular)
        navigationRouter.navigate(to: .dashboard)
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindowAction?()
        }
        NSApplication.shared.activate(ignoringOtherApps: true)

        // A SwiftUI Window scene can be recreated asynchronously after its red
        // close button was used. Re-check once so a stale openWindow closure
        // cannot strand a newly-created window behind other apps.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.mainWindow?.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private var mainWindow: NSWindow? {
        NSApplication.shared.windows.first {
            $0.identifier == TraceHaloWindowIdentity.main
        }
    }

    func closePopover() {
        closePopover(nil)
    }

    private func closePopover(_ sender: Any?) {
        popoverHostingView?.deactivatePreferredContentSizeMeasurements()
        if popover.isShown {
            popover.performClose(sender)
        } else {
            finishPopoverDismissal()
        }
    }

    private func finishPopoverDismissal() {
        popoverHostingView?.deactivatePreferredContentSizeMeasurements()
        finishPendingPresentationMeasurement(didShow: false)
        popoverPresentation.dismiss()
        visualState.isHighlighted = false
        popoverAnchorButton?.highlight(false)
    }

    private var popoverAnchorButton: NSButton? {
        statusItem?.button ?? popoverAnchorOverride
    }

    func popoverDidShow(_ notification: Notification) {
        finishPendingPresentationMeasurement(didShow: true)
    }

    func popoverDidClose(_ notification: Notification) {
        finishPopoverDismissal()
    }

    /// Read-only diagnostics for tests and Instruments correlation. It keeps
    /// AppKit objects private while exposing whether expensive content is
    /// mounted and how much work the most recent opening performed.
    var performanceSnapshot: MenuBarPopoverPerformanceSnapshot {
        MenuBarPopoverPerformanceSnapshot(
            isPresented: popoverPresentation.isPresented,
            isDashboardMounted: popoverHostingView != nil,
            presentationCount: completedPresentationCount,
            totalContentSizeChangeCount: totalPopoverContentSizeChangeCount,
            currentPresentationContentSizeChangeCount: popoverPresentation.isPresented
                ? totalPopoverContentSizeChangeCount - presentationSizeChangeStartCount
                : nil,
            lastOpeningLatencyMilliseconds: lastOpeningLatencyMilliseconds,
            lastOpeningContentSizeChangeCount: lastOpeningContentSizeChangeCount,
            lastOpeningWasCold: lastOpeningWasCold
        )
    }

    /// Geometry exposed to the in-memory AppKit lifecycle tests. Values are
    /// read directly from the mounted hierarchy so warm-open regressions cannot
    /// be hidden by the dashboard's intrinsic size alone.
    var popoverGeometrySnapshot: MenuBarPopoverGeometrySnapshot? {
        guard let popoverHostingView else { return nil }
        return MenuBarPopoverGeometrySnapshot(
            popoverContentSize: popover.contentSize,
            hostingFrame: popoverHostingView.frame,
            hostingBounds: popoverHostingView.bounds,
            hostingFrameInWindow: popoverHostingView.window.map { _ in
                popoverHostingView.convert(popoverHostingView.bounds, to: nil)
            },
            windowContentLayoutRect: popoverHostingView.window?.contentLayoutRect
        )
    }
}

struct MenuBarPopoverLayout: Equatable, Sendable {
    let columnHeight: CGFloat
    let contentSize: CGSize
}

enum MenuBarPopoverSizingPolicy {
    static let collapsedContentWidth = MenuBarDashboardLayout.collapsedContentWidth
    static let expandedContentWidth = MenuBarDashboardLayout.expandedContentWidth
    static let minimumColumnHeight = MenuBarDashboardLayout.minimumColumnHeight
    static let maximumColumnHeight = MenuBarDashboardLayout.maximumColumnHeight
    static let screenVerticalReservedSpace: CGFloat = 84
    static let contentVerticalChrome: CGFloat = 20

    static func layout(
        availableHeight: CGFloat?,
        fallbackHeight: CGFloat = 900
    ) -> MenuBarPopoverLayout {
        let safeFallbackHeight = fallbackHeight.isFinite && fallbackHeight > 0
            ? fallbackHeight
            : 900
        let usableHeight = availableHeight.flatMap { height in
            height.isFinite && height > 0 ? height : nil
        } ?? safeFallbackHeight
        let columnHeight = min(
            max(usableHeight - screenVerticalReservedSpace, minimumColumnHeight),
            maximumColumnHeight
        )
        return MenuBarPopoverLayout(
            columnHeight: columnHeight,
            contentSize: CGSize(
                width: collapsedContentWidth,
                height: columnHeight + contentVerticalChrome
            )
        )
    }

    static func contentSize(
        preferredWidth: CGFloat,
        columnHeight: CGFloat
    ) -> CGSize {
        let normalizedWidth = normalizedContentWidth(preferredWidth: preferredWidth)
        let finiteColumnHeight = columnHeight.isFinite
            ? columnHeight
            : minimumColumnHeight
        let normalizedColumnHeight = min(
            max(finiteColumnHeight, minimumColumnHeight),
            maximumColumnHeight
        )
        return CGSize(
            width: normalizedWidth,
            height: normalizedColumnHeight + contentVerticalChrome
        )
    }

    static func normalizedContentWidth(preferredWidth: CGFloat) -> CGFloat {
        guard preferredWidth.isFinite else { return collapsedContentWidth }
        let expansionThreshold = (collapsedContentWidth + expandedContentWidth) / 2
        return preferredWidth < expansionThreshold
            ? collapsedContentWidth
            : expandedContentWidth
    }

    static func needsUpdate(
        current: CGFloat,
        target: CGFloat,
        tolerance: CGFloat = 0.5
    ) -> Bool {
        guard current.isFinite, target.isFinite else { return true }
        return abs(current - target) > tolerance
    }

    static func needsUpdate(
        current: CGSize,
        target: CGSize,
        tolerance: CGFloat = 0.5
    ) -> Bool {
        needsUpdate(current: current.width, target: target.width, tolerance: tolerance)
            || needsUpdate(current: current.height, target: target.height, tolerance: tolerance)
    }
}

struct MenuBarPopoverPresentation: Equatable, Sendable {
    private(set) var isPresented = false
    private(set) var presentationID: UInt64 = 0
    private(set) var hasMountedDashboard = false

    var shouldMountDashboard: Bool { hasMountedDashboard }

    @discardableResult
    mutating func present() -> Bool {
        guard !isPresented else { return false }
        presentationID &+= 1
        isPresented = true
        hasMountedDashboard = true
        return true
    }

    @discardableResult
    mutating func dismiss() -> Bool {
        guard isPresented else { return false }
        isPresented = false
        return true
    }
}

struct MenuBarPopoverPerformanceSnapshot: Equatable, Sendable {
    let isPresented: Bool
    let isDashboardMounted: Bool
    let presentationCount: Int
    let totalContentSizeChangeCount: Int
    let currentPresentationContentSizeChangeCount: Int?
    let lastOpeningLatencyMilliseconds: Double?
    let lastOpeningContentSizeChangeCount: Int?
    let lastOpeningWasCold: Bool?
}

struct MenuBarPopoverGeometrySnapshot: Equatable, Sendable {
    let popoverContentSize: CGSize
    let hostingFrame: CGRect
    let hostingBounds: CGRect
    let hostingFrameInWindow: CGRect?
    let windowContentLayoutRect: CGRect?
}

private struct PendingPopoverPresentationMeasurement {
    let intervalState: OSSignpostIntervalState
    let startedAt: TimeInterval
    let contentSizeChangeCountAtStart: Int
    let wasCold: Bool
}

@MainActor
@Observable
private final class MenuBarStatusVisualState {
    var isHighlighted = false
}

private final class PassthroughHostingView: NSHostingView<AnyView> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

enum MenuBarStatusInteractionPolicy {
    static let actionEventMask: NSEvent.EventTypeMask = [.leftMouseDown]
}

@MainActor
@Observable
private final class MenuBarPopoverLayoutState {
    var maximumColumnHeight: CGFloat

    init(maximumColumnHeight: CGFloat) {
        self.maximumColumnHeight = maximumColumnHeight
    }
}

private final class MenuBarPopoverHostingView: NSHostingView<AnyView> {
    var onPreferredContentSizeChange: ((CGSize, UInt64) -> Void)?
    private var isMeasurementScheduled = false
    private var lastReportedPreferredSize = CGSize.zero
    private var activePresentationID: UInt64?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        requestPreferredContentSizeMeasurement()
    }

    func activatePreferredContentSizeMeasurements(for presentationID: UInt64) {
        guard presentationID > 0 else { return }
        if activePresentationID != presentationID {
            activePresentationID = presentationID
            lastReportedPreferredSize = .zero
        }
        requestPreferredContentSizeMeasurement()
    }

    func deactivatePreferredContentSizeMeasurements() {
        activePresentationID = nil
    }

    func requestPreferredContentSizeMeasurement() {
        guard let presentationID = activePresentationID else { return }
        guard !isMeasurementScheduled else { return }
        isMeasurementScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isMeasurementScheduled = false
            guard self.activePresentationID == presentationID else {
                // A measurement requested by an older popover presentation
                // must never resize a newer one. If another presentation is
                // already active, schedule a fresh measurement for that ID.
                self.requestPreferredContentSizeMeasurement()
                return
            }
            let preferredSize = self.fittingSize
            guard preferredSize.width.isFinite,
                  preferredSize.height.isFinite,
                  preferredSize.width > 0,
                  preferredSize.height > 0,
                  MenuBarPopoverSizingPolicy.needsUpdate(
                    current: self.lastReportedPreferredSize,
                    target: preferredSize
                  ) else { return }
            self.lastReportedPreferredSize = preferredSize
            self.onPreferredContentSizeChange?(preferredSize, presentationID)
        }
    }
}

private struct MenuBarStatusContentSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0, next.height > 0 {
            value = next
        }
    }
}

private struct MenuBarStatusContentSizeReader: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: MenuBarStatusContentSizePreferenceKey.self,
                value: proxy.size
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct MenuBarStatusHostingRoot: View {
    let model: AppModel
    let visualState: MenuBarStatusVisualState
    let onContentSizeChange: (CGSize) -> Void

    var body: some View {
        MenuBarStatusStrip()
            .environment(model)
            .traceHaloLanguageEnvironment()
            .foregroundStyle(visualState.isHighlighted ? Color.white : Color.primary)
            .background(MenuBarStatusContentSizeReader())
            .onPreferenceChange(MenuBarStatusContentSizePreferenceKey.self) { size in
                onContentSizeChange(size)
            }
    }
}

private struct MenuBarPopoverHostingRoot: View {
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    let model: AppModel
    let navigationRouter: AppNavigationRouter
    let layoutState: MenuBarPopoverLayoutState
    let openMainWindowAction: () -> Void
    let quitApplicationAction: () -> Void

    var body: some View {
        MenuBarDashboardView(
            maximumColumnHeightOverride: layoutState.maximumColumnHeight,
            openMainWindowAction: openMainWindowAction,
            quitApplicationAction: quitApplicationAction
        )
        .environment(model)
        .environment(navigationRouter)
        .traceHaloLanguageEnvironment()
        .transaction { transaction in
            transaction.animation = nil
        }
        .preferredColorScheme(preferredColorScheme)
        .traceHaloFocusAppearance()
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}
