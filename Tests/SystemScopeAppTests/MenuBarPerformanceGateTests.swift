import AppKit
import SwiftUI
import XCTest
@testable import SystemScopeApp
import SystemScopeCore

final class MenuBarPerformanceGateTests: XCTestCase {
    func testIdenticalPopoverHeightDoesNotRequestAChange() {
        let layout = MenuBarPopoverSizingPolicy.layout(availableHeight: 900)

        XCTAssertFalse(
            MenuBarPopoverSizingPolicy.needsUpdate(
                current: layout.columnHeight,
                target: layout.columnHeight
            )
        )
        XCTAssertFalse(
            MenuBarPopoverSizingPolicy.needsUpdate(
                current: layout.contentSize,
                target: layout.contentSize
            )
        )
    }

    func testRepeatedPreferredSizeDuringOneOpeningRequiresAtMostOneMutation() {
        let layout = MenuBarPopoverSizingPolicy.layout(availableHeight: 900)
        let preferredSizes: [CGFloat] = [
            MenuBarPopoverSizingPolicy.expandedContentWidth,
            MenuBarPopoverSizingPolicy.expandedContentWidth,
            MenuBarPopoverSizingPolicy.expandedContentWidth - 0.25,
            MenuBarPopoverSizingPolicy.expandedContentWidth
        ]
        var currentSize = layout.contentSize
        var mutationCount = 0

        for preferredWidth in preferredSizes {
            let targetSize = MenuBarPopoverSizingPolicy.contentSize(
                preferredWidth: preferredWidth,
                columnHeight: layout.columnHeight
            )
            guard MenuBarPopoverSizingPolicy.needsUpdate(
                current: currentSize,
                target: targetSize
            ) else { continue }
            currentSize = targetSize
            mutationCount += 1
        }

        XCTAssertEqual(currentSize.width, MenuBarPopoverSizingPolicy.expandedContentWidth)
        XCTAssertLessThanOrEqual(mutationCount, 1)
    }

    func testPopoverPreferredWidthSnapsToCollapsedOrExpandedState() {
        let collapsed = MenuBarPopoverSizingPolicy.collapsedContentWidth
        let expanded = MenuBarPopoverSizingPolicy.expandedContentWidth
        let threshold = (collapsed + expanded) / 2

        XCTAssertEqual(
            MenuBarPopoverSizingPolicy.normalizedContentWidth(preferredWidth: collapsed - 20),
            collapsed
        )
        XCTAssertEqual(
            MenuBarPopoverSizingPolicy.normalizedContentWidth(preferredWidth: threshold - 0.01),
            collapsed
        )
        XCTAssertEqual(
            MenuBarPopoverSizingPolicy.normalizedContentWidth(preferredWidth: threshold),
            expanded
        )
        XCTAssertEqual(
            MenuBarPopoverSizingPolicy.normalizedContentWidth(preferredWidth: expanded + 20),
            expanded
        )
        XCTAssertEqual(
            MenuBarPopoverSizingPolicy.normalizedContentWidth(preferredWidth: .nan),
            collapsed
        )
    }

    func testPopoverPresentationRetainsMountedDashboardAcrossOrdinaryDismissal() {
        var presentation = MenuBarPopoverPresentation()

        XCTAssertFalse(presentation.isPresented)
        XCTAssertFalse(presentation.shouldMountDashboard)
        XCTAssertEqual(presentation.presentationID, 0)

        XCTAssertTrue(presentation.present())
        XCTAssertTrue(presentation.shouldMountDashboard)
        XCTAssertEqual(presentation.presentationID, 1)
        XCTAssertFalse(presentation.present(), "已打开时重复点击不能重复挂载完整 Dashboard")
        XCTAssertEqual(presentation.presentationID, 1)

        XCTAssertTrue(presentation.dismiss())
        XCTAssertFalse(presentation.isPresented)
        XCTAssertTrue(
            presentation.shouldMountDashboard,
            "普通关闭后应保留已经挂载的 Dashboard 树供下次复用"
        )
        XCTAssertFalse(presentation.dismiss(), "隐藏态重复关闭必须无副作用")

        XCTAssertTrue(presentation.present())
        XCTAssertEqual(presentation.presentationID, 2)
    }

    func testStatusItemOpensOnMouseDownWithoutWaitingForMouseUp() {
        XCTAssertTrue(MenuBarStatusInteractionPolicy.actionEventMask.contains(.leftMouseDown))
        XCTAssertFalse(MenuBarStatusInteractionPolicy.actionEventMask.contains(.leftMouseUp))
    }

