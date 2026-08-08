import Foundation

public enum MonitorMetric: String, CaseIterable, Codable, Identifiable, Sendable {
    case cpuTotal
    case cpuUser
    case cpuSystem
    case gpuUsage
    case memoryPressure
    case memoryUsed
    case storageUsed
    case temperature
    case fanSpeed
    case networkReceived
    case networkSent
    case batteryCharge
    case batteryHealth
    case uptime

    public var id: String { rawValue }

    public func isAvailable(in snapshot: SystemSnapshot) -> Bool {
        switch self {
        case .cpuTotal:
            snapshot.cpu.totalPercent.isFinite
        case .cpuUser:
            snapshot.cpu.userPercent.isFinite
        case .cpuSystem:
            snapshot.cpu.systemPercent.isFinite
        case .gpuUsage:
            snapshot.gpus.first?.utilizationPercent?.isFinite == true
        case .memoryPressure:
            snapshot.memory.pressurePercent.isFinite
        case .memoryUsed:
            snapshot.memory.totalBytes > 0
        case .storageUsed:
            !snapshot.volumes.isEmpty
        case .temperature:
            snapshot.cpu.temperatureCelsius?.isFinite == true
        case .fanSpeed:
            !snapshot.cooling.fans.isEmpty
        case .networkReceived:
            snapshot.networkInterfaces.contains { $0.receivedBytesPerSecond?.isFinite == true }
        case .networkSent:
            snapshot.networkInterfaces.contains { $0.sentBytesPerSecond?.isFinite == true }
        case .batteryCharge:
            snapshot.battery.chargePercent?.isFinite == true
        case .batteryHealth:
            snapshot.battery.availability.isAvailable && snapshot.battery.health != .unknown
        case .uptime:
            snapshot.identity.uptime.isFinite
        }
    }
}

public enum MonitorWidgetKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case title
    case value
    case bar
    case compactBar
    case ring
    case sparkline
    case processList
    case separator

    public var id: String { rawValue }
}

public enum MonitorModule: String, CaseIterable, Codable, Identifiable, Sendable {
    case cpuAndGPU
    case memory
    case storage
    case sensors
    case network
    case power

    public var id: String { rawValue }

    /// Modules that have a reliable data source on this Mac.
    /// Preferences remain persisted for every module; this only controls presentation.
    public static func presentableCases(in snapshot: SystemSnapshot) -> [MonitorModule] {
        allCases.filter { module in
            switch module {
            case .power:
                PowerPresentationPolicy.isAvailable(in: snapshot)
            case .cpuAndGPU, .memory, .storage, .sensors, .network:
                true
            }
        }
    }
}

/// Shared visibility policy for battery and future whole-machine power telemetry.
///
/// TraceHalo currently has no reliable whole-machine AC input-power reader. The
/// battery voltage × current value belongs only to an internal battery and must
/// never be presented as a desktop Mac's wall or adapter input power.
public enum PowerPresentationPolicy {
    public static func isAvailable(in snapshot: SystemSnapshot) -> Bool {
        snapshot.battery.availability.isAvailable
    }
}

public struct MonitorModulePreference: Identifiable, Codable, Equatable, Sendable {
    public var module: MonitorModule
    public var isEnabled: Bool

    public var id: MonitorModule { module }

    public init(module: MonitorModule, isEnabled: Bool = true) {
        self.module = module
        self.isEnabled = isEnabled
    }
}

public struct MonitorWidget: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: MonitorWidgetKind
    public var metric: MonitorMetric
    public var title: String
    public var accentHex: String
    public var hideWhenUnavailable: Bool

    public init(
        id: UUID = UUID(),
        kind: MonitorWidgetKind,
        metric: MonitorMetric,
        title: String,
        accentHex: String = "7C5CFC",
        hideWhenUnavailable: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.metric = metric
        self.title = title
        self.accentHex = accentHex
        self.hideWhenUnavailable = hideWhenUnavailable
    }

    public func shouldHide(in snapshot: SystemSnapshot) -> Bool {
        guard hideWhenUnavailable else { return false }
        switch kind {
        case .title, .separator:
            return false
        case .processList:
            return snapshot.cpu.topProcesses.isEmpty
        case .value, .bar, .compactBar, .ring, .sparkline:
            return !metric.isAvailable(in: snapshot)
        }
    }
}

