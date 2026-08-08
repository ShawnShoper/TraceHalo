import Foundation

public enum CapabilityAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)
    case permissionRequired(reason: String)
    case failed(reason: String)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    public var message: String? {
        switch self {
        case .available:
            nil
        case let .unavailable(reason), let .permissionRequired(reason), let .failed(reason):
            reason
        }
    }
}

public struct MetricPoint: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let value: Double

    public init(id: UUID = UUID(), timestamp: Date = Date(), value: Double) {
        self.id = id
        self.timestamp = timestamp
        self.value = value
    }
}

public struct HardwareIdentity: Equatable, Sendable {
    public var computerName: String
    public var modelName: String
    public var modelIdentifier: String
    public var chipName: String
    public var operatingSystem: String
    public var physicalMemoryBytes: UInt64
    public var uptime: TimeInterval

    public init(
        computerName: String,
        modelName: String,
        modelIdentifier: String,
        chipName: String,
        operatingSystem: String,
        physicalMemoryBytes: UInt64,
        uptime: TimeInterval
    ) {
        self.computerName = computerName
        self.modelName = modelName
        self.modelIdentifier = modelIdentifier
        self.chipName = chipName
        self.operatingSystem = operatingSystem
        self.physicalMemoryBytes = physicalMemoryBytes
        self.uptime = uptime
    }
}

public struct ProcessUsage: Identifiable, Equatable, Sendable {
    public let id: Int32
    public var name: String
    public var cpuPercent: Double
    public var memoryBytes: UInt64
    public var energyImpact: Double?

    public init(
        id: Int32,
        name: String,
        cpuPercent: Double,
        memoryBytes: UInt64,
        energyImpact: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.energyImpact = energyImpact
    }
}

public struct CPUState: Equatable, Sendable {
    public var totalPercent: Double
    public var userPercent: Double
    public var systemPercent: Double
    public var perCorePercent: [Double]
    public var temperatureCelsius: Double?
    public var topProcesses: [ProcessUsage]

    public init(
        totalPercent: Double,
        userPercent: Double,
        systemPercent: Double,
        perCorePercent: [Double],
        temperatureCelsius: Double?,
        topProcesses: [ProcessUsage]
    ) {
        self.totalPercent = totalPercent
        self.userPercent = userPercent
        self.systemPercent = systemPercent
        self.perCorePercent = perCorePercent
        self.temperatureCelsius = temperatureCelsius
        self.topProcesses = topProcesses
    }
}

public struct MemoryState: Equatable, Sendable {
    public var totalBytes: UInt64
    public var usedBytes: UInt64
    public var activeBytes: UInt64
    public var wiredBytes: UInt64
    public var compressedBytes: UInt64
    public var inactiveBytes: UInt64
    public var availableBytes: UInt64
    public var swapUsedBytes: UInt64
    public var swapTotalBytes: UInt64
    public var pressurePercent: Double
    public var topProcesses: [ProcessUsage]

    public init(
        totalBytes: UInt64,
        usedBytes: UInt64,
        activeBytes: UInt64,
        wiredBytes: UInt64,
        compressedBytes: UInt64,
        inactiveBytes: UInt64,
        availableBytes: UInt64,
        swapUsedBytes: UInt64,
        swapTotalBytes: UInt64,
        pressurePercent: Double,
        topProcesses: [ProcessUsage]
    ) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.activeBytes = activeBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.inactiveBytes = inactiveBytes
        self.availableBytes = availableBytes
        self.swapUsedBytes = swapUsedBytes
        self.swapTotalBytes = swapTotalBytes
        self.pressurePercent = pressurePercent
        self.topProcesses = topProcesses
    }
}

