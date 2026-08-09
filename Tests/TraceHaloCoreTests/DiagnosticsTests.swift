import Foundation
import XCTest
@testable import TraceHaloCore

final class DiagnosticsTests: XCTestCase {
    func testBatteryHealthBoundaries() {
        XCTAssertEqual(
            BatteryHealthRules.evaluate(maximumCapacity: 900, designCapacity: 1_000, serviceRecommended: false),
            .excellent
        )
        XCTAssertEqual(
            BatteryHealthRules.evaluate(maximumCapacity: 899, designCapacity: 1_000, serviceRecommended: false),
            .good
        )
        XCTAssertEqual(
            BatteryHealthRules.evaluate(maximumCapacity: 800, designCapacity: 1_000, serviceRecommended: false),
            .good
        )
        XCTAssertEqual(
            BatteryHealthRules.evaluate(maximumCapacity: 799, designCapacity: 1_000, serviceRecommended: false),
            .aging
        )
        XCTAssertEqual(
            BatteryHealthRules.evaluate(maximumCapacity: 650, designCapacity: 1_000, serviceRecommended: false),
            .aging
        )
        XCTAssertEqual(
            BatteryHealthRules.evaluate(maximumCapacity: 649, designCapacity: 1_000, serviceRecommended: false),
            .serviceRecommended
        )
    }

    func testBatteryHealthRejectsInvalidCapacityAndHonorsServiceFlag() {
        XCTAssertEqual(
            BatteryHealthRules.evaluate(maximumCapacity: nil, designCapacity: 1_000, serviceRecommended: false),
            .unknown
        )
        XCTAssertEqual(
            BatteryHealthRules.evaluate(maximumCapacity: 800, designCapacity: 0, serviceRecommended: false),
            .unknown
        )
        XCTAssertEqual(
            BatteryHealthRules.evaluate(maximumCapacity: -1, designCapacity: 1_000, serviceRecommended: false),
            .unknown
        )
        XCTAssertEqual(
            BatteryHealthRules.evaluate(maximumCapacity: nil, designCapacity: nil, serviceRecommended: true),
            .serviceRecommended
        )
        XCTAssertEqual(
            BatteryHealthRules.evaluate(maximumCapacity: 950, designCapacity: 1_000, serviceRecommended: true),
            .serviceRecommended
        )
    }

    func testThermalTemperatureBoundaries() {
        XCTAssertEqual(ThermalRules.condition(forCelsius: nil), .unavailable)
        XCTAssertEqual(ThermalRules.condition(forCelsius: .nan), .unavailable)
        XCTAssertEqual(ThermalRules.condition(forCelsius: .infinity), .unavailable)
        XCTAssertEqual(ThermalRules.condition(forCelsius: 69.999), .nominal)
        XCTAssertEqual(ThermalRules.condition(forCelsius: 70), .fair)
        XCTAssertEqual(ThermalRules.condition(forCelsius: 84.999), .fair)
        XCTAssertEqual(ThermalRules.condition(forCelsius: 85), .serious)
        XCTAssertEqual(ThermalRules.condition(forCelsius: 94.999), .serious)
        XCTAssertEqual(ThermalRules.condition(forCelsius: 95), .critical)
    }

    func testThermalStateMapping() {
        XCTAssertEqual(ThermalRules.condition(for: .nominal), .nominal)
        XCTAssertEqual(ThermalRules.condition(for: .fair), .fair)
        XCTAssertEqual(ThermalRules.condition(for: .serious), .serious)
        XCTAssertEqual(ThermalRules.condition(for: .critical), .critical)
    }

    func testSystemReportDefaultsRedactPrivateValues() {
        let report = SystemReportBuilder().text(
            snapshot: .fixture,
            options: SystemReportOptions(),
            locale: Locale(identifier: "en")
        )

        XCTAssertTrue(report.contains("Top CPU processes: [redacted]"))
        XCTAssertTrue(report.contains("Serial: [redacted]"))
        XCTAssertTrue(report.contains("Input devices: 3 physical"))
        XCTAssertTrue(report.contains("Input device serials: [redacted]"))
        XCTAssertTrue(report.contains("Wi‑Fi (en0): [redacted]"))
        XCTAssertFalse(report.contains("Xcode"))
        XCTAssertFalse(report.contains("192.168.x.x"))
        XCTAssertFalse(report.contains("••••••••"))
        XCTAssertFalse(report.contains("Macintosh HD"))
        XCTAssertFalse(report.contains("REDACTED-FIXTURE-MOUSE"))
        XCTAssertTrue(report.contains("Volume 1"))
    }

    func testSystemReportOnlyRevealsOptedInProcessNamesAndNetworkAddresses() {
        var options = SystemReportOptions()
        options.includeProcessNames = true
        options.includeNetworkAddresses = true
        options.includeVolumeNames = true

        let report = SystemReportBuilder().text(
            snapshot: .fixture,
            options: options,
            locale: Locale(identifier: "en")
        )

        XCTAssertTrue(report.contains("Top CPU processes: Xcode"))
        XCTAssertTrue(report.contains("Wi‑Fi (en0): 192.168.x.x"))
        XCTAssertTrue(report.contains("Macintosh HD"))
        XCTAssertTrue(report.contains("Serial: [redacted]"))
        XCTAssertFalse(report.contains("••••••••"))
    }

    func testSystemReportSectionOptionsDoNotLeakExcludedSections() {
        let options = SystemReportOptions(
            includeHardware: false,
            includePerformance: false,
            includeStorage: false,
            includeGraphics: false,
            includeCooling: false,
            includeBattery: false
        )

        let report = SystemReportBuilder().text(
            snapshot: .fixture,
            options: options,
            locale: Locale(identifier: "en")
        )

        XCTAssertFalse(report.contains("[Hardware]"))
        XCTAssertFalse(report.contains("[Performance]"))
        XCTAssertFalse(report.contains("[Storage]"))
        XCTAssertFalse(report.contains("[Graphics]"))
        XCTAssertFalse(report.contains("[Cooling]"))
        XCTAssertFalse(report.contains("[Battery]"))
        XCTAssertTrue(report.contains("[Network]"))
        XCTAssertFalse(report.contains("192.168.x.x"))
    }
}
