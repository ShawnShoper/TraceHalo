import Foundation

public extension SystemSnapshot {
    static var fixture: SystemSnapshot { SystemSnapshot(
        capturedAt: Date(),
        identity: HardwareIdentity(
            computerName: "Studio Mac",
            modelName: "Mac Studio",
            modelIdentifier: "Mac13,2",
            chipName: "Apple M1 Ultra",
            operatingSystem: "macOS 15.5",
            physicalMemoryBytes: 64 * 1_024 * 1_024 * 1_024,
            uptime: 296_460
        ),
        cpu: CPUState(
            totalPercent: 34,
            userPercent: 24,
            systemPercent: 10,
            perCorePercent: [
                22, 37, 31, 48, 16, 28, 42, 35, 12, 19,
                26, 30, 14, 11, 9, 7, 5, 4, 3, 2
            ],
            temperatureCelsius: 48,
            topProcesses: [
                ProcessUsage(id: 101, name: "Xcode", cpuPercent: 41.2, memoryBytes: 3_420_000_000),
                ProcessUsage(id: 102, name: "Simulator", cpuPercent: 22.5, memoryBytes: 1_940_000_000),
                ProcessUsage(id: 103, name: "WindowServer", cpuPercent: 13.6, memoryBytes: 816_000_000),
                ProcessUsage(id: 104, name: "Safari", cpuPercent: 8.4, memoryBytes: 1_240_000_000),
                ProcessUsage(id: 107, name: "ChatGPT", cpuPercent: 7.8, memoryBytes: 1_180_000_000),
                ProcessUsage(id: 108, name: "Lark", cpuPercent: 6.1, memoryBytes: 980_000_000),
                ProcessUsage(id: 109, name: "TraceHalo", cpuPercent: 4.7, memoryBytes: 184_000_000),
                ProcessUsage(id: 110, name: "Finder", cpuPercent: 3.9, memoryBytes: 326_000_000),
                ProcessUsage(id: 111, name: "WeChat", cpuPercent: 3.2, memoryBytes: 742_000_000),
                ProcessUsage(id: 112, name: "macOS Kernel", cpuPercent: 2.6, memoryBytes: 0)
            ]
        ),
        memory: MemoryState(
            totalBytes: 64 * 1_024 * 1_024 * 1_024,
            usedBytes: 14 * 1_024 * 1_024 * 1_024,
            activeBytes: 9 * 1_024 * 1_024 * 1_024,
            wiredBytes: 2 * 1_024 * 1_024 * 1_024,
            compressedBytes: 3 * 1_024 * 1_024 * 1_024,
            inactiveBytes: 5 * 1_024 * 1_024 * 1_024,
            availableBytes: 50 * 1_024 * 1_024 * 1_024,
            swapUsedBytes: 2 * 1_024 * 1_024 * 1_024,
            swapTotalBytes: 4 * 1_024 * 1_024 * 1_024,
            pressurePercent: 22,
            topProcesses: [
                ProcessUsage(id: 101, name: "Xcode", cpuPercent: 41.2, memoryBytes: 3_420_000_000),
                ProcessUsage(id: 105, name: "Safari", cpuPercent: 8.4, memoryBytes: 2_140_000_000),
                ProcessUsage(id: 106, name: "Photos", cpuPercent: 3.1, memoryBytes: 1_360_000_000)
            ]
        ),
        volumes: [
            StorageVolume(
                name: "Macintosh HD",
                path: "/",
                totalBytes: 1_000_000_000_000,
                availableBytes: 421_000_000_000,
                isInternal: true,
                isRemovable: false,
                isReadOnly: false,
                isEncrypted: true,
                fileSystem: "APFS",
                uuid: "REDACTED-FIXTURE-UUID"
            ),
            StorageVolume(
                name: "Studio Archive",
                path: "/Volumes/Studio Archive",
                totalBytes: 2_000_000_000_000,
                availableBytes: 1_240_000_000_000,
                isInternal: false,
                isRemovable: true,
                isReadOnly: false,
                isEncrypted: false,
                fileSystem: "APFS"
            )
        ],
        networkInterfaces: [
            NetworkInterfaceState(
                name: "en0",
                displayName: "Wi‑Fi",
                localAddress: "192.168.x.x",
                isActive: true,
                receivedBytesPerSecond: 2_840_000,
                sentBytesPerSecond: 364_000,
                linkSpeedMbps: 1_200,
                rssi: -51,
                noise: -92
            ),
            NetworkInterfaceState(
                name: "en7",
                displayName: TraceHaloLocalization.string("network.ethernet", defaultValue: "Ethernet"),
                localAddress: "10.0.x.x",
                isActive: true,
                linkSpeedMbps: 1_000
            )
        ],
        cooling: CoolingState(
            availability: .available,
            condition: .nominal,
            sensors: [
                ThermalSensor(key: "cpu", name: "CPU Die", group: "CPU", temperatureCelsius: 48),
                ThermalSensor(key: "gpu", name: "GPU Die", group: "GPU", temperatureCelsius: 43),
                ThermalSensor(key: "memory", name: "Memory", group: TraceHaloLocalization.string("sensor.group.memory", defaultValue: "Memory"), temperatureCelsius: 41),
                ThermalSensor(key: "storage", name: "SSD", group: TraceHaloLocalization.string("sensor.group.storage", defaultValue: "Storage"), temperatureCelsius: 36),
                ThermalSensor(key: "ambient", name: "Ambient", group: TraceHaloLocalization.string("sensor.group.ambient", defaultValue: "Ambient"), temperatureCelsius: 24)
            ],
            fans: [
                FanState(name: "Fan 1", currentRPM: 1_326, minimumRPM: 1_100, maximumRPM: 3_500, targetRPM: 1_326),
                FanState(name: "Fan 2", currentRPM: 1_329, minimumRPM: 1_100, maximumRPM: 3_500, targetRPM: 1_329)
            ]
        ),
        battery: BatteryState(
            availability: .unavailable(
                reason: TraceHaloLocalization.string(
                    "battery.desktop.none",
                    defaultValue: "This desktop Mac does not have a built-in battery."
                )
            )
        ),
        gpus: [
            GPUState(
                name: "Apple M1 Ultra",
                vendor: "Apple",
                family: TraceHaloLocalization.string("gpu.memory.unified", defaultValue: "Unified Memory"),
                memoryDescription: "48 GB",
                driver: "com.apple.AGXG13X · 351.2",
                metalSupport: "Metal · Apple 7",
                modelIdentifier: "gpu,t6000",
                registryID: 0x100001070,
                coreCount: 64,
                isLowPower: true,
                isRemovable: false,
                hasUnifiedMemory: true,
                supportsRayTracing: true,
                supportsRayTracingInRenderPipelines: true,
                supportsDynamicLibraries: true,
                supportsRenderDynamicLibraries: true,
                argumentBufferTier: "Tier 2",
                maximumBufferLengthBytes: 32 * 1_024 * 1_024 * 1_024,
                maximumThreadgroupMemoryBytes: 32 * 1_024,
                maximumThreadsPerThreadgroup: "1024 × 1024 × 64",
                utilizationPercent: 19,
                temperatureCelsius: 43,
                usedMemoryBytes: 1_280_000_000,
                allocatedMemoryBytes: 8_000_000_000,
                displays: [
                    DisplayDevice(
                        name: "Studio Display",
                        resolution: "5120 × 2880",
                        refreshRateHz: 60,
                        isMain: true,
                        isBuiltIn: false,
                        displayID: 1,
                        vendorID: 0x0610,
                        productID: 0xA064,
                        serialNumber: 1,
                        pixelDimensions: TraceHaloLocalization.format(
                            "display.pixelDimensions",
                            defaultValue: "%@ pixels",
                            "5120 × 2880"
                        )
                    )
                ]
            )
        ],
        storageIO: StorageIOState(
            availability: .available,
            totalReadBytes: 4_024_514_007_040,
            totalWrittenBytes: 3_225_660_510_208,
            totalReadOperations: 464_327_179,
            totalWriteOperations: 149_019_979,
            readBytesPerSecond: 84_000_000,
            writeBytesPerSecond: 31_000_000,
            readOperationsPerSecond: 1_240,
            writeOperationsPerSecond: 690,
            deviceNames: ["APPLE SSD AP1024R Media"]
        ),
        inputDevices: InputDeviceInventory(
            availability: .available,
            devices: [
                InputDeviceState(
                    stableIdentifier: "hid-fixture-magic-keyboard",
                    name: "Magic Keyboard",
                    kinds: [.keyboard],
                    manufacturer: "Apple Inc.",
                    transport: "Bluetooth",
                    vendorID: 0x05AC,
                    productID: 0x0267,
                    versionNumber: 0x0110,
                    locationID: 0x0100_0000,
                    serialNumber: "REDACTED-FIXTURE-KEYBOARD",
                    isBuiltIn: false,
                    battery: InputDeviceBatteryState(
                        availability: .unavailable(
                            reason: TraceHaloLocalization.string(
                                "input.battery.unavailable",
                                defaultValue: "The device did not report a battery level through compatible Apple driver IORegistry metadata."
                            )
                        ),
                        chargingState: .unknown
                    )
                ),
                InputDeviceState(
                    stableIdentifier: "hid-fixture-magic-mouse",
                    name: "Magic Mouse",
                    kinds: [.mouse, .pointingDevice],
                    manufacturer: "Apple Inc.",
                    transport: "Bluetooth",
                    vendorID: 0x05AC,
                    productID: 0x0269,
                    versionNumber: 0x0100,
                    locationID: 0x0100_0001,
                    serialNumber: "REDACTED-FIXTURE-MOUSE",
                    isBuiltIn: false,
                    battery: InputDeviceBatteryState(
                        availability: .available,
                        levelPercent: 76,
                        source: .appleDriverRegistry,
                        chargingState: .notCharging
                    )
                ),
                InputDeviceState(
                    stableIdentifier: "hid-fixture-magic-trackpad",
                    name: "Magic Trackpad",
                    kinds: [.mouse, .trackpad, .pointingDevice],
                    manufacturer: "Apple Inc.",
                    transport: "Bluetooth",
                    vendorID: 0x05AC,
                    productID: 0x0265,
                    versionNumber: 0x0110,
                    locationID: 0x0100_0002,
                    serialNumber: "REDACTED-FIXTURE-TRACKPAD",
                    isBuiltIn: false,
                    battery: InputDeviceBatteryState(
                        availability: .available,
                        levelPercent: 62,
                        source: .appleDriverRegistry,
                        chargingState: .charging
                    )
                )
            ]
        )
    ) }
}

