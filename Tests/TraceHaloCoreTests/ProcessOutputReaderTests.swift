import Darwin
import Foundation
import XCTest
@testable import TraceHaloCore

final class ProcessOutputReaderTests: XCTestCase {
    func testReadsSuccessfulOutput() throws {
        let process = command("printf 'storage-info'")
        let output = try ProcessOutputReader.read(from: process, timeout: 2)
        XCTAssertEqual(String(decoding: output, as: UTF8.self), "storage-info")
        XCTAssertFalse(process.isRunning)
    }

    func testDrainsOutputLargerThanThePipeBufferWhileTheCommandRuns() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/head")
        process.arguments = ["-c", "262144", "/dev/zero"]

        let output = try ProcessOutputReader.read(from: process, timeout: 2)

        XCTAssertEqual(output.count, 262_144)
        XCTAssertFalse(process.isRunning)
    }

    func testTimesOutAndStopsAHungCommand() {
        let process = command("exec /bin/sleep 5")
        let start = ContinuousClock.now

        XCTAssertThrowsError(try ProcessOutputReader.read(from: process, timeout: 0.1)) {
            XCTAssertEqual($0 as? ProcessOutputReader.Failure, .timedOut)
        }

        XCTAssertLessThan(start.duration(to: .now), .seconds(2))
        XCTAssertFalse(process.isRunning)
    }

    func testKillsACommandThatIgnoresTermination() {
        let process = command("trap '' TERM; exec /bin/sleep 5")
        let start = ContinuousClock.now

        XCTAssertThrowsError(try ProcessOutputReader.read(from: process, timeout: 0.15)) {
            XCTAssertEqual($0 as? ProcessOutputReader.Failure, .timedOut)
        }

        XCTAssertLessThan(start.duration(to: .now), .seconds(2))
        XCTAssertFalse(process.isRunning)
        XCTAssertEqual(process.terminationStatus, SIGKILL)
    }

    func testClosingStdoutDoesNotLetAHungCommandEscapeTheDeadline() {
        let process = command("exec 1>&-; exec /bin/sleep 5")

        XCTAssertThrowsError(try ProcessOutputReader.read(from: process, timeout: 0.1)) {
            XCTAssertEqual($0 as? ProcessOutputReader.Failure, .timedOut)
        }

        XCTAssertFalse(process.isRunning)
    }

    func testCancellationStopsTheRunningCommand() {
        let process = command("exec /bin/sleep 5")
        var cancellationChecks = 0

        XCTAssertThrowsError(try ProcessOutputReader.read(from: process, timeout: 2, isCancelled: {
            cancellationChecks += 1
            return cancellationChecks >= 3
        })) {
            XCTAssertTrue($0 is CancellationError)
        }

        XCTAssertFalse(process.isRunning)
    }

    func testRejectsExcessOutputAndStopsTheCommand() {
        let process = command("while :; do printf '0123456789'; done")

        XCTAssertThrowsError(try ProcessOutputReader.read(from: process, timeout: 2, maximumOutputBytes: 1024)) {
            XCTAssertEqual($0 as? ProcessOutputReader.Failure, .outputTooLarge)
        }

        XCTAssertFalse(process.isRunning)
    }

    func testNonzeroExitDoesNotReturnPartialOutputAsSuccess() {
        let process = command("printf 'partial'; exit 7")

        XCTAssertThrowsError(try ProcessOutputReader.read(from: process, timeout: 2)) {
            XCTAssertEqual($0 as? ProcessOutputReader.Failure, .unsuccessfulExit(7))
        }
    }

    func testLaunchFailureReturnsAnErrorWithoutStartingAProcess() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/private/tmp/nonexistent-tracehalo-command-\(UUID())")

        XCTAssertThrowsError(try ProcessOutputReader.read(from: process, timeout: 2))
        XCTAssertFalse(process.isRunning)
    }

    func testStorageHealthPreservesCapacityWhenTheCommandTimesOut() async {
        let service = StorageHealthService(readDiskInfo: { _ in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sleep")
            process.arguments = ["5"]
            guard let data = try? ProcessOutputReader.read(from: process, timeout: 0.1) else { return nil }
            return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
        })
        let volume = StorageVolume(name: "Fixture", path: "/", totalBytes: 1_048_576, availableBytes: 262_144)
        let start = ContinuousClock.now

        let health = await service.health(for: volume)

        XCTAssertLessThan(start.duration(to: .now), .seconds(2))
        XCTAssertFalse(health.availability.isAvailable)
        XCTAssertEqual(health.metrics.first { $0.kind == .capacity }?.value, MetricFormatter.bytes(volume.totalBytes))
        XCTAssertEqual(health.metrics.first { $0.kind == .available }?.value, MetricFormatter.bytes(volume.availableBytes))
        XCTAssertNil(health.metrics.first { $0.kind == .smart })
    }

    private func command(_ script: String) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        return process
    }
}
