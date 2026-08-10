import Foundation
import XCTest
@testable import TraceHaloApp
import TraceHaloCore

final class DashboardHistoryStoreTests: XCTestCase {
    func testRetentionContractOnlyAllowsSupportedDurations() {
        XCTAssertEqual(DashboardHistoryRetention.allCases.map(\.rawValue), [3, 7, 14, 30])
        XCTAssertEqual(DashboardHistoryRetention.defaultValue, .threeDays)
        XCTAssertEqual(DashboardHistoryRetention.storageKey, "dashboardHistoryRetentionDays")
        XCTAssertNil(DashboardHistoryRetention(rawValue: 1))
    }

    func testMinuteBucketKeepsLatestCompleteSampleAndRoundTripsEveryMetric() async throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 20 * 86_400 + 125)
        let store = DashboardHistoryStore(directoryURL: directory)
        let first = sample(date: now.addingTimeInterval(-65), cpu: 11)
        let replacement = sample(date: now.addingTimeInterval(-61), cpu: 72)
        let current = sample(date: now, cpu: 33)

        await store.record(first, retention: .threeDays, now: now)
        await store.record(replacement, retention: .threeDays, now: now)
        await store.record(current, retention: .threeDays, now: now)

        let reloaded = await DashboardHistoryStore(directoryURL: directory).load(
            retention: .threeDays,
            now: now
        )
        XCTAssertEqual(reloaded.samples, [replacement, current])
        XCTAssertEqual(reloaded.samples[0].gpuPercent, replacement.gpuPercent)
        XCTAssertEqual(reloaded.samples[0].memoryPressurePercent, replacement.memoryPressurePercent)
        XCTAssertEqual(reloaded.samples[0].storageUsedPercent, replacement.storageUsedPercent)
        XCTAssertEqual(
            reloaded.samples[0].networkReceivedBytesPerSecond,
            replacement.networkReceivedBytesPerSecond
        )
        XCTAssertEqual(
            reloaded.samples[0].networkSentBytesPerSecond,
            replacement.networkSentBytesPerSecond
        )
        XCTAssertEqual(reloaded.samples[0].temperatureCelsius, replacement.temperatureCelsius)
    }

    func testRetentionUsesExactCutoffAndRewritesBoundarySegment() async throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // Align the cutoff to a minute boundary so the just-expired sample
        // remains in the preceding bucket and exercises exact cutoff pruning.
        let now = Date(timeIntervalSince1970: 40 * 86_400 + 120)
        let cutoff = now.addingTimeInterval(-DashboardHistoryRetention.threeDays.duration)
        let expired = sample(date: cutoff.addingTimeInterval(-1), cpu: 10)
        let boundary = sample(date: cutoff, cpu: 20)
        let recent = sample(date: now.addingTimeInterval(-60), cpu: 30)
        let store = DashboardHistoryStore(directoryURL: directory)

        await store.record(expired, retention: .thirtyDays, now: now)
        await store.record(boundary, retention: .thirtyDays, now: now)
        await store.record(recent, retention: .thirtyDays, now: now)
        let result = await store.updateRetention(.threeDays, now: now)

        XCTAssertEqual(result.samples, [boundary, recent])
        let reloaded = await DashboardHistoryStore(directoryURL: directory).load(
            retention: .threeDays,
            now: now
        )
        XCTAssertEqual(reloaded.samples, [boundary, recent])
    }

    func testCorruptAndUnknownVersionSegmentsAreRemovedWithoutBlockingLoad() async throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let corruptURL = directory.appendingPathComponent("dashboard-history-10.plist")
        let unknownURL = directory.appendingPathComponent("dashboard-history-11.plist")
        try Data("not a property list".utf8).write(to: corruptURL, options: .atomic)
        let unknownArchive = try PropertyListSerialization.data(
            fromPropertyList: ["version": 999, "samples": []],
            format: .binary,
            options: 0
        )
        try unknownArchive.write(to: unknownURL, options: .atomic)

        let result = await DashboardHistoryStore(directoryURL: directory).load(
            retention: .threeDays,
            now: Date(timeIntervalSince1970: 11 * 86_400)
        )

        XCTAssertTrue(result.samples.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: corruptURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: unknownURL.path))
    }

    func testFutureAndInvalidSamplesAreRejected() async {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 50 * 86_400)
        let store = DashboardHistoryStore(directoryURL: directory)
        let future = sample(date: now.addingTimeInterval(1), cpu: 10)
        let notANumber = DashboardTelemetrySample(
            date: now.addingTimeInterval(-240),
            cpuPercent: .nan,
            gpuPercent: 42,
            memoryPressurePercent: 37,
            storageUsedPercent: 58,
            networkReceivedBytesPerSecond: 12_345,
            networkSentBytesPerSecond: 6_789,
            temperatureCelsius: 51
        )
        let infiniteTemperature = DashboardTelemetrySample(
            date: now.addingTimeInterval(-180),
            cpuPercent: 20,
            gpuPercent: 42,
            memoryPressurePercent: 37,
            storageUsedPercent: 58,
            networkReceivedBytesPerSecond: 12_345,
            networkSentBytesPerSecond: 6_789,
            temperatureCelsius: .infinity
        )
        let negativeNetwork = DashboardTelemetrySample(
            // Use the valid sample's bucket to prove a rejected write cannot
            // erase the last known-good value for that minute.
            date: now.addingTimeInterval(-59),
            cpuPercent: 30,
            gpuPercent: 42,
            memoryPressurePercent: 37,
            storageUsedPercent: 58,
            networkReceivedBytesPerSecond: -1,
            networkSentBytesPerSecond: 6_789,
            temperatureCelsius: 51
        )
        let valid = sample(date: now.addingTimeInterval(-60), cpu: 40)

        for candidate in [future, notANumber, infiniteTemperature, valid, negativeNetwork] {
            await store.record(candidate, retention: .threeDays, now: now)
        }
        let result = await store.load(retention: .threeDays, now: now)

        XCTAssertEqual(result.samples, [valid])
    }

    func testDashboardRestoreSortsDeduplicatesAndRejectsFutureSamples() {
        let now = Date(timeIntervalSince1970: 55 * 86_400)
        let older = sample(date: now.addingTimeInterval(-120), cpu: 10)
        let duplicateDate = now.addingTimeInterval(-60)
        let replaced = sample(date: duplicateDate, cpu: 20)
        let replacement = sample(date: duplicateDate, cpu: 30)
        let future = sample(date: now.addingTimeInterval(1), cpu: 40)

        let restored = DashboardHistoryPolicy.restoring(
            [future, replaced, older, replacement],
            now: now
        )

        XCTAssertEqual(restored, [older, replacement])
    }

    func testSampleAndByteHardLimitsEvictOldestDataFirst() async throws {
        let sampleLimitedDirectory = makeTemporaryDirectory()
        let byteLimitedDirectory = makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: sampleLimitedDirectory)
            try? FileManager.default.removeItem(at: byteLimitedDirectory)
        }
        let now = Date(timeIntervalSince1970: 60 * 86_400)
        let sampleLimited = DashboardHistoryStore(
            directoryURL: sampleLimitedDirectory,
            maximumSampleCount: 3
        )
        for index in 0 ..< 6 {
            await sampleLimited.record(
                sample(date: now.addingTimeInterval(Double(index - 5) * 60), cpu: Double(index)),
                retention: .thirtyDays,
                now: now
            )
        }
        let sampleLimitedResult = await sampleLimited.load(retention: .thirtyDays, now: now)
        XCTAssertEqual(sampleLimitedResult.samples.map(\.cpuPercent), [3, 4, 5])

        let byteLimited = DashboardHistoryStore(
            directoryURL: byteLimitedDirectory,
            hardByteLimit: 1_024
        )
        for index in 0 ..< 12 {
            await byteLimited.record(
                sample(
                    date: now.addingTimeInterval(Double(index - 11) * 86_400),
                    cpu: Double(index)
                ),
                retention: .thirtyDays,
                now: now
            )
        }
        let byteLimitedResult = await byteLimited.load(retention: .thirtyDays, now: now)
        let bytes = try historyFiles(in: byteLimitedDirectory).reduce(0) { total, URL in
            let size = try XCTUnwrap(URL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            return total + size
        }
        XCTAssertLessThanOrEqual(bytes, 1_024)
        XCTAssertEqual(byteLimitedResult.samples.last?.cpuPercent, 11)
        XCTAssertLessThan(byteLimitedResult.samples.count, 12)
    }

    func testIncrementalRecordDoesNotRewriteUnchangedHistoricalDay() async throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 80 * 86_400 + 120)
        let store = DashboardHistoryStore(directoryURL: directory)
        await store.record(
            sample(date: now.addingTimeInterval(-86_400), cpu: 20),
            retention: .threeDays,
            now: now
        )
        await store.record(sample(date: now, cpu: 30), retention: .threeDays, now: now)

        let historicalURL = try XCTUnwrap(
            historyFiles(in: directory).min { lhs, rhs in
                lhs.lastPathComponent < rhs.lastPathComponent
            }
        )
        let before = try historicalURL.resourceValues(
            forKeys: [.fileResourceIdentifierKey, .contentModificationDateKey]
        )
        try await Task.sleep(for: .milliseconds(20))
        await store.record(
            sample(date: now.addingTimeInterval(60), cpu: 40),
            retention: .threeDays,
            now: now.addingTimeInterval(60)
        )
        let after = try historicalURL.resourceValues(
            forKeys: [.fileResourceIdentifierKey, .contentModificationDateKey]
        )

        XCTAssertEqual(
            String(describing: before.fileResourceIdentifier),
            String(describing: after.fileResourceIdentifier)
        )
        XCTAssertEqual(before.contentModificationDate, after.contentModificationDate)
    }

    private func makeTemporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("tracehalo-history-\(UUID().uuidString)", isDirectory: true)
    }

    private func historyFiles(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.lastPathComponent.hasPrefix("dashboard-history-") }
    }

    private func sample(
        date: Date,
        cpu: Double
    ) -> DashboardTelemetrySample {
        DashboardTelemetrySample(
            date: date,
            cpuPercent: cpu,
            gpuPercent: 42,
            memoryPressurePercent: 37,
            storageUsedPercent: 58,
            networkReceivedBytesPerSecond: 12_345,
            networkSentBytesPerSecond: 6_789,
            temperatureCelsius: 51
        )
    }
}