public enum FixtureCatalog {
    public static var startupItems: [StartupItem] { [
        StartupItem(
            label: "com.example.sync",
            displayName: "Cloud Sync",
            developer: "Example Studio",
            kind: .loginItem,
            path: "/Applications/Cloud Sync.app",
            isEnabled: true,
            scopeKind: .currentUser
        ),
        StartupItem(
            label: "com.example.helper",
            displayName: "Example Helper",
            developer: "Example Studio",
            kind: .launchAgent,
            path: "~/Library/LaunchAgents/com.example.helper.plist",
            isEnabled: false,
            scopeKind: .currentUser
        ),
        StartupItem(
            label: "com.example.service",
            displayName: "Example Service",
            developer: "Example Studio",
            kind: .launchDaemon,
            path: "/Library/LaunchDaemons/com.example.service.plist",
            isEnabled: true,
            scopeKind: .allUsers
        )
    ] }

    public static var applications: [ApplicationCandidate] { [
        ApplicationCandidate(
            name: "Sample Studio",
            bundleIdentifier: "com.example.SampleStudio",
            version: "5.2",
            bundleURL: URL(fileURLWithPath: "/Applications/Sample Studio.app"),
            sizeBytes: 682_000_000,
            associatedFiles: [
                AssociatedFile(
                    path: "~/Library/Application Support/Sample Studio",
                    category: .support,
                    sizeBytes: 312_000_000,
                    ownershipReason: TraceHaloLocalization.string(
                        "association.reason.applicationName.short",
                        defaultValue: "Directory name matches the application name"
                    ),
                    matchBasis: .applicationName("Sample Studio")
                ),
                AssociatedFile(
                    path: "~/Library/Caches/com.example.SampleStudio",
                    category: .cache,
                    sizeBytes: 84_000_000,
                    ownershipReason: TraceHaloLocalization.string(
                        "association.reason.bundleExact.short",
                        defaultValue: "Bundle identifier matches exactly"
                    ),
                    matchBasis: .exactBundleIdentifier("com.example.SampleStudio")
                ),
                AssociatedFile(
                    path: "~/Library/Preferences/com.example.SampleStudio.plist",
                    category: .preference,
                    sizeBytes: 18_000,
                    ownershipReason: TraceHaloLocalization.string(
                        "association.reason.bundleExact.short",
                        defaultValue: "Bundle identifier matches exactly"
                    ),
                    matchBasis: .exactBundleIdentifier("com.example.SampleStudio")
                )
            ]
        ),
        ApplicationCandidate(
            name: "Telemetry Notes",
            bundleIdentifier: "com.example.TelemetryNotes",
            version: "2.8",
            bundleURL: URL(fileURLWithPath: "/Applications/Telemetry Notes.app"),
            sizeBytes: 128_000_000,
            associatedFiles: []
        )
    ] }

