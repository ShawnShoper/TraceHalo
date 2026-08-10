import AppKit
import Foundation
import XCTest
@testable import TraceHaloApp
import TraceHaloCore

final class AppModelLifecycleTests: XCTestCase {
    func testBatteryAwareRefreshUsesReportedPowerSourceInsteadOfChargingState() {
        let pluggedInButNotCharging = BatteryState(
            availability: .available,
            isCharging: false,
            isOnExternalPower: true
        )
        let runningOnBattery = BatteryState(
            availability: .available,
            isCharging: false,
            isOnExternalPower: false
        )

        XCTAssertEqual(
            MonitoringRefreshPolicy.effectiveInterval(
                baseInterval: 2,
                reducesFrequencyOnBattery: true,
                battery: pluggedInButNotCharging
            ),
            2
        )
        XCTAssertEqual(
            MonitoringRefreshPolicy.effectiveInterval(
                baseInterval: 2,
                reducesFrequencyOnBattery: true,
                battery: runningOnBattery
            ),
            10
        )
    }

    func testBatteryAwareRefreshIgnoresUnavailableBatteryAndDisabledThrottle() {
        let noBattery = BatteryState(availability: .unavailable(reason: "desktop"))
        let runningOnBattery = BatteryState(
            availability: .available,
            isCharging: false,
            isOnExternalPower: false
        )

        XCTAssertEqual(
            MonitoringRefreshPolicy.effectiveInterval(
                baseInterval: 1,
                reducesFrequencyOnBattery: true,
                battery: noBattery
            ),
            1
        )
        XCTAssertEqual(
            MonitoringRefreshPolicy.effectiveInterval(
                baseInterval: 1,
                reducesFrequencyOnBattery: false,
                battery: runningOnBattery
            ),
            1
        )
    }

    @MainActor
    func testConfiguredLiveModelBlocksTheFirstFrameButFixtureQAIsImmediatelyReady() {
        let liveModel = AppModel.configured(arguments: ["TraceHalo"])
        let fixtureModel = AppModel.configured(arguments: ["TraceHalo", "--fixture-data"])

        XCTAssertEqual(liveModel.startupPreloadStatus.phase, .loading)
        XCTAssertEqual(liveModel.startupPreloadStatus.activeStage, .telemetry)
        XCTAssertTrue(
            StartupPresentationPolicy.showsOverlay(
                status: liveModel.startupPreloadStatus,
                hasLoadedSnapshot: liveModel.hasLoadedSnapshot
            )
        )
        XCTAssertEqual(fixtureModel.startupPreloadStatus.phase, .idle)
        XCTAssertFalse(
            StartupPresentationPolicy.showsOverlay(
                status: fixtureModel.startupPreloadStatus,
                hasLoadedSnapshot: fixtureModel.hasLoadedSnapshot
            )
        )
    }

    func testReadyTelemetryDegradationReleasesTheBlockingOverlay() {
        var status = StartupPreloadStatus()
        status.beginIfNeeded()
        status.complete(.telemetry, degraded: true)
        status.complete(.startupItems, degraded: false)
        status.complete(.applications, degraded: false)
        status.complete(.storageHealth, degraded: false)
        status.finish()

        XCTAssertEqual(status.phase, .ready)
        XCTAssertEqual(status.degradedStages, [.telemetry])
        XCTAssertFalse(
            StartupPresentationPolicy.showsOverlay(
                status: status,
                hasLoadedSnapshot: false
            ),
            "A settled telemetry failure must expose the degraded cached content instead of blocking forever"
        )
    }

    @MainActor
    func testApplicationRemainsRunningAfterLastWindowCloses() {
        let delegate = TraceHaloApplicationDelegate()

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
        XCTAssertEqual(model.startupPreloadStatus.phase, .ready)
        XCTAssertEqual(
            model.startupPreloadStatus.completedStages,
            Set(StartupPreloadStage.allCases)
        )
        XCTAssertTrue(model.startupPreloadStatus.degradedStages.isEmpty)
        XCTAssertEqual(model.startupPreloadStatus.progress, 1)

        await model.loadStartupItemsIfNeeded()
        await model.loadApplicationsIfNeeded()
        await model.loadStorageHealthIfNeeded()

        let eventsAfterMenuEntries = await recorder.events()
        XCTAssertEqual(
            eventsAfterMenuEntries,
            events,
            "Returning to an already prepared menu must reuse its cached model data"
        )
    }