    @MainActor
    func testUnstartedControllerHasNoHiddenDashboardMounted() {
        let controller = MenuBarStatusItemController(
            model: AppModel(),
            navigationRouter: AppNavigationRouter(destination: .dashboard)
        )

        let snapshot = controller.performanceSnapshot
        XCTAssertFalse(snapshot.isPresented)
        XCTAssertFalse(snapshot.isDashboardMounted)
        XCTAssertEqual(snapshot.presentationCount, 0)
        XCTAssertEqual(snapshot.totalContentSizeChangeCount, 0)
    }

    @MainActor
    func testRepeatedWarmPopoverReopenKeepsHostingGeometryStable() async throws {
        let model = AppModel()
        model.monitorConfiguration = .standard
        model.showMenuBarSummary = true
        let anchorButton = NSButton(frame: NSRect(x: 0, y: 0, width: 32, height: 22))
        let anchorWindow = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 32, height: 22),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        anchorWindow.isReleasedWhenClosed = false
        anchorWindow.contentView = anchorButton
        anchorWindow.orderFront(nil)
        let controller = MenuBarStatusItemController(
            model: model,
            navigationRouter: AppNavigationRouter(destination: .dashboard),
            popoverAnchorOverride: anchorButton
        )

        controller.start()
        defer {
            controller.closePopover()
            controller.stop()
            anchorWindow.orderOut(nil)
            anchorWindow.contentView = nil
            anchorWindow.close()
        }

        XCTAssertTrue(controller.showPopover(), "首次打开菜单栏弹窗必须成功")
        guard await waitForPopoverPresentation(controller) else { return }
        let baseline = try XCTUnwrap(
            controller.popoverGeometrySnapshot,
            "首次打开后必须已经挂载 Dashboard 宿主视图"
        )
        assertCollapsedPopoverGeometry(baseline, iteration: 0)

        controller.closePopover()
        guard await waitForPopoverDismissal(controller) else { return }

