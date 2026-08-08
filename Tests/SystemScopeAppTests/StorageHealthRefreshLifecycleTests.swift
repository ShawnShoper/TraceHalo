import Foundation
import XCTest
@testable import SystemScopeApp
import SystemScopeCore

final class StorageHealthRefreshLifecycleTests: XCTestCase {
    func testStalePolicyUsesFiveMinuteBoundaryWithoutTimers() {
        let loadedAt = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(StorageHealthRefreshPolicy.defaultStaleInterval, 300)
        XCTAssertTrue(
            StorageHealthRefreshPolicy.isStale(
                lastLoadedAt: nil,
                now: loadedAt
            )
        )
        XCTAssertFalse(
            StorageHealthRefreshPolicy.isStale(
                lastLoadedAt: loadedAt,
                now: loadedAt.addingTimeInterval(299.999)
            )
        )
        XCTAssertTrue(
            StorageHealthRefreshPolicy.isStale(
                lastLoadedAt: loadedAt,
                now: loadedAt.addingTimeInterval(300)
            )
        )
    }

    @MainActor
    func testStaleHealthRefreshRunsOffTelemetryChainAndDeduplicatesWhileInFlight() async {
        let startedAt = Date(timeIntervalSince1970: 10_000)
        let clock = InMemoryStorageHealthClock(now: startedAt)
        let healthProvider = ControllableStorageHealthProvider()
        var snapshot = SystemSnapshot.fixture
        snapshot.volumes = [makeVolume()]
        let model = AppModel(
            metricsProvider: RepeatingStorageHealthMetricsProvider(snapshot: snapshot),
            healthProvider: healthProvider,
            storageHealthNow: { clock.now }
        )

        await model.refreshAll()
        await model.loadStorageHealthIfNeeded()

        var requestCount = await healthProvider.requestCount()
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(model.storageHealthLastLoadedAt, startedAt)

        clock.now = startedAt.addingTimeInterval(299)
        await model.refreshAll()
        await allowScheduledTasksToRun()
        requestCount = await healthProvider.requestCount()
        XCTAssertEqual(requestCount, 1)

        clock.now = startedAt.addingTimeInterval(300)
        await healthProvider.gateNextRequest()
        await model.refreshAll()

        await waitForRequestCount(2, from: healthProvider)
        requestCount = await healthProvider.requestCount()
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(model.storageHealthLastLoadedAt, startedAt)

        // A slow SMART query must not hold the telemetry refresh, and repeated
        // two-second frames must not start duplicate health-provider work.
        await model.refreshAll()
        await allowScheduledTasksToRun()
        requestCount = await healthProvider.requestCount()
        XCTAssertEqual(requestCount, 2)

        await healthProvider.finishGatedRequest()
        await waitForLastLoadedDate(
            startedAt.addingTimeInterval(300),
            model: model
        )

        await model.refreshAll()
        await allowScheduledTasksToRun()
        requestCount = await healthProvider.requestCount()
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(
            model.storageHealthLastLoadedAt,
            startedAt.addingTimeInterval(300)
        )
    }

    private func makeVolume() -> StorageVolume {
        StorageVolume(
            name: "Macintosh HD",
            path: "/",
            totalBytes: 1_000,
            availableBytes: 400,
            isInternal: true,
            isRemovable: false,
            isReadOnly: false,
            isEncrypted: true,
            fileSystem: "APFS"
        )
    }

    @MainActor
    private func allowScheduledTasksToRun() async {
        for _ in 0 ..< 20 {
            await Task.yield()
        }
    }

    @MainActor
    private func waitForRequestCount(
        _ expectedCount: Int,
        from provider: ControllableStorageHealthProvider
    ) async {
        for _ in 0 ..< 1_000 {
            if await provider.requestCount() == expectedCount {
                return
            }
            await Task.yield()
        }
        XCTFail("后台存储健康刷新未启动")
    }

    @MainActor
    private func waitForLastLoadedDate(
        _ expectedDate: Date,
        model: AppModel
    ) async {
        for _ in 0 ..< 1_000 {
            if model.storageHealthLastLoadedAt == expectedDate {
                return
            }
            await Task.yield()
        }
        XCTFail("后台存储健康刷新未完成")
    }
}

@MainActor
private final class InMemoryStorageHealthClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

private actor RepeatingStorageHealthMetricsProvider: SystemMetricsProviding {
    let storedSnapshot: SystemSnapshot

    init(snapshot: SystemSnapshot) {
        storedSnapshot = snapshot
    }

    func snapshot() async -> SystemSnapshot {
        storedSnapshot
    }
}

private actor ControllableStorageHealthProvider: StorageHealthProviding {
    private var requests = 0
    private var gatesNextRequest = false
    private var continuation: CheckedContinuation<StorageHealth, Never>?

    func gateNextRequest() {
        gatesNextRequest = true
    }

    func health(for volume: StorageVolume) async -> StorageHealth {
        requests += 1
        guard gatesNextRequest else {
            return healthResult(for: volume)
        }

        gatesNextRequest = false
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func requestCount() -> Int {
        requests
    }

    func finishGatedRequest() {
        continuation?.resume(
            returning: StorageHealth(
                availability: .available,
                status: "正常",
                metrics: []
            )
        )
        continuation = nil
    }

    private func healthResult(for volume: StorageVolume) -> StorageHealth {
        StorageHealth(
            availability: .available,
            status: volume.name,
            metrics: []
        )
    }
}
