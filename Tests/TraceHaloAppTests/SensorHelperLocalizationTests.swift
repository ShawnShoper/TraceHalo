import Foundation
import TraceHaloCore
import XCTest
@testable import TraceHaloApp

final class SensorHelperLocalizationTests: XCTestCase {
    func testStableHelperErrorCodesRenderInTheForegroundLanguage() {
        let cases: [(SensorHelperErrorCode, String, String)] = [
            (
                .unavailable,
                "No readable temperature or fan sensors were found.",
                "未找到可读取的温度或风扇传感器。"
            ),
            (
                .permissionRequired,
                "macOS blocked read-only access to temperature and fan sensors.",
                "macOS 已阻止对温度和风扇传感器的只读访问。"
            ),
            (
                .readFailed,
                "The read-only sensor service could not collect sensor data.",
                "只读传感器服务无法读取传感器数据。"
            ),
            (
                .encodingFailed,
                "The read-only sensor service could not encode its result.",
                "只读传感器服务无法编码读取结果。"
            )
        ]

        for (code, english, chinese) in cases {
            XCTAssertEqual(
                SensorHelperErrorPresentation.reason(
                    code: code,
                    legacyMessage: "must not be shown",
                    locale: Locale(identifier: "en")
                ),
                english
            )
            XCTAssertEqual(
                SensorHelperErrorPresentation.reason(
                    code: code,
                    legacyMessage: "must not be shown",
                    locale: Locale(identifier: "zh-Hans")
                ),
                chinese
            )
        }
    }

    func testLegacyUnknownMessageIsPreservedForCompatibility() {
        XCTAssertEqual(
            SensorHelperErrorPresentation.reason(
                code: nil,
                legacyMessage: "driver detail",
                locale: Locale(identifier: "en")
            ),
            "driver detail"
        )
    }
}
