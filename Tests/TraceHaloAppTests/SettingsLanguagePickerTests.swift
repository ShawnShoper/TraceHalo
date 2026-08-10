import XCTest
@testable import TraceHaloApp

final class SettingsLanguagePickerTests: XCTestCase {
    func testLanguagePickerUsesRequiredOrderAndStableStoredValues() {
        XCTAssertEqual(
            SettingsLanguagePickerPolicy.options,
            [.system, .english, .simplifiedChinese]
        )
        XCTAssertEqual(
            SettingsLanguagePickerPolicy.options.map(\.rawValue),
            ["system", "en", "zh-Hans"]
        )
    }

    func testLanguagePickerDefaultsToFollowingTheSystem() {
        XCTAssertEqual(AppLanguagePreference.defaultValue, .system)
        XCTAssertEqual(
            SettingsLanguagePickerPolicy.selection(storedValue: ""),
            AppLanguagePreference.system.rawValue
        )
        XCTAssertEqual(
            SettingsLanguagePickerPolicy.selection(storedValue: "unsupported-language"),
            AppLanguagePreference.system.rawValue
        )
    }

    func testLanguagePickerPreservesEverySupportedPreference() {
        for preference in SettingsLanguagePickerPolicy.options {
            XCTAssertEqual(
                SettingsLanguagePickerPolicy.selection(storedValue: preference.rawValue),
                preference.rawValue
            )
        }
    }

    func testLanguagePickerTitlesFollowTheResolvedInterfaceLocale() {
        let english = Locale(identifier: "en")
        XCTAssertEqual(
            SettingsLanguagePickerPolicy.title(for: .system, locale: english),
            "Follow System"
        )
        XCTAssertEqual(
            SettingsLanguagePickerPolicy.title(for: .english, locale: english),
            "English"
        )
        XCTAssertEqual(
            SettingsLanguagePickerPolicy.title(for: .simplifiedChinese, locale: english),
            "Simplified Chinese"
        )

        let simplifiedChinese = Locale(identifier: "zh-Hans")
        XCTAssertEqual(
            SettingsLanguagePickerPolicy.title(for: .system, locale: simplifiedChinese),
            "跟随系统"
        )
        XCTAssertEqual(
            SettingsLanguagePickerPolicy.title(for: .simplifiedChinese, locale: simplifiedChinese),
            "简体中文"
        )
    }
}

final class SettingsUsageModePolicyTests: XCTestCase {
    func testUsageModesApplyTheRequiredAtomicConfigurations() {
        XCTAssertEqual(
            SettingsUsageModePolicy.configuration(for: .powerSaving),
            SettingsUsageModeConfiguration(
                refreshInterval: 5,
                pauseWhenOnBattery: true
            )
        )
        XCTAssertEqual(
            SettingsUsageModePolicy.configuration(for: .balanced),
            SettingsUsageModeConfiguration(
                refreshInterval: 2,
                pauseWhenOnBattery: true
            )
        )
        XCTAssertEqual(
            SettingsUsageModePolicy.configuration(for: .realtime),
            SettingsUsageModeConfiguration(
                refreshInterval: 1,
                pauseWhenOnBattery: false
            )
        )
    }

    func testPowerSavingIsRemovedOnlyAfterNoBatteryIsConfirmed() {
        XCTAssertEqual(
            SettingsUsageModePolicy.availableModes(for: .checking),
            [.powerSaving, .balanced, .realtime]
        )
        XCTAssertEqual(
            SettingsUsageModePolicy.availableModes(for: .available),
            [.powerSaving, .balanced, .realtime]
        )
        XCTAssertEqual(
            SettingsUsageModePolicy.availableModes(for: .unavailable),
            [.balanced, .realtime]
        )
    }

    func testBatteryCapabilityDoesNotTreatLoadingAsNoBattery() {
        XCTAssertEqual(
            SettingsUsageModePolicy.capability(
                hasLoadedSnapshot: false,
                hasBattery: false
            ),
            .checking
        )
        XCTAssertEqual(
            SettingsUsageModePolicy.capability(
                hasLoadedSnapshot: true,
                hasBattery: false
            ),
            .unavailable
        )
        XCTAssertEqual(
            SettingsUsageModePolicy.capability(
                hasLoadedSnapshot: true,
                hasBattery: true
            ),
            .available
        )
    }

