import AppKit
import SwiftUI
import TraceHaloCore
import XCTest
@testable import TraceHaloApp

final class MenuBarOverviewLayoutTests: XCTestCase {
    func testDashboardReferenceDimensionsMatchCollapsedAndExpandedPopoverWidths() {
        XCTAssertEqual(MenuBarDashboardLayout.collapsedContentWidth, 282)
        XCTAssertEqual(MenuBarDashboardLayout.expandedContentWidth, 552)
        XCTAssertEqual(
            MenuBarDashboardLayout.primaryColumnWidth
                + (MenuBarDashboardLayout.horizontalChrome * 2),
            MenuBarDashboardLayout.collapsedContentWidth
        )
        XCTAssertEqual(
            MenuBarDashboardLayout.expandedDashboardWidth
                + (MenuBarDashboardLayout.horizontalChrome * 2),
            MenuBarDashboardLayout.expandedContentWidth
        )
    }

    func testDashboardMaximumRenderedHeightIsExactly787Points() {
        XCTAssertEqual(MenuBarDashboardLayout.maximumColumnHeight, 767)
        XCTAssertEqual(
            MenuBarDashboardLayout.maximumColumnHeight
                + (MenuBarDashboardLayout.verticalChrome * 2),
            787
        )
    }

    func testQuickActionsFollowReferenceOrderAndSkipConsole() {
        let items = [
            quickItem(.console),
            quickItem(.systemSettings),
            quickItem(.terminal),
            quickItem(.activityMonitor),
            quickItem(.systemInformation),
            quickItem(.traceHalo)
        ]

        XCTAssertEqual(
            MenuBarQuickActionLayout.visibleItems(from: items).map(\.action),
            [
                .activityMonitor,
                .traceHalo,
                .terminal,
                .systemInformation,
                .systemSettings
            ]
        )
    }

    func testRecencyLabelUsesCompactChineseIntervals() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertEqual(MenuBarRecencyLabel.text(capturedAt: now, now: now), "刚刚")
        XCTAssertEqual(
            MenuBarRecencyLabel.text(capturedAt: now.addingTimeInterval(-59), now: now),
            "刚刚"
        )
        XCTAssertEqual(
            MenuBarRecencyLabel.text(capturedAt: now.addingTimeInterval(-60), now: now),
            "1 分钟前"
        )
        XCTAssertEqual(
            MenuBarRecencyLabel.text(capturedAt: now.addingTimeInterval(-3_599), now: now),
            "59 分钟前"
        )
        XCTAssertEqual(
            MenuBarRecencyLabel.text(capturedAt: now.addingTimeInterval(-3_600), now: now),
            "1 小时前"
        )
        XCTAssertEqual(
            MenuBarRecencyLabel.text(capturedAt: now.addingTimeInterval(30), now: now),
            "刚刚"
        )
    }

    @MainActor
    func testCollapsedOverviewRendersNonemptyBitmapWithin282Points() async throws {
        let model = AppModel()
        model.monitorConfiguration = .standard
        let router = AppNavigationRouter(destination: .dashboard)
        let hostingView = NSHostingView(
            rootView: MenuBarDashboardView(
                maximumColumnHeightOverride: MenuBarDashboardLayout.maximumColumnHeight
            )
            .environment(model)
            .environment(router)
            .preferredColorScheme(.dark)
        )

        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize

        XCTAssertEqual(
            fittingSize.width,
            MenuBarDashboardLayout.collapsedContentWidth,
            accuracy: 0.5
        )
        XCTAssertEqual(fittingSize.height, 787)

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

        await InMemoryHostingRenderer.settleUI(hostingView)

        let bitmap = try InMemoryHostingRenderer.bitmapData(for: hostingView)
        XCTAssertFalse(bitmap.isEmpty)
    }

    private func quickItem(_ action: MonitorQuickAction) -> MonitorQuickItem {
        MonitorQuickItem(
            action: action,
            title: action.rawValue,
            systemImage: "square"
        )
    }
}
