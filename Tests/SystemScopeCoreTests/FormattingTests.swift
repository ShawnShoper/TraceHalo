import Foundation
import XCTest
@testable import SystemScopeCore

final class FormattingTests: XCTestCase {
    func testTemperatureConversions() {
        XCTAssertEqual(TemperatureUnit.celsius.convert(celsius: 25), 25, accuracy: 0.000_001)
        XCTAssertEqual(TemperatureUnit.fahrenheit.convert(celsius: 25), 77, accuracy: 0.000_001)
        XCTAssertEqual(TemperatureUnit.kelvin.convert(celsius: 25), 298.15, accuracy: 0.000_001)
    }

    func testTemperatureSymbolsAndWholeNumberFormatting() {
        XCTAssertEqual(TemperatureUnit.celsius.symbol, "°C")
        XCTAssertEqual(TemperatureUnit.fahrenheit.symbol, "°F")
        XCTAssertEqual(TemperatureUnit.kelvin.symbol, "K")

        XCTAssertEqual(TemperatureUnit.celsius.formatted(celsius: 0), "0°C")
        XCTAssertEqual(TemperatureUnit.fahrenheit.formatted(celsius: 0), "32°F")
        XCTAssertEqual(TemperatureUnit.kelvin.formatted(celsius: 0), "273K")
    }

    func testPercentClampsToValidRangeAndRejectsNonFiniteValues() {
        XCTAssertEqual(MetricFormatter.percent(-2), "0%")
        XCTAssertEqual(MetricFormatter.percent(42), "42%")
        XCTAssertEqual(MetricFormatter.percent(120), "100%")
        XCTAssertEqual(MetricFormatter.percent(.infinity), "—")
        XCTAssertEqual(MetricFormatter.percent(.nan), "—")
    }

    func testRateRejectsInvalidInputWithoutSamplingAnything() {
        XCTAssertEqual(MetricFormatter.rate(bytesPerSecond: -1), "—")
        XCTAssertEqual(MetricFormatter.rate(bytesPerSecond: .infinity), "—")
        XCTAssertEqual(MetricFormatter.rate(bytesPerSecond: .nan), "—")

        let validRate = MetricFormatter.rate(bytesPerSecond: 1_048_576)
        XCTAssertTrue(validRate.hasSuffix("/s"))
        XCTAssertFalse(validRate.contains("—"))
    }

    func testByteAndRateFormattingHonorAnExplicitLocale() {
        let value: UInt64 = 1_234_567_890
        for locale in [Locale(identifier: "en"), Locale(identifier: "zh-Hans")] {
            let expectedBytes = value.formatted(
                ByteCountFormatStyle(style: .memory).locale(locale)
            )
            XCTAssertEqual(
                MetricFormatter.bytes(value, locale: locale),
                expectedBytes
            )
            XCTAssertEqual(
                MetricFormatter.rate(bytesPerSecond: Double(value), locale: locale),
                "\(expectedBytes)/s"
            )
        }
    }

    func testDurationFormattingClampsNegativeValues() {
        XCTAssertEqual(MetricFormatter.duration(-20), "0 分钟")
        XCTAssertEqual(MetricFormatter.duration(59), "0 分钟")
        XCTAssertEqual(MetricFormatter.duration(3_661), "1 小时 1 分钟")
        XCTAssertEqual(MetricFormatter.duration(90_061), "1 天 1 小时")
    }
}
