import AppKit
import SwiftUI
import XCTest
@testable import SystemScopeApp

final class ToolViewsLocalizationTests: XCTestCase {
    func testStartupAndApplicationLabelsResolveInMemory() {
        XCTAssertEqual(rendered("启动优化", locale: "en"), "Startup Optimization")
        XCTAssertEqual(rendered("应用管理", locale: "en"), "Application Management")
        XCTAssertEqual(rendered("启动优化", locale: "zh-Hans"), "启动优化")
        XCTAssertEqual(rendered("应用管理", locale: "zh-Hans"), "应用管理")
    }

    func testDynamicCountsPreserveArgumentsInBothLanguages() {
        XCTAssertEqual(
            formatted(
                "%lld / %lld 项",
                locale: "en",
                Int64(2),
                Int64(5)
            ),
            "2 / 5 items"
        )
        XCTAssertEqual(
            formatted(
                "%lld / %lld 项",
                locale: "zh-Hans",
                Int64(2),
                Int64(5)
            ),
            "2 / 5 项"
        )
        XCTAssertEqual(
            formatted(
                "已将 %lld 个确认项目移到废纸篓。",
                locale: "en",
                Int64(3)
            ),
            "Moved 3 confirmed items to the Trash."
        )
        XCTAssertEqual(
            formatted(
                "已将 %lld 个确认项目移到废纸篓。",
                locale: "zh-Hans",
                Int64(3)
            ),
            "已将 3 个确认项目移到废纸篓。"
        )
    }

    func testDynamicEvidencePreservesTheMatchedIdentifier() {
        let identifier = "com.example.product"
        XCTAssertEqual(
            formatted(
                "路径名称包含该应用的唯一标识 %@。这是较强证据；若同一开发者的其他应用共享此目录，仍应保留。",
                locale: "en",
                identifier
            ),
            "The path contains the unique identifier com.example.product."
        )
        XCTAssertEqual(
            formatted(
                "路径名称包含该应用的唯一标识 %@。这是较强证据；若同一开发者的其他应用共享此目录，仍应保留。",
                locale: "zh-Hans",
                identifier
            ),
            "路径包含唯一标识 com.example.product。"
        )
    }

    @MainActor
    func testEnglishAndChineseToolLabelsRenderEntirelyInMemory() throws {
        let english = try bitmap(for: localizedProbe(localeIdentifier: "en"))
        let chinese = try bitmap(for: localizedProbe(localeIdentifier: "zh-Hans"))

        XCTAssertFalse(english.isEmpty)
        XCTAssertFalse(chinese.isEmpty)
        XCTAssertNotEqual(english, chinese)
    }

    private func rendered(_ key: String, locale identifier: String) -> String {
        ToolViewsLocalization.text(
            key,
            locale: Locale(identifier: identifier),
            lookup: Self.lookup
        )
    }

    private func formatted(
        _ key: String,
        locale identifier: String,
        _ arguments: CVarArg...
    ) -> String {
        ToolViewsLocalization.format(
            key,
            locale: Locale(identifier: identifier),
            lookup: Self.lookup,
            arguments: arguments
        )
    }

    private func localizedProbe(localeIdentifier: String) -> some View {
        VStack(alignment: .leading) {
            Text(rendered("启动优化", locale: localeIdentifier))
            Text(rendered("应用管理", locale: localeIdentifier))
            Text(rendered("移除清单", locale: localeIdentifier))
        }
        .frame(width: 260, height: 100, alignment: .leading)
    }

    @MainActor
    private func bitmap<Content: View>(for content: Content) throws -> Data {
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: 260, height: 100)
        hostingView.layoutSubtreeIfNeeded()
        return try InMemoryHostingRenderer.bitmapData(for: hostingView)
    }

    private static func lookup(
        key: String,
        defaultValue: String,
        locale: Locale
    ) -> String {
        translations[locale.identifier]?[key] ?? defaultValue
    }

    private static let translations: [String: [String: String]] = [
        "en": [
            "启动优化": "Startup Optimization",
            "应用管理": "Application Management",
            "移除清单": "Removal List",
            "%lld / %lld 项": "%lld / %lld items",
            "已将 %lld 个确认项目移到废纸篓。": "Moved %lld confirmed items to the Trash.",
            "路径名称包含该应用的唯一标识 %@。这是较强证据；若同一开发者的其他应用共享此目录，仍应保留。": "The path contains the unique identifier %@."
        ],
        "zh-Hans": [
            "启动优化": "启动优化",
            "应用管理": "应用管理",
            "移除清单": "移除清单",
            "%lld / %lld 项": "%lld / %lld 项",
            "已将 %lld 个确认项目移到废纸篓。": "已将 %lld 个确认项目移到废纸篓。",
            "路径名称包含该应用的唯一标识 %@。这是较强证据；若同一开发者的其他应用共享此目录，仍应保留。": "路径包含唯一标识 %@。"
        ]
    ]
}