        for iteration in 1...20 {
            XCTAssertTrue(
                controller.showPopover(),
                "第 \(iteration) 次热打开菜单栏弹窗必须成功"
            )
            guard await waitForPopoverPresentation(controller) else { return }

            let geometry = try XCTUnwrap(
                controller.popoverGeometrySnapshot,
                "第 \(iteration) 次热打开必须复用已挂载的 Dashboard"
            )
            assertCollapsedPopoverGeometry(geometry, iteration: iteration)
            assertHorizontalPopoverGeometry(
                geometry,
                matches: baseline,
                iteration: iteration
            )

            controller.closePopover()
            guard await waitForPopoverDismissal(controller) else { return }
        }
    }

    func testProcessIconPrefetchKeyIsStableAcrossProviderOrdering() {
        let cpu = [
            process(id: 30, name: "Gamma"),
            process(id: 10, name: "Alpha"),
            process(id: 20, name: "Beta")
        ]
        let memory = [
            process(id: 40, name: "Delta"),
            process(id: 20, name: "Beta")
        ]

        let first = MenuBarIconPrefetchKey.processIdentities(
            cpuProcesses: cpu,
            memoryProcesses: memory
        )
        let reordered = MenuBarIconPrefetchKey.processIdentities(
            cpuProcesses: Array(cpu.reversed()),
            memoryProcesses: Array(memory.reversed())
        )

        XCTAssertEqual(first, reordered)
        XCTAssertEqual(
            first,
            [
                MenuBarProcessIconIdentity(processID: 10, name: "Alpha"),
                MenuBarProcessIconIdentity(processID: 20, name: "Beta"),
                MenuBarProcessIconIdentity(processID: 30, name: "Gamma"),
                MenuBarProcessIconIdentity(processID: 40, name: "Delta")
            ]
        )
    }

    func testProcessIconPrefetchKeyChangesWhenPIDNameChanges() {
        let original = MenuBarIconPrefetchKey.processIdentities(
            cpuProcesses: [process(id: 42, name: "Original")],
            memoryProcesses: []
        )
        let renamed = MenuBarIconPrefetchKey.processIdentities(
            cpuProcesses: [process(id: 42, name: "Replacement")],
            memoryProcesses: []
        )

        XCTAssertNotEqual(original, renamed)
    }

    func testQuickActionIconPrefetchKeyIgnoresPresentationTextAndOrdering() {
        let items = [
            quickItem(.terminal, title: "Terminal"),
            quickItem(.activityMonitor, title: "Activity Monitor"),
            quickItem(.systemSettings, title: "Settings")
        ]
        let presentationChanged = [
            quickItem(.systemSettings, title: "系统设置", systemImage: "gearshape"),
            quickItem(.terminal, title: "终端", systemImage: "apple.terminal"),
            quickItem(.activityMonitor, title: "活动监视器", systemImage: "waveform.path.ecg")
        ]

        XCTAssertEqual(
            MenuBarIconPrefetchKey.quickActions(items: items),
            MenuBarIconPrefetchKey.quickActions(items: presentationChanged)
        )
    }

    func testQuickActionIconPrefetchKeyChangesWithVisibleConfiguration() {
        let visibleItems = [
            quickItem(.terminal),
            quickItem(.systemSettings)
        ]
        let terminalHidden = [
            quickItem(.terminal, isVisible: false),
            quickItem(.systemSettings)
        ]

        XCTAssertNotEqual(
            MenuBarIconPrefetchKey.quickActions(items: visibleItems),
            MenuBarIconPrefetchKey.quickActions(items: terminalHidden)
        )
    }

    @MainActor
    func testColdAndWarmDashboardRenderingStayInMemoryAndRecordTiming() throws {
        let model = AppModel()
        model.monitorConfiguration = .standard
        let router = AppNavigationRouter(destination: .dashboard)

        let coldStart = DispatchTime.now().uptimeNanoseconds
        let hostingView = NSHostingView(
            rootView: MenuBarDashboardView(maximumColumnHeightOverride: 640)
                .environment(model)
                .environment(router)
                .preferredColorScheme(.dark)
        )
        hostingView.layoutSubtreeIfNeeded()

        let fittingSize = hostingView.fittingSize
        let frame = NSRect(origin: .zero, size: fittingSize)
        hostingView.frame = frame
        let window = NSWindow(
            contentRect: frame,
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

        hostingView.layoutSubtreeIfNeeded()
        let coldFrame = try InMemoryHostingRenderer.bitmapData(for: hostingView)
        let coldElapsed = DispatchTime.now().uptimeNanoseconds - coldStart

        let warmStart = DispatchTime.now().uptimeNanoseconds
        hostingView.layoutSubtreeIfNeeded()
        let warmFrame = try InMemoryHostingRenderer.bitmapData(for: hostingView)
        let warmElapsed = DispatchTime.now().uptimeNanoseconds - warmStart

        XCTAssertFalse(coldFrame.isEmpty)
        XCTAssertFalse(warmFrame.isEmpty)
        XCTAssertGreaterThanOrEqual(fittingSize.width, 280)
        XCTAssertGreaterThanOrEqual(fittingSize.height, 430)
        XCTAssertLessThan(
            milliseconds(coldElapsed),
            500,
            "菜单栏 Dashboard 冷渲染应保持在交互响应预算内"
        )
        XCTAssertLessThan(
            milliseconds(warmElapsed),
            250,
            "菜单栏 Dashboard 热渲染应保持在即时响应预算内"
        )

        let timing = String(
            format: "cold=%.2f ms, warm=%.2f ms, size=%.0fx%.0f",
            milliseconds(coldElapsed),
            milliseconds(warmElapsed),
            fittingSize.width,
            fittingSize.height
        )
        let attachment = XCTAttachment(string: timing)
        attachment.name = "Menu bar in-memory render timing"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("TRACEHALO_MENU_RENDER \(timing)")
    }

    @MainActor
    func testRepeatedWarmRenderingKeepsDashboardSizeStableWithinOnePoint() throws {
        let model = AppModel()
        model.monitorConfiguration = .standard
        let router = AppNavigationRouter(destination: .dashboard)
        let hostingView = NSHostingView(
            rootView: MenuBarDashboardView(maximumColumnHeightOverride: 640)
                .environment(model)
                .environment(router)
                .preferredColorScheme(.dark)
        )

        hostingView.layoutSubtreeIfNeeded()
        let initialSize = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: initialSize)
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

        var measuredSizes: [CGSize] = []
        for _ in 0..<3 {
            hostingView.layoutSubtreeIfNeeded()
            _ = try InMemoryHostingRenderer.bitmapData(for: hostingView)
            measuredSizes.append(hostingView.fittingSize)
        }

        for size in measuredSizes {
            XCTAssertEqual(size.width, initialSize.width, accuracy: 1)
            XCTAssertEqual(size.height, initialSize.height, accuracy: 1)
        }
    }

    @MainActor
    func testFreshDashboardFallbackConstructionStaysWithinPopoverBudget() throws {
        let model = AppModel()
        model.monitorConfiguration = .standard
        let router = AppNavigationRouter(destination: .dashboard)

        _ = try renderFreshDashboard(model: model, router: router)
        let samples = try (0..<3).map { _ in
            try renderFreshDashboard(model: model, router: router)
        }
        let elapsedMilliseconds = samples.map { milliseconds($0.elapsedNanoseconds) }

        XCTAssertTrue(samples.allSatisfy { !$0.frame.isEmpty })
        XCTAssertLessThan(
            elapsedMilliseconds.max() ?? .infinity,
            250,
            "仅在控制器重启等必要场景重建 Dashboard 时仍应满足响应预算"
        )
        print(
            "TRACEHALO_MENU_FRESH_CONSTRUCTION "
                + elapsedMilliseconds.map { String(format: "%.2f ms", $0) }.joined(separator: ", ")
        )
    }

    @MainActor
    func testEveryExpandedModuleBuildsWithinWarmInteractiveBudget() throws {
        let model = AppModel()
        model.monitorConfiguration = .standard
        let router = AppNavigationRouter(destination: .dashboard)

        // Absorb one-time SwiftUI, font, and image subsystem initialization.
        // Real module switches happen in the already-mounted warm popover.
        _ = try renderFreshDashboard(model: model, router: router)

        let measurements = try MenuBarDashboardSection.referenceOrder.map { section in
            let sample = try renderFreshDashboard(
                model: model,
                router: router,
                initialSection: section
            )
            return (section, milliseconds(sample.elapsedNanoseconds))
        }
        let slowest = measurements.max { $0.1 < $1.1 }

        XCTAssertLessThan(
            slowest?.1 ?? .infinity,
            160,
            "即使采用比真实热切换更严格的完整宿主重建，每个模块也应保持在热交互预算内"
        )
        let timingSummary = measurements.map { measurement in
            let formatted = String(format: "%.2f", measurement.1)
            return "\(measurement.0.rawValue)=\(formatted)ms"
        }
        print(
            "TRACEHALO_MENU_MODULE_COLD "
                + timingSummary.joined(separator: ", ")
        )
    }

    @MainActor
    func testMountedDashboardSwitchesEveryModuleWithoutAStagedDelay() throws {
        let model = AppModel()
        model.monitorConfiguration = .standard
        let router = AppNavigationRouter(destination: .dashboard)
        let selectionController = MenuBarPerformanceSelectionController(section: .cpu)
        let hostingView = NSHostingView(
            rootView: MenuBarPerformanceSelectionHarness(
                model: model,
                router: router,
                selectionController: selectionController
            )
        )
        hostingView.layoutSubtreeIfNeeded()
        hostingView.frame = NSRect(origin: .zero, size: hostingView.fittingSize)
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

        var previousFrame = try InMemoryHostingRenderer.bitmapData(for: hostingView)
        var timings: [(MenuBarDashboardSection, Double)] = []
        for section in MenuBarDashboardSection.referenceOrder.dropFirst() {
            let startedAt = DispatchTime.now().uptimeNanoseconds
            selectionController.section = section
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
            hostingView.layoutSubtreeIfNeeded()
            let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
            timings.append((section, milliseconds(elapsed)))
            let currentFrame = try InMemoryHostingRenderer.bitmapData(for: hostingView)
            XCTAssertNotEqual(currentFrame, previousFrame)
            previousFrame = currentFrame
        }

        let slowest = timings.map(\.1).max() ?? .infinity
        XCTAssertLessThan(
            slowest,
            50,
            "已挂载菜单的模块布局切换应在 50ms 内完成，且不得包含固定等待"
        )
        let timingSummary = timings.map { measurement in
            let formatted = String(format: "%.2f", measurement.1)
            return "\(measurement.0.rawValue)=\(formatted)ms"
        }
        print("TRACEHALO_MENU_MODULE_WARM " + timingSummary.joined(separator: ", "))
    }

    private func milliseconds(_ nanoseconds: UInt64) -> Double {
        Double(nanoseconds) / 1_000_000
    }

    @MainActor
    private func waitForPopoverPresentation(
        _ controller: MenuBarStatusItemController,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> Bool {
        for _ in 0..<100 {
            if controller.performanceSnapshot.isPresented,
               controller.popoverGeometrySnapshot?.hostingFrameInWindow != nil {
                return true
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("菜单栏弹窗未在 500ms 内完成展示", file: file, line: line)
        return false
    }

    @MainActor
    private func waitForPopoverDismissal(
        _ controller: MenuBarStatusItemController,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> Bool {
        for _ in 0..<100 {
            if !controller.performanceSnapshot.isPresented {
                return true
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("菜单栏弹窗未在 500ms 内完成关闭", file: file, line: line)
        return false
    }

    private func assertCollapsedPopoverGeometry(
        _ geometry: MenuBarPopoverGeometrySnapshot,
        iteration: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectedWidth = MenuBarDashboardLayout.collapsedContentWidth
        XCTAssertEqual(
            geometry.popoverContentSize.width,
            expectedWidth,
            accuracy: 0.5,
            "第 \(iteration) 次打开后 popover 宽度不再是 282pt",
            file: file,
            line: line
        )
        XCTAssertEqual(
            geometry.hostingFrame.width,
            expectedWidth,
            accuracy: 0.5,
            "第 \(iteration) 次打开后 Dashboard 宿主宽度被压缩",
            file: file,
            line: line
        )
        XCTAssertEqual(
            geometry.hostingBounds.width,
            expectedWidth,
            accuracy: 0.5,
            "第 \(iteration) 次打开后 Dashboard bounds 宽度被压缩",
            file: file,
            line: line
        )
    }

    private func assertHorizontalPopoverGeometry(
        _ geometry: MenuBarPopoverGeometrySnapshot,
        matches baseline: MenuBarPopoverGeometrySnapshot,
        iteration: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            geometry.hostingFrame.origin.x,
            baseline.hostingFrame.origin.x,
            accuracy: 1,
            "第 \(iteration) 次热打开后宿主横向位置发生漂移",
            file: file,
            line: line
        )
        XCTAssertEqual(
            geometry.hostingBounds.origin.x,
            baseline.hostingBounds.origin.x,
            accuracy: 1,
            "第 \(iteration) 次热打开后宿主 bounds 横向位置发生漂移",
            file: file,
            line: line
        )
        guard let currentFrame = geometry.hostingFrameInWindow,
              let currentLayout = geometry.windowContentLayoutRect,
              let baselineFrame = baseline.hostingFrameInWindow,
              let baselineLayout = baseline.windowContentLayoutRect
        else {
            XCTFail("第 \(iteration) 次热打开缺少窗口几何数据", file: file, line: line)
            return
        }
        XCTAssertEqual(
            currentFrame.minX - currentLayout.minX,
            baselineFrame.minX - baselineLayout.minX,
            accuracy: 1,
            "第 \(iteration) 次热打开后内容相对弹窗外壳的左边距发生漂移",
            file: file,
            line: line
        )
    }

    @MainActor
    private func renderFreshDashboard(
        model: AppModel,
        router: AppNavigationRouter,
        initialSection: MenuBarDashboardSection? = nil
    ) throws -> (elapsedNanoseconds: UInt64, frame: Data) {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let hostingView = NSHostingView(
            rootView: MenuBarDashboardView(
                initialSection: initialSection,
                maximumColumnHeightOverride: 640
            )
                .environment(model)
                .environment(router)
                .preferredColorScheme(.dark)
        )
        hostingView.layoutSubtreeIfNeeded()
        hostingView.frame = NSRect(origin: .zero, size: hostingView.fittingSize)
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

        hostingView.layoutSubtreeIfNeeded()
        let frame = try InMemoryHostingRenderer.bitmapData(for: hostingView)
        return (DispatchTime.now().uptimeNanoseconds - startedAt, frame)
    }

    private func process(id: Int32, name: String) -> ProcessUsage {
        ProcessUsage(
            id: id,
            name: name,
            cpuPercent: 0,
            memoryBytes: 0
        )
    }

    private func quickItem(
        _ action: MonitorQuickAction,
        title: String = "Item",
        systemImage: String = "square",
        isVisible: Bool = true
    ) -> MonitorQuickItem {
        MonitorQuickItem(
            action: action,
            title: title,
            systemImage: systemImage,
            isVisible: isVisible
        )
    }
}

@MainActor
private final class MenuBarPerformanceSelectionController: ObservableObject {
    @Published var section: MenuBarDashboardSection

    init(section: MenuBarDashboardSection) {
        self.section = section
    }
}

private struct MenuBarPerformanceSelectionHarness: View {
    let model: AppModel
    let router: AppNavigationRouter
    @ObservedObject var selectionController: MenuBarPerformanceSelectionController

    var body: some View {
        MenuBarDashboardView(
            initialSection: selectionController.section,
            maximumColumnHeightOverride: 640,
            showsQuickLaunchFooter: false,
            resetsSelectionOnPopoverClose: false,
            presentationMode: .embeddedPreview
        )
        .environment(model)
        .environment(router)
        .preferredColorScheme(.dark)
    }
}
