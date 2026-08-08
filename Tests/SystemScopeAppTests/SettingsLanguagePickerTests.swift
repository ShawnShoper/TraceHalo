import XCTest
@testable import SystemScopeApp

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
