import Foundation
import XCTest
@testable import TraceHaloCore

final class BatteryTelemetryParserTests: XCTestCase {
    func testNormalizedCapacityIsNotMislabelledAsMAhAndSystemGoodWins() throws {
        let reading = BatteryTelemetryParser.parse(
            powerSource: [
                "Current Capacity": 48,
                "Max Capacity": 100,
                "BatteryHealth": "Good"
            ],
            registry: [
                "CurrentCapacity": 48,
                "MaxCapacity": 100,
                "AppleRawMaxCapacity": 6_086,
                "DesignCapacity": 6_249,
                "PermanentFailureStatus": 1
            ]
        )

        XCTAssertEqual(try XCTUnwrap(reading.chargePercent), 48, accuracy: 0.001)
        XCTAssertNil(reading.currentCapacityMAh)
        XCTAssertEqual(reading.maximumCapacityMAh, 6_086)
        XCTAssertEqual(reading.designCapacityMAh, 6_249)
        XCTAssertEqual(reading.health, .good)
        XCTAssertEqual(reading.healthBasis, .systemReported)
    }

    func testExplicitRawCapacityKeysAreReportedAsMAh() throws {
        let reading = BatteryTelemetryParser.parse(
            powerSource: [:],
            registry: [
                "AppleRawCurrentCapacity": 3_000,
                "AppleRawMaxCapacity": 6_000,
                "DesignCapacity": 6_200
            ]
        )

        XCTAssertEqual(try XCTUnwrap(reading.chargePercent), 50, accuracy: 0.001)
        XCTAssertEqual(reading.currentCapacityMAh, 3_000)
        XCTAssertEqual(reading.maximumCapacityMAh, 6_000)
        XCTAssertEqual(reading.designCapacityMAh, 6_200)
        XCTAssertEqual(reading.health, .excellent)
        XCTAssertEqual(reading.healthBasis, .rawCapacityEstimate)
    }

    func testPublicConditionAndFailureModesRemainActionable() {
        let checkBattery = BatteryTelemetryParser.parse(
            powerSource: [
                "BatteryHealth": "Good",
                "BatteryHealthCondition": "Check Battery"
            ],
            registry: [:]
        )
        XCTAssertEqual(checkBattery.health, .serviceRecommended)
        XCTAssertEqual(checkBattery.healthBasis, .systemReported)

        let failureMode = BatteryTelemetryParser.parse(
            powerSource: [
                "BatteryHealth": "Good",
                "BatteryFailureModes": ["Cell Imbalance"]
            ],
            registry: [:]
        )
        XCTAssertEqual(failureMode.health, .serviceRecommended)
        XCTAssertEqual(failureMode.healthBasis, .systemReported)
    }

    func testNumericRegistryHealthUsesIOPMSystemValues() {
        let cases: [(code: Int, expected: BatteryHealth)] = [
            (3, .good),
            (2, .aging),
            (1, .serviceRecommended)
        ]

        for testCase in cases {
            let reading = BatteryTelemetryParser.parse(
                powerSource: [:],
                registry: [
                    "BatteryHealth": testCase.code,
                    "AppleRawMaxCapacity": 5_900,
                    "DesignCapacity": 6_000
                ]
            )

            XCTAssertEqual(reading.health, testCase.expected, "IOPM health code \(testCase.code)")
            XCTAssertEqual(reading.healthBasis, .systemReported, "IOPM health code \(testCase.code)")
        }
    }

    func testUndefinedOrUnknownNumericHealthFallsBackToCapacityEvidence() {
        for code in [0, 4, -1] {
            let reading = BatteryTelemetryParser.parse(
                powerSource: [:],
                registry: [
                    "BatteryHealth": code,
                    "AppleRawMaxCapacity": 5_900,
                    "DesignCapacity": 6_000
                ]
            )

            XCTAssertEqual(reading.health, .excellent, "IOPM health code \(code)")
            XCTAssertEqual(reading.healthBasis, .rawCapacityEstimate, "IOPM health code \(code)")
        }
    }

