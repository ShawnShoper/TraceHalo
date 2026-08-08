import AppKit
import SwiftUI
import XCTest
@testable import SystemScopeApp

final class MenuBarDashboardRenderingTests: XCTestCase {
    @MainActor
    func testEveryDashboardSectionRendersExpandedDetailInMemory() async throws {
        var detailImages: [MenuBarDashboardSection: Data] = [:]

        for section in MenuBarDashboardSection.referenceOrder {
            let (fittingSize, imageData, detailImageData) = try await render(section)
            XCTAssertEqual(
                fittingSize.width,
                MenuBarDashboardLayout.expandedContentWidth,
                accuracy: 0.5,
                "\(section.title) 详情宽度不足：\(fittingSize.width)"
            )
            XCTAssertGreaterThanOrEqual(
                fittingSize.height,
                450,
                "\(section.title) 详情高度不足：\(fittingSize.height)"
            )
            XCTAssertFalse(imageData.isEmpty, "\(section.title) 详情未生成内存位图")
            XCTAssertFalse(detailImageData.isEmpty, "\(section.title) 右侧详情未生成内存位图")
            XCTAssertFalse(
                detailImages.values.contains(detailImageData),
                "\(section.title) 右侧详情与其他监控项完全相同，可能没有切换到对应内容"
            )
            detailImages[section] = detailImageData
        }

        XCTAssertEqual(
            detailImages.count,
            MenuBarDashboardSection.referenceOrder.count,
            "每个菜单栏监控项都必须生成独立的右侧详情"
        )
    }

    @MainActor
    private func render(_ section: MenuBarDashboardSection) async throws -> (CGSize, Data, Data) {
        let model = AppModel()
        model.monitorConfiguration = .standard
        let router = AppNavigationRouter(destination: .dashboard)
        let hostingView = NSHostingView(
            rootView: MenuBarDashboardView(initialSection: section)
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

        await InMemoryHostingRenderer.settleUI(hostingView)

        let detailRect = NSRect(
            x: MenuBarDashboardLayout.horizontalChrome
                + MenuBarDashboardLayout.primaryColumnWidth
                + MenuBarDashboardLayout.columnSpacing,
            y: MenuBarDashboardLayout.verticalChrome,
            width: MenuBarDashboardLayout.detailColumnWidth,
            height: fittingSize.height - (MenuBarDashboardLayout.verticalChrome * 2)
        )
        return (
            fittingSize,
            try InMemoryHostingRenderer.bitmapData(for: hostingView),
            try InMemoryHostingRenderer.bitmapData(for: hostingView, in: detailRect)
        )
    }
}
