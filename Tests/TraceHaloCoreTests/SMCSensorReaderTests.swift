import Foundation
import XCTest
@testable import TraceHaloCore

final class SMCSensorReaderTests: XCTestCase {
    func testSMCWireStructureHasExpectedABI() {
        XCTAssertEqual(MemoryLayout<SMCKeyData>.stride, 80)
    }

    func testNumericDecodersUseDocumentedByteOrderAndScaling() throws {
        XCTAssertEqual(
            try XCTUnwrap(SMCValueDecoder.double(from: floatValue(key: "TEST", 42.5))),
            42.5,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            try XCTUnwrap(SMCValueDecoder.double(from: rawValue(key: "TEST", type: "fpe2", [0x1f, 0x40]))),
            2_000,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            try XCTUnwrap(SMCValueDecoder.double(from: rawValue(key: "TEST", type: "sp78", [0x2a, 0x80]))),
            42.5,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            try XCTUnwrap(SMCValueDecoder.double(from: rawValue(key: "TEST", type: "sp78", [0xfd, 0x80]))),
            -2.5,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            SMCValueDecoder.double(from: rawValue(key: "TEST", type: "ui32", [0, 0, 1, 0])),
            256
        )
        XCTAssertNil(SMCValueDecoder.double(from: rawValue(key: "TEST", type: "flt ", [0, 0])))
        XCTAssertNil(SMCValueDecoder.double(from: rawValue(key: "TEST", type: "????", [1, 2, 3, 4])))
    }

    func testAppleSiliconCatalogIsUniqueAndUsesFourByteKeys() {
        let m1Ultra = SMCTemperatureCatalog.definitions(forChipName: "Apple M1 Ultra")
        let m3 = SMCTemperatureCatalog.definitions(forChipName: "Apple M3 Max")
        let m5 = SMCTemperatureCatalog.definitions(forChipName: "Apple M5")

        XCTAssertTrue(m1Ultra.contains { $0.key == "TC10" })
        XCTAssertTrue(m1Ultra.contains { $0.key == "Tp09" })
        XCTAssertTrue(m1Ultra.contains { $0.key == "Tg05" })
        XCTAssertTrue(m3.contains { $0.key == "Tf04" })
        XCTAssertTrue(m5.contains { $0.key == "Tp00" })

        for definitions in [m1Ultra, m3, m5] {
            XCTAssertEqual(Set(definitions.map(\.key)).count, definitions.count)
            XCTAssertTrue(definitions.allSatisfy { $0.key.utf8.count == 4 })
        }
    }

    func testSnapshotReadsTwoFansAndRealTemperatureValues() async throws {
        let transport = FakeSMCTransport(values: [
            "TCMz": floatValue(key: "TCMz", 61.5),
            "FNum": rawValue(key: "FNum", type: "ui8 ", [2]),
            "F0Ac": floatValue(key: "F0Ac", 2_100),
            "F0Mn": floatValue(key: "F0Mn", 1_200),
            "F0Mx": floatValue(key: "F0Mx", 5_000),
            "F0Tg": floatValue(key: "F0Tg", 2_300),
            "F1Ac": rawValue(key: "F1Ac", type: "fpe2", [0x23, 0x28]),
            "F1Mn": floatValue(key: "F1Mn", 1_250),
            "F1Mx": floatValue(key: "F1Mx", 5_100),
            "F1Tg": floatValue(key: "F1Tg", 2_450)
        ])
        let reader = makeReader(transport: transport)

        let snapshot = await reader.snapshot()

        XCTAssertEqual(snapshot.availability, .available)
        XCTAssertEqual(try XCTUnwrap(snapshot.cpuTemperatureCelsius), 61.5, accuracy: 0.000_1)
        XCTAssertNil(snapshot.gpuTemperatureCelsius)
        XCTAssertEqual(snapshot.fans.count, 2)
        XCTAssertEqual(snapshot.fans[0], FanState(
            name: "Fan 1",
            currentRPM: 2_100,
            minimumRPM: 1_200,
            maximumRPM: 5_000,
            targetRPM: 2_300
        ))
        XCTAssertEqual(snapshot.fans[1].name, "Fan 2")
        XCTAssertEqual(snapshot.fans[1].currentRPM, 2_250)
        XCTAssertEqual(snapshot.fans[1].minimumRPM, 1_250)
        XCTAssertEqual(snapshot.fans[1].maximumRPM, 5_100)
        XCTAssertEqual(snapshot.fans[1].targetRPM, 2_450)
    }