public struct StorageVolume: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public var name: String
    public var path: String
    public var totalBytes: UInt64
    public var availableBytes: UInt64
    public var isInternal: Bool?
    public var isRemovable: Bool?
    public var isReadOnly: Bool?
    public var isEncrypted: Bool?
    public var fileSystem: String?
    public var uuid: String?

    public var usedBytes: UInt64 { totalBytes > availableBytes ? totalBytes - availableBytes : 0 }
    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(totalBytes), 0), 1)
    }

    public init(
        name: String,
        path: String,
        totalBytes: UInt64,
        availableBytes: UInt64,
        isInternal: Bool? = nil,
        isRemovable: Bool? = nil,
        isReadOnly: Bool? = nil,
        isEncrypted: Bool? = nil,
        fileSystem: String? = nil,
        uuid: String? = nil
    ) {
        self.name = name
        self.path = path
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.isInternal = isInternal
        self.isRemovable = isRemovable
        self.isReadOnly = isReadOnly
        self.isEncrypted = isEncrypted
        self.fileSystem = fileSystem
        self.uuid = uuid
    }
}

/// Aggregate read-only block-storage counters reported by IOKit.
///
/// macOS exposes these counters per physical block-storage driver rather than
/// per APFS volume. Keeping them separate from `StorageVolume` avoids assigning
/// physical-device traffic to an arbitrary mounted volume.
/// The cumulative values start when each `IOBlockStorageDriver` instance starts;
/// they are not lifetime media counters.
public struct StorageIOState: Equatable, Sendable {
    public var availability: CapabilityAvailability
    public var totalReadBytes: UInt64
    public var totalWrittenBytes: UInt64
    public var totalReadOperations: UInt64
    public var totalWriteOperations: UInt64
    public var readBytesPerSecond: Double?
    public var writeBytesPerSecond: Double?
    public var readOperationsPerSecond: Double?
    public var writeOperationsPerSecond: Double?
    public var deviceNames: [String]

    public init(
        availability: CapabilityAvailability,
        totalReadBytes: UInt64 = 0,
        totalWrittenBytes: UInt64 = 0,
        totalReadOperations: UInt64 = 0,
        totalWriteOperations: UInt64 = 0,
        readBytesPerSecond: Double? = nil,
        writeBytesPerSecond: Double? = nil,
        readOperationsPerSecond: Double? = nil,
        writeOperationsPerSecond: Double? = nil,
        deviceNames: [String] = []
    ) {
        self.availability = availability
        self.totalReadBytes = totalReadBytes
        self.totalWrittenBytes = totalWrittenBytes
        self.totalReadOperations = totalReadOperations
        self.totalWriteOperations = totalWriteOperations
        self.readBytesPerSecond = readBytesPerSecond
        self.writeBytesPerSecond = writeBytesPerSecond
        self.readOperationsPerSecond = readOperationsPerSecond
        self.writeOperationsPerSecond = writeOperationsPerSecond
        self.deviceNames = deviceNames
    }
}

public enum InputDeviceKind: String, CaseIterable, Equatable, Sendable {
    case keyboard
    case mouse
    case trackpad
    case pointingDevice
}

public enum InputDeviceBatterySource: String, Equatable, Sendable {
    /// A compatibility value published by Apple's input-device driver in the
    /// public IORegistry. The registry key is not a stable cross-version API,
    /// so callers must present it as a best-effort Apple driver report.
    case appleDriverRegistry
}

public enum InputDeviceChargingState: String, CaseIterable, Equatable, Hashable, Sendable {
    case charging
    case notCharging
    case unknown
}

public struct InputDeviceBatteryState: Equatable, Sendable {
    public var availability: CapabilityAvailability
    public var levelPercent: Double?
    public var source: InputDeviceBatterySource?
    public var chargingState: InputDeviceChargingState

    public init(
        availability: CapabilityAvailability,
        levelPercent: Double? = nil,
        source: InputDeviceBatterySource? = nil,
        chargingState: InputDeviceChargingState = .unknown
    ) {
        self.availability = availability
        self.levelPercent = levelPercent
        self.source = source
        self.chargingState = chargingState
    }
}