public struct MonitorPanel: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var isEnabled: Bool
    public var widgets: [MonitorWidget]

    public init(
        id: UUID = UUID(),
        name: String,
        symbol: String,
        isEnabled: Bool = true,
        widgets: [MonitorWidget]
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.isEnabled = isEnabled
        self.widgets = widgets
    }
}

public enum MonitorStatusBarComponentStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case value
    case miniChart
    case verticalGaugeValue

    public var id: String { rawValue }
}

public enum MonitorStatusBarLayoutMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case full
    case compact
    case iconOnly

    public var id: String { rawValue }
}

public struct MonitorStatusBarComponent: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var style: MonitorStatusBarComponentStyle
    public var metric: MonitorMetric
    public var title: String
    public var accentHex: String
    public var isVisible: Bool

    public init(
        id: UUID = UUID(),
        style: MonitorStatusBarComponentStyle,
        metric: MonitorMetric,
        title: String,
        accentHex: String = "7C5CFC",
        isVisible: Bool = true
    ) {
        self.id = id
        self.style = style
        self.metric = metric
        self.title = title
        self.accentHex = accentHex
        self.isVisible = isVisible
    }
}

public enum MonitorQuickAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case systemScope
    case activityMonitor
    case console
    case terminal
    case systemInformation
    case systemSettings

    public var id: String { rawValue }
}

public struct MonitorQuickItem: Identifiable, Codable, Equatable, Sendable {
    public var action: MonitorQuickAction
    public var title: String
    public var systemImage: String
    public var isVisible: Bool

    public var id: String { action.rawValue }

    public init(
        action: MonitorQuickAction,
        title: String,
        systemImage: String,
        isVisible: Bool = true
    ) {
        self.action = action
        self.title = title
        self.systemImage = systemImage
        self.isVisible = isVisible
    }
}

public struct MonitorConfiguration: Codable, Equatable, Sendable {
    public var isCombined: Bool
    public var panels: [MonitorPanel]
    public var modulePreferences: [MonitorModulePreference]
    public var statusBarLayoutMode: MonitorStatusBarLayoutMode
    public var showsStatusBarIcon: Bool
    public var statusBarComponents: [MonitorStatusBarComponent]
    public var quickItems: [MonitorQuickItem]

    public init(
        isCombined: Bool = true,
        panels: [MonitorPanel],
        modulePreferences: [MonitorModulePreference] = MonitorConfiguration.defaultModulePreferences,
        statusBarLayoutMode: MonitorStatusBarLayoutMode = .full,
        showsStatusBarIcon: Bool = false,
        statusBarComponents: [MonitorStatusBarComponent] = MonitorConfiguration.defaultStatusBarComponents,
        quickItems: [MonitorQuickItem] = MonitorConfiguration.defaultQuickItems
    ) {
        self.isCombined = isCombined
        self.panels = panels
        self.modulePreferences = Self.normalizedModulePreferences(modulePreferences)
        self.statusBarLayoutMode = statusBarLayoutMode
        self.showsStatusBarIcon = showsStatusBarIcon
        self.statusBarComponents = statusBarComponents
        self.quickItems = quickItems
    }

