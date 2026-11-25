import AppKit
import Darwin
import Observation
import SwiftUI
import XCTest
@testable import TraceHaloApp

final class MainWindowAndSidebarLayoutTests: XCTestCase {
    @MainActor
    func testEarlyActivationIsReplayedWhenSceneBridgeBecomesAvailable() {
        let application = NSApplication.shared
        let previousPolicy = application.activationPolicy()
        defer { application.setActivationPolicy(previousPolicy) }
        let router = AppNavigationRouter(destination: .report)
        let controller = MenuBarStatusItemController(model: AppModel(), navigationRouter: router)
        var openCount = 0

        controller.activateMainWindowPreservingDestination()
        controller.activateMainWindowPreservingDestination()
        controller.setOpenMainWindowAction { openCount += 1 }

        XCTAssertEqual(openCount, 1)
        XCTAssertEqual(router.destination, .report)
        controller.setOpenMainWindowAction { openCount += 1 }
        XCTAssertEqual(openCount, 1)
    }

    @MainActor
    func testMenuBarRestoresHiddenWindowWithSwiftUISceneIdentifier() {
        let application = NSApplication.shared
        let previousPolicy = application.activationPolicy()
        let router = AppNavigationRouter(destination: .report)
        let controller = MenuBarStatusItemController(model: AppModel(), navigationRouter: router)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 240, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("main")
        defer {
            window.close()
            application.setActivationPolicy(previousPolicy)
        }

        XCTAssertFalse(window.isVisible)

        controller.showMainWindow()

        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(router.destination, .dashboard)
    }

    @MainActor
    func testStatusBarRequestsApplicationActivationInAdditionToRestoringTheWindow() {
        let application = NSApplication.shared
        let previousPolicy = application.activationPolicy()
        var activationCount = 0
        let controller = MenuBarStatusItemController(
            model: AppModel(),
            navigationRouter: AppNavigationRouter(),
            activateMainApplication: { activationCount += 1 }
        )
        let window = makeRecoveryTestWindow()
        defer {
            window.close()
            application.setActivationPolicy(previousPolicy)
        }

        controller.showMainWindow()

        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(activationCount, 1)
    }

    @MainActor
    func testDockAndExistingInstanceActivationDoNotRequestAnotherApplicationReopen() {
        let application = NSApplication.shared
        let previousPolicy = application.activationPolicy()
        var activationCount = 0
        let controller = MenuBarStatusItemController(
            model: AppModel(),
            navigationRouter: AppNavigationRouter(),
            activateMainApplication: { activationCount += 1 }
        )
        let window = makeRecoveryTestWindow()
        defer {
            window.close()
            application.setActivationPolicy(previousPolicy)
        }

        controller.showMainWindow(source: .dock)
        controller.activateMainWindowPreservingDestination()

        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(activationCount, 0, "Launch Services' reopen callback must not start another reopen request")
    }

    @MainActor
    func testReopeningAlwaysAsksSwiftUIToRestoreTheSceneEvenWithARetainedWindow() {
        let application = NSApplication.shared
        let previousPolicy = application.activationPolicy()
        let controller = MenuBarStatusItemController(model: AppModel(), navigationRouter: AppNavigationRouter())
        let window = makeRecoveryTestWindow()
        var openCount = 0
        controller.setOpenMainWindowAction { openCount += 1 }
        defer {
            window.close()
            application.setActivationPolicy(previousPolicy)
        }

        controller.showMainWindow()

        XCTAssertEqual(openCount, 1, "A retained window must not bypass SwiftUI's scene lifecycle")
        XCTAssertTrue(window.isVisible)
    }

    @MainActor
    func testWindowRegistrationRestoresWindowWithoutRelyingOnSwiftUISceneIdentifier() {
        let application = NSApplication.shared
        let previousPolicy = application.activationPolicy()
        let controller = MenuBarStatusItemController(model: AppModel(), navigationRouter: AppNavigationRouter())
        let window = makeRecoveryTestWindow(identifier: "SwiftUI.generated.main")
        controller.registerMainWindow(window)
        defer {
            window.close()
            application.setActivationPolicy(previousPolicy)
        }

        controller.showMainWindow()

        XCTAssertTrue(window.isVisible)
    }

    @MainActor
    func testClosedSceneIsRecreatedInsteadOfOrderingItsOldWindowFront() {
        let application = NSApplication.shared
        let previousPolicy = application.activationPolicy()
        let controller = MenuBarStatusItemController(model: AppModel(), navigationRouter: AppNavigationRouter())
        let oldWindow = makeRecoveryTestWindow()
        controller.registerMainWindow(oldWindow)
        oldWindow.close()
        let replacement = makeRecoveryTestWindow(identifier: "SwiftUI.recreated.main")
        controller.setOpenMainWindowAction { [weak controller] in controller?.registerMainWindow(replacement) }
        defer {
            oldWindow.close()
            replacement.close()
            application.setActivationPolicy(previousPolicy)
        }

        controller.showMainWindow()

        XCTAssertFalse(oldWindow.isVisible)
        XCTAssertTrue(replacement.isVisible)
    }

