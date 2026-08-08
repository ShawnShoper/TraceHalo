import AppKit
import Observation
import XCTest
@testable import SystemScopeApp

final class MainWindowAndSidebarLayoutTests: XCTestCase {
    @MainActor
    func testRepeatedNavigationToTheActivePageDoesNotInvalidateObservers() {
        let router = AppNavigationRouter(destination: .monitor)
        let invalidationCounter = ThreadSafeInvalidationCounter()

        withObservationTracking {
            _ = router.destination
        } onChange: {
            invalidationCounter.increment()
        }

        router.navigate(to: .monitor)

        XCTAssertEqual(invalidationCounter.value, 0)
        XCTAssertEqual(router.destination, .monitor)
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

    func testMainScreenIsUsedWhenWindowHasNotResolvedItsScreenYet() {
        let mainScreenFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)

        XCTAssertEqual(
            MainWindowLayoutPolicy.resolvedVisibleFrame(
                windowScreen: nil,
                mainScreen: mainScreenFrame
            ),
            mainScreenFrame
        )

        let windowScreenFrame = CGRect(x: 1_440, y: 0, width: 1_728, height: 1_080)
        XCTAssertEqual(
            MainWindowLayoutPolicy.resolvedVisibleFrame(
                windowScreen: windowScreenFrame,
                mainScreen: mainScreenFrame
            ),
            windowScreenFrame
        )
    }

    @MainActor
    func testFixedCanvasHasOneNormalWindowSizeAuthority() {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        defer { window.close() }
        window.aspectRatio = CGSize(width: 16, height: 10)

        let target = MainWindowLayoutPolicy.preferredContentSize
        MainWindowLayoutPolicy.applyFixedCanvas(target, to: window)

        XCTAssertEqual(window.contentView?.bounds.size, target)
        XCTAssertEqual(window.contentMinSize, target)
        XCTAssertEqual(window.contentMaxSize, target)
        XCTAssertEqual(window.aspectRatio, .zero)
        XCTAssertFalse(window.styleMask.contains(.resizable))
    }

    @MainActor
    func testFixedCanvasApplicationIsIdempotentAndDisablesNativeResize() {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        defer { window.close() }

        let target = MainWindowLayoutPolicy.compactContentSize
        for _ in 0..<20 {
            MainWindowLayoutPolicy.applyFixedCanvas(target, to: window)
        }

        XCTAssertEqual(window.contentView?.bounds.size, target)
        XCTAssertEqual(window.contentMinSize, target)
        XCTAssertEqual(window.contentMaxSize, target)
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenPrimary))
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
        XCTAssertEqual(SidebarLayout.title(for: .monitor), "实时监控")
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
