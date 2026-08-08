import SwiftUI
import XCTest
@testable import SystemScopeApp

final class DashboardLocalizationTests: XCTestCase {
    func testLiteralEventResolvesInEnglishAndSimplifiedChinese() {
        let event = DashboardEventRecord(
            title: "系统启动",
            detail: "根据本机运行时间计算",
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            color: .green
        )

        XCTAssertEqual(event.localizedTitle(locale: Locale(identifier: "en")), "System Startup")
        XCTAssertEqual(
            event.localizedDetail(locale: Locale(identifier: "en")),
            "Calculated from this Mac's uptime"
        )
        XCTAssertEqual(event.localizedTitle(locale: Locale(identifier: "zh-Hans")), "系统启动")
        XCTAssertEqual(
            event.localizedDetail(locale: Locale(identifier: "zh-Hans")),
            "根据本机运行时间计算"
        )
    }

    func testFormattedEventLocalizesItsSemanticArgumentsAtRenderTime() {
        let event = DashboardEventRecord(
            titleKey: "dashboard.event.memory.change",
            titleDefaultValue: "内存压力%@ %@",
            titleArguments: ["上升", "8%"],
            titleLocalizedArgumentIndices: [0],
            detailKey: "与上一次采样相比",
            detailDefaultValue: "与上一次采样相比",
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            color: .orange
        )

        XCTAssertEqual(
            event.localizedTitle(locale: Locale(identifier: "en")),
            "Memory pressure increased 8%"
        )
        XCTAssertEqual(
            event.localizedTitle(locale: Locale(identifier: "zh-Hans")),
            "内存压力上升 8%"
        )
        XCTAssertEqual(
            event.localizedDetail(locale: Locale(identifier: "en")),
            "Compared with the previous sample"
        )
    }

    func testCoreNavigationAndDashboardKeysHaveEnglishFallbacks() {
        let locale = Locale(identifier: "en")
        let expected: [(String, String)] = [
            ("概览", "Overview"),
            ("实时监控", "Live Monitor"),
            ("系统工具", "System Tools"),
            ("硬件", "Hardware"),
            ("系统运行平稳", "System Running Smoothly"),
            ("事件记录", "Event Log"),
            ("正在读取本机状态", "Reading This Mac Status")
        ]

        for (key, english) in expected {
            XCTAssertEqual(
                AppLocalization.string(key, defaultValue: key, locale: locale),
                english,
                "Missing English localization for \(key)"
            )
        }
    }
}