    @MainActor
    func testLateSceneRegistrationCompletesPendingWindowPresentation() async {
        let application = NSApplication.shared
        let previousPolicy = application.activationPolicy()
        let controller = MenuBarStatusItemController(model: AppModel(), navigationRouter: AppNavigationRouter())
        controller.setOpenMainWindowAction {}
        controller.showMainWindow()
        let window = makeRecoveryTestWindow(identifier: "SwiftUI.late.main")
        defer {
            window.close()
            application.setActivationPolicy(previousPolicy)
        }

        controller.registerMainWindow(window)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(window.isVisible)
    }

    @MainActor
    func testDockReopenRestoresEvenWhenAppKitReportsAVisibleWindow() {
        let application = NSApplication.shared
        let previousPolicy = application.activationPolicy()
        let delegate = TraceHaloApplicationDelegate()
        let window = makeRecoveryTestWindow()
        window.orderFront(nil)
        var openCount = 0
        delegate.menuBarController.setOpenMainWindowAction { openCount += 1 }
        defer {
            window.close()
            application.setActivationPolicy(previousPolicy)
        }

        let shouldUseDefaultReopen = delegate.applicationShouldHandleReopen(application, hasVisibleWindows: true)

        XCTAssertFalse(shouldUseDefaultReopen)
        XCTAssertEqual(openCount, 1)
        XCTAssertTrue(window.isVisible)
    }

    @MainActor
    func testReopeningRestoresMinimizedWindowAndRegularActivationPolicy() {
        let application = NSApplication.shared
        let previousPolicy = application.activationPolicy()
        let controller = MenuBarStatusItemController(model: AppModel(), navigationRouter: AppNavigationRouter())
        let window = makeRecoveryTestWindow()
        window.orderFront(nil)
        window.miniaturize(nil)
        application.setActivationPolicy(.accessory)
        defer {
            window.close()
            application.setActivationPolicy(previousPolicy)
        }

        controller.showMainWindow()

        XCTAssertFalse(window.isMiniaturized)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(application.activationPolicy(), .regular)
        XCTAssertTrue(window.collectionBehavior.contains(.moveToActiveSpace))
    }

    @MainActor
    func testReopeningMovesAnOffscreenWindowBackOntoADisplay() throws {
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("Requires a display") }
        let application = NSApplication.shared
        let previousPolicy = application.activationPolicy()
        let controller = MenuBarStatusItemController(model: AppModel(), navigationRouter: AppNavigationRouter())
        let window = makeRecoveryTestWindow()
        window.setFrameOrigin(CGPoint(x: -50_000, y: -50_000))
        defer {
            window.close()
            application.setActivationPolicy(previousPolicy)
        }

        controller.showMainWindow()

