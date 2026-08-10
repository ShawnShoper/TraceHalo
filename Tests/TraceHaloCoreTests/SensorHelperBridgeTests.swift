import Foundation
import XCTest
@testable import TraceHaloCore

final class SensorHelperBridgeTests: XCTestCase {
    func testProductAndHelperIdentifiersMatchPackagedServices() {
        XCTAssertEqual(TraceHaloBundleIdentifiers.application, "com.tseai.tracehalo")
        XCTAssertEqual(
            SensorHelperConstants.machServiceName,
            "com.tseai.tracehalo.sensor-helper"
        )
        XCTAssertEqual(
            SensorHelperConstants.launchDaemonPlistName,
            "com.tseai.tracehalo.sensor-helper.plist"
        )
    }

    func testReadOnlyPayloadRoundTripsWithoutLosingOptionalFanValues() throws {
        let payload = SensorHelperPayload(
            capturedAt: Date(timeIntervalSince1970: 123),
            temperatures: [
                SensorHelperTemperature(
                    key: "TCMz",
                    name: "CPU Die Hotspot",
                    group: "CPU",
                    temperatureCelsius: 51.25
                )
            ],
            fans: [
                SensorHelperFan(
                    name: "Fan 1",
                    currentRPM: 1_328,
                    minimumRPM: 1_100,
                    maximumRPM: 3_500,
                    targetRPM: nil
                )
            ],
            cpuTemperatureCelsius: 51.25,
            gpuTemperatureCelsius: nil
        )

        let encoded = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(SensorHelperPayload.self, from: encoded)

        XCTAssertEqual(decoded, payload)
        XCTAssertTrue(decoded.hasMeasurements)
        XCTAssertNil(decoded.fans.first?.targetRPM)
    }

    func testErrorPayloadNeverInventsZeroMeasurements() {
        let payload = SensorHelperPayload(
            temperatures: [],
            fans: [],
            cpuTemperatureCelsius: nil,
            gpuTemperatureCelsius: nil,
            errorCode: .permissionRequired,
            errorMessage: "permission required",
            permissionRequired: true
        )

        XCTAssertFalse(payload.hasMeasurements)
        XCTAssertTrue(payload.permissionRequired)
        XCTAssertEqual(payload.errorCode, .permissionRequired)
        XCTAssertNil(payload.cpuTemperatureCelsius)
        XCTAssertTrue(payload.fans.isEmpty)
    }

    func testLegacyPayloadWithoutErrorCodeStillDecodes() throws {
        let legacyJSON = Data(
            #"{"capturedAt":0,"temperatures":[],"fans":[],"permissionRequired":true,"errorMessage":"legacy"}"#.utf8
        )

        let decoded = try JSONDecoder().decode(SensorHelperPayload.self, from: legacyJSON)

        XCTAssertNil(decoded.errorCode)
        XCTAssertEqual(decoded.errorMessage, "legacy")
        XCTAssertTrue(decoded.permissionRequired)
    }
}
