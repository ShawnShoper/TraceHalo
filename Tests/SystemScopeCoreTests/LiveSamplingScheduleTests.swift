import Foundation
import XCTest
@testable import SystemScopeCore

final class LiveSamplingScheduleTests: XCTestCase {
    func testKeepsHighCostDomainsInsideTheirIntendedCadenceBands() {
        XCTAssertEqual(LiveSamplingDomain.processes.interval, 10)
        XCTAssertEqual(LiveSamplingDomain.wifiLinkDetails.interval, 10)
        XCTAssertEqual(LiveSamplingDomain.storagePerformance.interval, 3)
        XCTAssertEqual(LiveSamplingDomain.gpuPerformance.interval, 3)
        XCTAssertEqual(LiveSamplingDomain.volumes.interval, 30)
        XCTAssertEqual(LiveSamplingDomain.battery.interval, 30)
        XCTAssertEqual(LiveSamplingDomain.inputDevices.interval, 30)
        XCTAssertEqual(LiveSamplingDomain.gpuInventory.interval, 30)
        XCTAssertEqual(LiveSamplingDomain.displayInventory.interval, 30)
        XCTAssertEqual(LiveSamplingDomain.networkDisplayNames.interval, 60)
    }

    func testRefreshesEachDomainIndependentlyAtTheIntervalBoundary() {
        let start = Date(timeIntervalSinceReferenceDate: 10_000)
        var schedule = LiveSamplingSchedule()

        XCTAssertTrue(schedule.consumeRefresh(for: .processes, at: start))
        XCTAssertTrue(schedule.consumeRefresh(for: .gpuPerformance, at: start))

        XCTAssertFalse(schedule.consumeRefresh(
            for: .processes,
            at: start.addingTimeInterval(9.999)
        ))
        XCTAssertTrue(schedule.consumeRefresh(
            for: .gpuPerformance,
            at: start.addingTimeInterval(3)
        ))
        XCTAssertTrue(schedule.consumeRefresh(
            for: .processes,
            at: start.addingTimeInterval(10)
        ))
    }

    func testEmptyGPUInventoryUsesBackoffInsteadOfRetryingEveryFrame() {
        let start = Date(timeIntervalSinceReferenceDate: 20_000)
        var schedule = LiveSamplingSchedule()
        var inventoryReadCount = 0

        for offset in [0.0, 1, 2, 5, 10, 29.999] {
            if schedule.consumeRefresh(
                for: .gpuInventory,
                at: start.addingTimeInterval(offset)
            ) {
                inventoryReadCount += 1
                let loadedInventory: [Int] = []
                XCTAssertTrue(loadedInventory.isEmpty)
            }
        }

        XCTAssertEqual(inventoryReadCount, 1)
        XCTAssertTrue(schedule.consumeRefresh(
            for: .gpuInventory,
            at: start.addingTimeInterval(30)
        ))
    }

    func testAllDomainsAreDueOnTheirFirstUse() {
        let now = Date(timeIntervalSinceReferenceDate: 30_000)
        var schedule = LiveSamplingSchedule()

        for domain in LiveSamplingDomain.allCases {
            XCTAssertTrue(schedule.consumeRefresh(for: domain, at: now))
        }
    }

    func testWallClockRollbackCannotFreezeASamplingDomain() {
        let now = Date(timeIntervalSinceReferenceDate: 40_000)
        var schedule = LiveSamplingSchedule()

        XCTAssertTrue(schedule.consumeRefresh(for: .battery, at: now))
        XCTAssertTrue(schedule.consumeRefresh(
            for: .battery,
            at: now.addingTimeInterval(-60)
        ))
    }
}
