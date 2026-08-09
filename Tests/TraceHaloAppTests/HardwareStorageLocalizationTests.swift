import Foundation
import TraceHaloCore
import XCTest
@testable import TraceHaloApp

final class HardwareStorageLocalizationTests: XCTestCase {
    func testEveryHardwareAndStorageChineseLiteralHasBothTranslations() throws {
        let english = try catalog(language: "en")
        let simplifiedChinese = try catalog(language: "zh-Hans")
        let sourceKeys = try userVisibleChineseLiterals()
            .subtracting(Self.sensorParserAliases)

        XCTAssertGreaterThanOrEqual(sourceKeys.count, 150)

        let missingEnglish = sourceKeys.subtracting(english.keys).sorted()
        let missingChinese = sourceKeys.subtracting(simplifiedChinese.keys).sorted()
        XCTAssertTrue(missingEnglish.isEmpty, "English keys missing: \(missingEnglish)")
        XCTAssertTrue(missingChinese.isEmpty, "Simplified Chinese keys missing: \(missingChinese)")

        for key in sourceKeys {
            let englishValue = try XCTUnwrap(english[key], "Missing English value for \(key)")
            XCTAssertFalse(englishValue.isEmpty)
            XCTAssertFalse(
                containsHan(englishValue),
                "English translation still contains Chinese: \(key) = \(englishValue)"
            )
            XCTAssertFalse(try XCTUnwrap(simplifiedChinese[key]).isEmpty)
        }
    }

    func testDynamicFormattingUsesTheSelectedLanguageCatalog() throws {
        let english = try catalog(language: "en")
        let simplifiedChinese = try catalog(language: "zh-Hans")
        let englishLocale = Locale(identifier: "en")
        let chineseLocale = Locale(identifier: "zh-Hans")

        XCTAssertEqual(
            HardwareStorageLocalization.format(
                "已识别 %lld 台物理输入设备",
                locale: englishLocale,
                lookup: lookup(english),
                Int64(3)
            ),
            "3 physical input devices detected"
        )
        XCTAssertEqual(
            HardwareStorageLocalization.format(
                "过去 %lld 秒",
                locale: chineseLocale,
                lookup: lookup(simplifiedChinese),
                Int64(60)
            ),
            "过去 60 秒"
        )
        XCTAssertEqual(
            HardwareStorageLocalization.format(
                "%@ I/O，最新读取 %@，写入 %@",
                locale: englishLocale,
                lookup: lookup(english),
                "Last 60 Seconds",
                "12 MB/s",
                "8 MB/s"
            ),
            "Last 60 Seconds I/O, latest read 12 MB/s, write 8 MB/s"
        )
    }

    func testStoragePresentationUsesMetricKindsInsteadOfLocalizedNames() {
        let volume = StorageVolume(
            name: "External",
            path: "/Volumes/External",
            totalBytes: 1_000,
            availableBytes: 500,
            isInternal: false,
            isRemovable: true
        )
        let health = StorageHealth(
            availability: .available,
            metrics: [
                StorageHealthMetric(kind: .device, name: "not a label", value: "disk9s1"),
                StorageHealthMetric(kind: .connection, name: "not a label", value: "USB4"),
                StorageHealthMetric(kind: .mediaType, name: "not a label", value: "Solid State")
            ]
        )

        let presentation = StorageVolumePresentation.make(
            volume: volume,
            health: health,
            locale: Locale(identifier: "en")
        )

        XCTAssertEqual(presentation.device, "disk9s1")
        XCTAssertEqual(presentation.connection, "USB4")
        XCTAssertEqual(presentation.medium, "Solid State")
    }

    private func catalog(language: String) throws -> [String: String] {
        let URL = projectRoot
            .appendingPathComponent("Sources/TraceHaloApp/Resources")
            .appendingPathComponent("\(language).lproj")
            .appendingPathComponent("Localizable.strings")
        let data = try Data(contentsOf: URL)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: String]
        )
    }

    private func userVisibleChineseLiterals() throws -> Set<String> {
        let sources = ["HardwareViews.swift", "StorageWorkspaceView.swift"]
        let expression = try NSRegularExpression(
            pattern: #"\"((?:\\.|[^\"\\])*)\""#
        )
        var result = Set<String>()

        for filename in sources {
            let source = try String(
                contentsOf: projectRoot
                    .appendingPathComponent("Sources/TraceHaloApp")
                    .appendingPathComponent(filename),
                encoding: .utf8
            )
            let range = NSRange(source.startIndex..., in: source)
            for match in expression.matches(in: source, range: range) {
                guard let valueRange = Range(match.range(at: 1), in: source) else { continue }
                let value = String(source[valueRange])
                if containsHan(value) { result.insert(value) }
            }
        }
        return result
    }

    private func containsHan(_ value: String) -> Bool {
        value.range(of: #"\p{script=Han}"#, options: .regularExpression) != nil
    }

    private func lookup(
        _ translations: [String: String]
    ) -> HardwareStorageLocalization.Lookup {
        { key, defaultValue, _ in translations[key] ?? defaultValue }
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// These literals are input-recognition aliases, not presentation strings.
    private static let sensorParserAliases: Set<String> = [
        "处理器", "中央处理器", "图形处理器", "机身", "环境"
    ]
}
