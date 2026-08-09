import AppKit
import SwiftUI
import XCTest
@testable import TraceHaloApp

final class ReportSettingsLocalizationTests: XCTestCase {
    func testReportAndSettingsLabelsResolveInEnglishAndSimplifiedChinese() {
        XCTAssertEqual(rendered("系统报告", locale: "en"), "System Report")
        XCTAssertEqual(rendered("设置", locale: "en"), "Settings")
        XCTAssertEqual(rendered("系统报告", locale: "zh-Hans"), "系统报告")
        XCTAssertEqual(rendered("设置", locale: "zh-Hans"), "设置")
    }

    func testDynamicStatusKeysCoverBothOutcomes() {
        XCTAssertEqual(
            ReportSettingsLocalization.exportAlertKey(succeeded: true),
            "PDF 已导出"
        )
        XCTAssertEqual(
            ReportSettingsLocalization.exportAlertKey(succeeded: false),
            "无法导出 PDF"
        )
        XCTAssertEqual(
            rendered(
                ReportSettingsLocalization.exportAlertKey(succeeded: true),
                locale: "en"
            ),
            "PDF Exported"
        )
        XCTAssertEqual(
            rendered(
                ReportSettingsLocalization.exportAlertKey(succeeded: false),
                locale: "zh-Hans"
            ),
            "无法导出 PDF"
        )
        XCTAssertEqual(
            ReportSettingsLocalization.dataSourceKey(.fixture),
            "演示数据"
        )
        XCTAssertEqual(ReportSettingsLocalization.dataSourceKey(.live), "本机数据")
        XCTAssertEqual(
            ReportSettingsLocalization.runtimeModeKey(isSafeTest: true),
            "安全测试（修改全部拒绝）"
        )
        XCTAssertEqual(
            ReportSettingsLocalization.runtimeModeKey(isSafeTest: false),
            "实时监测与受控修改"
        )

        XCTAssertEqual(
            rendered(ReportSettingsLocalization.dataSourceKey(.live), locale: "en"),
            "This Mac Data"
        )
        XCTAssertEqual(
            rendered(
                ReportSettingsLocalization.dataSourceKey(.live),
                locale: "zh-Hans"
            ),
            "本机数据"
        )
    }

    func testDatesUseTheSelectedInterfaceLocale() {
        let timestamp = Date(timeIntervalSince1970: 0)
        let english = ReportSettingsLocalization.updateTimestamp(
            timestamp,
            locale: Locale(identifier: "en")
        )
        let simplifiedChinese = ReportSettingsLocalization.updateTimestamp(
            timestamp,
            locale: Locale(identifier: "zh-Hans")
        )

        XCTAssertFalse(english.isEmpty)
        XCTAssertFalse(simplifiedChinese.isEmpty)
        XCTAssertNotEqual(english, simplifiedChinese)
    }

    @MainActor
    func testReportBodyUsesTheSelectedInterfaceLocale() {
        let model = AppModel()
        let english = model.reportText(locale: Locale(identifier: "en"))
        let simplifiedChinese = model.reportText(
            locale: Locale(identifier: "zh-Hans")
        )

        XCTAssertTrue(english.contains("TraceHalo System Report"))
        XCTAssertTrue(simplifiedChinese.contains("TraceHalo 系统报告"))
        XCTAssertNotEqual(english, simplifiedChinese)
    }

    @MainActor
    func testEnglishAndChineseLabelsRenderEntirelyInMemory() throws {
        let englishView = localizedProbe(localeIdentifier: "en")
        let chineseView = localizedProbe(localeIdentifier: "zh-Hans")
        let englishBitmap = try bitmap(for: englishView)
        let chineseBitmap = try bitmap(for: chineseView)

        XCTAssertFalse(englishBitmap.isEmpty)
        XCTAssertFalse(chineseBitmap.isEmpty)
        XCTAssertNotEqual(englishBitmap, chineseBitmap)
    }

    private func rendered(_ key: String, locale identifier: String) -> String {
        ReportSettingsLocalization.text(
            key,
            locale: Locale(identifier: identifier),
            lookup: { key, defaultValue, locale in
                Self.translations[locale.identifier]?[key] ?? defaultValue
            }
        )
    }

    private func localizedProbe(localeIdentifier: String) -> some View {
        VStack(alignment: .leading) {
            Text(rendered("系统报告", locale: localeIdentifier))
            Text(rendered("设置", locale: localeIdentifier))
            Text(rendered("本机数据", locale: localeIdentifier))
        }
        .frame(width: 240, height: 100, alignment: .leading)
    }

    @MainActor
    private func bitmap<Content: View>(for content: Content) throws -> Data {
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: 240, height: 100)
        hostingView.layoutSubtreeIfNeeded()
        return try InMemoryHostingRenderer.bitmapData(for: hostingView)
    }

    private static let translations: [String: [String: String]] = [
        "en": [
            "系统报告": "System Report",
            "设置": "Settings",
            "本机数据": "This Mac Data",
            "PDF 已导出": "PDF Exported"
        ],
        "zh-Hans": [
            "系统报告": "系统报告",
            "设置": "设置",
            "本机数据": "本机数据",
            "无法导出 PDF": "无法导出 PDF"
        ]
    ]
}
