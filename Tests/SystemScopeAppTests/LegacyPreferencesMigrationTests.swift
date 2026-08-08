import Foundation
import SystemScopeCore
import XCTest
@testable import SystemScopeApp

final class LegacyPreferencesMigrationTests: XCTestCase {
    func testWhitelistCoversEveryPersistedPreference() {
        XCTAssertEqual(
            LegacyPreferencesMigration.migratedKeys,
            [
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
        )
    }

    func testCopiesOnlyKnownKeysMissingFromCurrentDomain() {
        let current: [String: Any] = [
            "appearanceMode": "dark",
            "showMenuBarSummary": false
        ]
        let legacy: [String: Any] = [
            "appearanceMode": "light",
            "launchDestination": "monitor",
            "lastDestination": "storage",
            "monitorConfiguration": Data([1, 2, 3]),
            "refreshInterval": 5.0,
            "showMenuBarSummary": true,
            "unrelatedLegacyKey": "must not migrate"
        ]

        let plan = LegacyPreferencesMigration.plan(
            currentValues: current,
            legacyValues: legacy,
            migrationAlreadyCompleted: false
        )

        XCTAssertTrue(plan.shouldMarkComplete)
        XCTAssertEqual(plan.valuesToCopy["launchDestination"] as? String, "monitor")
        XCTAssertEqual(plan.valuesToCopy["lastDestination"] as? String, "storage")
        XCTAssertEqual(plan.valuesToCopy["monitorConfiguration"] as? Data, Data([1, 2, 3]))
        XCTAssertEqual(plan.valuesToCopy["refreshInterval"] as? Double, 5.0)
        XCTAssertNil(plan.valuesToCopy["appearanceMode"])
        XCTAssertNil(plan.valuesToCopy["showMenuBarSummary"])
        XCTAssertNil(plan.valuesToCopy["unrelatedLegacyKey"])
    }

    func testCompletedMigrationDoesNothing() {
        let plan = LegacyPreferencesMigration.plan(
            currentValues: [:],
            legacyValues: ["appearanceMode": "dark"],
            migrationAlreadyCompleted: true
        )

        XCTAssertFalse(plan.shouldMarkComplete)
        XCTAssertTrue(plan.valuesToCopy.isEmpty)
    }

    func testEmptyLegacyDomainStillProducesOneTimeCompletionPlan() {
        let plan = LegacyPreferencesMigration.plan(
            currentValues: [:],
            legacyValues: [:],
            migrationAlreadyCompleted: false
        )

        XCTAssertTrue(plan.shouldMarkComplete)
        XCTAssertTrue(plan.valuesToCopy.isEmpty)
    }

    func testMonitorConfigurationPayloadMigratesByteForByteWithoutTitleRewrites() throws {
        var configuration = MonitorConfiguration.standard
        configuration.panels.reverse()
        configuration.panels[0].name = "自定义电源面板"
        configuration.statusBarComponents.reverse()
        configuration.statusBarComponents[0].title = "我的温度"
        configuration.statusBarComponents[0].isVisible = false
        configuration.quickItems.reverse()
        configuration.quickItems[0].title = "我的系统设置"
        configuration.quickItems[0].isVisible = false
        let payload = try JSONEncoder().encode(configuration)

        let plan = LegacyPreferencesMigration.plan(
            currentValues: [:],
            legacyValues: ["monitorConfiguration": payload],
            migrationAlreadyCompleted: false
        )
        let copiedPayload = try XCTUnwrap(plan.valuesToCopy["monitorConfiguration"] as? Data)
        let decoded = try JSONDecoder().decode(MonitorConfiguration.self, from: copiedPayload)

        XCTAssertEqual(copiedPayload, payload)
        XCTAssertEqual(decoded, configuration)
        XCTAssertEqual(decoded.panels.first?.name, "自定义电源面板")
        XCTAssertEqual(decoded.statusBarComponents.first?.title, "我的温度")
        XCTAssertFalse(decoded.statusBarComponents.first?.isVisible ?? true)
        XCTAssertEqual(decoded.quickItems.first?.title, "我的系统设置")
        XCTAssertFalse(decoded.quickItems.first?.isVisible ?? true)
    }
}
