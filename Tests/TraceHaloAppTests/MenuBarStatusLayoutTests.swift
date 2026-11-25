import AppKit
import SwiftUI
import XCTest
@testable import TraceHaloApp
import TraceHaloCore

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

    @MainActor
    func testCPUChartHeightRepresentsAbsoluteUsagePercent() async throws {
        for percentage in [0.0, 11.0, 81.0] {
            let fraction = try await renderedCPUChartFraction(history: [percentage])
            XCTAssertEqual(
                fraction,
                percentage / 100,
                accuracy: 0.015,
                "CPU \(percentage)% must occupy its corresponding fraction of the chart height"
            )
        }
    }

    @MainActor
    func testCPUChartKeepsSameHeightWhenHistoricalPeakChanges() async throws {
        let lowOnly = try await renderedCPUChartFraction(history: [11])
        let afterPeak = try await renderedCPUChartFraction(
            history: [81] + Array(repeating: 11, count: 27)
        )

        XCTAssertEqual(lowOnly, afterPeak, accuracy: 0.015)
        XCTAssertEqual(afterPeak, 0.11, accuracy: 0.015)
    }

    @MainActor
    private func renderedCPUChartFraction(history: [Double]) async throws -> Double {
        let first = try XCTUnwrap(history.first)
        let values = Array(repeating: first, count: max(32 - history.count, 0)) + history
        let snapshots = values.map { percentage in
            var snapshot = SystemSnapshot.fixture
            snapshot.cpu.totalPercent = percentage
            snapshot.cpu.userPercent = percentage
            snapshot.cpu.systemPercent = 0
            return snapshot
        }
        let model = AppModel(metricsProvider: SequencedMetricsProvider(snapshots: snapshots))
        model.monitorConfiguration = .standard
        model.monitorConfiguration.showsStatusBarIcon = false
        model.monitorConfiguration.statusBarComponents = [
            MonitorStatusBarComponent(style: .miniChart, metric: .cpuTotal, title: "CPU")
        ]
        for _ in snapshots {
            await model.refreshAll()
        }

        // Magnify the normal status-strip view so the original 15-point chart
        // can distinguish a true zero baseline from a minimum-height floor.
        let magnification: CGFloat = 4
        let width = MenuBarStatusLayout.estimatedContentWidth(for: model.monitorConfiguration)
        let size = CGSize(width: width * magnification, height: 22 * magnification)
        let hostingView = NSHostingView(
            rootView: MenuBarStatusStrip()
                .environment(model)
                .environment(\.colorScheme, .light)
                .scaleEffect(magnification, anchor: .topLeading)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .background(Color.white)
        )
        hostingView.frame = NSRect(origin: .zero, size: size)
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
        await InMemoryHostingRenderer.settleUI(hostingView)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            data: InMemoryHostingRenderer.bitmapData(for: hostingView)
        ))
        let pixelsPerPoint = Double(bitmap.pixelsHigh) / 22

        // Sample an interior column where the final low samples are flat.
        // The chart occupies y=3.5...18.5 in the original 22-point strip.
        let x = Int(45 * pixelsPerPoint)
        var weightedY = 0.0
        var weight = 0.0
        for y in Int(3 * pixelsPerPoint)..<Int(19 * pixelsPerPoint) {
            let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
            let luminance = (color.redComponent + color.greenComponent + color.blueComponent) / 3
            if luminance < 0.25 {
                let darkness = 1 - luminance
                weightedY += (Double(y) + 0.5) * darkness
                weight += darkness
            }
        }
        if weight == 0 {
            // A zero-height area can clip its baseline stroke at the Canvas edge.
            XCTAssertEqual(history.last, 0, "A nonzero CPU value must produce a visible curve")
            return 0
        }
        return (18.5 - weightedY / max(weight, 1) / pixelsPerPoint) / 15
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