    private enum CodingKeys: String, CodingKey {
        case isCombined
        case panels
        case modulePreferences
        case statusBarLayoutMode
        case showsStatusBarIcon
        case statusBarComponents
        case quickItems
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isCombined = try container.decode(Bool.self, forKey: .isCombined)
        panels = try container.decode([MonitorPanel].self, forKey: .panels)
        if let savedPreferences = try container.decodeIfPresent(
            [MonitorModulePreference].self,
            forKey: .modulePreferences
        ) {
            modulePreferences = Self.normalizedModulePreferences(savedPreferences)
        } else {
            modulePreferences = Self.legacyModulePreferences(from: panels)
        }
        let hasSavedStatusBarLayout = container.contains(.statusBarLayoutMode)
        statusBarLayoutMode = try container.decodeIfPresent(
            MonitorStatusBarLayoutMode.self,
            forKey: .statusBarLayoutMode
        ) ?? .full
        showsStatusBarIcon = try container.decodeIfPresent(
            Bool.self,
            forKey: .showsStatusBarIcon
        ) ?? false
        var decodedStatusBarComponents = try container.decodeIfPresent(
            [MonitorStatusBarComponent].self,
            forKey: .statusBarComponents
        ) ?? Self.defaultStatusBarComponents
        if !hasSavedStatusBarLayout,
           decodedStatusBarComponents.map(\.metric) == [.cpuTotal, .memoryPressure, .storageUsed, .temperature] {
            decodedStatusBarComponents[0].style = .miniChart
            decodedStatusBarComponents[1].style = .verticalGaugeValue
            decodedStatusBarComponents[2].style = .verticalGaugeValue
            decodedStatusBarComponents[3].style = .value
        }
        statusBarComponents = decodedStatusBarComponents
        var decodedQuickItems = try container.decodeIfPresent(
            [MonitorQuickItem].self,
            forKey: .quickItems
        ) ?? Self.defaultQuickItems
        if let legacyAppIndex = decodedQuickItems.firstIndex(where: {
            $0.action == .systemScope && $0.title == "SystemScope"
        }) {
            decodedQuickItems[legacyAppIndex].title = "TraceHalo"
        }
        quickItems = decodedQuickItems
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isCombined, forKey: .isCombined)
        try container.encode(panels, forKey: .panels)
        try container.encode(modulePreferences, forKey: .modulePreferences)
        try container.encode(statusBarLayoutMode, forKey: .statusBarLayoutMode)
        try container.encode(showsStatusBarIcon, forKey: .showsStatusBarIcon)
        try container.encode(statusBarComponents, forKey: .statusBarComponents)
        try container.encode(quickItems, forKey: .quickItems)
    }

    public static let defaultStatusBarComponents = [
        MonitorStatusBarComponent(
            style: .miniChart,
            metric: .cpuTotal,
            title: "CPU",
            accentHex: "55B7F3"
        ),
        MonitorStatusBarComponent(
            style: .verticalGaugeValue,
            metric: .memoryPressure,
            title: "RAM",
            accentHex: "55B7F3"
        ),
        MonitorStatusBarComponent(
            style: .verticalGaugeValue,
            metric: .storageUsed,
            title: "SSD",
            accentHex: "3D8DFF"
        ),
        MonitorStatusBarComponent(
            style: .value,
            metric: .temperature,
            title: "CPU",
            accentHex: "78D993"
        )
    ]

    public static let defaultModulePreferences = MonitorModule.allCases.map {
        MonitorModulePreference(module: $0)
    }

    public var enabledModules: [MonitorModule] {
        MonitorModule.allCases.filter(isModuleEnabled)
    }

    public func isModuleEnabled(_ module: MonitorModule) -> Bool {
        modulePreferences.first(where: { $0.module == module })?.isEnabled ?? false
    }

    public mutating func setModule(_ module: MonitorModule, isEnabled: Bool) {
        modulePreferences = Self.normalizedModulePreferences(modulePreferences)
        guard let index = modulePreferences.firstIndex(where: { $0.module == module }) else { return }
        modulePreferences[index].isEnabled = isEnabled
    }

    private static func normalizedModulePreferences(
        _ preferences: [MonitorModulePreference]
    ) -> [MonitorModulePreference] {
        MonitorModule.allCases.map { module in
            preferences.first(where: { $0.module == module })
                ?? MonitorModulePreference(module: module)
        }
    }

    private static func legacyModulePreferences(
        from panels: [MonitorPanel]
    ) -> [MonitorModulePreference] {
        let enabledMetrics = Set(
            panels
                .filter(\.isEnabled)
                .flatMap(\.widgets)
                .map(\.metric)
        )
        let allMetrics = Set(panels.flatMap(\.widgets).map(\.metric))

        return MonitorModule.allCases.map { module in
            let metrics = module.legacyMetrics
            let wasConfigured = !allMetrics.isDisjoint(with: metrics)
            let wasEnabled = !enabledMetrics.isDisjoint(with: metrics)
            return MonitorModulePreference(
                module: module,
                isEnabled: wasConfigured ? wasEnabled : true
            )
        }
    }

    /// Persisted defaults are canonical and locale-independent. Views derive
    /// localized display titles from `action`; changing the app language must
    /// never rewrite ordering, visibility, or a user-supplied title.
    public static var defaultQuickItems: [MonitorQuickItem] { [
        MonitorQuickItem(action: .systemScope, title: "TraceHalo", systemImage: "scope"),
        MonitorQuickItem(action: .activityMonitor, title: "Activity Monitor", systemImage: "waveform.path.ecg.rectangle"),
        MonitorQuickItem(action: .console, title: "Console", systemImage: "list.bullet.rectangle"),
        MonitorQuickItem(action: .terminal, title: "Terminal", systemImage: "terminal"),
        MonitorQuickItem(action: .systemInformation, title: "System Information", systemImage: "info.circle"),
        MonitorQuickItem(action: .systemSettings, title: "System Settings", systemImage: "gearshape")
    ] }

    public static var standard: MonitorConfiguration { MonitorConfiguration(
        panels: [
            MonitorPanel(name: "CPU & GPU", symbol: "cpu", widgets: [
                MonitorWidget(kind: .ring, metric: .cpuTotal, title: "CPU"),
                MonitorWidget(kind: .bar, metric: .gpuUsage, title: "GPU", accentHex: "2AA8D8"),
                MonitorWidget(kind: .processList, metric: .cpuTotal, title: "Top Processes")
            ]),
            MonitorPanel(name: "Memory", symbol: "memorychip", widgets: [
                MonitorWidget(kind: .ring, metric: .memoryPressure, title: "Memory Usage", accentHex: "D45CAC"),
                MonitorWidget(kind: .bar, metric: .memoryUsed, title: "Memory Used", accentHex: "D45CAC")
            ]),
            MonitorPanel(name: "Storage", symbol: "internaldrive", widgets: [
                MonitorWidget(kind: .bar, metric: .storageUsed, title: "Storage", accentHex: "3D8DFF")
            ]),
            MonitorPanel(name: "Sensors", symbol: "thermometer.medium", widgets: [
                MonitorWidget(kind: .value, metric: .temperature, title: "Thermal Status", accentHex: "F28C42"),
                MonitorWidget(kind: .value, metric: .fanSpeed, title: "Fans", accentHex: "F28C42")
            ]),
            MonitorPanel(name: "Network", symbol: "network", widgets: [
                MonitorWidget(kind: .sparkline, metric: .networkReceived, title: "Download", accentHex: "25B79F"),
                MonitorWidget(kind: .sparkline, metric: .networkSent, title: "Upload", accentHex: "25B79F")
            ]),
            MonitorPanel(name: "Power", symbol: "bolt.circle", widgets: [
                MonitorWidget(kind: .ring, metric: .batteryCharge, title: "Battery", accentHex: "D6AA36"),
                MonitorWidget(kind: .value, metric: .uptime, title: "Uptime", accentHex: "D6AA36")
            ])
        ]
    ) }
}