final class DashboardHistoryAppModelIntegrationTests: XCTestCase {
    @MainActor
    func testLiveModelRestoresHistoryAndPersistsAtMostOncePerMinute() async throws {
        let now = Date(timeIntervalSince1970: 100 * 86_400 + 120)
        let restored = DashboardTelemetrySample(
            date: now.addingTimeInterval(-300),
            cpuPercent: 18,
            gpuPercent: 22,
            memoryPressurePercent: 31,
            storageUsedPercent: 44,
            networkReceivedBytesPerSecond: 1_000,
            networkSentBytesPerSecond: 500,
            temperatureCelsius: 49
        )
        let store = RecordingDashboardHistoryStore(restoredSamples: [restored])
        var firstSnapshot = SystemSnapshot.fixture
        firstSnapshot.capturedAt = now
        firstSnapshot.cpu.totalPercent = 55
        var secondSnapshot = firstSnapshot
        secondSnapshot.capturedAt = now.addingTimeInterval(5)
        secondSnapshot.cpu.totalPercent = 60
        var thirdSnapshot = secondSnapshot
        thirdSnapshot.capturedAt = now.addingTimeInterval(61)
        thirdSnapshot.cpu.totalPercent = 65
        let model = AppModel(
            metricsProvider: IntegrationMetricsProvider(
                snapshots: [firstSnapshot, secondSnapshot, thirdSnapshot]
            ),
            dashboardHistoryStore: store,
            dashboardHistoryNow: { now }
        )
        model.dataSource = .live

        await model.loadPersistedDashboardHistoryIfNeeded()
        XCTAssertEqual(model.dashboardHistory, [restored])
        await model.refreshAll()
        await model.refreshAll()
        await model.refreshAll()

        let deadline = ContinuousClock().now.advanced(by: .seconds(1))
        while await store.recordedSamples().count < 2,
              ContinuousClock().now < deadline {
            try? await Task.sleep(for: .milliseconds(2))
        }
        let recorded = await store.recordedSamples()
        XCTAssertEqual(recorded.map(\.date), [now, now.addingTimeInterval(61)])
    }