        XCTAssertTrue(NSScreen.screens.contains { $0.visibleFrame.intersects(window.frame) })
        XCTAssertTrue(window.isVisible)
    }

    @MainActor
    func testClosingWindowCancelsDeferredPresentation() async {
        let application = NSApplication.shared
        let previousPolicy = application.activationPolicy()
        let controller = MenuBarStatusItemController(model: AppModel(), navigationRouter: AppNavigationRouter())
        let window = makeRecoveryTestWindow()
        controller.registerMainWindow(window)
        defer {
            window.close()
            application.setActivationPolicy(previousPolicy)
        }

        controller.showMainWindow()
        window.close()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(window.isVisible, "A queued focus pass must not reopen a window the user just closed")
    }

    @MainActor
    func testReopeningRestoresAWindowWithOnlyOnePixelOnscreen() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let application = NSApplication.shared
        let previousPolicy = application.activationPolicy()
        let controller = MenuBarStatusItemController(model: AppModel(), navigationRouter: AppNavigationRouter())
        let window = makeRecoveryTestWindow()
        defer {
            window.close()
            application.setActivationPolicy(previousPolicy)
        }
        window.setFrameOrigin(CGPoint(x: screen.visibleFrame.maxX - 1, y: screen.visibleFrame.midY))
        XCTAssertEqual(screen.visibleFrame.intersection(window.frame).width, 1, accuracy: 0.01)

        controller.showMainWindow(source: .dock)

        XCTAssertTrue(screen.visibleFrame.contains(window.frame))
        XCTAssertTrue(window.isVisible)
    }

    func testWindowRecoveryPullsAOnePixelSliverFullyOntoTheDisplay() throws {
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let original = CGRect(x: 2559, y: 200, width: 1320, height: 868)
        let recovered = try XCTUnwrap(MainWindowRecoveryPolicy.recoveredFrame(
            for: original, visibleFrames: [screen], preferredVisibleFrame: screen
        ))
        XCTAssertTrue(screen.contains(recovered))
        XCTAssertEqual(recovered.size, original.size)
    }

    func testWindowRecoveryMakesAnOffscreenTitlebarReachable() throws {
        let screen = CGRect(x: 0, y: 24, width: 2560, height: 1390)
        let original = CGRect(x: 100, y: 1000, width: 1320, height: 868)
        let recovered = try XCTUnwrap(MainWindowRecoveryPolicy.recoveredFrame(
            for: original, visibleFrames: [screen], preferredVisibleFrame: screen
        ))
        XCTAssertTrue(screen.contains(recovered))
        XCTAssertEqual(recovered.maxY, screen.maxY)
    }

    func testWindowRecoveryPreservesAUsablePositionOnAnotherDisplay() {
        let left = CGRect(x: -2560, y: 0, width: 2560, height: 1440)
        let right = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        XCTAssertNil(MainWindowRecoveryPolicy.recoveredFrame(
            for: CGRect(x: -2400, y: 200, width: 1320, height: 868),
            visibleFrames: [left, right], preferredVisibleFrame: right
        ))
    }

    func testWindowRecoveryChoosesTheDisplayWithTheLargestVisibleArea() throws {
        let left = CGRect(x: -1600, y: 0, width: 1600, height: 1000)
        let right = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let recovered = try XCTUnwrap(MainWindowRecoveryPolicy.recoveredFrame(
            for: CGRect(x: -200, y: 100, width: 1320, height: 868),
            visibleFrames: [left, right], preferredVisibleFrame: left
        ))
        XCTAssertTrue(right.contains(recovered))
    }

    func testWindowRecoveryUsesThePreferredDisplayAfterADisplayIsRemoved() throws {
        let left = CGRect(x: -1600, y: 0, width: 1600, height: 1000)
        let right = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let recovered = try XCTUnwrap(MainWindowRecoveryPolicy.recoveredFrame(
            for: CGRect(x: 5000, y: 200, width: 1320, height: 868),
            visibleFrames: [left, right], preferredVisibleFrame: right
        ))
        XCTAssertTrue(right.contains(recovered))
    }

    func testWindowRecoveryKeepsTheTitlebarOnASmallerReplacementDisplay() throws {
        let screen = CGRect(x: 100, y: 200, width: 1000, height: 700)
        let original = CGRect(x: 900, y: 700, width: 1320, height: 868)
        let recovered = try XCTUnwrap(MainWindowRecoveryPolicy.recoveredFrame(
            for: original, visibleFrames: [screen], preferredVisibleFrame: screen
        ))
        XCTAssertEqual(recovered.size, original.size)
        XCTAssertEqual(recovered.minX, screen.minX)
        XCTAssertEqual(recovered.maxY, screen.maxY)
    }

    func testWindowRecoveryDoesNotMoveAnAlreadyUsableWindow() {
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        XCTAssertNil(MainWindowRecoveryPolicy.recoveredFrame(
            for: CGRect(x: 100, y: 100, width: 1320, height: 868),
            visibleFrames: [screen], preferredVisibleFrame: screen
        ))
    }

    func testWindowRecoveryWaitsWhenNoDisplayIsAvailable() {
        XCTAssertNil(MainWindowRecoveryPolicy.recoveredFrame(
            for: CGRect(x: -5000, y: 100, width: 1320, height: 868),
            visibleFrames: [], preferredVisibleFrame: nil
        ))
    }

    @MainActor
    private func makeRecoveryTestWindow(identifier: String = "main") -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: 100, y: 100, width: 240, height: 180),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier(identifier)
        return window
    }

    @MainActor
    func testRepeatedNavigationToTheActivePageDoesNotInvalidateObservers() {
        let router = AppNavigationRouter(destination: .dashboard)
        let invalidationCounter = ThreadSafeInvalidationCounter()

        withObservationTracking {
            _ = router.destination
        } onChange: {
            invalidationCounter.increment()
        }

        router.navigate(to: .dashboard)

        XCTAssertEqual(invalidationCounter.value, 0)
        XCTAssertEqual(router.destination, .dashboard)
    }

    func testMainWindowUsesPreferredCanvasWhenScreenCanContainIt() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_728, height: 1_080)

        XCTAssertEqual(
            MainWindowLayoutPolicy.contentSize(for: visibleFrame),
            CGSize(width: 1_320, height: 840)
        )
    }

    func testMainWindowUsesSingleCompactCanvasOnSmallScreen() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_300, height: 820)

        XCTAssertEqual(
            MainWindowLayoutPolicy.contentSize(for: visibleFrame),
            CGSize(width: 1_180, height: 750)
        )
    }

    func testMainWindowFitsAndLocksCanvasInsideVerySmallVisibleFrame() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_000, height: 700)
        let expected = CGSize(width: 976, height: 644)

        XCTAssertEqual(MainWindowLayoutPolicy.contentSize(for: visibleFrame), expected)
        XCTAssertEqual(MainWindowLayoutPolicy.contentSize(for: visibleFrame), expected)
        XCTAssertLessThanOrEqual(
            expected.width + MainWindowLayoutPolicy.horizontalScreenAllowance,
            visibleFrame.width
        )
        XCTAssertLessThanOrEqual(
            expected.height + MainWindowLayoutPolicy.verticalScreenAllowance,
            visibleFrame.height
        )
    }

    func testLaunchCanvasPrefersMainScreenAndFallsBackWhenNeeded() {
        let mainScreenFrame = CGRect(x: 0, y: 0, width: 1_300, height: 820)
        let fallbackScreenFrame = CGRect(x: 0, y: 0, width: 1_000, height: 700)

        XCTAssertEqual(
            MainWindowLayoutPolicy.lockedCanvasAtLaunch(
                mainScreenVisibleFrame: mainScreenFrame,
                fallbackScreenVisibleFrame: fallbackScreenFrame
            ).contentSize,
            MainWindowLayoutPolicy.compactContentSize
        )
        XCTAssertEqual(
            MainWindowLayoutPolicy.lockedCanvasAtLaunch(
                mainScreenVisibleFrame: nil,
                fallbackScreenVisibleFrame: fallbackScreenFrame
            ).contentSize,
            CGSize(width: 976, height: 644)
        )
    }

    func testLaunchCanvasDoesNotFollowLaterScreenChanges() {
        let launchFrame = CGRect(x: 0, y: 0, width: 1_300, height: 820)
        let lockedCanvas = MainWindowLayoutPolicy.lockedCanvasAtLaunch(
            mainScreenVisibleFrame: launchFrame,
            fallbackScreenVisibleFrame: nil
        )
        let laterLargerScreen = CGRect(x: 0, y: 0, width: 1_728, height: 1_080)

        XCTAssertEqual(lockedCanvas.contentSize, MainWindowLayoutPolicy.compactContentSize)
        XCTAssertEqual(
            MainWindowLayoutPolicy.contentSize(for: laterLargerScreen),
            MainWindowLayoutPolicy.preferredContentSize
        )
        XCTAssertEqual(lockedCanvas.contentSize, MainWindowLayoutPolicy.compactContentSize)
    }

    @MainActor
    func testFixedWindowCanvasRootHasExactSceneContentSize() {
        let target = CGSize(width: 1_180, height: 750)
        let hostingView = NSHostingView(
            rootView: FixedWindowCanvasRoot(contentSize: target) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        )

        XCTAssertEqual(hostingView.fittingSize, target)
    }

    @MainActor
    func testFixedCanvasHasOneNormalWindowSizeAuthority() {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert([
            .fullScreenPrimary,
            .fullScreenAllowsTiling,
        ])
        window.isRestorable = true
        window.isMovable = true
        window.isMovableByWindowBackground = true
        _ = window.setFrameAutosaveName("TraceHalo.MainWindowTest")
        defer { window.close() }
        window.aspectRatio = CGSize(width: 16, height: 10)

        let target = MainWindowLayoutPolicy.preferredContentSize
        MainWindowLayoutPolicy.applyFixedCanvas(target, to: window)

        XCTAssertEqual(window.contentView?.bounds.size, target)
        XCTAssertEqual(window.contentMinSize, target)
        XCTAssertEqual(window.contentMaxSize, target)
        XCTAssertEqual(window.aspectRatio, .zero)
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertTrue(window.styleMask.contains(.miniaturizable))
        XCTAssertFalse(window.isMovable)
        XCTAssertFalse(window.isMovableByWindowBackground)
        XCTAssertFalse(window.isRestorable)
        XCTAssertTrue(window.frameAutosaveName.isEmpty)
        XCTAssertFalse(window.collectionBehavior.contains(.fullScreenPrimary))
        XCTAssertFalse(window.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(window.collectionBehavior.contains(.fullScreenAllowsTiling))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenNone))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenDisallowsTiling))
        XCTAssertEqual(window.standardWindowButton(.zoomButton)?.isEnabled, false)
        XCTAssertEqual(window.standardWindowButton(.zoomButton)?.isHidden, true)
        XCTAssertNil(window.standardWindowButton(.zoomButton)?.target)
        XCTAssertNil(window.standardWindowButton(.zoomButton)?.action)
        XCTAssertEqual(window.standardWindowButton(.miniaturizeButton)?.isEnabled, true)
        XCTAssertEqual(window.standardWindowButton(.closeButton)?.isEnabled, true)
    }

    @MainActor
    func testFixedCanvasApplicationIsIdempotentAndReassertsWindowPolicy() throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }

        let target = MainWindowLayoutPolicy.compactContentSize
        let zoomActionProbe = WindowZoomActionProbe()
        _ = window.setFrameAutosaveName("TraceHalo.ReassertionTest")
        for _ in 0..<20 {
            // Restore a coherent resizable state before simulating SwiftUI's
            // style pollution. AppKit can trap if `.resizable` is inserted
            // while equal fixed-size constraints are still active.
            window.contentMinSize = CGSize(width: 1, height: 1)
            window.contentMaxSize = CGSize(width: 2_000, height: 2_000)
            window.styleMask.insert(.resizable)
            window.collectionBehavior.remove([
                .fullScreenNone,
                .fullScreenDisallowsTiling,
            ])
            window.collectionBehavior.insert([
                .fullScreenPrimary,
                .fullScreenAllowsTiling,
            ])
            window.isRestorable = true
            window.isMovable = true
            window.isMovableByWindowBackground = true
            if let zoomButton = window.standardWindowButton(.zoomButton) {
                zoomButton.isEnabled = true
                zoomButton.isHidden = false
                zoomButton.target = zoomActionProbe
                zoomButton.action = #selector(WindowZoomActionProbe.invoke(_:))
            }
            window.setContentSize(CGSize(width: 900, height: 700))
            MainWindowLayoutPolicy.applyFixedCanvas(target, to: window)
        }

        XCTAssertEqual(window.contentView?.bounds.size, target)
        XCTAssertEqual(window.contentMinSize, target)
        XCTAssertEqual(window.contentMaxSize, target)
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertFalse(window.collectionBehavior.contains(.fullScreenPrimary))
        XCTAssertFalse(window.collectionBehavior.contains(.fullScreenAllowsTiling))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenNone))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenDisallowsTiling))
        XCTAssertFalse(window.isMovable)
        XCTAssertFalse(window.isMovableByWindowBackground)
        XCTAssertFalse(window.isRestorable)
        XCTAssertTrue(window.frameAutosaveName.isEmpty)
        let zoomButton = try XCTUnwrap(window.standardWindowButton(.zoomButton))
        let lockedFrame = window.frame
        zoomButton.performClick(nil)
        window.performZoom(nil)
        XCTAssertFalse(zoomButton.isEnabled)
        XCTAssertTrue(zoomButton.isHidden)
        XCTAssertNil(zoomButton.target)
        XCTAssertNil(zoomButton.action)
        XCTAssertEqual(zoomActionProbe.invocationCount, 0)
        XCTAssertEqual(window.frame, lockedFrame)
    }

    @MainActor
    func testSettingsWindowUsesTheSameFullCanvasPolicyAndDisablesZoom() {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }

        let largeVisibleFrame = CGRect(x: 0, y: 0, width: 1_728, height: 1_080)
        let target = MainWindowLayoutPolicy.contentSize(for: largeVisibleFrame)
        MainWindowLayoutPolicy.applyFixedCanvas(
            target,
            to: window
        )

        let lockedFrame = window.frame
        window.performZoom(nil)

        XCTAssertEqual(
            window.contentView?.bounds.size,
            MainWindowLayoutPolicy.preferredContentSize
        )
        XCTAssertEqual(window.frame, lockedFrame)
        // On recent AppKit versions `performZoom` can toggle the internal
        // `isZoomed` bit even when the non-resizable frame cannot move. The
        // user-visible invariant is the unchanged frame plus a disabled,
        // hidden zoom control with no action.
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertFalse(window.isMovable)
        XCTAssertFalse(window.isMovableByWindowBackground)
        XCTAssertEqual(window.standardWindowButton(.zoomButton)?.isEnabled, false)
        XCTAssertEqual(window.standardWindowButton(.zoomButton)?.isHidden, true)
        XCTAssertNil(window.standardWindowButton(.zoomButton)?.target)
        XCTAssertNil(window.standardWindowButton(.zoomButton)?.action)
        XCTAssertEqual(window.standardWindowButton(.miniaturizeButton)?.isEnabled, true)
        XCTAssertEqual(window.standardWindowButton(.closeButton)?.isEnabled, true)
    }

    @MainActor
    func testFixedCanvasRestoresSizeWithoutChangingFrameOrigin() {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: CGRect(x: 220, y: 180, width: 640, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let originalOrigin = window.frame.origin

        MainWindowLayoutPolicy.applyFixedCanvas(
            MainWindowLayoutPolicy.preferredContentSize,
            to: window
        )

        XCTAssertEqual(window.frame.origin, originalOrigin)
        XCTAssertEqual(
            window.contentView?.bounds.size,
            MainWindowLayoutPolicy.preferredContentSize
        )
    }

    func testFixedCanvasDefersDuringFullScreenAndLiveResize() {
        XCTAssertTrue(
            MainWindowLayoutPolicy.shouldApplyFixedCanvas(
                isFullScreen: false,
                isInLiveResize: false
            )
        )
        XCTAssertFalse(
            MainWindowLayoutPolicy.shouldApplyFixedCanvas(
                isFullScreen: true,
                isInLiveResize: false
            )
        )
        XCTAssertFalse(
            MainWindowLayoutPolicy.shouldApplyFixedCanvas(
                isFullScreen: false,
                isInLiveResize: true
            )
        )
    }

    func testTitlebarDoubleClickMouseUpSuppressionIsWindowAndRegionScoped() {
        let contentLayoutRect = CGRect(x: 0, y: 0, width: 1_320, height: 812)
        let windowFrameSize = CGSize(width: 1_320, height: 840)
        let titlebarPoint = CGPoint(x: 660, y: 826)

        XCTAssertTrue(
            MainWindowLayoutPolicy.shouldSuppressTitlebarDoubleClickMouseUp(
                eventBelongsToManagedWindow: true,
                clickCount: 2,
                locationInWindow: titlebarPoint,
                contentLayoutRect: contentLayoutRect,
                windowFrameSize: windowFrameSize
            )
        )
        XCTAssertTrue(
            MainWindowLayoutPolicy.shouldSuppressTitlebarDoubleClickMouseUp(
                eventBelongsToManagedWindow: true,
                clickCount: 3,
                locationInWindow: titlebarPoint,
                contentLayoutRect: contentLayoutRect,
                windowFrameSize: windowFrameSize
            )
        )
        XCTAssertFalse(
            MainWindowLayoutPolicy.shouldSuppressTitlebarDoubleClickMouseUp(
                eventBelongsToManagedWindow: true,
                clickCount: 1,
                locationInWindow: titlebarPoint,
                contentLayoutRect: contentLayoutRect,
                windowFrameSize: windowFrameSize
            ),
            "A normal click or drag mouse-up must continue to AppKit"
        )
        XCTAssertFalse(
            MainWindowLayoutPolicy.shouldSuppressTitlebarDoubleClickMouseUp(
                eventBelongsToManagedWindow: true,
                clickCount: 2,
                locationInWindow: CGPoint(x: 660, y: 700),
                contentLayoutRect: contentLayoutRect,
                windowFrameSize: windowFrameSize
            ),
            "Double-clicks inside app content must not be consumed"
        )
        XCTAssertFalse(
            MainWindowLayoutPolicy.shouldSuppressTitlebarDoubleClickMouseUp(
                eventBelongsToManagedWindow: false,
                clickCount: 2,
                locationInWindow: titlebarPoint,
                contentLayoutRect: contentLayoutRect,
                windowFrameSize: windowFrameSize
            ),
            "The local monitor must not affect other windows"
        )
        XCTAssertFalse(
            MainWindowLayoutPolicy.shouldSuppressTitlebarDoubleClickMouseUp(
                eventBelongsToManagedWindow: true,
                clickCount: 2,
                locationInWindow: CGPoint(x: -1, y: 826),
                contentLayoutRect: contentLayoutRect,
                windowFrameSize: windowFrameSize
            ),
            "Points outside the managed window are never consumed"
        )
    }

    func testResizeMouseDownSuppressionCoversEdgesButPreservesTitlebarDrag() {
        let windowFrameSize = CGSize(width: 1_320, height: 840)
        let edgePoints = [
            CGPoint(x: 2, y: 420),
            CGPoint(x: 1_318, y: 420),
            CGPoint(x: 660, y: 2),
            CGPoint(x: 660, y: 838),
            CGPoint(x: 3, y: 837),
            CGPoint(x: -4, y: 420),
        ]

        for point in edgePoints {
            XCTAssertTrue(
                MainWindowLayoutPolicy.shouldSuppressResizeMouseDown(
                    eventBelongsToManagedWindow: true,
                    locationInWindow: point,
                    windowFrameSize: windowFrameSize
                ),
                "Expected edge point \(point) to start a suppressed resize gesture"
            )
        }

        XCTAssertFalse(
            MainWindowLayoutPolicy.shouldSuppressResizeMouseDown(
                eventBelongsToManagedWindow: true,
                locationInWindow: CGPoint(x: 660, y: 820),
                windowFrameSize: windowFrameSize
            ),
            "The ordinary titlebar drag region must not be treated as resize"
        )
        XCTAssertFalse(
            MainWindowLayoutPolicy.shouldSuppressResizeMouseDown(
                eventBelongsToManagedWindow: true,
                locationInWindow: CGPoint(x: 660, y: 420),
                windowFrameSize: windowFrameSize
            ),
            "The app content interior must remain interactive"
        )
        XCTAssertFalse(
            MainWindowLayoutPolicy.shouldSuppressResizeMouseDown(
                eventBelongsToManagedWindow: false,
                locationInWindow: CGPoint(x: 2, y: 420),
                windowFrameSize: windowFrameSize
            ),
            "Resize gestures in other windows must not be intercepted"
        )
        XCTAssertFalse(
            MainWindowLayoutPolicy.shouldSuppressResizeMouseDown(
                eventBelongsToManagedWindow: true,
                locationInWindow: CGPoint(x: -20, y: 420),
                windowFrameSize: windowFrameSize
            ),
            "Points outside AppKit's resize slop must pass through"
        )
    }

    func testManagedTitlebarDragOnlyAllowsSafeSingleClickRegion() {
        let windowFrameSize = CGSize(width: 1_320, height: 840)
        let contentLayoutRect = CGRect(x: 0, y: 0, width: 1_320, height: 812)
        let closeButtonFrame = CGRect(x: 10, y: 816, width: 14, height: 14)
        let minimizeButtonFrame = CGRect(x: 32, y: 816, width: 14, height: 14)
        let excludedControlFrames = [closeButtonFrame, minimizeButtonFrame]
        let safeTitlebarPoint = CGPoint(x: 660, y: 820)

        XCTAssertTrue(
            MainWindowLayoutPolicy.shouldPerformManagedTitlebarDragMouseDown(
                eventBelongsToManagedWindow: true,
                clickCount: 1,
                locationInWindow: safeTitlebarPoint,
                contentLayoutRect: contentLayoutRect,
                windowFrameSize: windowFrameSize,
                excludedControlFrames: excludedControlFrames
            )
        )

        let rejectedCases: [(belongs: Bool, clicks: Int, point: CGPoint)] = [
            (true, 2, safeTitlebarPoint),
            (true, 1, CGPoint(x: 660, y: 700)),
            (true, 1, CGPoint(x: 660, y: 838)),
            (true, 1, CGPoint(x: 3, y: 820)),
            (true, 1, CGPoint(x: closeButtonFrame.midX, y: closeButtonFrame.midY)),
            (true, 1, CGPoint(x: minimizeButtonFrame.midX, y: minimizeButtonFrame.midY)),
            (false, 1, safeTitlebarPoint),
        ]
        for rejectedCase in rejectedCases {
            XCTAssertFalse(
                MainWindowLayoutPolicy.shouldPerformManagedTitlebarDragMouseDown(
                    eventBelongsToManagedWindow: rejectedCase.belongs,
                    clickCount: rejectedCase.clicks,
                    locationInWindow: rejectedCase.point,
                    contentLayoutRect: contentLayoutRect,
                    windowFrameSize: windowFrameSize,
                    excludedControlFrames: excludedControlFrames
                ),
                "Rejected titlebar drag case unexpectedly passed: \(rejectedCase)"
            )
        }
    }

    func testManagedTitlebarDragUsesCapturedGlobalMouseDelta() {
        let state = MainWindowLayoutPolicy.ManagedTitlebarDragState(
            initialMouseLocation: CGPoint(x: 500, y: 400),
            initialWindowOrigin: CGPoint(x: 120, y: 180)
        )

        XCTAssertEqual(
            state.windowOrigin(for: CGPoint(x: 500, y: 400)),
            CGPoint(x: 120, y: 180)
        )
        XCTAssertEqual(
            state.windowOrigin(for: CGPoint(x: 650, y: 460)),
            CGPoint(x: 270, y: 240)
        )
        XCTAssertEqual(
            state.windowOrigin(for: CGPoint(x: 450, y: 350)),
            CGPoint(x: 70, y: 130)
        )
    }

    @MainActor
    func testManagedTitlebarOriginMovePreservesEveryFixedCanvasLock() {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }

        let target = MainWindowLayoutPolicy.compactContentSize
        MainWindowLayoutPolicy.applyFixedCanvas(target, to: window)
        let lockedFrameSize = window.frame.size
        let dragState = MainWindowLayoutPolicy.ManagedTitlebarDragState(
            initialMouseLocation: CGPoint(x: 500, y: 400),
            initialWindowOrigin: window.frame.origin
        )
        let expectedOrigin = dragState.windowOrigin(
            for: CGPoint(x: 580, y: 460)
        )

        window.setFrameOrigin(expectedOrigin)

        XCTAssertEqual(window.frame.origin, expectedOrigin)
        XCTAssertEqual(window.frame.size, lockedFrameSize)
        XCTAssertFalse(window.isMovable)
        XCTAssertFalse(window.isMovableByWindowBackground)
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertEqual(window.contentMinSize, target)
        XCTAssertEqual(window.contentMaxSize, target)
        XCTAssertEqual(window.standardWindowButton(.zoomButton)?.isHidden, true)
    }

    func testManagedMouseEventStateAlwaysClearsResizeSuppressionOnMouseUp() {
        let windowFrameSize = CGSize(width: 1_320, height: 840)
        let contentLayoutRect = CGRect(x: 0, y: 0, width: 1_320, height: 812)
        var isSuppressingResizeGesture = false

        XCTAssertTrue(
            MainWindowLayoutPolicy.shouldSuppressManagedMouseEvent(
                phase: .down,
                eventBelongsToManagedWindow: true,
                clickCount: 1,
                locationInWindow: CGPoint(x: 2, y: 420),
                contentLayoutRect: contentLayoutRect,
                windowFrameSize: windowFrameSize,
                isSuppressingResizeGesture: &isSuppressingResizeGesture
            )
        )
        XCTAssertTrue(isSuppressingResizeGesture)

        XCTAssertTrue(
            MainWindowLayoutPolicy.shouldSuppressManagedMouseEvent(
                phase: .up,
                eventBelongsToManagedWindow: true,
                clickCount: 2,
                locationInWindow: CGPoint(x: 2, y: 420),
                contentLayoutRect: contentLayoutRect,
                windowFrameSize: windowFrameSize,
                isSuppressingResizeGesture: &isSuppressingResizeGesture
            )
        )
        XCTAssertFalse(isSuppressingResizeGesture)

        XCTAssertFalse(
            MainWindowLayoutPolicy.shouldSuppressManagedMouseEvent(
                phase: .dragged,
                eventBelongsToManagedWindow: true,
                clickCount: 0,
                locationInWindow: CGPoint(x: 660, y: 420),
                contentLayoutRect: contentLayoutRect,
                windowFrameSize: windowFrameSize,
                isSuppressingResizeGesture: &isSuppressingResizeGesture
            ),
            "A consumed mouse-up must not poison the next event sequence"
        )
    }

    func testSidebarMotionPolicyDisablesAnimationForReduceMotion() {
        XCTAssertNil(
            SidebarMotionPolicy.animation(reduceMotion: true, duration: 0.2)
        )
        XCTAssertNil(
            SidebarMotionPolicy.easeOutAnimation(reduceMotion: true, duration: 0.14)
        )
        XCTAssertNotNil(
            SidebarMotionPolicy.animation(reduceMotion: false, duration: 0.2)
        )
    }

    func testSidebarUsesReadableWidthAndCompactChildIndent() {
        XCTAssertEqual(SidebarLayout.width, 184)
        XCTAssertGreaterThanOrEqual(SidebarLayout.childIndent, 8)
        XCTAssertLessThanOrEqual(SidebarLayout.childIndent, 10)
        XCTAssertEqual(SidebarLayout.primaryRowHeight, 40)
        XCTAssertEqual(SidebarLayout.childRowHeight, 35)
        XCTAssertGreaterThanOrEqual(SidebarLayout.childFontSize, 12.5)
    }

    func testSidebarKeepsRequestedNavigationTitlesComplete() {
        XCTAssertEqual(SidebarLayout.title(for: .dashboard), "实时监控")
        XCTAssertEqual(SidebarLayout.title(for: .optimizer), "启动优化")
        XCTAssertEqual(SidebarLayout.title(for: .uninstaller), "应用管理")
        XCTAssertEqual(SidebarLayout.title(for: .inputDevices), "键盘鼠标")
    }

    func testCurrentChildDestinationExpandsItsGroupOnFirstRender() {
        XCTAssertTrue(
            SidebarLayout.shouldExpand(
                current: .uninstaller,
                destinations: [.optimizer, .uninstaller]
            )
        )
        XCTAssertTrue(
            SidebarLayout.shouldExpand(
                current: .inputDevices,
                destinations: [.storage, .graphics, .inputDevices, .cooling]
            )
        )
        XCTAssertFalse(
            SidebarLayout.shouldExpand(
                current: .dashboard,
                destinations: [.optimizer, .uninstaller]
            )
        )
    }

    func testSingleInstanceGuardAllowsOnlyOneOwnerForTheSameLockFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TraceHaloSingleInstanceGuardTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let lockFile = directory.appendingPathComponent("instance.lock")

        var primary: TraceHaloSingleInstanceGuard? = TraceHaloSingleInstanceGuard(
            lockFileURL: lockFile
        )
        XCTAssertEqual(primary?.acquisition, .primary)

        let duplicate = TraceHaloSingleInstanceGuard(lockFileURL: lockFile)
        XCTAssertEqual(duplicate.acquisition, .secondary)

        primary = nil
        let replacement = TraceHaloSingleInstanceGuard(lockFileURL: lockFile)
        XCTAssertEqual(replacement.acquisition, .primary)
    }

    func testSingleInstanceGuardDoesNotTreatAPermissionErrorAsAnotherInstance() throws {
        guard geteuid() != 0 else { throw XCTSkip("Root bypasses file mode permission checks") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TraceHaloLockPermissions-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockFile = directory.appendingPathComponent("instance.lock")
        XCTAssertTrue(FileManager.default.createFile(atPath: lockFile.path, contents: Data()))
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: lockFile.path)
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: lockFile.path)

        let denied = TraceHaloSingleInstanceGuard(lockFileURL: lockFile)

        XCTAssertEqual(denied.acquisition, .unavailable)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: lockFile.path)
        let restored = TraceHaloSingleInstanceGuard(lockFileURL: lockFile)
        XCTAssertEqual(restored.acquisition, .primary)
        withExtendedLifetime(restored) {
            XCTAssertEqual(TraceHaloSingleInstanceGuard(lockFileURL: lockFile).acquisition, .secondary)
        }
    }

    func testSingleInstanceGuardDoesNotTreatAnInvalidLockDirectoryAsAnotherInstance() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TraceHaloLockPath-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let regularFile = directory.appendingPathComponent("not-a-directory")
        XCTAssertTrue(FileManager.default.createFile(atPath: regularFile.path, contents: Data()))

        let guardResult = TraceHaloSingleInstanceGuard(lockFileURL: regularFile.appendingPathComponent("instance.lock"))

        XCTAssertEqual(guardResult.acquisition, .unavailable)
    }

    func testEveryAppBundleInfoPlistProhibitsMultipleInstances() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plistURLs = [
            packageRoot.appendingPathComponent("Resources/Info.plist"),
            packageRoot.appendingPathComponent("Xcode/TraceHalo/Info.plist"),
        ]

        for plistURL in plistURLs {
            let data = try Data(contentsOf: plistURL)
            let plist = try XCTUnwrap(
                PropertyListSerialization.propertyList(
                    from: data,
                    format: nil
                ) as? [String: Any]
            )
            XCTAssertEqual(
                plist["LSMultipleInstancesProhibited"] as? Bool,
                true,
                plistURL.path
            )
        }
    }

    func testEveryAppBundleInfoPlistDeclaresTheBetaReleaseMetadata() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let expectations: [(URL, String, String, String)] = [
            (
                packageRoot.appendingPathComponent("Resources/Info.plist"),
                "0.2.2",
                "46",
                "Beta"
            ),
            (
                packageRoot.appendingPathComponent("Xcode/TraceHalo/Info.plist"),
                "$(MARKETING_VERSION)",
                "$(CURRENT_PROJECT_VERSION)",
                "$(TRACEHALO_RELEASE_CHANNEL)"
            ),
        ]

        for (plistURL, version, build, releaseChannel) in expectations {
            let data = try Data(contentsOf: plistURL)
            let plist = try XCTUnwrap(
                PropertyListSerialization.propertyList(
                    from: data,
                    format: nil
                ) as? [String: Any]
            )
            XCTAssertEqual(
                plist["CFBundleShortVersionString"] as? String,
                version,
                plistURL.path
            )
            XCTAssertEqual(
                plist["CFBundleVersion"] as? String,
                build,
                plistURL.path
            )
            XCTAssertEqual(
                plist["TraceHaloReleaseChannel"] as? String,
                releaseChannel,
                plistURL.path
            )
        }
    }
}

@MainActor
private final class WindowZoomActionProbe: NSObject {
    private(set) var invocationCount = 0

    @objc
    func invoke(_ sender: Any?) {
        invocationCount += 1
    }
}

private final class ThreadSafeInvalidationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.withLock { storedValue }
    }

    func increment() {
        lock.withLock { storedValue += 1 }
    }
}
