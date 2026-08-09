import CoreGraphics
import Darwin
import Foundation
import IOKit
import IOKit.ps
import Metal

private func liveText(_ key: String, _ defaultValue: String) -> String {
    TraceHaloLocalization.string(key, defaultValue: defaultValue)
}

private func liveFormat(
    _ key: String,
    _ defaultValue: String,
    _ arguments: CVarArg...
) -> String {
    TraceHaloLocalization.format(
        key,
        defaultValue: defaultValue,
        arguments: arguments
    )
}

public protocol SystemMetricsProviding: Sendable {
    func snapshot() async -> SystemSnapshot
}

public protocol StorageHealthProviding: Sendable {
    func health(for volume: StorageVolume) async -> StorageHealth
}

/// Expensive inventory and registry readers intentionally run on a slower
/// cadence than CPU, memory, and network byte counters. Keeping this policy in
/// one testable value prevents a missing or empty hardware result from turning
/// into an accidental per-frame retry loop.
enum LiveSamplingDomain: CaseIterable, Hashable, Sendable {
    case processes
    case networkDisplayNames
    case wifiLinkDetails
    case volumes
    case storagePerformance
    case battery
    case inputDevices
    case gpuInventory
    case displayInventory
    case gpuPerformance

    var interval: TimeInterval {
        switch self {
        case .processes, .wifiLinkDetails:
            10
        case .storagePerformance, .gpuPerformance:
            3
        case .volumes, .battery, .inputDevices, .gpuInventory, .displayInventory:
            30
        case .networkDisplayNames:
            60
        }
    }
}

struct LiveSamplingSchedule: Sendable {
    private var refreshedAt: [LiveSamplingDomain: Date] = [:]

    /// Claims a refresh slot and records it immediately. The timestamp is
    /// independent of the loaded value, so valid empty inventories are cached
    /// for the same interval as non-empty ones.
    mutating func consumeRefresh(
        for domain: LiveSamplingDomain,
        at now: Date
    ) -> Bool {
        if let previous = refreshedAt[domain] {
            let elapsed = now.timeIntervalSince(previous)
            if elapsed >= 0, elapsed < domain.interval {
                return false
            }
        }
        refreshedAt[domain] = now
        return true
    }
}

