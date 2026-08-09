import Foundation
import Testing
@testable import TraceHaloApp

@Suite("Final app localization coverage")
struct FinalLocalizationCoverageTests {
    @Test("Critical app chrome and dashboard keys resolve in both supported languages")
    func criticalKeysResolve() {
        let englishLocale = Locale(identifier: "en")
        let simplifiedChineseLocale = Locale(identifier: "zh-Hans")
        let expectedEnglish = [
            "刷新状态": "Refresh Status",
            "彻底退出 TraceHalo": "Quit TraceHalo Completely",
            "实时监控": "Live Monitor",
            "系统工具": "System Tools",
            "硬件": "Hardware",
            "展开诊断": "Open Diagnostics",
            "此刻与变化": "Now & Changes",
            "dashboard.cpu.detail": "User %@ · System %@",
            "sensor.helper.enable.error": "Unable to enable the read-only sensor service: %@",
            "需要权限": "Permission Required"
        ]

        for (key, english) in expectedEnglish {
            #expect(
                AppLocalization.string(
                    key,
                    defaultValue: key,
                    locale: englishLocale
                ) == english
            )
            #expect(
                AppLocalization.string(
                    key,
                    defaultValue: key,
                    locale: simplifiedChineseLocale
                ) != english
            )
        }
    }
}
