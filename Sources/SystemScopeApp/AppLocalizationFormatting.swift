import Foundation

extension AppLocalization {
    static var currentLocale: Locale {
        let storedValue = UserDefaults.standard.string(
            forKey: AppLanguagePreference.storageKey
        ) ?? AppLanguagePreference.defaultValue.rawValue
        return AppLanguageResolver.resolvedLocale(
            for: AppLanguagePreference.storedPreference(from: storedValue)
        )
    }

    static func currentString(
        _ key: String,
        defaultValue: String? = nil
    ) -> String {
        string(
            key,
            defaultValue: defaultValue ?? key,
            locale: currentLocale
        )
    }

    static func format(
        _ key: String,
        defaultValue: String,
        locale: Locale,
        _ arguments: CVarArg...
    ) -> String {
        let localizedFormat = string(
            key,
            defaultValue: defaultValue,
            locale: locale
        )
        return String(
            format: localizedFormat,
            locale: locale,
            arguments: arguments
        )
    }

    static func currentFormat(
        _ key: String,
        defaultValue: String,
        _ arguments: CVarArg...
    ) -> String {
        let locale = currentLocale
        let localizedFormat = string(
            key,
            defaultValue: defaultValue,
            locale: locale
        )
        return String(
            format: localizedFormat,
            locale: locale,
            arguments: arguments
        )
    }

    static func format(
        _ key: String,
        defaultValue: String,
        locale: Locale,
        arguments: [String]
    ) -> String {
        let localizedFormat = string(
            key,
            defaultValue: defaultValue,
            locale: locale
        )
        return String(
            format: localizedFormat,
            locale: locale,
            arguments: arguments.map { $0 as CVarArg }
        )
    }
}