public extension MonitorModule {
    func localizedTitle(locale: Locale? = nil) -> String {
        switch self {
        case .cpuAndGPU: TraceHaloLocalization.string("monitor.module.cpuGpu", defaultValue: "CPU & GPU", locale: locale)
        case .memory: TraceHaloLocalization.string("monitor.module.memory", defaultValue: "Memory", locale: locale)
        case .storage: TraceHaloLocalization.string("monitor.module.storage", defaultValue: "Storage", locale: locale)
        case .sensors: TraceHaloLocalization.string("monitor.module.sensors", defaultValue: "Sensors", locale: locale)
        case .network: TraceHaloLocalization.string("monitor.module.network", defaultValue: "Network", locale: locale)
        case .power: TraceHaloLocalization.string("monitor.module.power", defaultValue: "Power", locale: locale)
        }
    }
}

public extension MonitorMetric {
    func localizedTitle(locale: Locale? = nil) -> String {
        switch self {
        case .cpuTotal: TraceHaloLocalization.string("monitor.metric.cpuTotal", defaultValue: "CPU Load", locale: locale)
        case .cpuUser: TraceHaloLocalization.string("monitor.metric.cpuUser", defaultValue: "CPU User", locale: locale)
        case .cpuSystem: TraceHaloLocalization.string("monitor.metric.cpuSystem", defaultValue: "CPU System", locale: locale)
        case .gpuUsage: TraceHaloLocalization.string("monitor.metric.gpuUsage", defaultValue: "GPU Usage", locale: locale)
        case .memoryPressure: TraceHaloLocalization.string("monitor.metric.memoryPressure", defaultValue: "Memory Usage", locale: locale)
        case .memoryUsed: TraceHaloLocalization.string("monitor.metric.memoryUsed", defaultValue: "Memory Used", locale: locale)
        case .storageUsed: TraceHaloLocalization.string("monitor.metric.storageUsed", defaultValue: "Storage", locale: locale)
        case .temperature: TraceHaloLocalization.string("monitor.metric.temperature", defaultValue: "Thermal Status", locale: locale)
        case .fanSpeed: TraceHaloLocalization.string("monitor.metric.fanSpeed", defaultValue: "Fans", locale: locale)
        case .networkReceived: TraceHaloLocalization.string("monitor.metric.networkReceived", defaultValue: "Download", locale: locale)
        case .networkSent: TraceHaloLocalization.string("monitor.metric.networkSent", defaultValue: "Upload", locale: locale)
        case .batteryCharge: TraceHaloLocalization.string("monitor.metric.batteryCharge", defaultValue: "Battery", locale: locale)
        case .batteryHealth: TraceHaloLocalization.string("monitor.metric.batteryHealth", defaultValue: "Battery Health", locale: locale)
        case .uptime: TraceHaloLocalization.string("monitor.metric.uptime", defaultValue: "Uptime", locale: locale)
        }
    }