    @MainActor
    func testClockRollbackStartsANewPersistenceSequenceImmediately() async {
        let now = Date(timeIntervalSince1970: 110 * 86_400)
        let futurePersistedSample = DashboardTelemetrySample(
            date: now,
            cpuPercent: 18,
            gpuPercent: 22,
            memoryPressurePercent: 31,
            storageUsedPercent: 44,
            networkReceivedBytesPerSecond: 1_000,
            networkSentBytesPerSecond: 500,
            temperatureCelsius: 49
        )
        let rolledBackDate = now.addingTimeInterval(-3_600)
        var snapshot = SystemSnapshot.fixture
        snapshot.capturedAt = rolledBackDate
        let store = RecordingDashboardHistoryStore(restoredSamples: [futurePersistedSample])
        let model = AppModel(
            metricsProvider: IntegrationMetricsProvider(snapshots: [snapshot]),
            dashboardHistoryStore: store,
            dashboardHistoryNow: { rolledBackDate }
        )
        model.dataSource = .live

        await model.loadPersistedDashboardHistoryIfNeeded()
        await model.refreshAll()
        let deadline = ContinuousClock().now.advanced(by: .seconds(1))
        while await store.recordedSamples().isEmpty,
              ContinuousClock().now < deadline {
            try? await Task.sleep(for: .milliseconds(2))
        }

        let recorded = await store.recordedSamples()
        XCTAssertEqual(recorded.first?.date, rolledBackDate)
    }