/// A physical keyboard, mouse, trackpad, or other pointing device assembled
/// from one or more IOHID application collections.
///
/// `stableIdentifier` is an opaque deterministic identifier derived from the
/// strongest public physical identity that IOHID reports. It deliberately does
/// not expose a serial number or `PhysicalDeviceUniqueID` through `id`.
public struct InputDeviceState: Identifiable, Equatable, Sendable {
    public var id: String { stableIdentifier }
    public var stableIdentifier: String
    public var name: String
    public var kinds: [InputDeviceKind]
    public var manufacturer: String?
    public var transport: String?
    public var vendorID: UInt64?
    public var productID: UInt64?
    public var versionNumber: UInt64?
    public var locationID: UInt64?
    public var serialNumber: String?
    public var isBuiltIn: Bool?
    public var battery: InputDeviceBatteryState

    public var primaryKind: InputDeviceKind {
        if kinds.contains(.trackpad) { return .trackpad }
        if kinds.contains(.mouse) { return .mouse }
        if kinds.contains(.keyboard) { return .keyboard }
        return .pointingDevice
    }

    public init(
        stableIdentifier: String,
        name: String,
        kinds: [InputDeviceKind],
        manufacturer: String? = nil,
        transport: String? = nil,
        vendorID: UInt64? = nil,
        productID: UInt64? = nil,
        versionNumber: UInt64? = nil,
        locationID: UInt64? = nil,
        serialNumber: String? = nil,
        isBuiltIn: Bool? = nil,
        battery: InputDeviceBatteryState = InputDeviceBatteryState(
            availability: .unavailable(
                reason: TraceHaloLocalization.string(
                    "input.battery.unavailable",
                    defaultValue: "The device did not report a battery level through compatible Apple driver IORegistry metadata."
                )
            )
        )
    ) {
        self.stableIdentifier = stableIdentifier
        self.name = name
        self.kinds = Self.normalizedKinds(kinds)
        self.manufacturer = manufacturer
        self.transport = transport
        self.vendorID = vendorID
        self.productID = productID
        self.versionNumber = versionNumber
        self.locationID = locationID
        self.serialNumber = serialNumber
        self.isBuiltIn = isBuiltIn
        self.battery = battery
    }

    private static func normalizedKinds(_ kinds: [InputDeviceKind]) -> [InputDeviceKind] {
        let unique = Set(kinds)
        return InputDeviceKind.allCases.filter(unique.contains)
    }
}

public struct InputDeviceInventory: Equatable, Sendable {
    public var availability: CapabilityAvailability
    public var devices: [InputDeviceState]

    public init(
        availability: CapabilityAvailability,
        devices: [InputDeviceState] = []
    ) {
        self.availability = availability
        self.devices = devices
    }
}

public struct NetworkInterfaceState: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var displayName: String
    public var localAddress: String?
    public var isActive: Bool
    public var receivedBytesPerSecond: Double?
    public var sentBytesPerSecond: Double?
    public var linkSpeedMbps: Double?
    public var rssi: Int?
    public var noise: Int?

    public init(
        name: String,
        displayName: String,
        localAddress: String?,
        isActive: Bool,
        receivedBytesPerSecond: Double? = nil,
        sentBytesPerSecond: Double? = nil,
        linkSpeedMbps: Double? = nil,
        rssi: Int? = nil,
        noise: Int? = nil
    ) {
        self.name = name
        self.displayName = displayName
        self.localAddress = localAddress
        self.isActive = isActive
        self.receivedBytesPerSecond = receivedBytesPerSecond
        self.sentBytesPerSecond = sentBytesPerSecond
        self.linkSpeedMbps = linkSpeedMbps
        self.rssi = rssi
        self.noise = noise
    }
}

public enum ThermalCondition: String, Equatable, Sendable {
    case nominal
    case fair
    case serious
    case critical
    case unavailable
}

public struct ThermalSensor: Identifiable, Equatable, Sendable {
    public var id: String { key }
    public var key: String
    public var name: String
    public var group: String
    public var temperatureCelsius: Double

