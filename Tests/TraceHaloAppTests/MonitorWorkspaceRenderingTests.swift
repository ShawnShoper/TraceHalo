import AppKit
import SwiftUI
import XCTest
@testable import TraceHaloApp

final class MonitorWorkspaceRenderingTests: XCTestCase {
    func testConfigurationTabsNameTheStatusAreaExplicitly() {
        XCTAssertEqual(MonitorConfigurationTab.modules.title, "模块")
        XCTAssertEqual(MonitorConfigurationTab.statusBar.title, "状态区")
        XCTAssertEqual(MonitorConfigurationTab.quickItems.title, "快捷入口")
    }

    func testReferenceContentWidthReproducesConfigurationColumnWidth() {
        let configurationWidth = MonitorWorkspaceLayout.configurationWidth(
            totalWidth: MonitorWorkspaceLayout.referenceContentWidth
        )

        XCTAssertEqual(
            configurationWidth,
            MonitorWorkspaceLayout.preferredConfigurationWidth,
            accuracy: 0.5
        )
        assertSupportedColumnsFit(totalWidth: MonitorWorkspaceLayout.referenceContentWidth)
    }

    func testSupportedMinimumWindowKeepsBothColumnsAboveTheirMinimumWidths() {
        let totalContentWidth: CGFloat = 1_180 - 140
        let configurationWidth = MonitorWorkspaceLayout.configurationWidth(
            totalWidth: totalContentWidth
        )
        let previewWidth = totalContentWidth - configurationWidth - 1

        XCTAssertEqual(configurationWidth, 446, accuracy: 0.5)
        XCTAssertEqual(previewWidth, MonitorWorkspaceLayout.minimumPreviewWidth, accuracy: 0.5)
        assertSupportedColumnsFit(totalWidth: totalContentWidth)
    }

    func testConfigurationWidthRemainsProportionalAtDefaultWindowWidth() {
        let totalContentWidth: CGFloat = 1_320 - 140
        let configurationWidth = MonitorWorkspaceLayout.configurationWidth(
            totalWidth: totalContentWidth
        )
        let expected = totalContentWidth
            * (MonitorWorkspaceLayout.preferredConfigurationWidth
                / MonitorWorkspaceLayout.referenceContentWidth)

        XCTAssertEqual(configurationWidth, expected, accuracy: 0.5)
        assertSupportedColumnsFit(totalWidth: totalContentWidth)
    }

    @MainActor
    func testMonitorWorkspaceRendersEntirelyInMemoryAtSupportedWindowSizes() async throws {
        let sizes = [
            CGSize(width: 1_180, height: 700),
            CGSize(width: 1_320, height: 840),
            CGSize(width: 1_558, height: 1_010)
        ]

        for size in sizes {
            let image = try await renderRootMonitor(at: size)

            XCTAssertEqual(image.renderedSize.width, size.width, accuracy: 0.5)
            XCTAssertEqual(image.renderedSize.height, size.height, accuracy: 0.5)
            XCTAssertFalse(image.bitmap.isEmpty, "\(Int(size.width))×\(Int(size.height)) 未生成内存位图")
        }
    }

    private func assertSupportedColumnsFit(
        totalWidth: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let configurationWidth = MonitorWorkspaceLayout.configurationWidth(totalWidth: totalWidth)
        let previewWidth = totalWidth - configurationWidth - 1

        XCTAssertGreaterThanOrEqual(
            configurationWidth,
            MonitorWorkspaceLayout.minimumConfigurationWidth,
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            previewWidth,
            MonitorWorkspaceLayout.minimumPreviewWidth,
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            configurationWidth + previewWidth + 1,
            totalWidth + 0.5,
            "左右栏总宽度不能越过可用区域",
            file: file,
            line: line
        )
    }

    @MainActor
    private func renderRootMonitor(at size: CGSize) async throws -> (renderedSize: CGSize, bitmap: Data) {
        let model = AppModel()
        model.monitorConfiguration = .standard
        let router = AppNavigationRouter(destination: .monitor)
        let hostingView = NSHostingView(
            rootView: RootView()
                .environment(model)
                .environment(router)
                .preferredColorScheme(.dark)
                .frame(width: size.width, height: size.height)
        )
        let frame = NSRect(origin: .zero, size: size)
        hostingView.frame = frame

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hostingView
        window.orderOut(nil)
        defer {
            window.contentView = nil
            window.close()
        }

        await InMemoryHostingRenderer.settleUI(hostingView, milliseconds: 100)
        return (hostingView.bounds.size, try InMemoryHostingRenderer.bitmapData(for: hostingView))
    }
}
