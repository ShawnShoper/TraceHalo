import XCTest
@testable import TraceHaloApp
import TraceHaloCore

final class StorageWorkspacePresentationTests: XCTestCase {
    func testCriticalHealthStatusesNeverPresentAsNormal() {
        for status in ["failing", "需要维护"] {
            let presentation = StorageHealthPresentation.make(
                from: health(status: status)
            )

            XCTAssertEqual(presentation.tone, .critical, "\(status) 不得显示为正常状态")
            XCTAssertNotEqual(presentation.title, "正常")
        }
    }

    func testNegatedHealthStatusesNeverPresentAsNormal() {
        for status in ["not verified", "not good"] {
            let presentation = StorageHealthPresentation.make(
                from: health(status: status)
            )

            XCTAssertEqual(presentation.tone, .critical, "\(status) 不得被 verified/good 子串误判")
            XCTAssertNotEqual(presentation.title, "正常")
        }
    }

    func testExplicitHealthyStatusesPresentAsNormal() {
        for status in ["verified", "good", "正常"] {
            let presentation = StorageHealthPresentation.make(
                from: health(status: status)
            )

            XCTAssertEqual(presentation.tone, .normal)
            XCTAssertEqual(presentation.title, "正常")
        }
    }

    func testUnknownOptionalVolumeFlagsSaySystemDidNotProvideThem() {
        let volume = StorageVolume(
            name: "External",
            path: "/Volumes/External",
            totalBytes: 1_000,
            availableBytes: 500,
            isInternal: nil,
            isRemovable: nil,
            isReadOnly: nil,
            isEncrypted: nil
        )

        let presentation = StorageVolumePresentation.make(volume: volume, health: nil)

        XCTAssertEqual(presentation.storageType, "系统未提供")
        XCTAssertEqual(presentation.access, "系统未提供")
        XCTAssertEqual(presentation.encryption, "系统未提供")
        XCTAssertEqual(presentation.medium, "系统未提供")
    }

    func testHealthMetricsTakePriorityForDeviceConnectionAndMedium() {
        let volume = StorageVolume(
            name: "External",
            path: "/Volumes/External",
            totalBytes: 1_000,
            availableBytes: 500,
            isInternal: false,
            isRemovable: true
        )
        let health = StorageHealth(
            availability: .available,
            metrics: [
                StorageHealthMetric(name: "设备", value: "disk9s1"),
                StorageHealthMetric(name: "连接", value: "Thunderbolt / USB4"),
                StorageHealthMetric(name: "介质类型", value: "固态存储")
            ]
        )

        let presentation = StorageVolumePresentation.make(volume: volume, health: health)

        XCTAssertEqual(presentation.device, "disk9s1")
        XCTAssertEqual(presentation.connection, "Thunderbolt / USB4")
        XCTAssertEqual(presentation.medium, "固态存储")
    }

    func testVolumeMenuCapsLongNamesAtAnExplicitReadableWidth() {
        XCTAssertEqual(StorageWorkspaceLayout.volumeMenuMaximumWidth, 300)
        XCTAssertGreaterThanOrEqual(StorageWorkspaceLayout.volumeMenuMaximumWidth, 240)
        XCTAssertLessThanOrEqual(StorageWorkspaceLayout.volumeMenuMaximumWidth, 320)
    }

    @MainActor
    func testDashboardUsesTheSameStorageHealthSeverityAsStoragePage() {
        for status in ["not verified", "not good", "bad", "poor", "warning"] {
            let model = AppModel()
            model.storageHealth = ["/": health(status: status)]

            XCTAssertEqual(
                model.overallState,
                .attention,
                "\(status) 在概览与存储页必须使用同一严重度"
            )
        }
    }

    func testLineRevealContinuesWhenSixtySecondWindowKeepsAStablePointCount() {
        let start = Date(timeIntervalSince1970: 1_000)
        let oldSamples = [sample(at: start, read: 10), sample(at: start.addingTimeInterval(3), read: 20)]
        let newSamples = [sample(at: start.addingTimeInterval(3), read: 20), sample(at: start.addingTimeInterval(6), read: 30)]

        XCTAssertEqual(oldSamples.count, newSamples.count)
        XCTAssertTrue(
            StorageIOLineAnimationPolicy.shouldRevealLatestSegment(
                oldSamples: oldSamples,
                newSamples: newSamples,
                reduceMotion: false
            )
        )
        XCTAssertFalse(
            StorageIOLineAnimationPolicy.shouldRevealLatestSegment(
                oldSamples: oldSamples,
                newSamples: newSamples,
                reduceMotion: true
            )
        )
    }

    private func health(status: String) -> StorageHealth {
        StorageHealth(availability: .available, status: status)
    }

    private func sample(at date: Date, read: Double) -> StorageIOHistorySample {
        StorageIOHistorySample(
            capturedAt: date,
            readBytesPerSecond: read,
            writeBytesPerSecond: read / 2,
            readOperationsPerSecond: 10,
            writeOperationsPerSecond: 5
        )
    }
}
