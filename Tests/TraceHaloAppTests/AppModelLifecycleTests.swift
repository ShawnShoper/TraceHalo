import AppKit
import Foundation
import XCTest
@testable import TraceHaloApp
import TraceHaloCore

final class AppModelLifecycleTests: XCTestCase {
    @MainActor
    func testApplicationRemainsRunningAfterLastWindowCloses() {
        let delegate = TraceHaloApplicationDelegate(preferenceMigration: {})

        XCTAssertFalse(
            delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared)
        )
    }

    @MainActor
    func testMonitoringPublishesWithoutAnyWindowOrView() async throws {
        var firstSnapshot = SystemSnapshot.fixture
        firstSnapshot.cpu.totalPercent = 17
        var secondSnapshot = firstSnapshot
        secondSnapshot.cpu.totalPercent = 73

        let metrics = InMemorySequencedMetricsProvider(
            snapshots: [firstSnapshot, secondSnapshot]
        )
        let model = AppModel(metricsProvider: metrics)
        model.refreshInterval = 0
        model.startMonitoring()
        defer { model.stopMonitoring() }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2.5))
        while model.snapshot.cpu.totalPercent != secondSnapshot.cpu.totalPercent,
              clock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }

        let requestCount = await metrics.requestCount()
        XCTAssertGreaterThanOrEqual(requestCount, 2)
        XCTAssertEqual(model.snapshot.cpu.totalPercent, secondSnapshot.cpu.totalPercent)
    }

    @MainActor
    func testRepeatedLoadErrorDoesNotDiscardOtherSources() async {
        let model = AppModel(
            startupProvider: FailingStartupProvider(message: "startup failed"),
            applicationProvider: FailingApplicationProvider(message: "applications failed")
        )

        await model.loadStartupItemsIfNeeded()
        await model.loadApplicationsIfNeeded()
        await model.loadStartupItemsIfNeeded(force: true)

        XCTAssertEqual(
            model.lastError?.split(separator: "\n").map(String.init),
            ["启动项目：startup failed", "应用清单：applications failed"]
        )
    }

    @MainActor
    func testStorageHealthRefreshesOnlyAddedVolumesAndDropsRemovedVolumes() async {
        let volumeA = makeVolume(name: "A", path: "/Volumes/A")
        let volumeB = makeVolume(name: "B", path: "/Volumes/B")
        let volumeC = makeVolume(name: "C", path: "/Volumes/C")
        var firstSnapshot = SystemSnapshot.fixture
        firstSnapshot.volumes = [volumeA, volumeB]
        var secondSnapshot = firstSnapshot
        secondSnapshot.volumes = [volumeB, volumeC]

        let metrics = InMemorySequencedMetricsProvider(snapshots: [firstSnapshot, secondSnapshot])
        let health = RecordingStorageHealthProvider()
        let model = AppModel(metricsProvider: metrics, healthProvider: health)

        await model.refreshAll()
        await model.loadStorageHealthIfNeeded()
        let firstRequests = await health.requestedVolumeIDs()
        XCTAssertEqual(firstRequests, [volumeA.id, volumeB.id])
        XCTAssertEqual(Set(model.storageHealth.keys), Set([volumeA.id, volumeB.id]))

        await model.refreshAll()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while await health.requestedVolumeIDs().count < 3,
              clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        let secondRequests = await health.requestedVolumeIDs()
        XCTAssertEqual(secondRequests, [volumeA.id, volumeB.id, volumeC.id])
        XCTAssertEqual(Set(model.storageHealth.keys), Set([volumeB.id, volumeC.id]))
        XCTAssertNil(model.storageHealth[volumeA.id])
    }

    @MainActor
    func testSlowStorageHealthDoesNotBlockTelemetryPublication() async {
        let volume = makeVolume(name: "Slow", path: "/Volumes/Slow")
        var initialSnapshot = SystemSnapshot.fixture
        initialSnapshot.volumes = []
        var updatedSnapshot = initialSnapshot
        updatedSnapshot.cpu.totalPercent = 61
        updatedSnapshot.volumes = [volume]

        let metrics = InMemorySequencedMetricsProvider(
            snapshots: [initialSnapshot, updatedSnapshot]
        )
        let health = GatedStorageHealthProvider()
        let model = AppModel(metricsProvider: metrics, healthProvider: health)
        let refreshReturned = expectation(description: "telemetry refresh returned")

        await model.refreshAll()
        await model.loadStorageHealthIfNeeded()
        XCTAssertTrue(model.hasLoadedStorageHealth)

        let refreshTask = Task { @MainActor in
            await model.refreshAll()
            refreshReturned.fulfill()
        }

        let didStartHealthRefresh = await health.waitUntilStarted()
        XCTAssertTrue(didStartHealthRefresh)
        guard didStartHealthRefresh else {
            refreshTask.cancel()
            return
        }
        await fulfillment(of: [refreshReturned], timeout: 0.5)
        XCTAssertEqual(model.snapshot.cpu.totalPercent, 61)

        await health.finish()
        await refreshTask.value
    }

    @MainActor
    func testMemoryUsedMetricUsesPercentageForHistoryAndDisplay() async {
        var snapshot = SystemSnapshot.fixture
        snapshot.memory.totalBytes = 1_000
        snapshot.memory.usedBytes = 375
        let metrics = InMemorySequencedMetricsProvider(snapshots: [snapshot])
        let model = AppModel(metricsProvider: metrics)

        await model.refreshAll()

        XCTAssertEqual(model.history(for: .memoryUsed).last, 37.5)
        XCTAssertEqual(model.formattedValue(for: .memoryUsed), "38%")
    }

    @MainActor
    func testSystemReportedHealthyBatteryDoesNotRaiseDashboardAttention() async {
        var snapshot = SystemSnapshot.fixture
        snapshot.battery = BatteryState(
            availability: .available,
            chargePercent: 48,
            health: .good,
            healthBasis: .systemReported,
            maximumCapacityMAh: 6_086,
            designCapacityMAh: 6_249
        )
        let model = AppModel(
            metricsProvider: InMemorySequencedMetricsProvider(snapshots: [snapshot])
        )

        await model.refreshAll()

        XCTAssertEqual(model.overallState.title, OverallSystemState.normal.title)
    }

    @MainActor
    func testStartupPreloadRunsSequentialBatches() async {
        let recorder = PreloadOrderRecorder()
        let model = AppModel(
            startupProvider: OrderedStartupProvider(recorder: recorder),
            applicationProvider: OrderedApplicationProvider(recorder: recorder),
            healthProvider: OrderedStorageHealthProvider(recorder: recorder),
            startupPreloadSchedule: .immediate
        )

        await model.preloadToolData()

        let events = await recorder.events()
        XCTAssertEqual(Array(events.prefix(3)), ["startup", "applications", "storage"])
        XCTAssertTrue(model.hasLoadedStartupItems)
        XCTAssertTrue(model.hasLoadedApplications)
        XCTAssertTrue(model.hasLoadedStorageHealth)
    }

    @MainActor
    func testCancelledStartupPreloadDoesNotBeginInventoryScans() async {
        let recorder = PreloadOrderRecorder()
        let model = AppModel(
            startupProvider: OrderedStartupProvider(recorder: recorder),
            applicationProvider: OrderedApplicationProvider(recorder: recorder),
            healthProvider: OrderedStorageHealthProvider(recorder: recorder)
        )

        let preload = Task { await model.preloadToolData() }
        preload.cancel()
        await preload.value

        let events = await recorder.events()
        XCTAssertTrue(events.isEmpty)
        XCTAssertGreaterThan(StartupPreloadSchedule.standard.initialDelay, .zero)
        XCTAssertGreaterThan(StartupPreloadSchedule.standard.delayBetweenBatches, .zero)
    }

    func testDashboardHistorySkipsHighFrequencySamplesAndHasFixedCapacity() {
        let start = Date(timeIntervalSince1970: 1_000)
        let first = dashboardSample(date: start)

        XCTAssertNil(
            DashboardHistoryPolicy.appending(
                dashboardSample(
                    date: start.addingTimeInterval(
                        DashboardHistoryPolicy.minimumSampleInterval - 0.1
                    )
                ),
                to: [first]
            )
        )

        var history: [DashboardTelemetrySample] = []
        for index in 0 ..< DashboardHistoryPolicy.capacity + 3 {
            let sample = dashboardSample(
                date: start.addingTimeInterval(
                    Double(index) * DashboardHistoryPolicy.minimumSampleInterval
                )
            )
            if let next = DashboardHistoryPolicy.appending(sample, to: history) {
                history = next
            }
        }

        XCTAssertEqual(history.count, DashboardHistoryPolicy.capacity)
        XCTAssertEqual(
            history.first?.date,
            start.addingTimeInterval(3 * DashboardHistoryPolicy.minimumSampleInterval)
        )
    }

    @MainActor
    func testBackgroundRefreshDoesNotToggleUserActivityAndCancellationPreventsLatePublish() async {
        var staleSnapshot = SystemSnapshot.fixture
        staleSnapshot.cpu.totalPercent = 99
        let metrics = GatedMetricsProvider()
        let model = AppModel(metricsProvider: metrics)

        let refreshTask = Task { await model.runRefreshLoop() }
        await metrics.waitUntilStarted()

        XCTAssertFalse(model.isRefreshing)
        refreshTask.cancel()
        await metrics.finish(with: staleSnapshot)
        await refreshTask.value

        XCTAssertFalse(model.isRefreshing)
        XCTAssertEqual(model.snapshot.cpu.totalPercent, SystemSnapshot.fixture.cpu.totalPercent)
    }

    @MainActor
    func testManualRefreshShowsActivityUntilSnapshotPublishes() async {
        var refreshedSnapshot = SystemSnapshot.fixture
        refreshedSnapshot.cpu.totalPercent = 57
        let metrics = GatedMetricsProvider()
        let model = AppModel(metricsProvider: metrics)

        let refreshTask = Task { await model.refreshAll() }
        await metrics.waitUntilStarted()

        XCTAssertTrue(model.isRefreshing)
        await metrics.finish(with: refreshedSnapshot)
        await refreshTask.value

        XCTAssertFalse(model.isRefreshing)
        XCTAssertEqual(model.snapshot.cpu.totalPercent, 57)
    }

    private func makeVolume(name: String, path: String) -> StorageVolume {
        StorageVolume(
            name: name,
            path: path,
            totalBytes: 1_000,
            availableBytes: 400,
            isInternal: false,
            isRemovable: true,
            isReadOnly: false,
            isEncrypted: false,
            fileSystem: "APFS"
        )
    }

    private func dashboardSample(date: Date) -> DashboardTelemetrySample {
        DashboardTelemetrySample(
            date: date,
            cpuPercent: 20,
            gpuPercent: 10,
            memoryPressurePercent: 30,
            storageUsedPercent: 40,
            networkReceivedBytesPerSecond: 1_000,
            networkSentBytesPerSecond: 500,
            temperatureCelsius: 45
        )
    }
}