/// Live, read-only telemetry for the local Mac.
///
/// The actor keeps only the previous counters required to turn cumulative kernel
/// values into rates. It never changes system configuration and never writes to disk.
public actor LiveSystemService: SystemMetricsProviding {
    private struct CPUTicks: Sendable {
        var user: UInt64
        var system: UInt64
        var idle: UInt64
        var nice: UInt64

        var total: UInt64 { user &+ system &+ idle &+ nice }
    }

    private struct NetworkCounter: Sendable {
        var received: UInt64
        var sent: UInt64
    }

    private struct ProcessCounter: Sendable {
        var cpuNanoseconds: UInt64
    }

    private var previousCPUTicks: [CPUTicks]?
    private var previousNetworkCounters: [String: NetworkCounter] = [:]
    private var previousNetworkDate: Date?
    private var previousStorageCounters: [UInt64: StorageIODeviceCounters] = [:]
    private var previousStorageDate: Date?
    private var previousProcessCounters: [Int32: ProcessCounter] = [:]
    private var previousProcessDate: Date?
    private var processNames: [Int32: String] = [:]
    private var cachedCPUProcesses: [ProcessUsage] = []
    private var cachedMemoryProcesses: [ProcessUsage] = []
    private var cachedNetworkDisplayNames: [String: String] = [:]
    private var cachedWiFiLinkDetails: [String: NetworkLinkDetails] = [:]
    private var cachedIdentity: HardwareIdentity?
    private var cachedVolumes: [StorageVolume] = []
    private var cachedStorageIO = StorageIOState(
        availability: .unavailable(
            reason: liveText("storage.io.pendingRead", "Storage I/O has not been read yet.")
        )
    )
    private var cachedBattery = BatteryState(
        availability: .unavailable(
            reason: liveText("battery.pending", "Battery status has not been read yet.")
        )
    )
    private var cachedInputDevices = InputDeviceInventory(
        availability: .unavailable(
            reason: liveText("input.inventory.pendingRead", "The IOHID input-device inventory has not been read yet.")
        )
    )
    private var cachedGPUs: [GPUState] = []
    private var cachedGPUMetadata: [UInt64: GPUDeviceMetadata] = [:]
    private var cachedDisplays: [DisplayDevice] = []
    private var cachedGPUPerformance: [GPUPerformanceReading] = []
    private var storageMediaNameCache = StorageMediaNameCache()
    private var samplingSchedule = LiveSamplingSchedule()
    private let smcSensorReader = SMCSensorReader()

    public init() {}

    public func snapshot() async -> SystemSnapshot {
        let capturedAt = Date()
        async let smcSampleTask = smcSensorReader.snapshot()

        let currentTicks = Self.readCPUTicks()
        let cpuPercentages = Self.cpuPercentages(current: currentTicks, previous: previousCPUTicks)
        previousCPUTicks = currentTicks

        if samplingSchedule.consumeRefresh(for: .processes, at: capturedAt) {
            let processResult = Self.readProcesses(
                previous: previousProcessCounters,
                names: processNames,
                elapsed: previousProcessDate.map { max(capturedAt.timeIntervalSince($0), 0.001) }
            )
            previousProcessCounters = processResult.counters
            previousProcessDate = capturedAt
            processNames = processResult.names
            cachedCPUProcesses = Array(processResult.usages
                .sorted { lhs, rhs in
                    if lhs.cpuPercent == rhs.cpuPercent { return lhs.memoryBytes > rhs.memoryBytes }
                    return lhs.cpuPercent > rhs.cpuPercent
                }
                .prefix(10))
            cachedMemoryProcesses = Array(processResult.usages
                .sorted { $0.memoryBytes > $1.memoryBytes }
                .prefix(8))
        }

        if samplingSchedule.consumeRefresh(for: .networkDisplayNames, at: capturedAt) {
            cachedNetworkDisplayNames = NetworkServiceNaming.namesByBSDInterface()
        }
        if samplingSchedule.consumeRefresh(for: .wifiLinkDetails, at: capturedAt) {
            cachedWiFiLinkDetails = NetworkLinkDetailsReader.detailsByBSDInterface()
        }
        let networkResult = Self.readNetworkInterfaces(
            previous: previousNetworkCounters,
            elapsed: previousNetworkDate.map { max(capturedAt.timeIntervalSince($0), 0.001) },
            displayNames: cachedNetworkDisplayNames,
            linkDetails: cachedWiFiLinkDetails
        )
        previousNetworkCounters = networkResult.counters
        previousNetworkDate = capturedAt

        let memory = Self.readMemory(topProcesses: cachedMemoryProcesses)
        var identity = cachedIdentity ?? Self.readHardwareIdentity(totalMemory: memory.totalBytes)
        identity.physicalMemoryBytes = memory.totalBytes > 0
            ? memory.totalBytes
            : ProcessInfo.processInfo.physicalMemory
        identity.uptime = ProcessInfo.processInfo.systemUptime
        cachedIdentity = identity

        if samplingSchedule.consumeRefresh(for: .volumes, at: capturedAt) {
            cachedVolumes = Self.readVolumes()
        }
        if samplingSchedule.consumeRefresh(for: .storagePerformance, at: capturedAt) {
            let storageCounters = StorageIOReader.read(mediaNameCache: &storageMediaNameCache)
            cachedStorageIO = StorageIORateCalculator.state(
                current: storageCounters,
                previous: previousStorageCounters,
                elapsed: previousStorageDate.map { max(capturedAt.timeIntervalSince($0), 0.001) }
            )
            previousStorageCounters = Dictionary(
                uniqueKeysWithValues: storageCounters.map { ($0.registryID, $0) }
            )
            previousStorageDate = capturedAt
        }
        if samplingSchedule.consumeRefresh(for: .battery, at: capturedAt) {
            cachedBattery = Self.readBatteryState()
        }
        if samplingSchedule.consumeRefresh(for: .inputDevices, at: capturedAt) {
            cachedInputDevices = InputDeviceInventoryReader.read()
        }
        let didRefreshGPUInventory = samplingSchedule.consumeRefresh(
            for: .gpuInventory,
            at: capturedAt
        )
        if didRefreshGPUInventory {
            cachedGPUs = readGPUStates(displays: [])
            cachedGPUPerformance = []
        }
        if samplingSchedule.consumeRefresh(for: .displayInventory, at: capturedAt) {
            let ioKitRecords = DisplayMetadataReader.readIOKitRecords()
            let appKitNames = await DisplayMetadataReader.appKitNamesByDisplayID()
            cachedDisplays = Self.readDisplays(
                appKitNames: appKitNames,
                ioKitRecords: ioKitRecords
            )
        }
        let smcSample = await smcSampleTask
        let didReachGPUPerformanceCadence = samplingSchedule.consumeRefresh(
            for: .gpuPerformance,
            at: capturedAt
        )
        if !cachedGPUs.isEmpty,
           didRefreshGPUInventory || didReachGPUPerformanceCadence {
            cachedGPUPerformance = GPUStatisticsReader.read()
        }
        var gpus = cachedGPUs
        for index in gpus.indices {
            gpus[index].displays = index == gpus.startIndex ? cachedDisplays : []
            let performance = GPUStatisticsReader.sample(
                for: gpus[index].registryID,
                in: cachedGPUPerformance,
                totalGPUCount: gpus.count
            )
            gpus[index].utilizationPercent = performance?.utilizationPercent
            gpus[index].usedMemoryBytes = performance?.usedMemoryBytes
            gpus[index].allocatedMemoryBytes = performance?.allocatedMemoryBytes
        }
        let temperatureCandidates = gpus.indices.filter {
            gpus[$0].hasUnifiedMemory == true && gpus[$0].isRemovable != true
        }
        let temperatureIndex = gpus.count == 1 ? gpus.startIndex : temperatureCandidates.count == 1 ? temperatureCandidates[0] : nil
        if let temperatureIndex {
            gpus[temperatureIndex].temperatureCelsius = smcSample.gpuTemperatureCelsius
        }
        let cpu = CPUState(
            totalPercent: cpuPercentages.total,
            userPercent: cpuPercentages.user,
            systemPercent: cpuPercentages.system,
            perCorePercent: cpuPercentages.perCore,
            temperatureCelsius: smcSample.cpuTemperatureCelsius,
            topProcesses: cachedCPUProcesses
        )

        return SystemSnapshot(
            capturedAt: capturedAt,
            identity: identity,
            cpu: cpu,
            memory: memory,
            volumes: cachedVolumes,
            networkInterfaces: networkResult.interfaces,
            cooling: Self.readCoolingState(sensorSample: smcSample),
            battery: cachedBattery,
            gpus: gpus,
            storageIO: cachedStorageIO,
            inputDevices: cachedInputDevices
        )
    }

    private static func readHardwareIdentity(totalMemory: UInt64) -> HardwareIdentity {
        let processInfo = ProcessInfo.processInfo
        let modelIdentifier = sysctlString("hw.model") ?? "Unknown Mac"
        let chip = sysctlString("machdep.cpu.brand_string")
            ?? sysctlString("hw.machine")
            ?? "Unknown"

        return HardwareIdentity(
            computerName: Host.current().localizedName ?? processInfo.hostName,
            modelName: modelIdentifier,
            modelIdentifier: modelIdentifier,
            chipName: chip,
            operatingSystem: processInfo.operatingSystemVersionString,
            physicalMemoryBytes: totalMemory > 0 ? totalMemory : processInfo.physicalMemory,
            uptime: processInfo.systemUptime
        )
    }

    private static func readCPUTicks() -> [CPUTicks] {
        var processorCount: natural_t = 0
        var processorInfo: processor_info_array_t?
        var processorInfoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorInfoCount
        )
        guard result == KERN_SUCCESS, let processorInfo else { return [] }

        defer {
            let byteCount = vm_size_t(processorInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: processorInfo)),
                byteCount
            )
        }

        let values = UnsafeBufferPointer(start: processorInfo, count: Int(processorInfoCount))
        let stateCount = Int(CPU_STATE_MAX)
        return (0..<Int(processorCount)).compactMap { index in
            let base = index * stateCount
            guard base + Int(CPU_STATE_NICE) < values.count else { return nil }
            return CPUTicks(
                user: UInt64(max(values[base + Int(CPU_STATE_USER)], 0)),
                system: UInt64(max(values[base + Int(CPU_STATE_SYSTEM)], 0)),
                idle: UInt64(max(values[base + Int(CPU_STATE_IDLE)], 0)),
                nice: UInt64(max(values[base + Int(CPU_STATE_NICE)], 0))
            )
        }
    }

    private static func cpuPercentages(
        current: [CPUTicks],
        previous: [CPUTicks]?
    ) -> (total: Double, user: Double, system: Double, perCore: [Double]) {
        guard !current.isEmpty else { return (0, 0, 0, []) }

        let baseline: [CPUTicks]
        if let previous, previous.count == current.count {
            baseline = previous
        } else {
            baseline = current.map { _ in CPUTicks(user: 0, system: 0, idle: 0, nice: 0) }
        }

        var aggregateUser: UInt64 = 0
        var aggregateSystem: UInt64 = 0
        var aggregateTotal: UInt64 = 0
        var perCore: [Double] = []
        perCore.reserveCapacity(current.count)

        for (now, before) in zip(current, baseline) {
            let user = delta(now.user, before.user) &+ delta(now.nice, before.nice)
            let system = delta(now.system, before.system)
            let idle = delta(now.idle, before.idle)
            let total = user &+ system &+ idle

            aggregateUser &+= user
            aggregateSystem &+= system
            aggregateTotal &+= total
            perCore.append(total > 0 ? clampPercent(Double(user &+ system) / Double(total) * 100) : 0)
        }

        guard aggregateTotal > 0 else { return (0, 0, 0, perCore) }
        return (
            clampPercent(Double(aggregateUser &+ aggregateSystem) / Double(aggregateTotal) * 100),
            clampPercent(Double(aggregateUser) / Double(aggregateTotal) * 100),
            clampPercent(Double(aggregateSystem) / Double(aggregateTotal) * 100),
            perCore
        )
    }

    private static func readProcesses(
        previous: [Int32: ProcessCounter],
        names cachedNames: [Int32: String],
        elapsed: TimeInterval?
    ) -> (usages: [ProcessUsage], counters: [Int32: ProcessCounter], names: [Int32: String]) {
        let byteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard byteCount > 0 else { return ([], [:], [:]) }

        let capacity = Int(byteCount) / MemoryLayout<pid_t>.stride
        var pids = [pid_t](repeating: 0, count: capacity)
        let populatedBytes = pids.withUnsafeMutableBytes { buffer in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, buffer.baseAddress, Int32(buffer.count))
        }
        guard populatedBytes > 0 else { return ([], [:], [:]) }

        let populatedCount = min(Int(populatedBytes) / MemoryLayout<pid_t>.stride, pids.count)
        var usages: [ProcessUsage] = []
        var counters: [Int32: ProcessCounter] = [:]
        var names: [Int32: String] = [:]
        usages.reserveCapacity(populatedCount)
        counters.reserveCapacity(populatedCount)
        names.reserveCapacity(populatedCount)

        for pid in pids.prefix(populatedCount) where pid > 0 {
            var info = proc_taskinfo()
            let infoSize = MemoryLayout<proc_taskinfo>.stride
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                proc_pidinfo(pid, PROC_PIDTASKINFO, 0, pointer, Int32(infoSize))
            }
            guard result == Int32(infoSize) else { continue }

            let identifier = Int32(pid)
            let totalCPU = info.pti_total_user &+ info.pti_total_system
            counters[identifier] = ProcessCounter(cpuNanoseconds: totalCPU)

            let cpuPercent: Double
            if let elapsed, let old = previous[identifier], totalCPU >= old.cpuNanoseconds {
                cpuPercent = max(Double(totalCPU - old.cpuNanoseconds) / 1_000_000_000 / elapsed * 100, 0)
            } else {
                cpuPercent = 0
            }

            let name: String
            if let cachedName = cachedNames[identifier] {
                name = cachedName
            } else {
                var nameBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
                let nameLength = nameBuffer.withUnsafeMutableBytes { buffer in
                    proc_name(pid, buffer.baseAddress, UInt32(buffer.count))
                }
                name = nameLength > 0 ? decodedCString(nameBuffer) : "PID \(pid)"
            }
            names[identifier] = name

            usages.append(ProcessUsage(
                id: identifier,
                name: name,
                cpuPercent: cpuPercent,
                memoryBytes: info.pti_resident_size
            ))
        }

        return (usages, counters, names)
    }

    private static func readMemory(topProcesses: [ProcessUsage]) -> MemoryState {
        let total = ProcessInfo.processInfo.physicalMemory
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return MemoryState(
                totalBytes: total,
                usedBytes: 0,
                activeBytes: 0,
                wiredBytes: 0,
                compressedBytes: 0,
                inactiveBytes: 0,
                availableBytes: total,
                swapUsedBytes: 0,
                swapTotalBytes: 0,
                pressurePercent: 0,
                topProcesses: topProcesses
            )
        }

        var kernelPageSize: vm_size_t = 0
        let pageSizeResult = host_page_size(mach_host_self(), &kernelPageSize)
        let pageSize = pageSizeResult == KERN_SUCCESS ? UInt64(kernelPageSize) : UInt64(getpagesize())
        let active = UInt64(statistics.active_count) * pageSize
        let wired = UInt64(statistics.wire_count) * pageSize
        let compressed = UInt64(statistics.compressor_page_count) * pageSize
        let inactive = UInt64(statistics.inactive_count) * pageSize
        let used = min(active &+ wired &+ compressed, total)
        let available = total >= used ? total - used : 0
        let swap = readSwapUsage()

        return MemoryState(
            totalBytes: total,
            usedBytes: used,
            activeBytes: active,
            wiredBytes: wired,
            compressedBytes: compressed,
            inactiveBytes: inactive,
            availableBytes: available,
            swapUsedBytes: swap.used,
            swapTotalBytes: swap.total,
            pressurePercent: total > 0 ? clampPercent(Double(used) / Double(total) * 100) : 0,
            topProcesses: topProcesses
        )
    }

    private static func readSwapUsage() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        guard result == 0 else { return (0, 0) }
        return (UInt64(usage.xsu_used), UInt64(usage.xsu_total))
    }

    private static func readVolumes() -> [StorageVolume] {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsInternalKey,
            .volumeIsRemovableKey,
            .volumeIsReadOnlyKey,
            .volumeIsEncryptedKey,
            .volumeLocalizedFormatDescriptionKey,
            .volumeUUIDStringKey
        ]

        var URLs = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: [.skipHiddenVolumes]
        ) ?? []
        if !URLs.contains(where: { $0.path == "/" }) {
            URLs.append(URL(fileURLWithPath: "/", isDirectory: true))
        }

        var seen = Set<String>()
        return URLs.compactMap { URL in
            let path = URL.standardizedFileURL.path
            guard seen.insert(path).inserted else { return nil }

            let values = try? URL.resourceValues(forKeys: keys)
            let fileSystemAttributes = try? FileManager.default.attributesOfFileSystem(forPath: path)
            let total = uint64(values?.volumeTotalCapacity)
                ?? uint64(fileSystemAttributes?[.systemSize])
                ?? 0
            let available = uint64(values?.volumeAvailableCapacityForImportantUsage)
                ?? uint64(fileSystemAttributes?[.systemFreeSize])
                ?? 0

            return StorageVolume(
                name: values?.volumeName ?? (path == "/" ? "Macintosh HD" : URL.lastPathComponent),
                path: path,
                totalBytes: total,
                availableBytes: min(available, total),
                isInternal: values?.volumeIsInternal,
                isRemovable: values?.volumeIsRemovable,
                isReadOnly: values?.volumeIsReadOnly,
                isEncrypted: values?.volumeIsEncrypted,
                fileSystem: values?.volumeLocalizedFormatDescription,
                uuid: values?.volumeUUIDString
            )
        }
        .sorted { lhs, rhs in
            if lhs.path == "/" { return true }
            if rhs.path == "/" { return false }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static func readNetworkInterfaces(
        previous: [String: NetworkCounter],
        elapsed: TimeInterval?,
        displayNames: [String: String],
        linkDetails: [String: NetworkLinkDetails]
    ) -> (interfaces: [NetworkInterfaceState], counters: [String: NetworkCounter]) {
        struct InterfaceAccumulator {
            var address: String?
            var isActive = false
            var received: UInt64 = 0
            var sent: UInt64 = 0
            var linkSpeedMbps: Double?
        }

        var firstAddress: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&firstAddress) == 0, let firstAddress else { return ([], [:]) }
        defer { freeifaddrs(firstAddress) }

        var accumulated: [String: InterfaceAccumulator] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let current = cursor {
            let item = current.pointee
            let name = String(cString: item.ifa_name)
            var value = accumulated[name] ?? InterfaceAccumulator()
            let flags = Int32(item.ifa_flags)
            value.isActive = value.isActive
                || ((flags & IFF_UP) != 0 && (flags & IFF_RUNNING) != 0)

            if let rawData = item.ifa_data {
                let data = rawData.assumingMemoryBound(to: if_data.self).pointee
                value.received = max(value.received, UInt64(data.ifi_ibytes))
                value.sent = max(value.sent, UInt64(data.ifi_obytes))
                if data.ifi_baudrate > 0 {
                    value.linkSpeedMbps = Double(data.ifi_baudrate) / 1_000_000
                }
            }

            if let socketAddress = item.ifa_addr {
                let family = Int32(socketAddress.pointee.sa_family)
                if family == AF_INET || (family == AF_INET6 && value.address == nil) {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let status = getnameinfo(
                        socketAddress,
                        socklen_t(socketAddress.pointee.sa_len),
                        &host,
                        socklen_t(host.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    if status == 0 {
                        let candidate = decodedCString(host)
                        if !candidate.hasPrefix("fe80:") {
                            value.address = candidate
                        }
                    }
                }
            }

            accumulated[name] = value
            cursor = item.ifa_next
        }

        var counters: [String: NetworkCounter] = [:]
        let interfaces = accumulated.map { name, value -> NetworkInterfaceState in
            let counter = NetworkCounter(received: value.received, sent: value.sent)
            counters[name] = counter

            let receivedRate: Double?
            let sentRate: Double?
            if let elapsed, let old = previous[name] {
                receivedRate = Double(delta(counter.received, old.received)) / elapsed
                sentRate = Double(delta(counter.sent, old.sent)) / elapsed
            } else {
                receivedRate = nil
                sentRate = nil
            }

            return NetworkInterfaceState(
                name: name,
                displayName: displayNames[name] ?? displayName(forInterface: name),
                localAddress: value.address,
                isActive: value.isActive,
                receivedBytesPerSecond: receivedRate,
                sentBytesPerSecond: sentRate,
                linkSpeedMbps: linkDetails[name]?.transmitRateMbps ?? value.linkSpeedMbps,
                rssi: linkDetails[name]?.rssi,
                noise: linkDetails[name]?.noise
            )
        }
        .sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive { return lhs.isActive }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        return (interfaces, counters)
    }

    private static func readCoolingState(sensorSample: SMCSensorSnapshot) -> CoolingState {
        let condition = ThermalRules.condition(for: ProcessInfo.processInfo.thermalState)

        return CoolingState(
            availability: condition == .unavailable
                ? .unavailable(reason: liveText("thermal.unavailable", "The system did not provide a thermal state."))
                : .available,
            sensorAvailability: sensorSample.availability,
            condition: condition,
            sensors: sensorSample.sensors,
            fans: sensorSample.fans
        )
    }

    private static func readBatteryState() -> BatteryState {
        guard
            let sourceInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sourceList = IOPSCopyPowerSourcesList(sourceInfo)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return BatteryState(
                availability: .unavailable(
                    reason: liveText("battery.notDetected", "No battery was detected.")
                )
            )
        }

        let descriptions: [[String: Any]] = sourceList.compactMap { source in
            IOPSGetPowerSourceDescription(sourceInfo, source)?.takeUnretainedValue() as? [String: Any]
        }
        guard let description = descriptions.first(where: {
            ($0[kIOPSTypeKey as String] as? String) == (kIOPSInternalBatteryType as String)
                || ($0["Type"] as? String) == "InternalBattery"
        }) else {
            return BatteryState(
                availability: .unavailable(
                    reason: liveText("battery.none", "This Mac does not have a built-in battery.")
                )
            )
        }

        let registry = batteryRegistryProperties()
        let telemetry = BatteryTelemetryParser.parse(
            powerSource: description,
            registry: registry
        )

        let rawTemperature = integer(registry["Temperature"])
        let temperature = rawTemperature.flatMap { value -> Double? in
            let celsius = Double(value) / 10 - 273.15
            return (-30...120).contains(celsius) ? celsius : nil
        }
        let cycleCount = integer(registry["CycleCount"])
        let designCycleCount = integer(registry["DesignCycleCount"])
        let remaining = integer(description[kIOPSTimeToEmptyKey as String])
        return BatteryState(
            availability: .available,
            chargePercent: telemetry.chargePercent,
            isCharging: boolean(description[kIOPSIsChargingKey as String]) ?? false,
            health: telemetry.health,
            healthBasis: telemetry.healthBasis,
            currentCapacityMAh: telemetry.currentCapacityMAh,
            maximumCapacityMAh: telemetry.maximumCapacityMAh,
            designCapacityMAh: telemetry.designCapacityMAh,
            cycleCount: cycleCount,
            designCycleCount: designCycleCount,
            voltageMV: integer(registry["Voltage"]),
            amperageMA: integer(registry["Amperage"]),
            temperatureCelsius: temperature,
            timeRemainingMinutes: remaining.flatMap { $0 >= 0 ? $0 : nil },
            manufacturer: registry["Manufacturer"] as? String,
            serialNumber: registry["SerialNumber"] as? String
        )
    }

    private static func batteryRegistryProperties() -> [String: Any] {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return [:] }
        defer { IOObjectRelease(service) }

        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(
            service,
            &unmanagedProperties,
            kCFAllocatorDefault,
            0
        )
        guard result == KERN_SUCCESS, let unmanagedProperties else { return [:] }
        return unmanagedProperties.takeRetainedValue() as? [String: Any] ?? [:]
    }

    private func readGPUStates(displays: [DisplayDevice]) -> [GPUState] {
        let devices = MTLCopyAllDevices()
        let activeRegistryIDs = Set(devices.map(\.registryID).filter { $0 != 0 })
        cachedGPUMetadata = cachedGPUMetadata.filter { activeRegistryIDs.contains($0.key) }

        return devices.enumerated().map { index, device in
            let metadata: GPUDeviceMetadata
            if device.registryID == 0 {
                metadata = GPUDeviceMetadataReader.read(registryID: 0)
            } else if let cached = cachedGPUMetadata[device.registryID] {
                metadata = cached
            } else {
                let discovered = GPUDeviceMetadataReader.read(registryID: device.registryID)
                cachedGPUMetadata[device.registryID] = discovered
                metadata = discovered
            }
            let deviceName = metadata.modelName ?? device.name
            let lowercaseName = deviceName.lowercased()
            let vendor: String
            if lowercaseName.contains("apple") { vendor = "Apple" }
            else if lowercaseName.contains("amd") || lowercaseName.contains("radeon") { vendor = "AMD" }
            else if lowercaseName.contains("intel") { vendor = "Intel" }
            else if lowercaseName.contains("nvidia") { vendor = "NVIDIA" }
            else { vendor = liveText("common.notProvided", "Not Provided") }

            let memoryDescription: String?
            if device.recommendedMaxWorkingSetSize > 0 {
                memoryDescription = MetricFormatter.bytes(device.recommendedMaxWorkingSetSize)
            } else {
                memoryDescription = nil
            }

            return GPUState(
                name: deviceName,
                vendor: vendor,
                family: device.hasUnifiedMemory
                    ? liveText("gpu.memory.unified", "Unified Memory")
                    : liveText("gpu.memory.discrete", "Discrete Memory"),
                memoryDescription: memoryDescription,
                driver: metadata.driverDescription,
                metalSupport: Self.metalFamilyDescription(device),
                modelIdentifier: metadata.modelIdentifier,
                registryID: device.registryID == 0 ? nil : device.registryID,
                coreCount: metadata.coreCount,
                isLowPower: device.isLowPower,
                isRemovable: device.isRemovable,
                hasUnifiedMemory: device.hasUnifiedMemory,
                supportsRayTracing: device.supportsRaytracing,
                supportsRayTracingInRenderPipelines: device.supportsRaytracingFromRender,
                supportsDynamicLibraries: device.supportsDynamicLibraries,
                supportsRenderDynamicLibraries: device.supportsRenderDynamicLibraries,
                argumentBufferTier: Self.argumentBufferTierDescription(device.argumentBuffersSupport),
                maximumBufferLengthBytes: UInt64(device.maxBufferLength),
                maximumThreadgroupMemoryBytes: UInt64(device.maxThreadgroupMemoryLength),
                maximumThreadsPerThreadgroup: "\(device.maxThreadsPerThreadgroup.width) × \(device.maxThreadsPerThreadgroup.height) × \(device.maxThreadsPerThreadgroup.depth)",
                displays: index == 0 ? displays : []
            )
        }
    }

    private static func metalFamilyDescription(_ device: any MTLDevice) -> String {
        var appleFamilies: [(MTLGPUFamily, String)] = [
            (.apple9, "Apple 9"),
            (.apple8, "Apple 8"),
            (.apple7, "Apple 7"),
            (.apple6, "Apple 6"),
            (.apple5, "Apple 5"),
            (.apple4, "Apple 4"),
            (.apple3, "Apple 3"),
            (.apple2, "Apple 2"),
            (.apple1, "Apple 1")
        ]
        if #available(macOS 15.0, *) {
            appleFamilies.insert((.apple10, "Apple 10"), at: 0)
        }
        let macFamilies: [(MTLGPUFamily, String)] = [
            (.mac2, "Mac 2")
        ]
        let commonFamilies: [(MTLGPUFamily, String)] = [
            (.common3, "Common 3"),
            (.common2, "Common 2"),
            (.common1, "Common 1")
        ]
        let family = appleFamilies.first(where: { device.supportsFamily($0.0) })?.1
            ?? macFamilies.first(where: { device.supportsFamily($0.0) })?.1
            ?? commonFamilies.first(where: { device.supportsFamily($0.0) })?.1
        return family.map { "Metal · \($0)" }
            ?? liveText("gpu.metal.familyUnavailable", "Metal (family not reported by the device)")
    }

    private static func argumentBufferTierDescription(_ tier: MTLArgumentBuffersTier) -> String {
        switch tier {
        case .tier1: "Tier 1"
        case .tier2: "Tier 2"
        @unknown default: liveText("common.notReported", "Not Reported")
        }
    }

    private static func readDisplays(
        appKitNames: [CGDirectDisplayID: String],
        ioKitRecords: [IODisplayRecord]
    ) -> [DisplayDevice] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var identifiers = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &identifiers, &count) == .success else { return [] }

        return identifiers.prefix(Int(count)).compactMap { identifier in
            guard let mode = CGDisplayCopyDisplayMode(identifier) else { return nil }
            let builtIn = CGDisplayIsBuiltin(identifier) != 0
            let refreshRate = mode.refreshRate > 0 ? mode.refreshRate : nil
            let vendorID = CGDisplayVendorNumber(identifier)
            let productID = CGDisplayModelNumber(identifier)
            let serialNumber = CGDisplaySerialNumber(identifier)
            let ioKitRecord = DisplayMetadataReader.matchingRecord(
                vendorID: vendorID,
                productID: productID,
                serialNumber: serialNumber,
                records: ioKitRecords
            )
            return DisplayDevice(
                name: DisplayMetadataReader.resolvedName(
                    appKitName: appKitNames[identifier],
                    ioKitName: ioKitRecord?.productName,
                    isBuiltIn: builtIn,
                    vendorID: vendorID,
                    productID: productID
                ),
                resolution: "\(mode.width) × \(mode.height)",
                refreshRateHz: refreshRate,
                isMain: CGDisplayIsMain(identifier) != 0,
                isBuiltIn: builtIn,
                displayID: identifier,
                vendorID: vendorID == 0 ? nil : vendorID,
                productID: productID == 0 ? nil : productID,
                serialNumber: serialNumber == 0 ? nil : serialNumber,
                pixelDimensions: liveFormat(
                    "display.pixelDimensions",
                    "%@ pixels",
                    "\(mode.pixelWidth) × \(mode.pixelHeight)"
                )
            )
        }
    }

    private static func displayName(forInterface name: String) -> String {
        if name == "lo0" { return "Loopback" }
        if name.hasPrefix("en") {
            return liveFormat("network.interface", "Network Interface %@", name)
        }
        if name.hasPrefix("awdl") { return "Apple Wireless Direct Link" }
        if name.hasPrefix("utun") {
            return liveFormat("network.vpnTunnel", "VPN Tunnel %@", name)
        }
        if name.hasPrefix("bridge") {
            return liveFormat("network.bridge", "Network Bridge %@", name)
        }
        return name
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return decodedCString(buffer)
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? Int { return value }
        return nil
    }

    private static func boolean(_ value: Any?) -> Bool? {
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? Bool { return value }
        return nil
    }

    private static func uint64(_ value: Any?) -> UInt64? {
        if let value = value as? NSNumber, value.int64Value >= 0 { return value.uint64Value }
        if let value = value as? Int, value >= 0 { return UInt64(value) }
        if let value = value as? Int64, value >= 0 { return UInt64(value) }
        return nil
    }

    private static func delta(_ current: UInt64, _ previous: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }

    private static func decodedCString(_ buffer: [CChar]) -> String {
        buffer.withUnsafeBytes { rawBuffer in
            String(decoding: rawBuffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    private static func clampPercent(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }
}

/// Read-only storage status. `diskutil info -plist` is used only to enrich the
/// URL resource values with the device's reported SMART state when available.
public struct StorageHealthService: StorageHealthProviding, Sendable {
    public init() {}

    public func health(for volume: StorageVolume) async -> StorageHealth {
        let URL = URL(fileURLWithPath: volume.path, isDirectory: true)
        guard URL.isFileURL, FileManager.default.fileExists(atPath: URL.path) else {
            return StorageHealth(
                availability: .unavailable(
                    reason: liveText("storage.volumePathUnavailable", "The volume path is unavailable.")
                )
            )
        }

        var metrics: [StorageHealthMetric] = [
            StorageHealthMetric(kind: .capacity, name: liveText("storage.metric.capacity", "Capacity"), value: MetricFormatter.bytes(volume.totalBytes)),
            StorageHealthMetric(kind: .used, name: liveText("storage.metric.used", "Used"), value: MetricFormatter.bytes(volume.usedBytes)),
            StorageHealthMetric(kind: .available, name: liveText("storage.metric.available", "Available"), value: MetricFormatter.bytes(volume.availableBytes))
        ]
        if let fileSystem = volume.fileSystem {
            metrics.append(StorageHealthMetric(kind: .fileSystem, name: liveText("storage.metric.fileSystem", "File System"), value: fileSystem))
        }
        if let isInternal = volume.isInternal {
            metrics.append(StorageHealthMetric(
                kind: .location,
                name: liveText("storage.metric.location", "Location"),
                value: isInternal
                    ? liveText("storage.value.internal", "Internal")
                    : liveText("storage.value.external", "External")
            ))
        }
        if let isEncrypted = volume.isEncrypted {
            metrics.append(StorageHealthMetric(
                kind: .encryption,
                name: liveText("storage.metric.encryption", "Encryption"),
                value: isEncrypted
                    ? liveText("storage.value.encrypted", "Encrypted")
                    : liveText("storage.value.notEncrypted", "Not Encrypted")
            ))
        }
        if let isReadOnly = volume.isReadOnly {
            metrics.append(StorageHealthMetric(
                kind: .access,
                name: liveText("storage.metric.access", "Access"),
                value: isReadOnly
                    ? liveText("storage.value.readOnly", "Read Only")
                    : liveText("storage.value.readWrite", "Read & Write")
            ))
        }

        let diskInfo = Self.diskutilInfo(for: volume.path)
        Self.appendDiskMetric("DeviceIdentifier", kind: .device, name: liveText("storage.metric.device", "Device"), from: diskInfo, to: &metrics)
        Self.appendDiskMetric("MediaName", kind: .media, name: liveText("storage.metric.media", "Media"), from: diskInfo, to: &metrics)
        Self.appendDiskMetric("BusProtocol", kind: .connection, name: liveText("storage.metric.connection", "Connection"), from: diskInfo, to: &metrics)
        if let solidState = diskInfo?["SolidState"] as? Bool {
            metrics.append(StorageHealthMetric(
                kind: .mediaType,
                name: liveText("storage.metric.mediaType", "Media Type"),
                value: solidState
                    ? liveText("storage.value.solidState", "Solid State")
                    : liveText("storage.value.rotational", "Rotational Storage")
            ))
        }

        let smart = diskInfo?["SMARTStatus"] as? String
        let availability: CapabilityAvailability
        let status: String
        switch smart?.lowercased() {
        case "verified":
            availability = .available
            status = liveText("storage.health.normal", "Normal")
        case "failing":
            availability = .available
            status = liveText("storage.health.serviceRequired", "Service Required")
        case "not supported":
            availability = .unavailable(
                reason: liveText(
                    "storage.health.smartUnsupportedReason",
                    "This device does not support S.M.A.R.T. status."
                )
            )
            status = liveText("storage.health.smartUnsupported", "S.M.A.R.T. Not Supported")
        case .some(let value):
            availability = .available
            status = value
        case nil:
            availability = .unavailable(
                reason: liveText(
                    "storage.health.smartUnknownReason",
                    "The device did not return a verifiable S.M.A.R.T. health status."
                )
            )
            status = liveText("common.unknown", "Unknown")
        }
        if let smart {
            metrics.append(StorageHealthMetric(kind: .smart, name: "SMART", value: smart))
        }

        return StorageHealth(
            availability: availability,
            status: status,
            temperatureCelsius: nil,
            lifeRemainingPercent: nil,
            metrics: metrics
        )
    }

    private static func diskutilInfo(for path: String) -> [String: Any]? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", path]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            return try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        } catch {
            return nil
        }
    }

    private static func appendDiskMetric(
        _ key: String,
        kind: StorageHealthMetric.Kind,
        name: String,
        from dictionary: [String: Any]?,
        to metrics: inout [StorageHealthMetric]
    ) {
        guard let value = dictionary?[key] as? String, !value.isEmpty else { return }
        metrics.append(StorageHealthMetric(kind: kind, name: name, value: value))
    }
}