    fileprivate func localizedProcessTitle(locale: Locale? = nil) -> String {
        TraceHaloLocalization.string(
            "monitor.metric.topProcesses",
            defaultValue: "Top Processes",
            locale: locale
        )
    }
}

public extension MonitorQuickAction {
    func localizedTitle(locale: Locale? = nil) -> String {
        switch self {
        case .systemScope: "TraceHalo"
        case .activityMonitor: TraceHaloLocalization.string("monitor.quick.activityMonitor", defaultValue: "Activity Monitor", locale: locale)
        case .console: TraceHaloLocalization.string("monitor.quick.console", defaultValue: "Console", locale: locale)
        case .terminal: TraceHaloLocalization.string("monitor.quick.terminal", defaultValue: "Terminal", locale: locale)
        case .systemInformation: TraceHaloLocalization.string("monitor.quick.systemInformation", defaultValue: "System Information", locale: locale)
        case .systemSettings: TraceHaloLocalization.string("monitor.quick.systemSettings", defaultValue: "System Settings", locale: locale)
        }
    }

    func localizedTitle(
        persistedTitle: String,
        locale: Locale? = nil
    ) -> String {
        let knownAliases: Set<String> = switch self {
        case .systemScope: ["", "TraceHalo", "SystemScope"]
        case .activityMonitor: ["", "活动监视器", "Activity Monitor"]
        case .console: ["", "控制台", "Console"]
        case .terminal: ["", "终端", "Terminal"]
        case .systemInformation: ["", "系统信息", "System Information"]
        case .systemSettings: ["", "系统设置", "System Settings"]
        }
        return knownAliases.contains(persistedTitle)
            ? localizedTitle(locale: locale)
            : persistedTitle
    }
}

public extension MonitorPanel {
    /// Localizes only known default/legacy names. Unknown values are user data
    /// and must remain byte-for-byte unchanged.
    func localizedDisplayName(locale: Locale? = nil) -> String {
        let module: MonitorModule? = switch name {
        case "CPU 与 GPU", "CPU & GPU": .cpuAndGPU
        case "内存", "Memory": .memory
        case "存储", "Storage": .storage
        case "传感器", "Sensors": .sensors
        case "网络", "Network": .network
        case "电源", "Power": .power
        default: nil
        }
        return module?.localizedTitle(locale: locale) ?? name
    }
}

public extension MonitorWidget {
    /// Resolves legacy default copy by semantic metric while preserving every
    /// title that does not match a shipped default alias.
    func localizedDisplayTitle(locale: Locale? = nil) -> String {
        if kind == .processList,
           ["CPU 使用进程", "高占用进程", "Top Processes"].contains(title) {
            return TraceHaloLocalization.string(
                "monitor.metric.topProcesses",
                defaultValue: "Top Processes",
                locale: locale
            )
        }
        guard metric.defaultWidgetTitleAliases.contains(title) else { return title }
        return metric.localizedTitle(locale: locale)
    }
}