private struct TestProviderError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

private struct FailingStartupProvider: StartupItemProviding {
    let message: String

    func items() async throws -> [StartupItem] {
        throw TestProviderError(message: message)
    }
}

private struct FailingApplicationProvider: ApplicationProviding {
    let message: String

    func applications() async throws -> [ApplicationCandidate] {
        throw TestProviderError(message: message)
    }
}

private actor PreloadOrderRecorder {
    private var recordedEvents: [String] = []

    func record(_ event: String) {
        recordedEvents.append(event)
    }

    func events() -> [String] {
        recordedEvents
    }
}

private struct OrderedStartupProvider: StartupItemProviding {
    let recorder: PreloadOrderRecorder

    func items() async throws -> [StartupItem] {
        await recorder.record("startup")
        return []
    }
}

private struct OrderedApplicationProvider: ApplicationProviding {
    let recorder: PreloadOrderRecorder

    func applications() async throws -> [ApplicationCandidate] {
        await recorder.record("applications")
        return []
    }
}

private struct OrderedStorageHealthProvider: StorageHealthProviding {
    let recorder: PreloadOrderRecorder

    func health(for volume: StorageVolume) async -> StorageHealth {
        await recorder.record("storage")
        return StorageHealth(availability: .available, status: volume.name, metrics: [])
    }
}