    func testFiveSecondAdvancedValueRemainsCustomWithoutBattery() {
        XCTAssertEqual(
            SettingsUsageModePolicy.selection(
                refreshInterval: 5,
                pauseWhenOnBattery: true,
                capability: .unavailable
            ),
            .custom
        )
    }

    func testCustomAdvancedValuesUseSafeVisualDerivation() {
        XCTAssertEqual(
            SettingsUsageModePolicy.selection(
                refreshInterval: 1.2,
                pauseWhenOnBattery: false,
                capability: .available
            ),
            .realtime
        )
        XCTAssertEqual(
            SettingsUsageModePolicy.selection(
                refreshInterval: 10,
                pauseWhenOnBattery: true,
                capability: .available
            ),
            .powerSaving
        )
        XCTAssertEqual(
            SettingsUsageModePolicy.selection(
                refreshInterval: 10,
                pauseWhenOnBattery: true,
                capability: .unavailable
            ),
            .custom
        )
    }

    func testNewSettingsLabelsResolveInBothSupportedLanguages() {
        XCTAssertEqual(
            ReportSettingsLocalization.text(
                "settings.usage.balanced.title",
                locale: Locale(identifier: "en")
            ),
            "Balanced"
        )
        XCTAssertEqual(
            ReportSettingsLocalization.text(
                "settings.usage.balanced.title",
                locale: Locale(identifier: "zh-Hans")
            ),
            "均衡"
        )
        XCTAssertEqual(
            ReportSettingsLocalization.text(
                "settings.diagnostics.title",
                locale: Locale(identifier: "en")
            ),
            "Data Status & Troubleshooting"
        )
        XCTAssertEqual(
            ReportSettingsLocalization.text(
                "settings.diagnostics.title",
                locale: Locale(identifier: "zh-Hans")
            ),
            "数据状态与故障排查"
        )
        XCTAssertEqual(
            ReportSettingsLocalization.text(
                "settings.selection.hint",
                locale: Locale(identifier: "en")
            ),
            "Show available options"
        )
        XCTAssertEqual(
            ReportSettingsLocalization.text(
                "settings.selection.hint",
                locale: Locale(identifier: "zh-Hans")
            ),
            "显示可用选项"
        )
    }
}

final class SettingsHistoryRetentionPresentationTests: XCTestCase {
    func testRetentionUsesTheCoordinatedStorageContract() {
        XCTAssertEqual(
            DashboardHistoryRetention.storageKey,
            "dashboardHistoryRetentionDays"
        )
        XCTAssertEqual(DashboardHistoryRetention.defaultValue, .threeDays)
        XCTAssertEqual(
            DashboardHistoryRetention.allCases.map(\.rawValue),
            [3, 7, 14, 30]
        )
    }

    func testUnsupportedStoredValuesFallBackToThreeDays() {
        XCTAssertEqual(
            SettingsHistoryRetentionPresentation.retention(storedDays: 0),
            .threeDays
        )
        XCTAssertEqual(
            SettingsHistoryRetentionPresentation.retention(storedDays: 90),
            .threeDays
        )
        for retention in DashboardHistoryRetention.allCases {
            XCTAssertEqual(
                SettingsHistoryRetentionPresentation.retention(
                    storedDays: retention.rawValue
                ),
                retention
            )
        }
    }

    func testRetentionTitlesFollowTheSelectedInterfaceLocale() {
        XCTAssertEqual(
            SettingsHistoryRetentionPresentation.title(
                retention: .threeDays,
                locale: Locale(identifier: "en")
            ),
            "3 days"
        )
        XCTAssertEqual(
            SettingsHistoryRetentionPresentation.title(
                retention: .thirtyDays,
                locale: Locale(identifier: "zh-Hans")
            ),
            "30 天"
        )
    }
}
