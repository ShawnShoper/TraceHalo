import Foundation
import XCTest
@testable import TraceHaloCore

final class GPUDeviceMetadataReaderTests: XCTestCase {
    func testDecodesAppleGPUIdentityFromRegistryPropertiesWithoutHardwareAccess() {
        let metadata = GPUDeviceMetadataReader.metadata(properties: [
            "model": "Apple M1 Ultra",
            "IONameMatched": "gpu,t6000",
            "CFBundleIdentifier": "com.apple.AGXG13X",
            "IOSourceVersion": "351.2",
            "gpu-core-count": NSNumber(value: 64)
        ])

        XCTAssertEqual(metadata.modelName, "Apple M1 Ultra")
        XCTAssertEqual(metadata.modelIdentifier, "gpu,t6000")
        XCTAssertEqual(metadata.driverDescription, "com.apple.AGXG13X · 351.2")
        XCTAssertEqual(metadata.coreCount, 64)
    }

    func testDecodesDataAndConfigurationFallbacks() {
        let metadata = GPUDeviceMetadataReader.metadata(properties: [
            "model": Data([65, 77, 68, 0]),
            "IONameMatch": ["display-controller"],
            "GPUConfigurationVariable": ["num_cores": 32]
        ])

        XCTAssertEqual(metadata.modelName, "AMD")
        XCTAssertEqual(metadata.modelIdentifier, "display-controller")
        XCTAssertEqual(metadata.coreCount, 32)
        XCTAssertNil(metadata.driverDescription)
    }

    func testMissingRegistryPropertiesRemainUnavailable() {
        let metadata = GPUDeviceMetadataReader.metadata(properties: [:])
        XCTAssertNil(metadata.modelName)
        XCTAssertNil(metadata.modelIdentifier)
        XCTAssertNil(metadata.driverDescription)
        XCTAssertNil(metadata.coreCount)
    }
}
