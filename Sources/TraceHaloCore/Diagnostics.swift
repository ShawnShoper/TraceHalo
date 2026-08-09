import Foundation

public struct SystemReportOptions: Equatable, Sendable {
    public var includeHardware: Bool
    public var includePerformance: Bool
    public var includeStorage: Bool
    public var includeGraphics: Bool
    public var includeCooling: Bool
    public var includeBattery: Bool
    public var includeNetworkAddresses: Bool
    public var includeProcessNames: Bool
    public var includeVolumeNames: Bool

    public init(
        includeHardware: Bool = true,
        includePerformance: Bool = true,
        includeStorage: Bool = true,
        includeGraphics: Bool = true,
        includeCooling: Bool = true,
        includeBattery: Bool = true,
        includeNetworkAddresses: Bool = false,
        includeProcessNames: Bool = false,
        includeVolumeNames: Bool = false
    ) {
        self.includeHardware = includeHardware
        self.includePerformance = includePerformance
        self.includeStorage = includeStorage
        self.includeGraphics = includeGraphics
        self.includeCooling = includeCooling
        self.includeBattery = includeBattery
        self.includeNetworkAddresses = includeNetworkAddresses
        self.includeProcessNames = includeProcessNames
        self.includeVolumeNames = includeVolumeNames
    }
}

public enum BatteryHealthRules {
    public static func evaluate(
        maximumCapacity: Int?,
        designCapacity: Int?,
        serviceRecommended: Bool
    ) -> BatteryHealth {
        if serviceRecommended { return .serviceRecommended }
        guard
            let maximumCapacity,
            let designCapacity,
            designCapacity > 0,
            maximumCapacity >= 0
        else {
            return .unknown
        }

        let ratio = Double(maximumCapacity) / Double(designCapacity)
        return switch ratio {
        case 0.90...: .excellent
        case 0.80..<0.90: .good
        case 0.65..<0.80: .aging
        default: .serviceRecommended
        }
    }
}

public enum ThermalRules {
    public static func condition(for state: ProcessInfo.ThermalState) -> ThermalCondition {
        return switch state {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .unavailable
        }
    }

    public static func condition(forCelsius value: Double?) -> ThermalCondition {
        guard let value, value.isFinite else { return .unavailable }
        return switch value {
        case ..<70: .nominal
        case 70..<85: .fair
        case 85..<95: .serious
        default: .critical
        }
    }
}

public struct SystemReportBuilder: Sendable {
    public init() {}

