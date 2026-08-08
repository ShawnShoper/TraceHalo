import Foundation
import XCTest
@testable import SystemScopeCore

final class MonitorModuleConfigurationTests: XCTestCase {
    func testPowerModuleIsOnlyPresentableWithReliablePowerTelemetry() {
        var desktopSnapshot = SystemSnapshot.fixture
        desktopSnapshot.battery = BatteryState(
            availability: .unavailable(reason: "此 Mac 没有内置电池。")
        )
        XCTAssertFalse(MonitorModule.presentableCases(in: desktopSnapshot).contains(.power))
        XCTAssertFalse(PowerPresentationPolicy.isAvailable(in: desktopSnapshot))

        var portableSnapshot = desktopSnapshot
        portableSnapshot.battery = BatteryState(
            availability: .available,
            chargePercent: 48,
            health: .good,
            healthBasis: .systemReported
        )
        XCTAssertTrue(MonitorModule.presentableCases(in: portableSnapshot).contains(.power))
        XCTAssertTrue(PowerPresentationPolicy.isAvailable(in: portableSnapshot))
    }

    func testDefaultModuleOrderIsStableAndFullyEnabled() {
        let configuration = MonitorConfiguration.standard

        XCTAssertEqual(
            MonitorModule.allCases,
            [.cpuAndGPU, .memory, .storage, .sensors, .network, .power]
        )
        XCTAssertEqual(
            configuration.modulePreferences.map(\.module),
            MonitorModule.allCases
        )
        XCTAssertTrue(configuration.modulePreferences.allSatisfy(\.isEnabled))
        XCTAssertEqual(configuration.enabledModules, MonitorModule.allCases)
    }

    func testModuleCanBeDisabledAndEnabledAgain() {
        var configuration = MonitorConfiguration.standard

        configuration.setModule(.network, isEnabled: false)
        XCTAssertFalse(configuration.isModuleEnabled(.network))
        XCTAssertFalse(configuration.enabledModules.contains(.network))
        XCTAssertTrue(configuration.isModuleEnabled(.cpuAndGPU))

        configuration.setModule(.network, isEnabled: true)
        XCTAssertTrue(configuration.isModuleEnabled(.network))
        XCTAssertEqual(configuration.enabledModules, MonitorModule.allCases)
    }

    func testModulePreferencesCodableRoundTripStaysInMemory() throws {
        var source = MonitorConfiguration.standard
        source.setModule(.cpuAndGPU, isEnabled: false)
        source.setModule(.sensors, isEnabled: false)
        source.setModule(.power, isEnabled: false)

        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(MonitorConfiguration.self, from: data)

        XCTAssertEqual(decoded, source)
        XCTAssertEqual(
            decoded.enabledModules,
            [.memory, .storage, .network]
        )
    }

    func testLegacyConfigurationWithoutModulePreferencesMigratesPanelState() throws {
        struct LegacyConfiguration: Encodable {
            let isCombined: Bool
            let panels: [MonitorPanel]
        }

        var panels = MonitorConfiguration.standard.panels
        panels[0].isEnabled = false
        panels[3].isEnabled = false
        let legacy = LegacyConfiguration(isCombined: true, panels: panels)

        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(MonitorConfiguration.self, from: data)

        XCTAssertFalse(decoded.isModuleEnabled(.cpuAndGPU))
        XCTAssertFalse(decoded.isModuleEnabled(.sensors))
        XCTAssertTrue(decoded.isModuleEnabled(.memory))
        XCTAssertTrue(decoded.isModuleEnabled(.storage))
        XCTAssertTrue(decoded.isModuleEnabled(.network))
        XCTAssertTrue(decoded.isModuleEnabled(.power))
        XCTAssertEqual(
            decoded.modulePreferences.map(\.module),
            MonitorModule.allCases
        )
    }

    func testLegacyConfigurationDefaultsModulesMissingFromPanelsToEnabled() throws {
        struct LegacyConfiguration: Encodable {
            let isCombined: Bool
            let panels: [MonitorPanel]
        }

        let legacy = LegacyConfiguration(
            isCombined: false,
            panels: Array(MonitorConfiguration.standard.panels.prefix(1))
        )
        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(MonitorConfiguration.self, from: data)

        XCTAssertEqual(decoded.enabledModules, MonitorModule.allCases)
    }

    func testMissingAndDuplicatePreferencesNormalizeToCanonicalOrder() throws {
        struct PersistedConfiguration: Encodable {
            let isCombined: Bool
            let panels: [MonitorPanel]
            let modulePreferences: [MonitorModulePreference]
        }

        let persisted = PersistedConfiguration(
            isCombined: true,
            panels: MonitorConfiguration.standard.panels,
            modulePreferences: [
                MonitorModulePreference(module: .network, isEnabled: false),
                MonitorModulePreference(module: .cpuAndGPU, isEnabled: false),
                MonitorModulePreference(module: .network, isEnabled: true)
            ]
        )
        let data = try JSONEncoder().encode(persisted)
        let decoded = try JSONDecoder().decode(MonitorConfiguration.self, from: data)

        XCTAssertEqual(
            decoded.modulePreferences.map(\.module),
            MonitorModule.allCases
        )
        XCTAssertEqual(decoded.modulePreferences.count, MonitorModule.allCases.count)
        XCTAssertFalse(decoded.isModuleEnabled(.cpuAndGPU))
        XCTAssertFalse(
            decoded.isModuleEnabled(.network),
            "重复偏好必须保留第一个持久化值，不能由后续重复项覆盖"
        )
        XCTAssertTrue(decoded.isModuleEnabled(.memory))
        XCTAssertTrue(decoded.isModuleEnabled(.storage))
        XCTAssertTrue(decoded.isModuleEnabled(.sensors))
        XCTAssertTrue(decoded.isModuleEnabled(.power))
    }
}