    @MainActor
    func testRetentionUpdateUsesOnlySupportedValuesAndImmediatelyPrunesStore() async {
        let defaults = UserDefaults.standard
        let originalValue = defaults.object(forKey: DashboardHistoryRetention.storageKey)
        defer {
            if let originalValue {
                defaults.set(originalValue, forKey: DashboardHistoryRetention.storageKey)
            } else {
                defaults.removeObject(forKey: DashboardHistoryRetention.storageKey)
            }
        }
        defaults.removeObject(forKey: DashboardHistoryRetention.storageKey)
        let store = RecordingDashboardHistoryStore(restoredSamples: [])
        let model = AppModel(dashboardHistoryStore: store)
        model.dataSource = .live

        XCTAssertEqual(model.dashboardHistoryRetention, .threeDays)
        model.updateDashboardHistoryRetentionDays(7)
        let deadline = ContinuousClock().now.advanced(by: .seconds(1))
        while await store.retentionUpdates().isEmpty,
              ContinuousClock().now < deadline {
            try? await Task.sleep(for: .milliseconds(2))
        }

        XCTAssertEqual(model.dashboardHistoryRetention, .sevenDays)
        XCTAssertEqual(defaults.integer(forKey: DashboardHistoryRetention.storageKey), 7)
        let retentionUpdates = await store.retentionUpdates()
        XCTAssertEqual(retentionUpdates, [.sevenDays])
        model.updateDashboardHistoryRetentionDays(5)
        XCTAssertEqual(model.dashboardHistoryRetention, .sevenDays)
    }
}

private actor RecordingDashboardHistoryStore: DashboardHistoryPersisting {
    private let restoredSamples: [DashboardTelemetrySample]
    private var records: [DashboardTelemetrySample] = []
    private var updates: [DashboardHistoryRetention] = []

    init(restoredSamples: [DashboardTelemetrySample]) {
        self.restoredSamples = restoredSamples
    }

    func load(
        retention _: DashboardHistoryRetention,
        now _: Date
    ) -> DashboardHistoryLoadResult {
        DashboardHistoryLoadResult(samples: restoredSamples)
    }

    func record(
        _ sample: DashboardTelemetrySample,
        retention _: DashboardHistoryRetention,
        now _: Date
    ) {
        records.append(sample)
    }

    func updateRetention(
        _ retention: DashboardHistoryRetention,
        now _: Date
    ) -> DashboardHistoryLoadResult {
        updates.append(retention)
        return DashboardHistoryLoadResult(samples: restoredSamples)
    }

    func recordedSamples() -> [DashboardTelemetrySample] { records }
    func retentionUpdates() -> [DashboardHistoryRetention] { updates }
}

private actor IntegrationMetricsProvider: SystemMetricsProviding {
    private let snapshots: [SystemSnapshot]
    private var index = 0

    init(snapshots: [SystemSnapshot]) {
        self.snapshots = snapshots
    }

    func snapshot() -> SystemSnapshot {
        defer { index += 1 }
        return snapshots[min(index, snapshots.count - 1)]
    }
}