    @MainActor
    func testStartupPreloadSettlesFailuresAndDoesNotRetryThemOnMenuEntry() async {
        let recorder = PreloadOrderRecorder()
        let model = AppModel(
            startupProvider: OrderedFailingStartupProvider(recorder: recorder),
            applicationProvider: OrderedFailingApplicationProvider(recorder: recorder),
            healthProvider: OrderedStorageHealthProvider(recorder: recorder),
            startupPreloadSchedule: .immediate
        )

        await model.preloadToolData()

        XCTAssertEqual(model.startupPreloadStatus.phase, .ready)
        XCTAssertEqual(
            model.startupPreloadStatus.completedStages,
            Set(StartupPreloadStage.allCases)
        )
        XCTAssertEqual(
            model.startupPreloadStatus.degradedStages,
            Set([.startupItems, .applications])
        )
        XCTAssertTrue(model.hasAttemptedStartupItems)
        XCTAssertTrue(model.hasAttemptedApplications)
        XCTAssertTrue(model.hasAttemptedStorageHealth)
        XCTAssertFalse(model.hasLoadedStartupItems)
        XCTAssertFalse(model.hasLoadedApplications)
        XCTAssertTrue(model.hasLoadedStorageHealth)

        let eventsAfterPreload = await recorder.events()
        await model.loadStartupItemsIfNeeded()
        await model.loadApplicationsIfNeeded()
        let eventsAfterMenuEntries = await recorder.events()
        XCTAssertEqual(
            eventsAfterMenuEntries,
            eventsAfterPreload,
            "A degraded menu should show its cached error instead of rescanning on every visit"
        )

        await model.loadStartupItemsIfNeeded(force: true)
        await model.loadApplicationsIfNeeded(force: true)
        let eventsAfterExplicitRetry = await recorder.events()
        XCTAssertEqual(eventsAfterExplicitRetry.filter { $0 == "startup" }.count, 2)
        XCTAssertEqual(eventsAfterExplicitRetry.filter { $0 == "applications" }.count, 2)
    }

    @MainActor
    func testStartupReadinessWaitsForEveryRequiredPreloadStage() async {
        let applications = GatedApplicationProvider()
        let model = AppModel(
            applicationProvider: applications,
            startupPreloadSchedule: .immediate
        )
        model.startMonitoring()
        defer { model.stopMonitoring() }

        let didStartApplications = await applications.waitUntilStarted()
        XCTAssertTrue(didStartApplications)
        XCTAssertEqual(model.startupPreloadStatus.phase, .loading)
        XCTAssertEqual(model.startupPreloadStatus.activeStage, .applications)
        XCTAssertTrue(model.startupPreloadStatus.completedStages.contains(.telemetry))
        XCTAssertTrue(model.startupPreloadStatus.completedStages.contains(.startupItems))
        XCTAssertFalse(model.startupPreloadStatus.completedStages.contains(.applications))

        await applications.finish()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while model.startupPreloadStatus.phase != .ready, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(2))
        }

        XCTAssertEqual(model.startupPreloadStatus.phase, .ready)
        XCTAssertEqual(
            model.startupPreloadStatus.completedStages,
            Set(StartupPreloadStage.allCases)
        )
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
        XCTAssertEqual(StartupPreloadSchedule.standard, .immediate)
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

private struct OrderedFailingStartupProvider: StartupItemProviding {
    let recorder: PreloadOrderRecorder

    func items() async throws -> [StartupItem] {
        await recorder.record("startup")
        throw TestProviderError(message: "startup preload failed")
    }
}

private struct OrderedFailingApplicationProvider: ApplicationProviding {
    let recorder: PreloadOrderRecorder

    func applications() async throws -> [ApplicationCandidate] {
        await recorder.record("applications")
        throw TestProviderError(message: "application preload failed")
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

private actor GatedApplicationProvider: ApplicationProviding {
    private var started = false
    private var continuation: CheckedContinuation<[ApplicationCandidate], Never>?

    func applications() async throws -> [ApplicationCandidate] {
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
        continuation?.resume(returning: [])
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
