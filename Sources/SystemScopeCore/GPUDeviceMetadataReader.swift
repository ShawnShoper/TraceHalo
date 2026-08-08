import Foundation
import IOKit

struct GPUDeviceMetadata: Equatable, Sendable {
    var modelName: String?
    var modelIdentifier: String?
    var driverBundleIdentifier: String?
    var driverVersion: String?
    var coreCount: Int?

    var driverDescription: String? {
        switch (driverBundleIdentifier, driverVersion) {
        case let (bundle?, version?): "\(bundle) · \(version)"
        case let (bundle?, nil): bundle
        case let (nil, version?): version
        case (nil, nil): nil
        }
    }
}

/// Resolves static GPU identity from the registry entry backing an `MTLDevice`.
/// The reader intentionally accepts missing properties instead of manufacturing
/// a model or driver name.
enum GPUDeviceMetadataReader {
    static func read(registryID: UInt64) -> GPUDeviceMetadata {
        guard registryID != 0 else { return GPUDeviceMetadata() }
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IORegistryEntryIDMatching(registryID)
        )
        guard service != IO_OBJECT_NULL else { return GPUDeviceMetadata() }
        defer { IOObjectRelease(service) }

        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        guard
            IORegistryEntryCreateCFProperties(
                service,
                &unmanagedProperties,
                kCFAllocatorDefault,
                0
            ) == KERN_SUCCESS,
            let unmanagedProperties,
            let properties = unmanagedProperties.takeRetainedValue() as? [String: Any]
        else {
            return GPUDeviceMetadata()
        }
        return metadata(properties: properties)
    }

    static func metadata(properties: [String: Any]) -> GPUDeviceMetadata {
        let configuration = properties["GPUConfigurationVariable"] as? [String: Any]
        return GPUDeviceMetadata(
            modelName: string(properties["model"]),
            modelIdentifier: string(properties["IONameMatched"])
                ?? string((properties["IONameMatched"] as? [Any])?.first)
                ?? string(properties["IONameMatch"])
                ?? string((properties["IONameMatch"] as? [Any])?.first),
            driverBundleIdentifier: string(properties["CFBundleIdentifier"]),
            driverVersion: string(properties["IOSourceVersion"]),
            coreCount: integer(properties["gpu-core-count"])
                ?? integer(configuration?["num_cores"])
        )
    }

    private static func string(_ value: Any?) -> String? {
        let decoded: String?
        if let value = value as? String {
            decoded = value
        } else if let data = value as? Data {
            decoded = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
        } else {
            decoded = nil
        }
        guard let decoded else { return nil }
        let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int, value >= 0 { return value }
        if let value = value as? NSNumber, value.int64Value >= 0 { return value.intValue }
        return nil
    }
}