    public init(key: String, name: String, group: String, temperatureCelsius: Double) {
        self.key = key
        self.name = name
        self.group = group
        self.temperatureCelsius = temperatureCelsius
    }
}

public struct FanState: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var currentRPM: Int
    public var minimumRPM: Int?
    public var maximumRPM: Int?
    public var targetRPM: Int?

    public init(name: String, currentRPM: Int, minimumRPM: Int? = nil, maximumRPM: Int? = nil, targetRPM: Int? = nil) {
        self.name = name
        self.currentRPM = currentRPM
        self.minimumRPM = minimumRPM
        self.maximumRPM = maximumRPM
        self.targetRPM = targetRPM
    }
}

public struct CoolingState: Equatable, Sendable {
    public var availability: CapabilityAvailability
    /// Availability of detailed SMC/HID sensors. This is intentionally separate
    /// from the public system thermal condition, which can remain available even
    /// when fan RPM and temperatures cannot be read.
    public var sensorAvailability: CapabilityAvailability
    public var condition: ThermalCondition
    public var sensors: [ThermalSensor]
    public var fans: [FanState]

    public init(
        availability: CapabilityAvailability,
        sensorAvailability: CapabilityAvailability = .available,
        condition: ThermalCondition,
        sensors: [ThermalSensor],
        fans: [FanState]
    ) {
        self.availability = availability
        self.sensorAvailability = sensorAvailability
        self.condition = condition
        self.sensors = sensors
        self.fans = fans
    }
}

public enum BatteryHealth: String, Equatable, Sendable {
    case excellent
    case good
    case aging
    case serviceRecommended
    case unknown
}

/// Describes where TraceHalo obtained the user-facing battery health result.
///
/// The public IOPowerSources health fields are authoritative when present.
/// Raw capacity values are kept as a separate estimate because their ratio is
/// not the same metric shown as “Maximum Capacity” in System Settings.
public enum BatteryHealthBasis: String, Equatable, Sendable {
    case systemReported
    case rawCapacityEstimate
    case unavailable
}

public struct BatteryState: Equatable, Sendable {
    public var availability: CapabilityAvailability
    public var chargePercent: Double?
    public var isCharging: Bool
    public var health: BatteryHealth
    public var healthBasis: BatteryHealthBasis
    public var currentCapacityMAh: Int?
    public var maximumCapacityMAh: Int?
    public var designCapacityMAh: Int?
    public var cycleCount: Int?
    public var designCycleCount: Int?
    public var voltageMV: Int?
    public var amperageMA: Int?
    public var temperatureCelsius: Double?
    public var timeRemainingMinutes: Int?
    public var manufacturer: String?
    public var serialNumber: String?

    /// Signed electrical power at the internal battery pack. This is not the
    /// Mac's wall, adapter, or whole-system input power.
    public var powerWatts: Double? {
        guard let voltageMV, let amperageMA else { return nil }
        return Double(voltageMV) * Double(amperageMA) / 1_000_000
    }

    /// A best-effort ratio from the battery driver's raw full-charge and design
    /// capacity counters. This is deliberately not named `maximumCapacityPercent`:
    /// macOS System Settings uses a separate, Apple-defined health estimate.
    public var rawCapacityEstimatePercent: Double? {
        guard
            let maximumCapacityMAh,
            let designCapacityMAh,
            maximumCapacityMAh > 0,
            designCapacityMAh > 0
        else {
            return nil
        }
        let percent = Double(maximumCapacityMAh) / Double(designCapacityMAh) * 100
        guard percent.isFinite, (0...150).contains(percent) else { return nil }
        return min(percent, 100)
    }

