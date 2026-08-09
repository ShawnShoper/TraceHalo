import Foundation
import XCTest
@testable import TraceHaloApp
import TraceHaloCore

final class StorageIOHistoryPolicyTests: XCTestCase {
    func testSkipsCachedStorageSampleUntilUnderlyingIntervalElapses() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let first = sample(at: start, read: 100)

        XCTAssertNil(
            StorageIOHistoryPolicy.appending(
                sample(at: start.addingTimeInterval(2), read: 100),
                to: [first]
            )
        )

        let next = try XCTUnwrap(
            StorageIOHistoryPolicy.appending(
                sample(at: start.addingTimeInterval(3), read: 100),
                to: [first]
            )
        )
        XCTAssertEqual(next.map(\.capturedAt), [start, start.addingTimeInterval(3)])
    }

    func testChangedUnderlyingStorageSamplePublishesImmediately() throws {
        let start = Date(timeIntervalSince1970: 2_000)
        let first = sample(at: start, read: 100)
        let changed = sample(at: start.addingTimeInterval(2), read: 180)

        let next = try XCTUnwrap(
            StorageIOHistoryPolicy.appending(changed, to: [first])
        )

        XCTAssertEqual(next, [first, changed])
    }

    func testHistoryRetainsOnlySixtySecondsAndHasDefensiveCapacity() throws {
        let start = Date(timeIntervalSince1970: 3_000)
        var history: [StorageIOHistorySample] = []

        for index in 0 ..< 201 {
            let current = sample(
                at: start.addingTimeInterval(Double(index) * 0.5),
                read: Double(index)
            )
            if let next = StorageIOHistoryPolicy.appending(current, to: history) {
                history = next
            }
        }

        XCTAssertEqual(history.count, StorageIOHistoryPolicy.capacity)
        let latestDate = try XCTUnwrap(history.last?.capturedAt)
        let earliestDate = try XCTUnwrap(history.first?.capturedAt)
        XCTAssertGreaterThanOrEqual(
            earliestDate,
            latestDate.addingTimeInterval(-StorageIOHistoryPolicy.windowDuration)
        )
    }

    func testWallClockCorrectionStartsANewHistoryWindow() throws {
        let start = Date(timeIntervalSince1970: 4_000)
        let existing = [
            sample(at: start, read: 100),
            sample(at: start.addingTimeInterval(3), read: 200)
        ]
        let corrected = sample(at: start.addingTimeInterval(-10), read: 300)

        let next = try XCTUnwrap(
            StorageIOHistoryPolicy.appending(corrected, to: existing)
        )

        XCTAssertEqual(next, [corrected])
    }

    func testBuildsSamplesOnlyFromCompleteFiniteAvailableRates() throws {
        let date = Date(timeIntervalSince1970: 5_000)
        let unavailable = StorageIOState(
            availability: .unavailable(reason: "not ready"),
            readBytesPerSecond: 1,
            writeBytesPerSecond: 2,
            readOperationsPerSecond: 3,
            writeOperationsPerSecond: 4
        )
        XCTAssertNil(
            StorageIOHistoryPolicy.sample(capturedAt: date, storageIO: unavailable)
        )

        let incomplete = StorageIOState(
            availability: .available,
            readBytesPerSecond: 1,
            writeBytesPerSecond: nil,
            readOperationsPerSecond: 3,
            writeOperationsPerSecond: 4
        )
        XCTAssertNil(
            StorageIOHistoryPolicy.sample(capturedAt: date, storageIO: incomplete)
        )

        let invalid = StorageIOState(
            availability: .available,
            readBytesPerSecond: .infinity,
            writeBytesPerSecond: 2,
            readOperationsPerSecond: 3,
            writeOperationsPerSecond: 4
        )
        XCTAssertNil(
            StorageIOHistoryPolicy.sample(capturedAt: date, storageIO: invalid)
        )

        let valid = StorageIOState(
            availability: .available,
            readBytesPerSecond: 1,
            writeBytesPerSecond: 2,
            readOperationsPerSecond: 3,
            writeOperationsPerSecond: 4
        )
        let built = try XCTUnwrap(
            StorageIOHistoryPolicy.sample(capturedAt: date, storageIO: valid)
        )
        XCTAssertEqual(built, sample(at: date, read: 1, write: 2, readOps: 3, writeOps: 4))
    }

    @MainActor
    func testAppModelPublishesDeduplicatedStorageHistory() async {
        let start = Date(timeIntervalSince1970: 6_000)
        let provider = StorageHistoryMetricsProvider(
            snapshots: [
                snapshot(at: start, read: 100),
                snapshot(at: start.addingTimeInterval(2), read: 100),
                snapshot(at: start.addingTimeInterval(4), read: 100)
            ]
        )
        let model = AppModel(metricsProvider: provider)

        await model.refreshAll()
        await model.refreshAll()
        await model.refreshAll()

        XCTAssertEqual(model.storageIOHistory.count, 2)
        XCTAssertEqual(model.storageIOHistory.map(\.capturedAt), [
            start,
            start.addingTimeInterval(4)
        ])
        XCTAssertEqual(model.storageIOHistory.map(\.readBytesPerSecond), [100, 100])
    }

    private func sample(
        at date: Date,
        read: Double,
        write: Double = 20,
        readOps: Double = 3,
        writeOps: Double = 4
    ) -> StorageIOHistorySample {
        StorageIOHistorySample(
            capturedAt: date,
            readBytesPerSecond: read,
            writeBytesPerSecond: write,
            readOperationsPerSecond: readOps,
            writeOperationsPerSecond: writeOps
        )
    }

    private func snapshot(at date: Date, read: Double) -> SystemSnapshot {
        var value = SystemSnapshot.fixture
        value.capturedAt = date
        value.storageIO = StorageIOState(
            availability: .available,
            readBytesPerSecond: read,
            writeBytesPerSecond: 20,
            readOperationsPerSecond: 3,
            writeOperationsPerSecond: 4
        )
        return value
    }
}

private actor StorageHistoryMetricsProvider: SystemMetricsProviding {
    private let snapshots: [SystemSnapshot]
    private var nextIndex = 0

    init(snapshots: [SystemSnapshot]) {
        self.snapshots = snapshots
    }

    func snapshot() async -> SystemSnapshot {
        guard !snapshots.isEmpty else { return .fixture }
        let index = min(nextIndex, snapshots.count - 1)
        nextIndex += 1
        return snapshots[index]
    }
}
