import Foundation

public enum AppLanguagePreference: String, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    public static let storageKey = "appLanguagePreference"
    public static let defaultValue: AppLanguagePreference = .system

    public var id: String { rawValue }

    public static func storedPreference(from rawValue: String) -> AppLanguagePreference {
        AppLanguagePreference(rawValue: rawValue) ?? defaultValue
    }
}

public enum AppLanguageResolver {
    public static let englishIdentifier = AppLanguagePreference.english.rawValue
    public static let simplifiedChineseIdentifier = AppLanguagePreference.simplifiedChinese.rawValue

    public static func resolvedIdentifier(
        for preference: AppLanguagePreference,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        switch preference {
        case .english:
            return englishIdentifier
        case .simplifiedChinese:
            return simplifiedChineseIdentifier
        case .system:
            guard let primaryLanguage = preferredLanguages.first else {
                return englishIdentifier
            }
            return supportedIdentifier(for: primaryLanguage) ?? englishIdentifier
        }
    }

    public static func resolvedLocale(
        for preference: AppLanguagePreference,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> Locale {
        Locale(
            identifier: resolvedIdentifier(
                for: preference,
                preferredLanguages: preferredLanguages
            )
        )
    }

    public static func supportedIdentifier(for languageIdentifier: String) -> String? {
        let normalized = languageIdentifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()

        if normalized == "en" || normalized.hasPrefix("en-") {
            return englishIdentifier
        }

        let components = normalized.split(separator: "-").map(String.init)
        guard components.first == "zh" else { return nil }

        // TraceHalo ships Simplified Chinese only. Traditional Chinese is an
        // unsupported language and follows the documented English fallback.
        if components.contains("hant")
            || components.contains("tw")
            || components.contains("hk")
            || components.contains("mo") {
            return nil
        }
        if components.contains("hans")
            || components.contains("cn")
            || components.contains("sg") {
            return simplifiedChineseIdentifier
        }

        return nil
    }
}

public enum TraceHaloLocalization {
    /// Resolves the live preference on every call. `@AppStorage` writes to the
    /// same defaults domain, so non-SwiftUI strings switch language immediately
    /// without a process restart or mutable global language singleton.
    public static func currentLocale(
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> Locale {
        resolvedLocale(
            storedPreferenceRawValue: UserDefaults.standard.string(
                forKey: AppLanguagePreference.storageKey
            ),
            preferredLanguages: preferredLanguages
        )
    }

    public static func resolvedLocale(
        storedPreferenceRawValue: String?,
        preferredLanguages: [String]
    ) -> Locale {
        let preference = storedPreferenceRawValue.map(
            AppLanguagePreference.storedPreference(from:)
        ) ?? .defaultValue
        return AppLanguageResolver.resolvedLocale(
            for: preference,
            preferredLanguages: preferredLanguages
        )
    }

    public static func string(
        _ key: String,
        defaultValue: String,
        locale: Locale? = nil
    ) -> String {
        let resolvedLocale = locale ?? currentLocale()
        return bundleCache.localizedString(
            forKey: key,
            defaultValue: defaultValue,
            locale: resolvedLocale
        )
    }

    public static func format(
        _ key: String,
        defaultValue: String,
        locale: Locale? = nil,
        _ arguments: CVarArg...
    ) -> String {
        format(
            key,
            defaultValue: defaultValue,
            locale: locale,
            arguments: arguments
        )
    }

    public static func format(
        _ key: String,
        defaultValue: String,
        locale: Locale? = nil,
        arguments: [CVarArg]
    ) -> String {
        let resolvedLocale = locale ?? currentLocale()
        let format = string(
            key,
            defaultValue: defaultValue,
            locale: resolvedLocale
        )
        return String(
            format: format,
            locale: resolvedLocale,
            arguments: arguments
        )
    }

    private static let bundleCache = LocalizationBundleCache(
        resourceBundle: packagedOrModuleResourceBundle()
    )

    /// SwiftPM's generated `Bundle.module` accessor expects its resource bundle
    /// beside `Bundle.main.bundleURL`. A standard macOS app stores nested
    /// resource bundles under `Contents/Resources`, so resolve that packaged
    /// location first and retain `Bundle.module` for tests and command-line
    /// SwiftPM builds.
    private static func packagedOrModuleResourceBundle() -> Bundle {
        if let resourcesURL = Bundle.main.resourceURL,
           let packagedBundle = Bundle(
               url: resourcesURL.appendingPathComponent(
                   "SystemScope_SystemScopeCore.bundle",
                   isDirectory: true
               )
           ) {
            return packagedBundle
        }
        return .module
    }
}

private final class LocalizationBundleCache: @unchecked Sendable {
    private let resourceBundle: Bundle
    private let lock = NSLock()
    private var bundles: [String: Bundle] = [:]

    init(resourceBundle: Bundle) {
        self.resourceBundle = resourceBundle
    }

    func localizedString(
        forKey key: String,
        defaultValue: String,
        locale: Locale
    ) -> String {
        let identifier = AppLanguageResolver.supportedIdentifier(
            for: locale.identifier
        ) ?? AppLanguageResolver.englishIdentifier
        guard let bundle = bundle(for: identifier) else { return defaultValue }
        return bundle.localizedString(
            forKey: key,
            value: defaultValue,
            table: nil
        )
    }

    private func bundle(for localization: String) -> Bundle? {
        lock.lock()
        defer { lock.unlock() }

        if let cached = bundles[localization] {
            return cached
        }
        let resourceLocalization = localization == AppLanguageResolver.simplifiedChineseIdentifier
            ? "zh-hans"
            : localization
        guard let url = resourceBundle.url(
            forResource: resourceLocalization,
            withExtension: "lproj"
        ), let bundle = Bundle(url: url) else {
            return nil
        }
        bundles[localization] = bundle
        return bundle
    }
}
