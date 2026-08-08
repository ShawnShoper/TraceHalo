import Foundation
import IOKit

/// Best-effort, read-only GPU counters exposed by the active IOAccelerator.
///
/// These registry keys are not guaranteed on every Mac. Callers must treat a
/// missing sample as unavailable and must never substitute a fabricated zero.
struct GPUPerformanceSample: Equatable, Sendable {
    var utilizationPercent: Double?
    var usedMemoryBytes: UInt64?
    var allocatedMemoryBytes: UInt64?
}

struct GPUPerformanceReading: Equatable, Sendable {
    var registryID: UInt64?
    var sample: GPUPerformanceSample
}

enum GPUStatisticsReader {
    static func read() -> [GPUPerformanceReading] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"),
            &iterator
        ) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var readings: [GPUPerformanceReading] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            guard let properties = IORegistryEntryCreateCFProperty(
                service,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? [String: Any] else {
                continue
            }

            guard let sample = sample(from: properties) else {
                continue
            }

            var rawRegistryID: UInt64 = 0
            let registryID = IORegistryEntryGetRegistryEntryID(service, &rawRegistryID) == KERN_SUCCESS
                && rawRegistryID != 0
                ? rawRegistryID
                : nil
            readings.append(GPUPerformanceReading(registryID: registryID, sample: sample))
        }
        return readings
    }

    /// Resolves one IOAccelerator sample to one Metal device. A single-device
    /// fallback is permitted because some macOS versions expose the same GPU via
    /// registry entries at different levels. Multi-GPU systems require an exact
    /// Registry ID match so counters are never attributed to the wrong device.
    static func sample(
        for registryID: UInt64?,
        in readings: [GPUPerformanceReading],
        totalGPUCount: Int
    ) -> GPUPerformanceSample? {
        if let registryID,
           let exact = readings.first(where: { $0.registryID == registryID })
        {
            return exact.sample
        }
        guard totalGPUCount == 1, readings.count == 1 else { return nil }
        return readings[0].sample
    }

    static func sample(from properties: [String: Any]) -> GPUPerformanceSample? {
        let utilization = number(properties["Device Utilization %"])
            ?? maxOptional(
                number(properties["Renderer Utilization %"]),
                number(properties["Tiler Utilization %"])
            )
        let used = unsignedInteger(properties["In use system memory"])
            ?? unsignedInteger(properties["In use system memory (driver)"])
        let allocated = unsignedInteger(properties["Alloc system memory"])

        let sample = GPUPerformanceSample(
            utilizationPercent: utilization.map { min(max($0, 0), 100) },
            usedMemoryBytes: used,
            allocatedMemoryBytes: allocated
        )
        guard sample.utilizationPercent != nil
                || sample.usedMemoryBytes != nil
                || sample.allocatedMemoryBytes != nil else {
            return nil
        }
        return sample
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        return nil
    }

    private static func unsignedInteger(_ value: Any?) -> UInt64? {
        if let value = value as? NSNumber, value.int64Value >= 0 { return value.uint64Value }
        if let value = value as? UInt64 { return value }
        if let value = value as? Int, value >= 0 { return UInt64(value) }
        return nil
    }

    private static func maxOptional<T: Comparable>(_ lhs: T?, _ rhs: T?) -> T? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?): max(lhs, rhs)
        case let (lhs?, nil): lhs
        case let (nil, rhs?): rhs
        case (nil, nil): nil
        }
    }
}