    func testMissingActualFanSpeedDoesNotBecomeZero() async {
        let transport = FakeSMCTransport(values: [
            "TCMz": floatValue(key: "TCMz", 58),
            "FNum": rawValue(key: "FNum", type: "ui8 ", [1])
        ])
        let reader = makeReader(transport: transport)

        let snapshot = await reader.snapshot()

        XCTAssertEqual(snapshot.availability, .available)
        XCTAssertTrue(snapshot.fans.isEmpty)
        XCTAssertEqual(snapshot.cpuTemperatureCelsius, 58)
    }

    func testAppleSMCTemperaturesPreserveSensorGroups() async {
        let transport = FakeSMCTransport(values: [
            "TCMz": floatValue(key: "TCMz", 52),
            "TG0D": floatValue(key: "TG0D", 46),
            "Tm0P": floatValue(key: "Tm0P", 41),
            "FNum": rawValue(key: "FNum", type: "ui8 ", [1]),
            "F0Ac": floatValue(key: "F0Ac", 1_900)
        ])
        let reader = makeReader(transport: transport)

        let snapshot = await reader.snapshot()

        XCTAssertEqual(snapshot.availability, .available)
        XCTAssertEqual(snapshot.sensors.count, 3)
        XCTAssertEqual(Set(snapshot.sensors.map(\.group)), Set(["CPU", "GPU", "System"]))
        XCTAssertEqual(snapshot.cpuTemperatureCelsius, 52)
        XCTAssertEqual(snapshot.gpuTemperatureCelsius, 46)
        XCTAssertEqual(snapshot.fans.first?.currentRPM, 1_900)
    }

    func testPermissionFailureIsExplicitAndNeverReturnsZeroMeasurements() async {
        let reader = SMCSensorReader(
            chipName: "Apple M1 Ultra",
            transportFactory: { throw SMCReadError.permissionDenied }
        )

        let snapshot = await reader.snapshot()

        guard case let .permissionRequired(reason) = snapshot.availability else {
            return XCTFail("Expected permissionRequired, got \(snapshot.availability)")
        }
        XCTAssertTrue(reason.contains("只读连接"))
        XCTAssertTrue(snapshot.sensors.isEmpty)
        XCTAssertTrue(snapshot.fans.isEmpty)
        XCTAssertNil(snapshot.cpuTemperatureCelsius)
        XCTAssertNil(snapshot.gpuTemperatureCelsius)
    }

    func testSuccessfulSnapshotUsesCacheWithoutReadingHardwareAgain() async {
        let transport = FakeSMCTransport(values: [
            "TCMz": floatValue(key: "TCMz", 55),
            "FNum": rawValue(key: "FNum", type: "ui8 ", [0])
        ])
        let reader = makeReader(transport: transport, cacheInterval: 3_600)

        let first = await reader.snapshot()
        let readsAfterFirstSample = transport.readCount
        let second = await reader.snapshot()

        XCTAssertEqual(first, second)
        XCTAssertGreaterThan(readsAfterFirstSample, 0)
        XCTAssertEqual(transport.readCount, readsAfterFirstSample)
    }

    func testStaleTransportFailureIsReportedAndTransportIsRebuilt() async {
        let staleTransport = FailingSMCTransport(
            error: .invalidPayload(key: "stale transport")
        )
        let recoveredTransport = FakeSMCTransport(values: [
            "FNum": rawValue(key: "FNum", type: "ui8 ", [1]),
            "F0Ac": floatValue(key: "F0Ac", 2_080),
            "F0Mn": floatValue(key: "F0Mn", 1_200),
            "F0Mx": floatValue(key: "F0Mx", 5_000),
            "F0Tg": floatValue(key: "F0Tg", 2_200)
        ])
        let factory = SequencedSMCTransportFactory([
            staleTransport,
            recoveredTransport
        ])
        let reader = SMCSensorReader(
            cacheInterval: 0,
            failureCacheInterval: 0,
            temperatureProbeRetryInterval: 3_600,
            chipName: "Apple M1 Ultra",
            transportFactory: { try factory.makeTransport() }
        )

        let failed = await reader.snapshot()

        XCTAssertEqual(factory.makeCount, 1)
        XCTAssertGreaterThan(staleTransport.readCount, 0)
        guard case .failed = failed.availability else {
            return XCTFail("Expected an explicit AppleSMC failure, got \(failed.availability)")
        }
        XCTAssertTrue(failed.sensors.isEmpty)
        XCTAssertNil(failed.cpuTemperatureCelsius)
        XCTAssertTrue(failed.fans.isEmpty)

        let recovered = await reader.snapshot()

        XCTAssertEqual(factory.makeCount, 2)
        XCTAssertEqual(recovered.availability, .available)
        XCTAssertTrue(recovered.sensors.isEmpty)
        XCTAssertNil(recovered.cpuTemperatureCelsius)
        XCTAssertEqual(recovered.fans, [
            FanState(
                name: "Fan 1",
                currentRPM: 2_080,
                minimumRPM: 1_200,
                maximumRPM: 5_000,
                targetRPM: 2_200
            )
        ])
        XCTAssertGreaterThan(recoveredTransport.readCount, 0)

        _ = await reader.snapshot()
        XCTAssertEqual(factory.makeCount, 2, "A healthy rebuilt transport should be reused")
    }

