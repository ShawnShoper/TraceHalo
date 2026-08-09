import Foundation
import IOKit

struct StorageIODeviceCounters: Equatable, Sendable {
    var registryID: UInt64
    var name: String?
    var readBytes: UInt64
    var writtenBytes: UInt64
    var readOperations: UInt64
    var writeOperations: UInt64
}

/// Device names are registry metadata, not counters. Cache both successful and
/// unsuccessful lookups so the child registry tree is traversed only when a
/// device first appears.
struct StorageMediaNameCache: Sendable {
    private var namesByRegistryID: [UInt64: String] = [:]
    private var resolvedRegistryIDs: Set<UInt64> = []

    mutating func name(
        for registryID: UInt64,
        load: () -> String?
    ) -> String? {
        if resolvedRegistryIDs.contains(registryID) {
            return namesByRegistryID[registryID]
        }

        resolvedRegistryIDs.insert(registryID)
        if let loaded = Self.normalized(load()) {
            namesByRegistryID[registryID] = loaded
            return loaded
        }
        return nil
    }

    mutating func retainRegistryIDs(_ registryIDs: Set<UInt64>) {
        resolvedRegistryIDs.formIntersection(registryIDs)
        namesByRegistryID = namesByRegistryID.filter { registryIDs.contains($0.key) }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Read-only access to the cumulative counters maintained by
/// `IOBlockStorageDriver`. No files or storage configuration are touched.
enum StorageIOReader {
    static func read() -> [StorageIODeviceCounters] {
        var mediaNameCache = StorageMediaNameCache()
        return read(mediaNameCache: &mediaNameCache)
    }

    static func read(
        mediaNameCache: inout StorageMediaNameCache
    ) -> [StorageIODeviceCounters] {
        guard let matching = IOServiceMatching("IOBlockStorageDriver") else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var devices: [StorageIODeviceCounters] = []
        var activeRegistryIDs: Set<UInt64> = []
        while true {
            let service = IOIteratorNext(iterator)
            guard service != IO_OBJECT_NULL else { break }
            defer { IOObjectRelease(service) }

            var registryID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &registryID) == KERN_SUCCESS else { continue }
            activeRegistryIDs.insert(registryID)
            let name = mediaNameCache.name(for: registryID) {
                mediaName(for: service)
            }
            guard
                let property = IORegistryEntryCreateCFProperty(
                    service,
                    "Statistics" as CFString,
                    kCFAllocatorDefault,
                    0
                )?.takeRetainedValue(),
                let statistics = property as? [String: Any],
                let counters = counters(
                    registryID: registryID,
                    name: name,
                    statistics: statistics
                )
            else {
                continue
            }
            devices.append(counters)
        }
        mediaNameCache.retainRegistryIDs(activeRegistryIDs)
        return devices.sorted { $0.registryID < $1.registryID }
    }

    static func counters(
        registryID: UInt64,
        name: String?,
        statistics: [String: Any]
    ) -> StorageIODeviceCounters? {
        guard
            let readBytes = unsignedInteger(statistics["Bytes (Read)"]),
            let writtenBytes = unsignedInteger(statistics["Bytes (Write)"]),
            let readOperations = unsignedInteger(statistics["Operations (Read)"]),
            let writeOperations = unsignedInteger(statistics["Operations (Write)"])
        else {
            return nil
        }
        return StorageIODeviceCounters(
            registryID: registryID,
            name: normalized(name),
            readBytes: readBytes,
            writtenBytes: writtenBytes,
            readOperations: readOperations,
            writeOperations: writeOperations
        )
    }

    private static func mediaName(for service: io_registry_entry_t) -> String? {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        while true {
            let child = IOIteratorNext(iterator)
            guard child != IO_OBJECT_NULL else { return nil }
            defer { IOObjectRelease(child) }

            var name = [CChar](repeating: 0, count: 128)
            let result = name.withUnsafeMutableBufferPointer { buffer in
                IORegistryEntryGetName(child, buffer.baseAddress)
            }
            let bytes = name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            if result == KERN_SUCCESS, let decoded = normalized(String(decoding: bytes, as: UTF8.self)) {
                return decoded
            }
        }
    }

    private static func unsignedInteger(_ value: Any?) -> UInt64? {
        if let value = value as? UInt64 { return value }
        if let value = value as? UInt { return UInt64(value) }
        if let value = value as? Int, value >= 0 { return UInt64(value) }
        if let value = value as? Int64, value >= 0 { return UInt64(value) }
        if let value = value as? NSNumber, value.doubleValue >= 0, value.doubleValue.isFinite {
            return value.uint64Value
        }
        return nil
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum StorageIORateCalculator {
    static func state(
        current: [StorageIODeviceCounters],
        previous: [UInt64: StorageIODeviceCounters],
        elapsed: TimeInterval?
    ) -> StorageIOState {
        guard !current.isEmpty else {
            return StorageIOState(
                availability: .unavailable(
                    reason: TraceHaloLocalization.string(
                        "storage.io.noCounters",
                        defaultValue: "IOKit did not return read and write counters for block-storage devices."
                    )
                )
            )
        }

        let totals = current.reduce(into: (read: UInt64(0), write: UInt64(0), readOps: UInt64(0), writeOps: UInt64(0))) {
            $0.read = saturatedAdd($0.read, $1.readBytes)
            $0.write = saturatedAdd($0.write, $1.writtenBytes)
            $0.readOps = saturatedAdd($0.readOps, $1.readOperations)
            $0.writeOps = saturatedAdd($0.writeOps, $1.writeOperations)
        }
        let names = Array(Set(current.compactMap(\.name))).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }

        guard let elapsed, elapsed > 0, !previous.isEmpty else {
            return StorageIOState(
                availability: .available,
                totalReadBytes: totals.read,
                totalWrittenBytes: totals.write,
                totalReadOperations: totals.readOps,
                totalWriteOperations: totals.writeOps,
                deviceNames: names
            )
        }

        let deltas = current.reduce(into: (read: UInt64(0), write: UInt64(0), readOps: UInt64(0), writeOps: UInt64(0))) {
            guard let old = previous[$1.registryID] else { return }
            $0.read = saturatedAdd($0.read, monotonicDelta($1.readBytes, old.readBytes))
            $0.write = saturatedAdd($0.write, monotonicDelta($1.writtenBytes, old.writtenBytes))
            $0.readOps = saturatedAdd($0.readOps, monotonicDelta($1.readOperations, old.readOperations))
            $0.writeOps = saturatedAdd($0.writeOps, monotonicDelta($1.writeOperations, old.writeOperations))
        }

        return StorageIOState(
            availability: .available,
            totalReadBytes: totals.read,
            totalWrittenBytes: totals.write,
            totalReadOperations: totals.readOps,
            totalWriteOperations: totals.writeOps,
            readBytesPerSecond: Double(deltas.read) / elapsed,
            writeBytesPerSecond: Double(deltas.write) / elapsed,
            readOperationsPerSecond: Double(deltas.readOps) / elapsed,
            writeOperationsPerSecond: Double(deltas.writeOps) / elapsed,
            deviceNames: names
        )
    }

    private static func monotonicDelta(_ current: UInt64, _ previous: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }

    private static func saturatedAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? .max : value
    }
}
