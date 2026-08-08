import Foundation
import Testing
@testable import SystemScopeApp

@Suite("App language resolution")
struct AppLanguageTests {
    @Test("Preference contract remains stable for persisted settings")
    func preferenceContract() {
        #expect(AppLanguagePreference.system.rawValue == "system")
        #expect(AppLanguagePreference.english.rawValue == "en")
        #expect(AppLanguagePreference.simplifiedChinese.rawValue == "zh-Hans")
        #expect(AppLanguagePreference.defaultValue == .system)
        #expect(AppLanguagePreference.storageKey == "appLanguagePreference")
    }

    @Test("Explicit preferences override the system language")
    func explicitPreferences() {
        #expect(
            AppLanguageResolver.resolvedIdentifier(
                for: .english,
                preferredLanguages: ["zh-Hans-CN"]
            ) == "en"
        )
        #expect(
            AppLanguageResolver.resolvedIdentifier(
                for: .simplifiedChinese,
                preferredLanguages: ["fr-FR"]
            ) == "zh-Hans"
        )
    }

    @Test(
        "System preference maps supported languages",
        arguments: [
            ("en", "en"),
            ("en-US", "en"),
            ("zh-Hans", "zh-Hans"),
            ("zh-Hans-CN", "zh-Hans"),
            ("zh_CN", "zh-Hans"),
            ("zh-SG", "zh-Hans")
        ]
    )
    func supportedSystemLanguage(input: String, expected: String) {
        #expect(
            AppLanguageResolver.resolvedIdentifier(
                for: .system,
                preferredLanguages: [input]
            ) == expected
        )
    }

    @Test(
        "Unsupported languages fall back to English",
        arguments: ["fr-FR", "de-DE", "ja-JP", "zh-Hant-TW", "zh-HK", "zh"]
    )
    func unsupportedSystemLanguage(input: String) {
        #expect(
            AppLanguageResolver.resolvedIdentifier(
                for: .system,
                preferredLanguages: [input, "zh-Hans-CN"]
            ) == "en"
        )
    }

    @Test("No system preference falls back to English")
    func missingSystemLanguage() {
        #expect(
            AppLanguageResolver.resolvedIdentifier(
                for: .system,
                preferredLanguages: []
            ) == "en"
        )
    }

    @Test("Invalid persisted value safely restores system behavior")
    func invalidPersistedValue() {
        let preference = AppLanguagePreference.storedPreference(from: "obsolete-value")
        #expect(preference == .system)
        #expect(
            AppLanguageResolver.resolvedIdentifier(
                for: preference,
                preferredLanguages: ["fr-FR"]
            ) == "en"
        )
    }

    @Test("Both localization resources are available")
    func localizedResources() {
        let english = AppLocalization.string(
            "language.settings.title",
            defaultValue: "Missing",
            locale: Locale(identifier: "en")
        )
        let simplifiedChinese = AppLocalization.string(
            "language.settings.title",
            defaultValue: "缺失",
            locale: Locale(identifier: "zh-Hans")
        )

        #expect(english == "Language")
        #expect(simplifiedChinese == "语言")
    }
}
