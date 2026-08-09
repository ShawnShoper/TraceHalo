import Foundation
import XCTest
@testable import TraceHaloCore

final class StorageIOReaderTests: XCTestCase {
    func testCachesStaticMediaNamesIncludingUnavailableLookups() {
        var cache = StorageMediaNameCache()
        var successfulLookupCount = 0
        var unavailableLookupCount = 0

        let first = cache.name(for: 42) {
            successfulLookupCount += 1
            return "  APPLE SSD Media  "
        }
        let repeated = cache.name(for: 42) {
            successfulLookupCount += 1
            return "Unexpected replacement"
        }
        let unavailable = cache.name(for: 99) {
            unavailableLookupCount += 1
            return nil
        }
        let repeatedUnavailable = cache.name(for: 99) {
            unavailableLookupCount += 1
            return "Should not be loaded"
        }

        XCTAssertEqual(first, "APPLE SSD Media")
        XCTAssertEqual(repeated, "APPLE SSD Media")
        XCTAssertNil(unavailable)
        XCTAssertNil(repeatedUnavailable)
        XCTAssertEqual(successfulLookupCount, 1)
        XCTAssertEqual(unavailableLookupCount, 1)
    }

    func testRemovedRegistryIDCanResolveANewMediaName() {
        var cache = StorageMediaNameCache()
        XCTAssertEqual(cache.name(for: 7) { "Old SSD" }, "Old SSD")

        cache.retainRegistryIDs([])

        XCTAssertEqual(cache.name(for: 7) { "Replacement SSD" }, "Replacement SSD")
    }

    func testDecodesIOKitBlockStorageCountersWithoutHardwareAccess() throws {
        let counters = try XCTUnwrap(StorageIOReader.counters(
            registryID: 42,
            name: "  APPLE SSD Media  ",
            statistics: [
                "Bytes (Read)": NSNumber(value: 4_096),
                "Bytes (Write)": UInt64(2_048),
                "Operations (Read)": 12,
                "Operations (Write)": Int64(7)
            ]
        ))

        XCTAssertEqual(counters.registryID, 42)
        XCTAssertEqual(counters.name, "APPLE SSD Media")
        XCTAssertEqual(counters.readBytes, 4_096)
        XCTAssertEqual(counters.writtenBytes, 2_048)
        XCTAssertEqual(counters.readOperations, 12)
        XCTAssertEqual(counters.writeOperations, 7)
    }

    func testRejectsIncompleteOrNegativeStatistics() {
        XCTAssertNil(StorageIOReader.counters(
            registryID: 1,
            name: nil,
            statistics: ["Bytes (Read)": 1]
        ))
        XCTAssertNil(StorageIOReader.counters(
            registryID: 1,
            name: nil,
            statistics: [
                "Bytes (Read)": -1,
                "Bytes (Write)": 0,
                "Operations (Read)": 0,
                "Operations (Write)": 0
            ]
        ))
    }

    func testBuildsRatesOnlyAfterMatchingDeviceBaseline() throws {
        let baseline = StorageIODeviceCounters(
            registryID: 7,
            name: "Internal SSD",
            readBytes: 10_000,
            writtenBytes: 5_000,
            readOperations: 100,
            writeOperations: 50
        )
        let first = StorageIORateCalculator.state(current: [baseline], previous: [:], elapsed: nil)
        XCTAssertTrue(first.availability.isAvailable)
        XCTAssertNil(first.readBytesPerSecond)
        XCTAssertEqual(first.totalReadBytes, 10_000)

        let current = StorageIODeviceCounters(
            registryID: 7,
            name: "Internal SSD",
            readBytes: 14_000,
            writtenBytes: 7_000,
            readOperations: 120,
            writeOperations: 60
        )
        let second = StorageIORateCalculator.state(
            current: [current],
            previous: [7: baseline],
            elapsed: 2
        )
        XCTAssertEqual(try XCTUnwrap(second.readBytesPerSecond), 2_000, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(second.writeBytesPerSecond), 1_000, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(second.readOperationsPerSecond), 10, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(second.writeOperationsPerSecond), 5, accuracy: 0.000_001)
        XCTAssertEqual(second.deviceNames, ["Internal SSD"])
    }

    func testNewDeviceDoesNotCreateFalseRateSpike() throws {
        let existing = StorageIODeviceCounters(
            registryID: 1,
            name: "Internal",
            readBytes: 1_000,
            writtenBytes: 1_000,
            readOperations: 10,
            writeOperations: 10
        )
        let external = StorageIODeviceCounters(
            registryID: 2,
            name: "External",
            readBytes: 900_000,
            writtenBytes: 700_000,
            readOperations: 9_000,
            writeOperations: 7_000
        )
        let state = StorageIORateCalculator.state(
            current: [existing, external],
            previous: [1: existing],
            elapsed: 2
        )

        XCTAssertEqual(try XCTUnwrap(state.readBytesPerSecond), 0, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(state.writeBytesPerSecond), 0, accuracy: 0.000_001)
        XCTAssertEqual(state.deviceNames, ["External", "Internal"])
    }

    func testEmptyDeviceListExplainsUnavailableState() {
        let state = StorageIORateCalculator.state(current: [], previous: [:], elapsed: 2)
        XCTAssertFalse(state.availability.isAvailable)
        XCTAssertNotNil(state.availability.message)
    }
}
