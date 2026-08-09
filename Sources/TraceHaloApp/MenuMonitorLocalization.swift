import Foundation
import TraceHaloCore

enum MenuMonitorCountUnit: String, Sendable {
    case service
    case activeService
    case connectedService
    case fan
    case sensor
    case core
    case cycle

    fileprivate var simplifiedChineseFormat: String {
        switch self {
        case .service: "%lld 个服务"
        case .activeService: "%lld 个活跃"
        case .connectedService: "%lld 个已连接"
        case .fan: "%lld 个风扇"
        case .sensor: "%lld 个传感器"
        case .core: "%lld 核"
        case .cycle: "%lld 次"
        }
    }

    fileprivate var englishSingularFormat: String {
        switch self {
        case .service: "%lld service"
        case .activeService: "%lld active"
        case .connectedService: "%lld connected"
        case .fan: "%lld fan"
        case .sensor: "%lld sensor"
        case .core: "%lld core"
        case .cycle: "%lld cycle"
        }
    }

    fileprivate var englishPluralFormat: String {
        switch self {
        case .service: "%lld services"
        case .activeService: "%lld active"
        case .connectedService: "%lld connected"
        case .fan: "%lld fans"
        case .sensor: "%lld sensors"
        case .core: "%lld cores"
        case .cycle: "%lld cycles"
        }
    }
}

/// Locale-aware text used by the menu-bar monitor and its configuration UI.
///
/// Chinese source strings remain stable localization keys so the migration can
/// be incremental without changing persisted identifiers or parser aliases.
enum MenuMonitorLocalization {
    static func string(
        _ key: String,
        english: String,
        locale: Locale
    ) -> String {
        AppLocalization.string(key, defaultValue: english, locale: locale)
    }

    static func format(
        _ key: String,
        english: String,
        locale: Locale,
        _ arguments: CVarArg...
    ) -> String {
        String(
            format: string(key, english: english, locale: locale),
            locale: locale,
            arguments: arguments
        )
    }

    /// Localizes a canonical message supplied by a read-only service. Unknown
    /// OS messages are already localized by macOS and are therefore preserved.
    static func serviceMessage(_ message: String, locale: Locale) -> String {
        AppLocalization.string(message, defaultValue: message, locale: locale)
    }

    /// Resolves a source-language catalog key at reusable view boundaries.
    /// A catalog-coverage test guarantees an English value for every key used
    /// this way; the key itself is the correct Simplified Chinese fallback.
    static func catalogString(_ key: String, locale: Locale) -> String {
        AppLocalization.string(key, defaultValue: key, locale: locale)
    }

    static func count(
        _ value: Int,
        unit: MenuMonitorCountUnit,
        locale: Locale
    ) -> String {
        let language = AppLanguageResolver.supportedIdentifier(for: locale.identifier)
            ?? AppLanguageResolver.englishIdentifier
        let pluralCategory = value == 1 ? "one" : "other"
        let key = "menu.count.\(unit.rawValue).\(pluralCategory)"
        let fallback: String
        if language == AppLanguageResolver.simplifiedChineseIdentifier {
            fallback = unit.simplifiedChineseFormat
        } else {
            fallback = value == 1
                ? unit.englishSingularFormat
                : unit.englishPluralFormat
        }
        let localizedFormat = AppLocalization.string(
            key,
            defaultValue: fallback,
            locale: locale
        )
        return String(format: localizedFormat, locale: locale, Int64(value))
    }

    static func quickItemTitle(
        _ action: MonitorQuickAction,
        fallback: String,
        locale: Locale
    ) -> String {
        action.localizedTitle(persistedTitle: fallback, locale: locale)
    }
}

/// AppKit-owned strings cannot inherit SwiftUI's locale environment, so the
/// status item resolves them from the same language preference explicitly.
/// Keeping this pure also lets tests cover language switching without creating
/// an `NSStatusItem` or mutating user defaults.
struct MenuBarStatusItemLocalizedText: Equatable, Sendable {
    let toolTip: String
    let accessibilityLabel: String

    static func resolve(locale: Locale) -> Self {
        Self(
            toolTip: MenuMonitorLocalization.string(
                "TraceHalo 实时监控",
                english: "TraceHalo Real-Time Monitor",
                locale: locale
            ),
            accessibilityLabel: MenuMonitorLocalization.string(
                "TraceHalo，打开实时监控",
                english: "TraceHalo, open real-time monitor",
                locale: locale
            )
        )
    }
}