    public init(
        availability: CapabilityAvailability,
        chargePercent: Double? = nil,
        isCharging: Bool = false,
        health: BatteryHealth = .unknown,
        healthBasis: BatteryHealthBasis = .unavailable,
        currentCapacityMAh: Int? = nil,
        maximumCapacityMAh: Int? = nil,
        designCapacityMAh: Int? = nil,
        cycleCount: Int? = nil,
        designCycleCount: Int? = nil,
        voltageMV: Int? = nil,
        amperageMA: Int? = nil,
        temperatureCelsius: Double? = nil,
        timeRemainingMinutes: Int? = nil,
        manufacturer: String? = nil,
        serialNumber: String? = nil
    ) {
        self.availability = availability
        self.chargePercent = chargePercent
        self.isCharging = isCharging
        self.health = health
        self.healthBasis = healthBasis
        self.currentCapacityMAh = currentCapacityMAh
        self.maximumCapacityMAh = maximumCapacityMAh
        self.designCapacityMAh = designCapacityMAh
        self.cycleCount = cycleCount
        self.designCycleCount = designCycleCount
        self.voltageMV = voltageMV
        self.amperageMA = amperageMA
        self.temperatureCelsius = temperatureCelsius
        self.timeRemainingMinutes = timeRemainingMinutes
        self.manufacturer = manufacturer
        self.serialNumber = serialNumber
    }
}

public struct DisplayDevice: Identifiable, Equatable, Sendable {
    public var id: String {
        if let displayID { return "cg-display-\(displayID)" }
        return "\(vendorID ?? 0)-\(productID ?? 0)-\(serialNumber ?? 0)-\(name)-\(resolution)"
    }
    public var name: String
    public var resolution: String
    public var refreshRateHz: Double?
    public var isMain: Bool
    public var isBuiltIn: Bool
    public var displayID: UInt32?
    public var vendorID: UInt32?
    public var productID: UInt32?
    public var serialNumber: UInt32?
    /// Physical pixel dimensions of the selected display mode. This is not a
    /// color bit depth and can differ from the logical resolution on Retina displays.
    public var pixelDimensions: String?

    public init(
        name: String,
        resolution: String,
        refreshRateHz: Double? = nil,
        isMain: Bool = false,
        isBuiltIn: Bool = false,
        displayID: UInt32? = nil,
        vendorID: UInt32? = nil,
        productID: UInt32? = nil,
        serialNumber: UInt32? = nil,
        pixelDimensions: String? = nil
    ) {
        self.name = name
        self.resolution = resolution
        self.refreshRateHz = refreshRateHz
        self.isMain = isMain
        self.isBuiltIn = isBuiltIn
        self.displayID = displayID
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.pixelDimensions = pixelDimensions
    }
}

public struct GPUState: Identifiable, Equatable, Sendable {
    public var id: String {
        registryID.map { "gpu-\($0)" } ?? "\(vendor)-\(modelIdentifier ?? name)"
    }
    public var name: String
    public var vendor: String
    public var family: String?
    public var memoryDescription: String?
    public var driver: String?
    public var metalSupport: String?
    public var modelIdentifier: String?
    public var registryID: UInt64?
    public var coreCount: Int?
    public var isLowPower: Bool?
    public var isRemovable: Bool?
    public var hasUnifiedMemory: Bool?
    /// Metal ray-tracing API support in compute pipelines.
    public var supportsRayTracing: Bool?
    /// Metal ray-tracing API support in render pipeline stages.
    public var supportsRayTracingInRenderPipelines: Bool?
    /// Metal dynamic-library support in compute pipelines.
    public var supportsDynamicLibraries: Bool?
    /// Metal dynamic-library support in render pipeline stages.
    public var supportsRenderDynamicLibraries: Bool?
    public var argumentBufferTier: String?
    public var maximumBufferLengthBytes: UInt64?
    public var maximumThreadgroupMemoryBytes: UInt64?
    public var maximumThreadsPerThreadgroup: String?
    public var utilizationPercent: Double?
    public var temperatureCelsius: Double?
    public var usedMemoryBytes: UInt64?
    public var allocatedMemoryBytes: UInt64?
    public var displays: [DisplayDevice]