    func testFanStaticValuesAreCachedButActualAndTargetRefresh() async {
        let transport = FakeSMCTransport(values: [
            "TCMz": floatValue(key: "TCMz", 55),
            "FNum": rawValue(key: "FNum", type: "ui8 ", [1]),
            "F0Ac": floatValue(key: "F0Ac", 2_100),
            "F0Mn": floatValue(key: "F0Mn", 1_200),
            "F0Mx": floatValue(key: "F0Mx", 5_000),
            "F0Tg": floatValue(key: "F0Tg", 2_300)
        ])
        let reader = makeReader(transport: transport, cacheInterval: 0)

        _ = await reader.snapshot()
        _ = await reader.snapshot()

        XCTAssertEqual(transport.readCount(for: "FNum"), 1)
        XCTAssertEqual(transport.readCount(for: "F0Mn"), 1)
        XCTAssertEqual(transport.readCount(for: "F0Mx"), 1)
        XCTAssertEqual(transport.readCount(for: "F0Ac"), 2)
        XCTAssertEqual(transport.readCount(for: "F0Tg"), 2)
    }

    private func makeReader(
        transport: FakeSMCTransport,
        cacheInterval: TimeInterval = 2
    ) -> SMCSensorReader {
        SMCSensorReader(
            cacheInterval: cacheInterval,
            failureCacheInterval: 30,
            temperatureProbeRetryInterval: 60,
            chipName: "Apple M1 Ultra",
            transportFactory: { transport }
        )
    }
}

private final class FakeSMCTransport: SMCValueReading, @unchecked Sendable {
    private let lock = NSLock()
    private let values: [String: SMCRawValue]
    private var mutableReadCount = 0
    private var mutableReadCounts: [String: Int] = [:]

    init(values: [String: SMCRawValue]) {
        self.values = values
    }

    var readCount: Int {
        lock.withLock { mutableReadCount }
    }

    func readCount(for key: String) -> Int {
        lock.withLock { mutableReadCounts[key, default: 0] }
    }

    func readValue(for key: String) throws -> SMCRawValue {
        try lock.withLock {
            mutableReadCount += 1
            mutableReadCounts[key, default: 0] += 1
            guard let value = values[key] else { throw SMCReadError.firmware(0x84) }
            return value
        }
    }
}

private final class FailingSMCTransport: SMCValueReading, @unchecked Sendable {
    private let lock = NSLock()
    private let error: SMCReadError
    private var mutableReadCount = 0

    init(error: SMCReadError) {
        self.error = error
    }

    var readCount: Int {
        lock.withLock { mutableReadCount }
    }

    func readValue(for key: String) throws -> SMCRawValue {
        try lock.withLock {
            mutableReadCount += 1
            throw error
        }
    }
}

private final class SequencedSMCTransportFactory: @unchecked Sendable {
    private let lock = NSLock()
    private let transports: [any SMCValueReading]
    private var mutableMakeCount = 0

    init(_ transports: [any SMCValueReading]) {
        self.transports = transports
    }

    var makeCount: Int {
        lock.withLock { mutableMakeCount }
    }

    func makeTransport() throws -> any SMCValueReading {
        try lock.withLock {
            guard mutableMakeCount < transports.count else {
                throw SMCReadError.serviceUnavailable
            }
            defer { mutableMakeCount += 1 }
            return transports[mutableMakeCount]
        }
    }
}

private func rawValue(key: String, type: String, _ bytes: [UInt8]) -> SMCRawValue {
    SMCRawValue(key: key, dataType: type, bytes: bytes)
}

private func floatValue(key: String, _ value: Float) -> SMCRawValue {
    let bits = value.bitPattern
    return rawValue(key: key, type: "flt ", [
        UInt8(bits & 0xff),
        UInt8((bits >> 8) & 0xff),
        UInt8((bits >> 16) & 0xff),
        UInt8((bits >> 24) & 0xff)
    ])
}