    public static let storageHealth = StorageHealth(
        availability: .available,
        status: "Verified",
        temperatureCelsius: 36,
        lifeRemainingPercent: 98,
        metrics: [
            StorageHealthMetric(name: "Critical Warning", value: "0"),
            StorageHealthMetric(name: "Available Spare", value: "100%"),
            StorageHealthMetric(name: "Percentage Used", value: "2%"),
            StorageHealthMetric(name: "Data Units Read", value: "55.2 TB"),
            StorageHealthMetric(name: "Data Units Written", value: "60.8 TB"),
            StorageHealthMetric(name: "Power On Hours", value: "2,901 h"),
            StorageHealthMetric(name: "Unsafe Shutdowns", value: "45"),
            StorageHealthMetric(name: "Media/Data Errors", value: "0")
        ]
    )
}

public struct FixtureSystemMetricsProvider: SystemMetricsProviding {
    public init() {}

    public func snapshot() async -> SystemSnapshot {
        var value = SystemSnapshot.fixture
        value.capturedAt = Date()
        return value
    }
}

public struct FixtureStartupItemProvider: StartupItemProviding {
    public init() {}
    public func items() async throws -> [StartupItem] { FixtureCatalog.startupItems }
}

public struct FixtureApplicationProvider: ApplicationProviding {
    public init() {}
    public func applications() async throws -> [ApplicationCandidate] { FixtureCatalog.applications }
}

public struct FixtureStorageHealthProvider: StorageHealthProviding {
    public init() {}
    public func health(for volume: StorageVolume) async -> StorageHealth { FixtureCatalog.storageHealth }
}