public extension MonitorStatusBarComponent {
    /// Status labels are editable and normally use language-neutral acronyms.
    /// Only Chinese labels known to have shipped as defaults are translated
    /// when presenting an English UI; arbitrary custom labels are preserved.
    func localizedDisplayTitle(locale: Locale? = nil) -> String {
        let resolvedLocale = locale ?? TraceHaloLocalization.currentLocale()
        guard AppLanguageResolver.supportedIdentifier(for: resolvedLocale.identifier)
                != AppLanguageResolver.simplifiedChineseIdentifier,
              metric.legacyChineseStatusTitleAliases.contains(title)
        else { return title }
        return metric.canonicalStatusTitle
    }
}

private extension MonitorMetric {
    var defaultWidgetTitleAliases: Set<String> {
        switch self {
        case .cpuTotal: ["CPU 负载", "CPU 总负载"]
        case .cpuUser: ["CPU 用户", "CPU User"]
        case .cpuSystem: ["CPU 系统", "CPU System"]
        case .gpuUsage: ["GPU 使用率", "GPU Usage"]
        case .memoryPressure: ["内存压力", "内存占用", "内存占用估算", "Memory Usage"]
        case .memoryUsed: ["内存使用", "已用内存", "Memory Used"]
        case .storageUsed: ["存储", "已用存储", "Storage"]
        case .temperature: ["温度", "热状态", "Thermal Status"]
        case .fanSpeed: ["风扇", "风扇转速", "Fans"]
        case .networkReceived: ["接收", "接收速率", "下载", "Download"]
        case .networkSent: ["发送", "发送速率", "上传", "Upload"]
        case .batteryCharge: ["电池", "电池电量", "Battery"]
        case .batteryHealth: ["电池健康", "Battery Health"]
        case .uptime: ["运行时间", "Uptime"]
        }
    }

    var legacyChineseStatusTitleAliases: Set<String> {
        switch self {
        case .cpuTotal: ["CPU 负载", "CPU 总负载", "处理器"]
        case .cpuUser: ["CPU 用户"]
        case .cpuSystem: ["CPU 系统"]
        case .gpuUsage: ["GPU 使用率", "图形"]
        case .memoryPressure: ["内存", "内存压力", "内存占用", "内存占用估算"]
        case .memoryUsed: ["内存", "内存使用", "已用内存"]
        case .storageUsed: ["存储", "已用存储"]
        case .temperature: ["温度", "热状态"]
        case .fanSpeed: ["风扇", "风扇转速"]
        case .networkReceived: ["接收", "接收速率", "下载"]
        case .networkSent: ["发送", "发送速率", "上传"]
        case .batteryCharge: ["电池", "电池电量"]
        case .batteryHealth: ["电池", "电池健康"]
        case .uptime: ["运行", "运行时间"]
        }
    }

    var canonicalStatusTitle: String {
        switch self {
        case .cpuTotal, .cpuUser, .cpuSystem, .temperature: "CPU"
        case .gpuUsage: "GPU"
        case .memoryPressure, .memoryUsed: "RAM"
        case .storageUsed: "SSD"
        case .fanSpeed: "FAN"
        case .networkReceived: "RX"
        case .networkSent: "TX"
        case .batteryCharge, .batteryHealth: "BAT"
        case .uptime: "UP"
        }
    }
}

private extension MonitorModule {
    var legacyMetrics: Set<MonitorMetric> {
        switch self {
        case .cpuAndGPU:
            [.cpuTotal, .cpuUser, .cpuSystem, .gpuUsage]
        case .memory:
            [.memoryPressure, .memoryUsed]
        case .storage:
            [.storageUsed]
        case .sensors:
            [.temperature, .fanSpeed]
        case .network:
            [.networkReceived, .networkSent]
        case .power:
            [.batteryCharge, .batteryHealth, .uptime]
        }
    }
}

public enum StartupItemKind: String, CaseIterable, Sendable {
    case loginItem = "Open at Login"
    case launchAgent = "Launch Agent"
    case launchDaemon = "Launch Daemon"
}

public enum StartupItemScope: String, CaseIterable, Sendable {
    case currentUser
    case allUsers
    case system
    case macOS
    case unknown