    func testPowerSourceHealthAndFailureConditionOverrideRegistryHealth() {
        let powerSourceWins = BatteryTelemetryParser.parse(
            powerSource: ["BatteryHealth": "Good"],
            registry: ["BatteryHealth": 1]
        )
        XCTAssertEqual(powerSourceWins.health, .good)
        XCTAssertEqual(powerSourceWins.healthBasis, .systemReported)

        let normalConditionWins = BatteryTelemetryParser.parse(
            powerSource: ["BatteryHealthCondition": "Normal"],
            registry: ["BatteryHealth": 1]
        )
        XCTAssertEqual(normalConditionWins.health, .good)
        XCTAssertEqual(normalConditionWins.healthBasis, .systemReported)

        let failureConditionWins = BatteryTelemetryParser.parse(
            powerSource: ["BatteryHealthCondition": "Service Recommended"],
            registry: ["BatteryHealth": 3]
        )
        XCTAssertEqual(failureConditionWins.health, .serviceRecommended)
        XCTAssertEqual(failureConditionWins.healthBasis, .systemReported)
    }

    func testRemainingChargeDoesNotChangeBatteryHealth() throws {
        let lowCharge = BatteryTelemetryParser.parse(
            powerSource: ["Current Capacity": 5, "Max Capacity": 100],
            registry: ["BatteryHealth": 3]
        )
        let highCharge = BatteryTelemetryParser.parse(
            powerSource: ["Current Capacity": 95, "Max Capacity": 100],
            registry: ["BatteryHealth": 3]
        )

        XCTAssertEqual(try XCTUnwrap(lowCharge.chargePercent), 5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(highCharge.chargePercent), 95, accuracy: 0.001)
        XCTAssertEqual(lowCharge.health, .good)
        XCTAssertEqual(highCharge.health, .good)
        XCTAssertEqual(lowCharge.healthBasis, .systemReported)
        XCTAssertEqual(highCharge.healthBasis, .systemReported)
    }

    func testPrivateFailureStatusDoesNotCreateAServiceWarning() {
        let reading = BatteryTelemetryParser.parse(
            powerSource: [:],
            registry: [
                "AppleRawMaxCapacity": 5_900,
                "DesignCapacity": 6_000,
                "PermanentFailureStatus": 7
            ]
        )

        XCTAssertEqual(reading.health, .excellent)
        XCTAssertEqual(reading.healthBasis, .rawCapacityEstimate)
    }

    func testLowRawCapacityEstimateDoesNotClaimAppleRecommendedService() {
        let reading = BatteryTelemetryParser.parse(
            powerSource: [:],
            registry: [
                "AppleRawMaxCapacity": 3_000,
                "DesignCapacity": 6_000
            ]
        )

        XCTAssertEqual(reading.health, .aging)
        XCTAssertEqual(reading.healthBasis, .rawCapacityEstimate)
    }

    func testEmptyFailureModeDictionaryMeansNoDetectedFailure() {
        let reading = BatteryTelemetryParser.parse(
            powerSource: [
                "BatteryHealth": "Good",
                "BatteryFailureModes": [String: Any]()
            ],
            registry: ["PermanentFailureStatus": 3]
        )

        XCTAssertEqual(reading.health, .good)
        XCTAssertEqual(reading.healthBasis, .systemReported)
    }

    func testAmbiguousCapacityUnitsAreHidden() {
        let reading = BatteryTelemetryParser.parse(
            powerSource: ["Current Capacity": 48, "Max Capacity": 100],
            registry: [
                "CurrentCapacity": 48,
                "MaxCapacity": 100,
                "DesignCapacity": 100
            ]
        )

        XCTAssertEqual(reading.chargePercent, 48)
        XCTAssertNil(reading.currentCapacityMAh)
        XCTAssertNil(reading.maximumCapacityMAh)
        XCTAssertNil(reading.designCapacityMAh)
        XCTAssertEqual(reading.health, .unknown)
        XCTAssertEqual(reading.healthBasis, .unavailable)
    }
}
