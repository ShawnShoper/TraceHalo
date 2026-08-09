import Foundation

public enum TemperatureUnit: String, CaseIterable, Codable, Identifiable, Sendable {
    case celsius
    case fahrenheit
    case kelvin

    public var id: String { rawValue }

    public func convert(celsius: Double) -> Double {
        switch self {
        case .celsius: celsius
        case .fahrenheit: celsius * 9 / 5 + 32
        case .kelvin: celsius + 273.15
        }
    }

    public var symbol: String {
        switch self {
        case .celsius: "°C"
        case .fahrenheit: "°F"
        case .kelvin: "K"
        }
    }

    public func formatted(celsius: Double, locale: Locale? = nil) -> String {
        let resolvedLocale = locale ?? TraceHaloLocalization.currentLocale()
        let value = convert(celsius: celsius).formatted(
            .number
                .precision(.fractionLength(0))
                .locale(resolvedLocale)
        )
        return "\(value)\(symbol)"
    }
}

public enum MetricFormatter {
    private static let byteCountStyle = ByteCountFormatStyle(style: .memory)

    public static func bytes(_ value: UInt64) -> String {
        bytes(value, locale: nil)
    }

    public static func bytes(_ value: UInt64, locale: Locale?) -> String {
        let resolvedLocale = locale ?? TraceHaloLocalization.currentLocale()
        return value.formatted(byteCountStyle.locale(resolvedLocale))
    }

    public static func rate(bytesPerSecond: Double) -> String {
        rate(bytesPerSecond: bytesPerSecond, locale: nil)
    }

    public static func rate(bytesPerSecond: Double, locale: Locale?) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond >= 0 else { return "—" }
        return "\(bytes(UInt64(bytesPerSecond), locale: locale))/s"
    }

    public static func percent(
        _ value: Double,
        fractionDigits: Int = 0,
        locale: Locale? = nil
    ) -> String {
        guard value.isFinite else { return "—" }
        let resolvedLocale = locale ?? TraceHaloLocalization.currentLocale()
        let number = min(max(value, 0), 100).formatted(
            .number
                .precision(.fractionLength(fractionDigits))
                .locale(resolvedLocale)
        )
        return "\(number)%"
    }

    public static func duration(
        _ interval: TimeInterval,
        locale: Locale? = nil
    ) -> String {
        let seconds = max(Int(interval), 0)
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 {
            return TraceHaloLocalization.format(
                "format.duration.daysHours",
                defaultValue: "%lld d %lld hr",
                locale: locale,
                Int64(days), Int64(hours)
            )
        }
        if hours > 0 {
            return TraceHaloLocalization.format(
                "format.duration.hoursMinutes",
                defaultValue: "%lld hr %lld min",
                locale: locale,
                Int64(hours), Int64(minutes)
            )
        }
        return TraceHaloLocalization.format(
            "format.duration.minutes",
            defaultValue: "%lld min",
            locale: locale,
            Int64(minutes)
        )
    }
}