    public init(legacyValue: String) {
        switch legacyValue.lowercased() {
        case "当前用户", "current user": self = .currentUser
        case "所有用户", "all users": self = .allUsers
        case "系统", "system": self = .system
        case "macos": self = .macOS
        default: self = .unknown
        }
    }

    public func localizedTitle(locale: Locale? = nil) -> String {
        switch self {
        case .currentUser: TraceHaloLocalization.string("startup.scope.currentUser", defaultValue: "Current User", locale: locale)
        case .allUsers: TraceHaloLocalization.string("startup.scope.allUsers", defaultValue: "All Users", locale: locale)
        case .system: TraceHaloLocalization.string("startup.scope.system", defaultValue: "System", locale: locale)
        case .macOS: "macOS"
        case .unknown: TraceHaloLocalization.string("common.unknown", defaultValue: "Unknown", locale: locale)
        }
    }
}

public struct StartupItem: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public var label: String
    public var displayName: String
    public var developer: String?
    public var kind: StartupItemKind
    public var path: String
    public var isEnabled: Bool
    public var scopeKind: StartupItemScope
    private var legacyScopeFallback: String?

    public var scope: String {
        scopeKind == .unknown
            ? legacyScopeFallback ?? scopeKind.localizedTitle()
            : scopeKind.localizedTitle()
    }

    public init(
        label: String,
        displayName: String,
        developer: String? = nil,
        kind: StartupItemKind,
        path: String,
        isEnabled: Bool,
        scope: String
    ) {
        self.label = label
        self.displayName = displayName
        self.developer = developer
        self.kind = kind
        self.path = path
        self.isEnabled = isEnabled
        scopeKind = StartupItemScope(legacyValue: scope)
        legacyScopeFallback = scopeKind == .unknown ? scope : nil
    }

    public init(
        label: String,
        displayName: String,
        developer: String? = nil,
        kind: StartupItemKind,
        path: String,
        isEnabled: Bool,
        scopeKind: StartupItemScope
    ) {
        self.label = label
        self.displayName = displayName
        self.developer = developer
        self.kind = kind
        self.path = path
        self.isEnabled = isEnabled
        self.scopeKind = scopeKind
        legacyScopeFallback = nil
    }
}

public enum AssociatedFileCategory: String, CaseIterable, Sendable {
    case binary = "应用程序"
    case cache = "缓存"
    case container = "容器"
    case groupContainer = "群组容器"
    case helper = "辅助工具"
    case loginItem = "登录项"
    case log = "日志"
    case plugin = "插件"
    case preference = "偏好设置"
    case script = "脚本"
    case support = "支持文件"
    case other = "其他"

    public func localizedTitle(locale: Locale? = nil) -> String {
        switch self {
        case .binary: TraceHaloLocalization.string("associated.category.binary", defaultValue: "Application", locale: locale)
        case .cache: TraceHaloLocalization.string("associated.category.cache", defaultValue: "Cache", locale: locale)
        case .container: TraceHaloLocalization.string("associated.category.container", defaultValue: "Container", locale: locale)
        case .groupContainer: TraceHaloLocalization.string("associated.category.groupContainer", defaultValue: "Group Container", locale: locale)
        case .helper: TraceHaloLocalization.string("associated.category.helper", defaultValue: "Helper", locale: locale)
        case .loginItem: TraceHaloLocalization.string("associated.category.loginItem", defaultValue: "Login Item", locale: locale)
        case .log: TraceHaloLocalization.string("associated.category.log", defaultValue: "Log", locale: locale)
        case .plugin: TraceHaloLocalization.string("associated.category.plugin", defaultValue: "Plugin", locale: locale)
        case .preference: TraceHaloLocalization.string("associated.category.preference", defaultValue: "Preferences", locale: locale)
        case .script: TraceHaloLocalization.string("associated.category.script", defaultValue: "Script", locale: locale)
        case .support: TraceHaloLocalization.string("associated.category.support", defaultValue: "Support File", locale: locale)
        case .other: TraceHaloLocalization.string("associated.category.other", defaultValue: "Other", locale: locale)
        }
    }
}

/// Structured, user-reviewable evidence for why a path was associated with an
/// application. A match is evidence, not proof, so associated items remain
/// unselected until the user explicitly confirms them.
public enum AssociatedFileMatchBasis: Equatable, Sendable {
    case exactBundleIdentifier(String)
    case bundleIdentifierPrefix(String)
    case applicationName(String)
    case unspecified
}

