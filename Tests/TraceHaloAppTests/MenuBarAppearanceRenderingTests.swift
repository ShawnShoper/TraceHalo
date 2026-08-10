import AppKit
import SwiftUI
import XCTest
@testable import TraceHaloApp

final class MenuBarAppearanceRenderingTests: XCTestCase {
    func testAppearanceModeNormalizesStoredValues() {
        XCTAssertEqual(TraceHaloAppearanceMode(storedValue: nil), .system)
        XCTAssertEqual(TraceHaloAppearanceMode(storedValue: "unsupported"), .system)
        for mode in TraceHaloAppearanceMode.allCases {
            XCTAssertEqual(TraceHaloAppearanceMode(storedValue: mode.rawValue), mode)
        }
    }

    @MainActor
    func testWindowReturnsFromLightToInheritedSystemAppearanceWithoutFocusChange() throws {
        let inheritedAppearanceSource = NSView(frame: .zero)
        inheritedAppearanceSource.appearance = try XCTUnwrap(
            NSAppearance(named: .darkAqua)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearanceSource = inheritedAppearanceSource
        window.orderOut(nil)
        defer { window.close() }
        let applicationOverrideName = NSApp.appearance?.name

        XCTAssertTrue(TraceHaloAppearancePolicy.apply(.light, to: window))
        XCTAssertEqual(window.appearance?.name, .aqua)
        XCTAssertEqual(
            window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]),
            .aqua
        )
        XCTAssertFalse(window.isKeyWindow)
        XCTAssertFalse(
            TraceHaloAppearancePolicy.apply(.light, to: window),
            "重复应用相同外观必须无副作用"
        )

        XCTAssertTrue(TraceHaloAppearancePolicy.apply(.system, to: window))
        XCTAssertNil(window.appearance, "跟随系统必须清除 NSWindow 的显式外观")
        XCTAssertEqual(
            window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]),
            .darkAqua,
            "清除浅色覆盖后应立即继承系统深色，无需重新聚焦窗口"
        )
        XCTAssertFalse(window.isKeyWindow)
        XCTAssertFalse(TraceHaloAppearancePolicy.apply(.system, to: window))
        XCTAssertEqual(NSApp.appearance?.name, applicationOverrideName)
    }

    @MainActor
    func testSystemPopoverUsesResolvedSystemAppearanceWithoutChangingApplicationOverride() throws {
        let popover = NSPopover()
        let viewController = NSViewController()
        viewController.view = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 100))
        popover.contentViewController = viewController
        let systemAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let applicationOverrideName = NSApp.appearance?.name

        XCTAssertTrue(
            TraceHaloAppearancePolicy.apply(
                .system,
                to: popover,
                systemAppearance: systemAppearance
            )
        )
        XCTAssertEqual(
            popover.appearance?.name,
            .darkAqua,
            "NSPopover 的 nil 外观默认是 Vibrant Light，系统模式必须显式解析"
        )
        XCTAssertFalse(
            TraceHaloAppearancePolicy.apply(
                .system,
                to: popover,
                systemAppearance: systemAppearance
            ),
            "相同的系统有效外观不应重复触发重绘"
        )
        XCTAssertEqual(NSApp.appearance?.name, applicationOverrideName)
    }

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
