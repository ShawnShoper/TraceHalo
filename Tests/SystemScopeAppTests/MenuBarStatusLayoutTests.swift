import AppKit
import SwiftUI
import XCTest
@testable import SystemScopeApp
import SystemScopeCore

final class MenuBarStatusLayoutTests: XCTestCase {
    func testSenseiDefaultLayoutUsesFullVariableWidth() {
        XCTAssertEqual(
            MenuBarStatusLayout.estimatedStatusItemWidth(for: .standard),
            226
        )
    }

    func testCompactAndIconOnlyModesUseExpectedWidths() {
        var configuration = MonitorConfiguration.standard
        configuration.statusBarLayoutMode = .compact
        XCTAssertEqual(
            MenuBarStatusLayout.estimatedStatusItemWidth(for: configuration),
            54
        )

        configuration.statusBarLayoutMode = .iconOnly
        XCTAssertEqual(
            MenuBarStatusLayout.estimatedStatusItemWidth(for: configuration),
            24
        )
    }

    func testAllHiddenComponentsFallBackToClickableIconWidth() {
        var configuration = MonitorConfiguration.standard
        for index in configuration.statusBarComponents.indices {
            configuration.statusBarComponents[index].isVisible = false
        }

        XCTAssertTrue(MenuBarStatusLayout.showsStatusIcon(in: configuration))
        XCTAssertEqual(
            MenuBarStatusLayout.estimatedStatusItemWidth(for: configuration),
            24
        )
    }

    func testAddingStatusIconExpandsInsteadOfClippingContent() {
        var configuration = MonitorConfiguration.standard
        let withoutIcon = MenuBarStatusLayout.estimatedStatusItemWidth(for: configuration)
        configuration.showsStatusBarIcon = true

        XCTAssertEqual(
            MenuBarStatusLayout.estimatedStatusItemWidth(for: configuration),
            withoutIcon + 22
        )
    }

    func testReorderingKeepsWidthAndChangesDisplayOrder() {
        var configuration = MonitorConfiguration.standard
        let originalWidth = MenuBarStatusLayout.estimatedStatusItemWidth(for: configuration)
        configuration.statusBarComponents.swapAt(0, 3)

        XCTAssertEqual(
            MenuBarStatusLayout.estimatedStatusItemWidth(for: configuration),
            originalWidth
        )
        XCTAssertEqual(
            MenuBarStatusLayout.displayedComponents(in: configuration).first?.metric,
            .temperature
        )
    }

    @MainActor
    func testStatusStripRedrawsFromSharedModelWithoutChangingWidth() async throws {
        var lowSnapshot = SystemSnapshot.fixture
        lowSnapshot.cpu.totalPercent = 12
        lowSnapshot.cpu.userPercent = 7
        lowSnapshot.cpu.systemPercent = 5
        lowSnapshot.memory.pressurePercent = 21
        lowSnapshot.cpu.temperatureCelsius = 43

        var highSnapshot = lowSnapshot
        highSnapshot.cpu.totalPercent = 81
        highSnapshot.cpu.userPercent = 63
        highSnapshot.cpu.systemPercent = 18
        highSnapshot.memory.pressurePercent = 72
        highSnapshot.cpu.temperatureCelsius = 78

        let provider = SequencedMetricsProvider(snapshots: [lowSnapshot, highSnapshot])
        let model = AppModel(metricsProvider: provider)
        model.monitorConfiguration = .standard

        let hostingView = NSHostingView(
            rootView: MenuBarStatusStrip()
                .environment(model)
        )
        let expectedWidth = MenuBarStatusLayout.estimatedContentWidth(
            for: model.monitorConfiguration
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: expectedWidth, height: 22)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.orderOut(nil)
        defer {
            window.contentView = nil
            window.close()
        }

        await model.refreshAll()
        await InMemoryHostingRenderer.settleUI(hostingView)
        let firstWidth = hostingView.fittingSize.width
        let firstImage = try InMemoryHostingRenderer.bitmapData(for: hostingView)

        await model.refreshAll()
        await InMemoryHostingRenderer.settleUI(hostingView)
        let secondWidth = hostingView.fittingSize.width
        let secondImage = try InMemoryHostingRenderer.bitmapData(for: hostingView)

        XCTAssertEqual(firstWidth, secondWidth, accuracy: 0.5)
        XCTAssertNotEqual(firstImage, secondImage)
        XCTAssertEqual(model.snapshot.cpu.totalPercent, 81)
        XCTAssertEqual(model.snapshot.memory.pressurePercent, 72)
        XCTAssertEqual(model.snapshot.cpu.temperatureCelsius, 78)
    }
}

private actor SequencedMetricsProvider: SystemMetricsProviding {
    private let snapshots: [SystemSnapshot]
    private var index = 0

    init(snapshots: [SystemSnapshot]) {
        self.snapshots = snapshots
    }

    func snapshot() async -> SystemSnapshot {
        guard !snapshots.isEmpty else { return .fixture }
        let snapshot = snapshots[min(index, snapshots.count - 1)]
        index += 1
        return snapshot
    }
}
