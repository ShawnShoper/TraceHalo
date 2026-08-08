import Foundation
import XCTest
@testable import SystemScopeCore

final class ModelTests: XCTestCase {
    func testCapabilityAvailabilityPreservesReason() {
        XCTAssertTrue(CapabilityAvailability.available.isAvailable)
        XCTAssertNil(CapabilityAvailability.available.message)

        let missing = CapabilityAvailability.permissionRequired(reason: "需要授权")
        XCTAssertFalse(missing.isAvailable)
        XCTAssertEqual(missing.message, "需要授权")
    }

    func testStorageVolumeUsageIsClampedAndNormalized() {
        let partlyUsed = StorageVolume(
            name: "Data",
            path: "/Volumes/Data",
            totalBytes: 1_000,
            availableBytes: 250
        )
        XCTAssertEqual(partlyUsed.usedBytes, 750)
        XCTAssertEqual(partlyUsed.usedFraction, 0.75, accuracy: 0.000_001)

        let inconsistent = StorageVolume(
            name: "Inconsistent",
            path: "/Volumes/Inconsistent",
            totalBytes: 100,
            availableBytes: 150
        )
        XCTAssertEqual(inconsistent.usedBytes, 0)
        XCTAssertEqual(inconsistent.usedFraction, 0)

        let empty = StorageVolume(name: "Empty", path: "/Volumes/Empty", totalBytes: 0, availableBytes: 0)
        XCTAssertEqual(empty.usedFraction, 0)
    }

    func testBatteryPowerUsesSignedVoltageAndAmperage() throws {
        let discharging = BatteryState(
            availability: .available,
            voltageMV: 12_000,
            amperageMA: -500
        )
        XCTAssertEqual(try XCTUnwrap(discharging.powerWatts), -6, accuracy: 0.000_001)

        let unavailable = BatteryState(availability: .available, voltageMV: 12_000)
        XCTAssertNil(unavailable.powerWatts)
    }

    func testStableModelIdentifiersUseTheirDocumentedKeys() {
        let process = ProcessUsage(id: 42, name: "Example", cpuPercent: 1, memoryBytes: 2)
        let sensor = ThermalSensor(key: "TC0P", name: "CPU", group: "CPU", temperatureCelsius: 40)
        let network = NetworkInterfaceState(name: "en0", displayName: "Wi-Fi", localAddress: nil, isActive: true)

        XCTAssertEqual(process.id, 42)
        XCTAssertEqual(sensor.id, "TC0P")
        XCTAssertEqual(network.id, "en0")
    }

    func testProcessSortingIsDeterministicAndInMemory() {
        let processes = [
            ProcessUsage(id: 3, name: "Gamma", cpuPercent: 12, memoryBytes: 300),
            ProcessUsage(id: 1, name: "Alpha", cpuPercent: 61, memoryBytes: 100),
            ProcessUsage(id: 2, name: "Beta", cpuPercent: 25, memoryBytes: 200)
        ]

        XCTAssertEqual(processes.sorted { $0.cpuPercent > $1.cpuPercent }.map(\.id), [1, 2, 3])
        XCTAssertEqual(processes.sorted { $0.memoryBytes > $1.memoryBytes }.map(\.id), [3, 2, 1])
        XCTAssertEqual(processes.sorted { $0.name < $1.name }.map(\.id), [1, 2, 3])
    }
}