private actor InMemorySequencedMetricsProvider: SystemMetricsProviding {
    private let snapshots: [SystemSnapshot]
    private var index = 0
    private var requests = 0

    init(snapshots: [SystemSnapshot]) {
        self.snapshots = snapshots
    }

    func snapshot() async -> SystemSnapshot {
        guard !snapshots.isEmpty else { return .fixture }
        requests += 1
        let snapshot = snapshots[min(index, snapshots.count - 1)]
        index += 1
        return snapshot
    }

    func requestCount() -> Int {
        requests
    }
}

private actor RecordingStorageHealthProvider: StorageHealthProviding {
    private var requests: [String] = []

    func health(for volume: StorageVolume) async -> StorageHealth {
        requests.append(volume.id)
        return StorageHealth(
            availability: .available,
            status: volume.name,
            metrics: []
        )
    }

    func requestedVolumeIDs() -> [String] {
        requests
    }
}

private actor GatedMetricsProvider: SystemMetricsProviding {
    private var started = false
    private var continuation: CheckedContinuation<SystemSnapshot, Never>?

    func snapshot() async -> SystemSnapshot {
        started = true
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    func finish(with snapshot: SystemSnapshot) {
        continuation?.resume(returning: snapshot)
        continuation = nil
    }
}

private actor GatedStorageHealthProvider: StorageHealthProviding {
    private var started = false
    private var continuation: CheckedContinuation<StorageHealth, Never>?

    func health(for volume: StorageVolume) async -> StorageHealth {
        started = true
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted(timeout: Duration = .seconds(1)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !started, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(2))
        }
        return started
    }

    func finish() {
        continuation?.resume(
            returning: StorageHealth(
                availability: .available,
                status: "完成",
                metrics: []
            )
        )
        continuation = nil
    }
}