public struct AssociatedFile: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public var path: String
    public var category: AssociatedFileCategory
    public var sizeBytes: UInt64?
    public var ownershipReason: String
    public var matchBasis: AssociatedFileMatchBasis
    public var isSelected: Bool

    public init(
        path: String,
        category: AssociatedFileCategory,
        sizeBytes: UInt64? = nil,
        ownershipReason: String,
        matchBasis: AssociatedFileMatchBasis = .unspecified,
        isSelected: Bool = false
    ) {
        self.path = path
        self.category = category
        self.sizeBytes = sizeBytes
        self.ownershipReason = ownershipReason
        self.matchBasis = matchBasis
        self.isSelected = isSelected
    }
}

public struct ApplicationCandidate: Identifiable, Equatable, Sendable {
    public var id: String { bundleURL.path }
    public var name: String
    public var bundleIdentifier: String?
    public var version: String?
    public var bundleURL: URL
    public var sizeBytes: UInt64?
    public var associatedFiles: [AssociatedFile]

    public init(
        name: String,
        bundleIdentifier: String?,
        version: String?,
        bundleURL: URL,
        sizeBytes: UInt64? = nil,
        associatedFiles: [AssociatedFile] = []
    ) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.bundleURL = bundleURL
        self.sizeBytes = sizeBytes
        self.associatedFiles = associatedFiles
    }
}

public struct UninstallPlan: Equatable, Sendable {
    public var application: ApplicationCandidate
    public var selectedFiles: [AssociatedFile]

    public init(application: ApplicationCandidate, selectedFiles: [AssociatedFile]) {
        self.application = application
        self.selectedFiles = selectedFiles
    }

    public var totalItemCount: Int { 1 + selectedFiles.count }
    public var allPaths: [String] { [application.bundleURL.path] + selectedFiles.map(\.path) }

    /// Returns an exact total only when every included item has a known size.
    /// Unknown or overflowing values must stay unknown rather than becoming 0.
    public var knownTotalBytes: UInt64? {
        guard var total = application.sizeBytes else { return nil }
        for file in selectedFiles {
            guard let size = file.sizeBytes else { return nil }
            let addition = total.addingReportingOverflow(size)
            guard !addition.overflow else { return nil }
            total = addition.partialValue
        }
        return total
    }
}

public struct StorageHealthMetric: Identifiable, Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case capacity
        case used
        case available
        case fileSystem
        case location
        case encryption
        case access
        case device
        case media
        case connection
        case mediaType
        case smart

        init?(legacyName: String) {
            switch legacyName.lowercased() {
            case "容量", "capacity": self = .capacity
            case "已用", "used": self = .used
            case "可用", "available": self = .available
            case "文件系统", "file system": self = .fileSystem
            case "位置", "location": self = .location
            case "加密", "encryption": self = .encryption
            case "访问", "access": self = .access
            case "设备", "device": self = .device
            case "介质", "media": self = .media
            case "连接", "connection": self = .connection
            case "介质类型", "media type": self = .mediaType
            case "smart": self = .smart
            default: return nil
            }
        }
    }

    public var id: String { kind?.rawValue ?? name }
    public var kind: Kind?
    public var name: String
    public var value: String
    public var detail: String?

    public init(
        kind: Kind? = nil,
        name: String,
        value: String,
        detail: String? = nil
    ) {
        self.kind = kind ?? Kind(legacyName: name)
        self.name = name
        self.value = value
        self.detail = detail
    }
}

public struct StorageHealth: Equatable, Sendable {
    public var availability: CapabilityAvailability
    public var status: String?
    public var temperatureCelsius: Double?
    public var lifeRemainingPercent: Double?
    public var metrics: [StorageHealthMetric]

    public init(
        availability: CapabilityAvailability,
        status: String? = nil,
        temperatureCelsius: Double? = nil,
        lifeRemainingPercent: Double? = nil,
        metrics: [StorageHealthMetric] = []
    ) {
        self.availability = availability
        self.status = status
        self.temperatureCelsius = temperatureCelsius
        self.lifeRemainingPercent = lifeRemainingPercent
        self.metrics = metrics
    }
}
