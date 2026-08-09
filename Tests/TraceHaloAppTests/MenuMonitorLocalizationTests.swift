import AppKit
import SwiftUI
import TraceHaloCore
import XCTest
@testable import TraceHaloApp

final class MenuMonitorLocalizationTests: XCTestCase {
    private let english = Locale(identifier: AppLanguageResolver.englishIdentifier)
    private let simplifiedChinese = Locale(
        identifier: AppLanguageResolver.simplifiedChineseIdentifier
    )

    func testConfigurationTabsResolveBothSupportedLanguages() {
        XCTAssertEqual(MonitorConfigurationTab.modules.localizedTitle(locale: english), "Modules")
        XCTAssertEqual(MonitorConfigurationTab.statusBar.localizedTitle(locale: english), "Status Area")
        XCTAssertEqual(MonitorConfigurationTab.quickItems.localizedTitle(locale: english), "Quick Actions")

        XCTAssertEqual(MonitorConfigurationTab.modules.localizedTitle(locale: simplifiedChinese), "模块")
        XCTAssertEqual(MonitorConfigurationTab.statusBar.localizedTitle(locale: simplifiedChinese), "状态区")
        XCTAssertEqual(MonitorConfigurationTab.quickItems.localizedTitle(locale: simplifiedChinese), "快捷入口")
    }

    func testAppKitStatusItemTextResolvesWithoutUserDefaultsMutation() {
        XCTAssertEqual(
            MenuBarStatusItemLocalizedText.resolve(locale: english),
            MenuBarStatusItemLocalizedText(
                toolTip: "TraceHalo Real-Time Monitor",
                accessibilityLabel: "TraceHalo, open real-time monitor"
            )
        )
        XCTAssertEqual(
            MenuBarStatusItemLocalizedText.resolve(locale: simplifiedChinese),
            MenuBarStatusItemLocalizedText(
                toolTip: "TraceHalo 实时监控",
                accessibilityLabel: "TraceHalo，打开实时监控"
            )
        )
    }

    func testRecencyLabelsResolveEnglishAndSimplifiedChinese() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertEqual(
            MenuBarRecencyLabel.text(capturedAt: now, now: now, locale: english),
            "Just Now"
        )
        XCTAssertEqual(
            MenuBarRecencyLabel.text(
                capturedAt: now.addingTimeInterval(-3_600),
                now: now,
                locale: english
            ),
            "1 hr ago"
        )
        XCTAssertEqual(
            MenuBarRecencyLabel.text(
                capturedAt: now.addingTimeInterval(-60),
                now: now,
                locale: simplifiedChinese
            ),
            "1 分钟前"
        )
    }

    func testCountFormattingUsesEnglishSingularAndPluralForms() {
        let expectations: [(MenuMonitorCountUnit, String, String)] = [
            (.service, "1 service", "2 services"),
            (.fan, "1 fan", "2 fans"),
            (.sensor, "1 sensor", "2 sensors"),
            (.core, "1 core", "2 cores"),
            (.cycle, "1 cycle", "2 cycles")
        ]

        for (unit, singular, plural) in expectations {
            XCTAssertEqual(
                MenuMonitorLocalization.count(1, unit: unit, locale: english),
                singular
            )
            XCTAssertEqual(
                MenuMonitorLocalization.count(2, unit: unit, locale: english),
                plural
            )
        }
    }

    func testCountFormattingKeepsSimplifiedChineseClassifiersStable() {
        XCTAssertEqual(
            MenuMonitorLocalization.count(1, unit: .fan, locale: simplifiedChinese),
            "1 个风扇"
        )
        XCTAssertEqual(
            MenuMonitorLocalization.count(2, unit: .sensor, locale: simplifiedChinese),
            "2 个传感器"
        )
        XCTAssertEqual(
            MenuMonitorLocalization.count(1, unit: .cycle, locale: simplifiedChinese),
            "1 次"
        )
    }

    func testSemanticQuickActionLocalizationPreservesCustomPersistedTitle() {
        XCTAssertEqual(
            MenuMonitorLocalization.quickItemTitle(
                .activityMonitor,
                fallback: "活动监视器",
                locale: english
            ),
            "Activity Monitor"
        )
        XCTAssertEqual(
            MenuMonitorLocalization.quickItemTitle(
                .activityMonitor,
                fallback: "My Diagnostics",
                locale: simplifiedChinese
            ),
            "My Diagnostics"
        )
    }

    func testLongEnglishMonitorCopyIsLocalizedAndDoesNotFallBackToChinese() {
        let copy = MenuMonitorLocalization.catalogString(
            "需要精确调整菜单栏短标签、数据和样式时再使用这里；普通使用保持推荐布局即可。",
            locale: english
        )

        XCTAssertEqual(
            copy,
            "Use these controls only when you need precise labels, metrics, or styles. The recommended layout works for most people."
        )
        XCTAssertFalse(copy.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        })
    }

    @MainActor
    func testExpandedMenuGeometryIsStableAcrossBothLanguagesInMemory() async throws {
        for locale in [english, simplifiedChinese] {
            let model = AppModel()
            model.monitorConfiguration = .standard
            let router = AppNavigationRouter(destination: .dashboard)
            let hostingView = NSHostingView(
                rootView: MenuBarDashboardView(
                    initialSection: .cpu,
                    maximumColumnHeightOverride: MenuBarDashboardLayout.maximumColumnHeight
                )
                .environment(model)
                .environment(router)
                .environment(\.locale, locale)
                .preferredColorScheme(.dark)
            )

            hostingView.layoutSubtreeIfNeeded()
            let fittingSize = hostingView.fittingSize
            XCTAssertEqual(
                fittingSize.width,
                MenuBarDashboardLayout.expandedContentWidth,
                accuracy: 0.5,
                "Unexpected width for \(locale.identifier)"
            )
            XCTAssertEqual(fittingSize.height, 787, accuracy: 0.5)

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
            XCTAssertFalse(try InMemoryHostingRenderer.bitmapData(for: hostingView).isEmpty)
        }
    }

    @MainActor
    func testLegacyStatusLabelLanguageSwitchKeepsMeasuredStripWidthStable() async throws {
        var configuration = MonitorConfiguration.standard
        configuration.statusBarComponents = [
            MonitorStatusBarComponent(
                style: .verticalGaugeValue,
                metric: .memoryPressure,
                title: "内存",
                accentHex: "55B7F3"
            )
        ]
        let model = AppModel()
        model.monitorConfiguration = configuration
        let expectedWidth = MenuBarStatusLayout.estimatedContentWidth(for: configuration)
        var measuredWidths: [CGFloat] = []

        for locale in [english, simplifiedChinese] {
            let hostingView = NSHostingView(
                rootView: MenuBarStatusStrip()
                    .environment(model)
                    .environment(\.locale, locale)
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

            await InMemoryHostingRenderer.settleUI(hostingView)
            measuredWidths.append(hostingView.fittingSize.width)
            XCTAssertFalse(try InMemoryHostingRenderer.bitmapData(for: hostingView).isEmpty)
        }

        XCTAssertEqual(measuredWidths.count, 2)
        XCTAssertEqual(measuredWidths[0], expectedWidth, accuracy: 0.5)
        XCTAssertEqual(measuredWidths[1], expectedWidth, accuracy: 0.5)
        XCTAssertEqual(measuredWidths[0], measuredWidths[1], accuracy: 0.5)
        XCTAssertEqual(
            configuration.statusBarComponents[0].localizedDisplayTitle(locale: english),
            "RAM"
        )
        XCTAssertEqual(configuration.statusBarComponents[0].title, "内存")
    }
}