    public init(
        name: String,
        vendor: String,
        family: String? = nil,
        memoryDescription: String? = nil,
        driver: String? = nil,
        metalSupport: String? = nil,
        modelIdentifier: String? = nil,
        registryID: UInt64? = nil,
        coreCount: Int? = nil,
        isLowPower: Bool? = nil,
        isRemovable: Bool? = nil,
        hasUnifiedMemory: Bool? = nil,
        supportsRayTracing: Bool? = nil,
        supportsRayTracingInRenderPipelines: Bool? = nil,
        supportsDynamicLibraries: Bool? = nil,
        supportsRenderDynamicLibraries: Bool? = nil,
        argumentBufferTier: String? = nil,
        maximumBufferLengthBytes: UInt64? = nil,
        maximumThreadgroupMemoryBytes: UInt64? = nil,
        maximumThreadsPerThreadgroup: String? = nil,
        utilizationPercent: Double? = nil,
        temperatureCelsius: Double? = nil,
        usedMemoryBytes: UInt64? = nil,
        allocatedMemoryBytes: UInt64? = nil,
        displays: [DisplayDevice] = []
    ) {
        self.name = name
        self.vendor = vendor
        self.family = family
        self.memoryDescription = memoryDescription
        self.driver = driver
        self.metalSupport = metalSupport
        self.modelIdentifier = modelIdentifier
        self.registryID = registryID
        self.coreCount = coreCount
        self.isLowPower = isLowPower
        self.isRemovable = isRemovable
        self.hasUnifiedMemory = hasUnifiedMemory
        self.supportsRayTracing = supportsRayTracing
        self.supportsRayTracingInRenderPipelines = supportsRayTracingInRenderPipelines
        self.supportsDynamicLibraries = supportsDynamicLibraries
        self.supportsRenderDynamicLibraries = supportsRenderDynamicLibraries
        self.argumentBufferTier = argumentBufferTier
        self.maximumBufferLengthBytes = maximumBufferLengthBytes
        self.maximumThreadgroupMemoryBytes = maximumThreadgroupMemoryBytes
        self.maximumThreadsPerThreadgroup = maximumThreadsPerThreadgroup
        self.utilizationPercent = utilizationPercent
        self.temperatureCelsius = temperatureCelsius
        self.usedMemoryBytes = usedMemoryBytes
        self.allocatedMemoryBytes = allocatedMemoryBytes
        self.displays = displays
    }
}

public struct SystemSnapshot: Equatable, Sendable {
    public var capturedAt: Date
    public var identity: HardwareIdentity
    public var cpu: CPUState
    public var memory: MemoryState
    public var volumes: [StorageVolume]
    public var networkInterfaces: [NetworkInterfaceState]
    public var cooling: CoolingState
    public var battery: BatteryState
    public var gpus: [GPUState]
    public var storageIO: StorageIOState
    public var inputDevices: InputDeviceInventory

    public init(
        capturedAt: Date = Date(),
        identity: HardwareIdentity,
        cpu: CPUState,
        memory: MemoryState,
        volumes: [StorageVolume],
        networkInterfaces: [NetworkInterfaceState],
        cooling: CoolingState,
        battery: BatteryState,
        gpus: [GPUState],
        storageIO: StorageIOState = StorageIOState(
            availability: .unavailable(
                reason: TraceHaloLocalization.string(
                    "storage.io.pending",
                    defaultValue: "IOKit has not returned block-storage statistics yet."
                )
            )
        ),
        inputDevices: InputDeviceInventory = InputDeviceInventory(
            availability: .unavailable(
                reason: TraceHaloLocalization.string(
                    "input.inventory.pending",
                    defaultValue: "IOHID has not returned keyboard and mouse devices yet."
                )
            )
        )
    ) {
        self.capturedAt = capturedAt
        self.identity = identity
        self.cpu = cpu
        self.memory = memory
        self.volumes = volumes
        self.networkInterfaces = networkInterfaces
        self.cooling = cooling
        self.battery = battery
        self.gpus = gpus
        self.storageIO = storageIO
        self.inputDevices = inputDevices
    }
}