    public func text(
        snapshot: SystemSnapshot,
        options: SystemReportOptions,
        locale: Locale? = nil
    ) -> String {
        let locale = locale ?? TraceHaloLocalization.currentLocale()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium

        var lines = [
            localized("report.title", "TraceHalo System Report", locale: locale),
            formatted(
                "report.generated",
                "Generated: %@",
                locale: locale,
                dateFormatter.string(from: snapshot.capturedAt)
            ),
            ""
        ]

        if options.includeHardware {
            lines += [
                localized("report.section.hardware", "[Hardware]", locale: locale),
                formatted("report.hardware.model", "Model: %@", locale: locale, snapshot.identity.modelName),
                formatted("report.hardware.identifier", "Identifier: %@", locale: locale, snapshot.identity.modelIdentifier),
                formatted("report.hardware.chip", "Chip: %@", locale: locale, snapshot.identity.chipName),
                formatted("report.hardware.memory", "Memory: %@", locale: locale, MetricFormatter.bytes(snapshot.identity.physicalMemoryBytes)),
                formatted("report.hardware.system", "System: %@", locale: locale, snapshot.identity.operatingSystem),
                formatted("report.hardware.uptime", "Uptime: %@", locale: locale, MetricFormatter.duration(snapshot.identity.uptime, locale: locale)),
                inputDeviceSummary(snapshot.inputDevices, locale: locale),
                localized("report.hardware.inputSerials", "Input device serials: [redacted]", locale: locale),
                ""
            ]
        }

        if options.includePerformance {
            lines += [
                localized("report.section.performance", "[Performance]", locale: locale),
                formatted("report.performance.cpu", "CPU: %@", locale: locale, MetricFormatter.percent(snapshot.cpu.totalPercent, locale: locale)),
                formatted(
                    "report.performance.cpuUserSystem",
                    "CPU User/System: %@ / %@",
                    locale: locale,
                    MetricFormatter.percent(snapshot.cpu.userPercent, locale: locale),
                    MetricFormatter.percent(snapshot.cpu.systemPercent, locale: locale)
                ),
                formatted("report.performance.memoryEstimate", "Memory used estimate: %@", locale: locale, MetricFormatter.percent(snapshot.memory.pressurePercent, locale: locale)),
                formatted(
                    "report.performance.memoryUsed",
                    "Memory used: %@ of %@",
                    locale: locale,
                    MetricFormatter.bytes(snapshot.memory.usedBytes),
                    MetricFormatter.bytes(snapshot.memory.totalBytes)
                )
            ]
            if options.includeProcessNames {
                lines.append(formatted(
                    "report.performance.topProcesses",
                    "Top CPU processes: %@",
                    locale: locale,
                    snapshot.cpu.topProcesses.map(\.name).joined(separator: ", ")
                ))
            } else {
                lines.append(localized(
                    "report.performance.topProcessesRedacted",
                    "Top CPU processes: [redacted]",
                    locale: locale
                ))
            }
            lines.append("")
        }

        if options.includeStorage {
            lines += [localized("report.section.storage", "[Storage]", locale: locale)]
            for (index, volume) in snapshot.volumes.enumerated() {
                let name = options.includeVolumeNames
                    ? volume.name
                    : formatted("report.storage.volume", "Volume %ld", locale: locale, index + 1)
                lines.append(formatted(
                    "report.storage.usage",
                    "%@: %@ used / %@",
                    locale: locale,
                    name,
                    MetricFormatter.bytes(volume.usedBytes),
                    MetricFormatter.bytes(volume.totalBytes)
                ))
            }
            lines.append("")
        }

        if options.includeGraphics {
            lines += [localized("report.section.graphics", "[Graphics]", locale: locale)]
            for gpu in snapshot.gpus {
                lines.append(formatted(
                    "report.graphics.gpu",
                    "%@ — %@, memory: %@",
                    locale: locale,
                    gpu.name,
                    gpu.vendor,
                    gpu.memoryDescription ?? localized("common.unavailable", "Unavailable", locale: locale)
                ))
                for display in gpu.displays {
                    lines.append(formatted(
                        "report.graphics.display",
                        "Display: %@, %@",
                        locale: locale,
                        display.name,
                        display.resolution
                    ))
                }
            }
            lines.append("")
        }

        if options.includeCooling {
            lines += [
                localized("report.section.cooling", "[Cooling]", locale: locale),
                formatted("report.cooling.condition", "Thermal condition: %@", locale: locale, thermalTitle(snapshot.cooling.condition, locale: locale)),
                formatted("report.cooling.sensors", "Sensors: %ld", locale: locale, snapshot.cooling.sensors.count),
                formatted("report.cooling.fans", "Fans: %ld", locale: locale, snapshot.cooling.fans.count),
                ""
            ]
        }

        if options.includeBattery {
            lines += [
                localized("report.section.battery", "[Battery]", locale: locale),
                formatted(
                    "report.battery.availability",
                    "Availability: %@",
                    locale: locale,
                    snapshot.battery.availability.isAvailable
                        ? localized("common.available", "Available", locale: locale)
                        : localized("common.unavailable", "Unavailable", locale: locale)
                ),
                formatted(
                    "report.battery.charge",
                    "Charge: %@",
                    locale: locale,
                    snapshot.battery.chargePercent.map {
                        MetricFormatter.percent($0, locale: locale)
                    } ?? localized("common.unavailable", "Unavailable", locale: locale)
                ),
                formatted("report.battery.health", "Health: %@", locale: locale, batteryHealthTitle(snapshot.battery.health, locale: locale)),
                localized("report.battery.serial", "Serial: [redacted]", locale: locale),
                ""
            ]
        }

        lines += [localized("report.section.network", "[Network]", locale: locale)]
        for interface in snapshot.networkInterfaces {
            let address = options.includeNetworkAddresses
                ? (interface.localAddress ?? localized("common.unavailable", "Unavailable", locale: locale))
                : localized("common.redacted", "[redacted]", locale: locale)
            lines.append("\(interface.displayName) (\(interface.name)): \(address)")
        }

        return lines.joined(separator: "\n")
    }

    private func inputDeviceSummary(
        _ inventory: InputDeviceInventory,
        locale: Locale
    ) -> String {
        guard inventory.availability.isAvailable else {
            return localized(
                "report.hardware.inputUnavailable",
                "Input devices: Unavailable",
                locale: locale
            )
        }
        let counts = InputDeviceKind.allCases.map { kind in
            inventory.devices.filter { $0.kinds.contains(kind) }.count
        }
        return formatted(
            "report.hardware.inputSummary",
            "Input devices: %ld physical (keyboard %ld, mouse %ld, trackpad %ld, pointer %ld)",
            locale: locale,
            inventory.devices.count,
            counts[0],
            counts[1],
            counts[2],
            counts[3]
        )
    }

    private func thermalTitle(_ condition: ThermalCondition, locale: Locale) -> String {
        switch condition {
        case .nominal: localized("thermal.nominal", "Normal", locale: locale)
        case .fair: localized("thermal.fair", "Elevated", locale: locale)
        case .serious: localized("thermal.serious", "High", locale: locale)
        case .critical: localized("thermal.critical", "Critical", locale: locale)
        case .unavailable: localized("common.unavailable", "Unavailable", locale: locale)
        }
    }

    private func batteryHealthTitle(_ health: BatteryHealth, locale: Locale) -> String {
        switch health {
        case .excellent: localized("battery.health.excellent", "Excellent", locale: locale)
        case .good: localized("battery.health.good", "Good", locale: locale)
        case .aging: localized("battery.health.aging", "Aging", locale: locale)
        case .serviceRecommended: localized("battery.health.serviceRecommended", "Service Recommended", locale: locale)
        case .unknown: localized("common.unknown", "Unknown", locale: locale)
        }
    }

    private func localized(_ key: String, _ defaultValue: String, locale: Locale) -> String {
        TraceHaloLocalization.string(key, defaultValue: defaultValue, locale: locale)
    }

    private func formatted(
        _ key: String,
        _ defaultValue: String,
        locale: Locale,
        _ arguments: CVarArg...
    ) -> String {
        TraceHaloLocalization.format(
            key,
            defaultValue: defaultValue,
            locale: locale,
            arguments: arguments
        )
    }
}
