import Foundation
import TraceHaloCore

struct LegacyPreferenceMigrationPlan {
    let valuesToCopy: [String: Any]
    let shouldMarkComplete: Bool
}

/// One-time compatibility bridge for the Bundle ID change. The decision logic
/// is kept pure so unit tests never instantiate or mutate `UserDefaults`.
enum LegacyPreferencesMigration {
    static let completionKey = TraceHaloLegacyIdentifiers.preferencesMigrationCompletionKey
    static let migratedKeys: Set<String> = [
        "appearanceMode",
        "includeProcessNamesInReport",
        "includeVolumeNamesInReport",
        "lastDestination",
        "launchDestination",
        "monitorConfiguration",
        "pauseWhenOnBattery",
        "refreshInterval",
        "showMenuBarSummary",
        "temperatureUnit"
    ]

    static func plan(
        currentValues: [String: Any],
        legacyValues: [String: Any],
        migrationAlreadyCompleted: Bool
    ) -> LegacyPreferenceMigrationPlan {
        guard !migrationAlreadyCompleted else {
            return LegacyPreferenceMigrationPlan(
                valuesToCopy: [:],
                shouldMarkComplete: false
            )
        }

        let valuesToCopy = migratedKeys.reduce(into: [String: Any]()) { result, key in
            guard currentValues[key] == nil, let legacyValue = legacyValues[key] else { return }
            result[key] = legacyValue
        }
        return LegacyPreferenceMigrationPlan(
            valuesToCopy: valuesToCopy,
            shouldMarkComplete: true
        )
    }

    /// Called only by the packaged app's normal delegate initializer. Tests use
    /// the pure `plan` function and inject a no-op startup action.
    static func performIfNeeded() {
        let defaults = UserDefaults.standard
        let currentDomain = defaults.persistentDomain(
            forName: TraceHaloBundleIdentifiers.application
        ) ?? [:]
        let legacyDomain = defaults.persistentDomain(
            forName: TraceHaloBundleIdentifiers.legacyApplication
        ) ?? [:]
        let migrationPlan = plan(
            currentValues: currentDomain,
            legacyValues: legacyDomain,
            migrationAlreadyCompleted: defaults.bool(forKey: completionKey)
        )
        guard migrationPlan.shouldMarkComplete else { return }

        for (key, value) in migrationPlan.valuesToCopy {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: completionKey)
    }
}
