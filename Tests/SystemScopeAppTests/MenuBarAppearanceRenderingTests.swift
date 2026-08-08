import AppKit
import SwiftUI
import XCTest
@testable import SystemScopeApp

final class MenuBarAppearanceRenderingTests: XCTestCase {
    @MainActor
    func testLightAndDarkAppearancesKeepIdenticalExpandedGeometry() async throws {
        let light = try await renderDashboard(appearance: .aqua, colorScheme: .light)
        let dark = try await renderDashboard(appearance: .darkAqua, colorScheme: .dark)

        XCTAssertEqual(light.size.width, MenuBarDashboardLayout.expandedContentWidth, accuracy: 0.5)
        XCTAssertEqual(dark.size.width, MenuBarDashboardLayout.expandedContentWidth, accuracy: 0.5)
        XCTAssertEqual(light.size.width, dark.size.width, accuracy: 0.5)
        XCTAssertEqual(light.size.height, dark.size.height, accuracy: 0.5)
        XCTAssertFalse(light.bitmap.isEmpty)
        XCTAssertFalse(dark.bitmap.isEmpty)
    }

    @MainActor
    func testDashboardPaletteActuallyChangesWithAppearance() async throws {
        let light = try await renderDashboard(appearance: .aqua, colorScheme: .light)
        let dark = try await renderDashboard(appearance: .darkAqua, colorScheme: .dark)

        let lightLuminance = try averageLuminance(of: light.bitmap)
        let darkLuminance = try averageLuminance(of: dark.bitmap)

        XCTAssertGreaterThan(
            lightLuminance,
            darkLuminance + 0.30,
            "浅色外观必须得到明显更亮的菜单栏监控界面"
        )
        XCTAssertNotEqual(light.bitmap, dark.bitmap, "浅色与深色渲染不能共用同一套固定配色")
    }

    @MainActor
    private func renderDashboard(
        appearance: NSAppearance.Name,
        colorScheme: ColorScheme
    ) async throws -> (size: CGSize, bitmap: Data) {
        let model = AppModel()
        model.monitorConfiguration = .standard
        let router = AppNavigationRouter(destination: .monitor)
        let hostingView = NSHostingView(
            rootView: MenuBarDashboardView(
                initialSection: .cpu,
                maximumColumnHeightOverride: 560,
                showsQuickLaunchFooter: false,
                resetsSelectionOnPopoverClose: false,
                presentationMode: .embeddedPreview
            )
            .environment(model)
            .environment(router)
            .preferredColorScheme(colorScheme)
        )

        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        let frame = NSRect(origin: .zero, size: size)
        hostingView.frame = frame

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hostingView
        window.orderOut(nil)
        defer {
            window.contentView = nil
            window.close()
        }

        await InMemoryHostingRenderer.settleUI(hostingView)
        return (size, try InMemoryHostingRenderer.bitmapData(for: hostingView))
    }

    private func averageLuminance(of pngData: Data) throws -> Double {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: pngData))
        var luminance = 0.0
        var sampleCount = 0

        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 8) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 8) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }
                luminance += (0.2126 * color.redComponent)
                    + (0.7152 * color.greenComponent)
                    + (0.0722 * color.blueComponent)
                sampleCount += 1
            }
        }

        XCTAssertGreaterThan(sampleCount, 0)
        return luminance / Double(max(sampleCount, 1))
    }
}
