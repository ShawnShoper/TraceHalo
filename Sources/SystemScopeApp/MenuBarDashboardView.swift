import AppKit
import Observation
import SwiftUI
import SystemScopeCore

private enum MenuPalette {
    static let blue = CalmTheme.accent
    static let cyan = CalmTheme.cyan
    static let violet = CalmTheme.violet
    static let green = CalmTheme.mint
    static let amber = CalmTheme.amber
}

private func preferredStorageVolume(in volumes: [StorageVolume]) -> StorageVolume? {
    volumes.first(where: { $0.path == "/" })
        ?? volumes.first(where: { $0.isInternal == true })
        ?? volumes.first
}

private func sumIfAvailable(_ values: [Double]) -> Double? {
    values.isEmpty ? nil : values.reduce(0, +)
}

private struct MenuNetworkProjection {
    let services: [NetworkInterfaceState]
    let totalReceivedRate: Double?
    let totalSentRate: Double?

    static let empty = MenuNetworkProjection(
        services: [],
        totalReceivedRate: nil,
        totalSentRate: nil
    )
}

enum MenuBarDashboardLayout {
    static let collapsedContentWidth: CGFloat = 282
    static let expandedContentWidth: CGFloat = 552
    static let primaryColumnWidth: CGFloat = 276
    static let detailColumnWidth: CGFloat = 262
    static let columnSpacing: CGFloat = 8
    static let horizontalChrome: CGFloat = 3
    static let verticalChrome: CGFloat = 10

    static let headerHeight: CGFloat = 101
    static let footerHeight: CGFloat = 60
    static let minimumColumnHeight: CGFloat = 430
    static let maximumColumnHeight: CGFloat = 767

    static let sectionHeaderHeight: CGFloat = 35.5
    static let cpuRowHeight: CGFloat = 66
    static let memoryRowHeight: CGFloat = 66.5
    static let gpuRowHeight: CGFloat = 66.5
    static let storageRowHeight: CGFloat = 61
    static let networkRowHeight: CGFloat = 96
    static let fansRowHeight: CGFloat = 59.5
    static let sensorsRowHeight: CGFloat = 84.5

    static let maximumQuickActionCount = 5

    static var expandedDashboardWidth: CGFloat {
        primaryColumnWidth + columnSpacing + detailColumnWidth
    }
}

enum MenuOverviewPalette {
    // The dark values are the selected reference design. Light values preserve
    // the same hierarchy while following the app/system appearance instead of
    // forcing the menu dashboard to remain dark.
    static let background = Color(lightHex: "F7F8FA", darkHex: "0E151B")
    static let row = Color(lightHex: "FFFFFF", darkHex: "111A20")
    static let selectedRow = Color(lightHex: "EAF1FB", darkHex: "141E25")
    static let divider = Color(lightHex: "D9E0E5", darkHex: "2C3137")
    static let border = Color(lightHex: "C5CED5", darkHex: "383E45")
    static let primaryText = Color(lightHex: "172028", darkHex: "E8ECEE")
    static let secondaryText = Color(lightHex: "4C5A64", darkHex: "A7B1BA")
    static let tertiaryText = Color(lightHex: "687681", darkHex: "7F8B95")
    static let blue = Color(lightHex: "3D72D8", darkHex: "5891FA")
    static let violet = Color(lightHex: "7954BE", darkHex: "AA78F0")
    static let cyan = Color(lightHex: "248FA6", darkHex: "4CBFD3")
    static let amber = Color(lightHex: "BC7417", darkHex: "F4AD48")
    static let green = Color(lightHex: "3B9855", darkHex: "88D09E")
    static let rose = Color(lightHex: "C64F60", darkHex: "EC747C")
}

enum MenuBarDashboardPresentationMode: Equatable {
    case popover
    case embeddedPreview
}

enum MenuBarRecencyLabel {
    static func text(
        capturedAt: Date,
        now: Date = Date(),
        locale: Locale = Locale(identifier: AppLanguageResolver.simplifiedChineseIdentifier)
    ) -> String {
        let seconds = max(now.timeIntervalSince(capturedAt), 0)
        if seconds < 60 {
            return MenuMonitorLocalization.string("刚刚", english: "Just Now", locale: locale)
        }
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return MenuMonitorLocalization.format(
                "%lld 分钟前",
                english: "%lld min ago",
                locale: locale,
                Int64(minutes)
            )
        }
        return MenuMonitorLocalization.format(
            "%lld 小时前",
            english: "%lld hr ago",
            locale: locale,
            Int64(seconds / 3_600)
        )
    }
}

enum MenuBarQuickActionLayout {
    static let referenceOrder: [MonitorQuickAction] = [
        .activityMonitor,
        .systemScope,
        .terminal,
        .systemInformation,
        .systemSettings
    ]

    static func visibleItems(from items: [MonitorQuickItem]) -> [MonitorQuickItem] {
        referenceOrder.compactMap { action in
            items.first { $0.action == action && $0.isVisible }
        }
    }
}

struct MenuBarProcessIconIdentity: Hashable, Sendable {
    let processID: Int32
    let name: String
}

enum MenuBarIconPrefetchKey {
    static func processIdentities(
        cpuProcesses: [ProcessUsage],
        memoryProcesses: [ProcessUsage],
        limitPerMetric: Int = 10
    ) -> [MenuBarProcessIconIdentity] {
        let limit = max(limitPerMetric, 0)
        let identities = cpuProcesses.prefix(limit).map {
            MenuBarProcessIconIdentity(processID: $0.id, name: $0.name)
        } + memoryProcesses.prefix(limit).map {
            MenuBarProcessIconIdentity(processID: $0.id, name: $0.name)
        }
        return Array(Set(identities)).sorted { lhs, rhs in
            if lhs.processID != rhs.processID { return lhs.processID < rhs.processID }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func quickActions(
        items: [MonitorQuickItem],
        limit: Int = MenuBarDashboardLayout.maximumQuickActionCount
    ) -> [MonitorQuickAction] {
        let actions = MenuBarQuickActionLayout.visibleItems(from: items).lazy
            .prefix(max(limit, 0))
            .map(\.action)
        return Array(Set(actions)).sorted { $0.rawValue < $1.rawValue }
    }
}

private struct MenuBarIconPayload: Sendable {
    let applicationPath: String
    let data: Data?
}

private struct MenuBarQuickIconRequest: Sendable {
    let action: MonitorQuickAction
    let candidatePaths: [String]
}

private struct MenuBarPreparedQuickIcon: Sendable {
    let action: MonitorQuickAction
    let payload: MenuBarIconPayload?
}

private struct MenuBarProcessIconRequest: Sendable {
    let identity: MenuBarProcessIconIdentity
    let candidatePaths: [String]
}

private struct MenuBarPreparedProcessIcon: Sendable {
    let identity: MenuBarProcessIconIdentity
    let payload: MenuBarIconPayload?
}

private enum MenuBarIconPayloadLoader {
    static func load(firstAvailableAt candidatePaths: [String]) -> MenuBarIconPayload? {
        let fileManager = FileManager.default
        for applicationPath in candidatePaths {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: applicationPath, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }

            let applicationURL = URL(fileURLWithPath: applicationPath, isDirectory: true)
            let iconURL = iconResourceURL(in: applicationURL, fileManager: fileManager)
            let data = iconURL.flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) }
            return MenuBarIconPayload(applicationPath: applicationPath, data: data)
        }
        return nil
    }

    private static func iconResourceURL(
        in applicationURL: URL,
        fileManager: FileManager
    ) -> URL? {
        let contentsURL = applicationURL.appendingPathComponent("Contents", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let infoURL = contentsURL.appendingPathComponent("Info.plist", isDirectory: false)

        if let data = try? Data(contentsOf: infoURL, options: .mappedIfSafe),
           let propertyList = try? PropertyListSerialization.propertyList(
               from: data,
               options: [],
               format: nil
           ),
           let info = propertyList as? [String: Any] {
            for iconName in iconNames(in: info) {
                let fileName = (iconName as NSString).pathExtension.isEmpty
                    ? "\(iconName).icns"
                    : iconName
                let iconURL = resourcesURL.appendingPathComponent(fileName, isDirectory: false)
                if fileManager.fileExists(atPath: iconURL.path) {
                    return iconURL
                }
            }
        }

        guard let resources = try? fileManager.contentsOfDirectory(
            at: resourcesURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        return resources
            .filter { $0.pathExtension.caseInsensitiveCompare("icns") == .orderedSame }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }

    private static func iconNames(in info: [String: Any]) -> [String] {
        var names: [String] = []
        if let iconFile = info["CFBundleIconFile"] as? String {
            names.append(iconFile)
        }
        if let iconName = info["CFBundleIconName"] as? String {
            names.append(iconName)
        }
        if let icons = info["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let iconFiles = primary["CFBundleIconFiles"] as? [String] {
            names.append(contentsOf: iconFiles.reversed())
        }
        return names
    }
}

@MainActor
@Observable
private final class MenuBarIconRepository {
    static let shared = MenuBarIconRepository()

    private(set) var applicationIcons: [MonitorQuickAction: NSImage] = [:]
    private(set) var processIcons: [MenuBarProcessIconIdentity: NSImage] = [:]

    @ObservationIgnored private var iconsByApplicationPath: [String: NSImage] = [:]
    @ObservationIgnored private var pendingQuickActions: Set<MonitorQuickAction> = []
    @ObservationIgnored private var unavailableQuickActions: Set<MonitorQuickAction> = []
    @ObservationIgnored private var pendingProcesses: Set<MenuBarProcessIconIdentity> = []
    @ObservationIgnored private var unavailableProcesses: Set<MenuBarProcessIconIdentity> = []
    @ObservationIgnored private var processCacheOrder: [MenuBarProcessIconIdentity] = []

    private let maximumProcessIconCount = 192

    func applicationIcon(for action: MonitorQuickAction) -> NSImage? {
        applicationIcons[action]
    }

    func processIcon(for process: ProcessUsage) -> NSImage? {
        processIcons[
            MenuBarProcessIconIdentity(processID: process.id, name: process.name)
        ]
    }

    func prefetchQuickActions(_ actions: [MonitorQuickAction]) {
        var requests: [MenuBarQuickIconRequest] = []
        for action in actions {
            if action == .systemScope {
                if applicationIcons[action] == nil {
                    applicationIcons[action] = NSApplication.shared.applicationIconImage
                }
                continue
            }
            guard applicationIcons[action] == nil,
                  !pendingQuickActions.contains(action),
                  !unavailableQuickActions.contains(action) else {
                continue
            }

            pendingQuickActions.insert(action)
            requests.append(
                MenuBarQuickIconRequest(
                    action: action,
                    candidatePaths: Self.quickActionCandidatePaths(for: action)
                )
            )
        }
        guard !requests.isEmpty else { return }
        let resolvedRequests = requests

        Task { [weak self] in
            let prepared = await Task.detached(priority: .utility) {
                resolvedRequests.map { request in
                    MenuBarPreparedQuickIcon(
                        action: request.action,
                        payload: MenuBarIconPayloadLoader.load(
                            firstAvailableAt: request.candidatePaths
                        )
                    )
                }
            }.value
            guard let self else { return }

            var icons = applicationIcons
            for item in prepared {
                pendingQuickActions.remove(item.action)
                guard let payload = item.payload,
                      let image = image(from: payload) else {
                    unavailableQuickActions.insert(item.action)
                    continue
                }
                icons[item.action] = image
            }
            applicationIcons = icons
        }
    }

    func prefetchProcessIcons(_ identities: [MenuBarProcessIconIdentity]) {
        var requests: [MenuBarProcessIconRequest] = []
        for identity in identities {
            guard processIcons[identity] == nil,
                  !pendingProcesses.contains(identity),
                  !unavailableProcesses.contains(identity) else {
                continue
            }

            var candidatePaths: [String] = []
            if let bundleURL = NSRunningApplication(
                processIdentifier: pid_t(identity.processID)
            )?.bundleURL {
                candidatePaths.append(bundleURL.path)
            }
            candidatePaths.append(contentsOf: Self.processCandidatePaths(name: identity.name))
            candidatePaths = Self.uniqued(candidatePaths)
            let resolvedCandidatePaths = candidatePaths

            if let image = resolvedCandidatePaths.lazy.compactMap({ self.iconsByApplicationPath[$0] }).first {
                store(image, for: identity)
                continue
            }

            pendingProcesses.insert(identity)
            requests.append(
                MenuBarProcessIconRequest(
                    identity: identity,
                    candidatePaths: resolvedCandidatePaths
                )
            )
        }
        guard !requests.isEmpty else { return }
        let resolvedRequests = requests

        Task { [weak self] in
            let prepared = await Task.detached(priority: .utility) {
                resolvedRequests.map { request in
                    MenuBarPreparedProcessIcon(
                        identity: request.identity,
                        payload: MenuBarIconPayloadLoader.load(
                            firstAvailableAt: request.candidatePaths
                        )
                    )
                }
            }.value
            guard let self else { return }

            var resolvedIcons: [(MenuBarProcessIconIdentity, NSImage)] = []
            for item in prepared {
                pendingProcesses.remove(item.identity)
                guard let payload = item.payload,
                      let image = image(from: payload) else {
                    unavailableProcesses.insert(item.identity)
                    continue
                }
                resolvedIcons.append((item.identity, image))
            }
            store(resolvedIcons)
            trimUnavailableProcessCacheIfNeeded()
        }
    }

    private func image(from payload: MenuBarIconPayload) -> NSImage? {
        if let cached = iconsByApplicationPath[payload.applicationPath] {
            return cached
        }
        let image = payload.data.flatMap(NSImage.init(data:))
            ?? NSWorkspace.shared.icon(forFile: payload.applicationPath)
        iconsByApplicationPath[payload.applicationPath] = image
        return image
    }

    private func store(_ image: NSImage, for identity: MenuBarProcessIconIdentity) {
        store([(identity, image)])
    }

    private func store(_ resolvedIcons: [(MenuBarProcessIconIdentity, NSImage)]) {
        guard !resolvedIcons.isEmpty else { return }
        var icons = processIcons
        for (identity, image) in resolvedIcons {
            icons[identity] = image
            processCacheOrder.removeAll { $0 == identity }
            processCacheOrder.append(identity)
        }
        while processCacheOrder.count > maximumProcessIconCount {
            icons.removeValue(forKey: processCacheOrder.removeFirst())
        }
        processIcons = icons
    }

    private func trimUnavailableProcessCacheIfNeeded() {
        guard unavailableProcesses.count > maximumProcessIconCount else { return }
        unavailableProcesses = Set(unavailableProcesses.prefix(maximumProcessIconCount))
    }

    private static func quickActionCandidatePaths(
        for action: MonitorQuickAction
    ) -> [String] {
        switch action {
        case .systemScope: []
        case .activityMonitor: ["/System/Applications/Utilities/Activity Monitor.app"]
        case .console: ["/System/Applications/Utilities/Console.app"]
        case .terminal: ["/System/Applications/Utilities/Terminal.app"]
        case .systemInformation: ["/System/Applications/Utilities/System Information.app"]
        case .systemSettings: ["/System/Applications/System Settings.app"]
        }
    }

    private static func processCandidatePaths(name: String) -> [String] {
        [
            "/Applications/\(name).app",
            "/Applications/Utilities/\(name).app",
            "/System/Applications/\(name).app",
            "/System/Applications/Utilities/\(name).app"
        ]
    }

    private static func uniqued(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        return paths.filter { seen.insert($0).inserted }
    }
}

enum MenuBarDashboardSection: String, CaseIterable, Identifiable, Equatable {
    case cpu
    case memory
    case gpu
    case storage
    case network
    case fans
    case sensors
    case battery

    var id: String { rawValue }

    static let referenceOrder: [Self] = allCases

    static func visibleSections(
        in configuration: MonitorConfiguration,
        snapshot: SystemSnapshot? = nil
    ) -> [Self] {
        referenceOrder.filter { section in
            configuration.isModuleEnabled(section.module)
                && (snapshot == nil
                    || section.module != .power
                    || snapshot.map { PowerPresentationPolicy.isAvailable(in: $0) } == true)
        }
    }

    static func previewSection(for module: MonitorModule) -> Self {
        switch module {
        case .cpuAndGPU: .cpu
        case .memory: .memory
        case .storage: .storage
        case .sensors: .sensors
        case .network: .network
        case .power: .battery
        }
    }

    static func requiresNetworkProjection(
        visibleSections: [Self],
        selectedSection: Self?
    ) -> Bool {
        visibleSections.contains(.network) || selectedSection == .network
    }

    var module: MonitorModule {
        switch self {
        case .cpu, .gpu: .cpuAndGPU
        case .memory: .memory
        case .storage: .storage
        case .fans, .sensors: .sensors
        case .network: .network
        case .battery: .power
        }
    }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "内存"
        case .gpu: "GPU"
        case .storage: "存储"
        case .network: "网络服务"
        case .fans: "风扇"
        case .sensors: "温度传感器"
        case .battery: "电池"
        }
    }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .cpu: "CPU"
        case .memory: MenuMonitorLocalization.string("内存", english: "Memory", locale: locale)
        case .gpu: "GPU"
        case .storage: MenuMonitorLocalization.string("存储", english: "Storage", locale: locale)
        case .network: MenuMonitorLocalization.string("网络服务", english: "Network Services", locale: locale)
        case .fans: MenuMonitorLocalization.string("风扇", english: "Fans", locale: locale)
        case .sensors: MenuMonitorLocalization.string("温度传感器", english: "Temperature Sensors", locale: locale)
        case .battery: MenuMonitorLocalization.string("电池", english: "Battery", locale: locale)
        }
    }
}

struct MenuBarDashboardSelection: Equatable {
    private(set) var selectedSection: MenuBarDashboardSection?

    init(selectedSection: MenuBarDashboardSection? = nil) {
        self.selectedSection = selectedSection
    }

    var isExpanded: Bool { selectedSection != nil }

    mutating func toggle(_ section: MenuBarDashboardSection) {
        selectedSection = selectedSection == section ? nil : section
    }

    mutating func toggle(
        _ section: MenuBarDashboardSection,
        loadedDetailSection: inout MenuBarDashboardSection?
    ) {
        toggle(section)
        loadedDetailSection = selectedSection
    }

    mutating func select(_ section: MenuBarDashboardSection?) {
        selectedSection = section
    }

    mutating func collapse() {
        selectedSection = nil
    }

    mutating func collapse(
        loadedDetailSection: inout MenuBarDashboardSection?
    ) {
        collapse()
        loadedDetailSection = nil
    }
}

struct MenuBarStatusStrip: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 7) {
            if shouldShowStatusIcon {
                Image(systemName: "scope")
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 15, height: 18)
                    .accessibilityHidden(true)
            }

            ForEach(displayedComponents) { component in
                componentView(component)
            }
        }
        .padding(.horizontal, 1)
        .frame(height: 22)
        .fixedSize(horizontal: true, vertical: true)
        .transaction { transaction in
            transaction.animation = nil
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint(MenuMonitorLocalization.string(
            "打开 TraceHalo 实时监控",
            english: "Open TraceHalo real-time monitor",
            locale: locale
        ))
    }

    private var displayedComponents: [MonitorStatusBarComponent] {
        MenuBarStatusLayout.displayedComponents(in: model.monitorConfiguration)
            .filter { component in
                switch component.metric {
                case .batteryCharge, .batteryHealth:
                    PowerPresentationPolicy.isAvailable(in: model.snapshot)
                default:
                    true
                }
            }
    }

    private var shouldShowStatusIcon: Bool {
        MenuBarStatusLayout.showsStatusIcon(in: model.monitorConfiguration)
    }

    @ViewBuilder
    private func componentView(_ component: MonitorStatusBarComponent) -> some View {
        let displayTitle = component.localizedDisplayTitle(locale: locale)
        switch component.style {
        case .miniChart:
            HStack(spacing: 2) {
                StatusBarVerticalLabel(text: displayTitle)
                StatusBarAreaChart(
                    values: chartValues(for: component.metric),
                    ceiling: miniChartCeiling(for: component.metric),
                    maximumBarCount: 28
                )
                .frame(width: 36, height: 15)
                .padding(.horizontal, 2)
                .padding(.vertical, 1)
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 2))
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(.primary.opacity(0.5), lineWidth: 0.6)
                }
            }
        case .value:
            HStack(spacing: 3) {
                StatusBarVerticalLabel(text: displayTitle)
                Text(displayStatusValue(for: component.metric))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(width: valueWidth(for: component.metric), alignment: .trailing)
            }
        case .verticalGaugeValue:
            HStack(spacing: 3) {
                StatusBarVerticalLabel(text: displayTitle)
                StatusBarVerticalGauge(fraction: gaugeFraction(for: component.metric))
                Text(displayStatusValue(for: component.metric))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(width: valueWidth(for: component.metric), alignment: .trailing)
            }
        }
    }

    private var accessibilitySummary: String {
        guard !displayedComponents.isEmpty else { return "TraceHalo" }
        let metrics = displayedComponents.map { component in
            "\(component.localizedDisplayTitle(locale: locale)) \(statusValue(for: component.metric))"
        }
        .joined(separator: MenuMonitorLocalization.string("，", english: ", ", locale: locale))
        return MenuMonitorLocalization.format(
            "TraceHalo，%@",
            english: "TraceHalo, %@",
            locale: locale,
            metrics
        )
    }

    private func chartValues(for metric: MonitorMetric) -> [Double] {
        guard model.hasLoadedSnapshot else { return [] }
        let history = model.history(for: metric)
        if !history.isEmpty { return history }
        return currentNumericValue(for: metric).map { [$0] } ?? []
    }

    private func statusValue(for metric: MonitorMetric) -> String {
        guard model.hasLoadedSnapshot else { return "—" }
        if metric == .storageUsed {
            return rootVolume.map {
                MetricFormatter.percent($0.usedFraction * 100, locale: locale)
            } ?? "—"
        }
        return model.formattedValue(for: metric)
    }

    private func displayStatusValue(for metric: MonitorMetric) -> String {
        let value = statusValue(for: metric)
        guard metric == .temperature else { return value }
        return value
            .replacingOccurrences(of: "°C", with: "°")
            .replacingOccurrences(of: "°F", with: "°")
    }

    private func valueWidth(for metric: MonitorMetric) -> CGFloat {
        MenuBarStatusLayout.valueWidth(for: metric)
    }

    private func gaugeFraction(for metric: MonitorMetric) -> Double? {
        guard let value = currentNumericValue(for: metric), value.isFinite else { return nil }
        let upperBound = chartCeiling(for: metric) ?? max(value, 1)
        guard upperBound > 0 else { return nil }
        return min(max(value / upperBound, 0), 1)
    }

    private func currentNumericValue(for metric: MonitorMetric) -> Double? {
        let snapshot = model.snapshot
        return switch metric {
        case .cpuTotal: snapshot.cpu.totalPercent
        case .cpuUser: snapshot.cpu.userPercent
        case .cpuSystem: snapshot.cpu.systemPercent
        case .gpuUsage: snapshot.gpus.first?.utilizationPercent
        case .memoryPressure: snapshot.memory.pressurePercent
        case .memoryUsed:
            snapshot.memory.totalBytes > 0
                ? Double(snapshot.memory.usedBytes) / Double(snapshot.memory.totalBytes) * 100
                : nil
        case .storageUsed: rootVolume.map { $0.usedFraction * 100 }
        case .temperature: snapshot.cpu.temperatureCelsius
        case .fanSpeed: snapshot.cooling.fans.first.map { Double($0.currentRPM) }
        case .networkReceived: sumIfAvailable(snapshot.networkInterfaces.compactMap(\.receivedBytesPerSecond))
        case .networkSent: sumIfAvailable(snapshot.networkInterfaces.compactMap(\.sentBytesPerSecond))
        case .batteryCharge: snapshot.battery.chargePercent
        case .batteryHealth, .uptime: nil
        }
    }

    private func chartCeiling(for metric: MonitorMetric) -> Double? {
        switch metric {
        case .cpuTotal, .cpuUser, .cpuSystem, .gpuUsage, .memoryPressure, .memoryUsed, .storageUsed,
             .batteryCharge, .temperature:
            100
        case .fanSpeed, .networkReceived, .networkSent, .batteryHealth, .uptime:
            nil
        }
    }

    private func miniChartCeiling(for metric: MonitorMetric) -> Double? {
        switch metric {
        case .cpuTotal, .cpuUser, .cpuSystem, .gpuUsage, .memoryPressure, .memoryUsed, .storageUsed,
             .batteryCharge:
            let recentMaximum = model.history(for: metric).max() ?? 0
            let currentValue = currentNumericValue(for: metric) ?? 0
            return min(max(max(recentMaximum, currentValue) * 1.2, 25), 100)
        case .temperature:
            return 100
        case .fanSpeed, .networkReceived, .networkSent, .batteryHealth, .uptime:
            return nil
        }
    }

    private var rootVolume: StorageVolume? {
        preferredStorageVolume(in: model.snapshot.volumes)
    }
}

private struct StatusBarVerticalLabel: View {
    let text: String

    private var characters: [Character] {
        Array(text.uppercased().prefix(3))
    }

    var body: some View {
        VStack(spacing: -2) {
            ForEach(characters.indices, id: \.self) { index in
                Text(String(characters[index]))
                    .font(.system(size: 6.2, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(width: 8, height: 20)
        .accessibilityHidden(true)
    }
}

private struct StatusBarVerticalGauge: View {
    let fraction: Double?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(.primary.opacity(0.22))
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(.primary.opacity(0.92))
                    .frame(height: proxy.size.height * min(max(fraction ?? 0, 0), 1))
            }
        }
        .frame(width: 7, height: 16)
        .accessibilityHidden(true)
    }
}

private struct StatusBarAreaChart: View {
    let values: [Double]
    let ceiling: Double?
    let maximumBarCount: Int

    var body: some View {
        Canvas { context, size in
            let limit = max(maximumBarCount, 2)
            let recent = Array(values.suffix(limit))
            guard !recent.isEmpty else {
                let dash = Path(CGRect(x: 0, y: size.height / 2, width: size.width, height: 1))
                context.fill(dash, with: .color(.primary.opacity(0.45)))
                return
            }

            let samples = Array(repeating: recent[0], count: max(limit - recent.count, 0)) + recent
            let upperBound = max(ceiling ?? samples.max() ?? 1, 0.001)
            let points = samples.enumerated().map { index, value in
                CGPoint(
                    x: CGFloat(index) / CGFloat(samples.count - 1) * size.width,
                    y: size.height - (size.height * min(max(value / upperBound, 0.04), 1))
                )
            }

            var area = Path()
            area.move(to: CGPoint(x: 0, y: size.height))
            area.addLine(to: points[0])
            for point in points.dropFirst() {
                area.addLine(to: point)
            }
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .color(.primary.opacity(0.34)))

            var line = Path()
            line.move(to: points[0])
            for point in points.dropFirst() {
                line.addLine(to: point)
            }
            context.stroke(line, with: .color(.primary.opacity(0.92)), lineWidth: 0.9)
        }
        .accessibilityHidden(true)
    }
}

struct MenuBarDashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigationRouter.self) private var navigationRouter
    @Environment(\.openWindow) private var openWindow
    @Environment(\.locale) private var locale
    @State private var iconRepository = MenuBarIconRepository.shared
    @State private var selection: MenuBarDashboardSelection
    @State private var loadedDetailSection: MenuBarDashboardSection?
    private let openMainWindowAction: (() -> Void)?
    private let quitApplicationAction: (() -> Void)?
    private let maximumColumnHeightOverride: CGFloat?
    private let showsQuickLaunchFooter: Bool
    private let resetsSelectionOnPopoverClose: Bool
    private let presentationMode: MenuBarDashboardPresentationMode
    private let requestedSection: MenuBarDashboardSection?
    private let onSelectionChange: ((MenuBarDashboardSection?) -> Void)?

    init(
        initialSection: MenuBarDashboardSection? = nil,
        maximumColumnHeightOverride: CGFloat? = nil,
        openMainWindowAction: (() -> Void)? = nil,
        quitApplicationAction: (() -> Void)? = nil,
        showsQuickLaunchFooter: Bool = true,
        resetsSelectionOnPopoverClose: Bool = true,
        presentationMode: MenuBarDashboardPresentationMode = .popover,
        onSelectionChange: ((MenuBarDashboardSection?) -> Void)? = nil
    ) {
        _selection = State(
            initialValue: MenuBarDashboardSelection(
                selectedSection: initialSection
            )
        )
        _loadedDetailSection = State(
            initialValue: initialSection
        )
        self.openMainWindowAction = openMainWindowAction
        self.quitApplicationAction = quitApplicationAction
        self.maximumColumnHeightOverride = maximumColumnHeightOverride
        self.showsQuickLaunchFooter = showsQuickLaunchFooter
        self.resetsSelectionOnPopoverClose = resetsSelectionOnPopoverClose
        self.presentationMode = presentationMode
        requestedSection = initialSection
        self.onSelectionChange = onSelectionChange
    }

    var body: some View {
        let visibleSections = MenuBarDashboardSection.visibleSections(
            in: model.monitorConfiguration,
            snapshot: model.snapshot
        )
        let networkProjection = MenuBarDashboardSection.requiresNetworkProjection(
            visibleSections: visibleSections,
            selectedSection: selection.selectedSection
        ) ? makeNetworkProjection() : .empty

        HStack(alignment: .top, spacing: MenuBarDashboardLayout.columnSpacing) {
            primaryColumn(
                networkProjection: networkProjection,
                visibleSections: visibleSections
            )

            if selection.isExpanded {
                detailColumn(networkProjection: networkProjection)
                    .transition(.opacity)
            }
        }
        .frame(
            width: dashboardContentWidth,
            height: maximumColumnHeight,
            alignment: .topLeading
        )
        .padding(.horizontal, MenuBarDashboardLayout.horizontalChrome)
        .padding(.vertical, MenuBarDashboardLayout.verticalChrome)
        .background(
            MenuOverviewPalette.background,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .inset(by: 0.5)
                .stroke(MenuOverviewPalette.border, lineWidth: 1)
        }
        .fixedSize(horizontal: true, vertical: true)
        .task(
            id: MenuBarIconPrefetchKey.quickActions(
                items: model.monitorConfiguration.quickItems
            )
        ) {
            guard showsQuickLaunchFooter else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            iconRepository.prefetchQuickActions(
                MenuBarIconPrefetchKey.quickActions(
                    items: model.monitorConfiguration.quickItems
                )
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.didCloseNotification)) { _ in
            guard resetsSelectionOnPopoverClose else { return }
            selection.collapse(loadedDetailSection: &loadedDetailSection)
        }
        .onChange(of: visibleSections) { _, sections in
            guard let selectedSection = selection.selectedSection,
                  !sections.contains(selectedSection)
            else { return }
            if presentationMode == .embeddedPreview {
                selectSection(sections.first)
            } else {
                selection.collapse(loadedDetailSection: &loadedDetailSection)
                onSelectionChange?(nil)
            }
        }
        .onChange(of: requestedSection) { _, requested in
            guard presentationMode == .embeddedPreview else { return }
            let next = requested.flatMap { visibleSections.contains($0) ? $0 : nil }
                ?? visibleSections.first
            selectSection(next)
        }
    }

    private func primaryColumn(
        networkProjection: MenuNetworkProjection,
        visibleSections: [MenuBarDashboardSection]
    ) -> some View {
        let footerHeight = showsQuickLaunchFooter
            ? MenuBarDashboardLayout.footerHeight
            : 0
        let scrollingHeight = max(
            maximumColumnHeight - MenuBarDashboardLayout.headerHeight - footerHeight,
            0
        )

        return VStack(spacing: 0) {
            liveOverviewHeader

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    if visibleSections.isEmpty {
                        emptyModulesCard
                    } else {
                        overviewGroups(
                            networkProjection: networkProjection,
                            visibleSections: visibleSections
                        )
                    }
                }
            }
            .frame(height: scrollingHeight)

            if showsQuickLaunchFooter {
                quickLaunchFooter
            }
        }
        .frame(
            width: MenuBarDashboardLayout.primaryColumnWidth,
            height: maximumColumnHeight,
            alignment: .top
        )
        .background(MenuOverviewPalette.background)
    }

    private var liveOverviewHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Text(text("实时监控", "Real-Time Monitor"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MenuOverviewPalette.primaryText)
                Spacer(minLength: 8)
                Text(
                    model.isRefreshing
                        ? text("更新中", "Updating")
                        : MenuBarRecencyLabel.text(
                            capturedAt: model.snapshot.capturedAt,
                            locale: locale
                        )
                )
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(MenuOverviewPalette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

                Button {
                    Task { await model.refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(MenuOverviewPalette.secondaryText)
                        .frame(width: 18, height: 18)
                        .rotationEffect(.degrees(model.isRefreshing ? 360 : 0))
                        .animation(
                            model.isRefreshing
                                ? .linear(duration: 0.7).repeatForever(autoreverses: false)
                                : .default,
                            value: model.isRefreshing
                        )
                }
                .buttonStyle(.plain)
                .disabled(model.isRefreshing)
                .help(text("立即刷新实时监控", "Refresh the real-time monitor"))
                .accessibilityLabel(model.isRefreshing
                    ? text("正在刷新", "Refreshing")
                    : text("立即刷新实时监控", "Refresh the real-time monitor"))
            }
            .padding(.leading, 9)
            .padding(.trailing, 8)
            .padding(.top, 8)
            .frame(height: 32, alignment: .top)

            HStack(spacing: 0) {
                MenuOverviewTopMetric(
                    title: "CPU",
                    value: model.hasLoadedSnapshot
                        ? MetricFormatter.percent(model.snapshot.cpu.totalPercent, locale: locale)
                        : "—",
                    symbol: "cpu",
                    tint: MenuOverviewPalette.blue
                )

                MenuOverviewTopMetricDivider()

                MenuOverviewTopMetric(
                    title: text("内存", "Memory"),
                    value: model.hasLoadedSnapshot
                        ? MetricFormatter.percent(model.snapshot.memory.pressurePercent, locale: locale)
                        : "—",
                    symbol: "memorychip",
                    tint: MenuOverviewPalette.violet
                )

                MenuOverviewTopMetricDivider()

                MenuOverviewTopMetric(
                    title: text("温度", "Temperature"),
                    value: model.hasLoadedSnapshot
                        ? model.snapshot.cpu.temperatureCelsius.map {
                            model.temperatureUnit.formatted(celsius: $0, locale: locale)
                        } ?? "—"
                        : "—",
                    symbol: "thermometer.medium",
                    tint: MenuOverviewPalette.green
                )
            }
            .padding(.horizontal, 8)
            .frame(height: MenuBarDashboardLayout.headerHeight - 32)
        }
        .frame(
            width: MenuBarDashboardLayout.primaryColumnWidth,
            height: MenuBarDashboardLayout.headerHeight
        )
        .background(MenuOverviewPalette.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MenuOverviewPalette.divider)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func overviewGroups(
        networkProjection: MenuNetworkProjection,
        visibleSections: [MenuBarDashboardSection]
    ) -> some View {
        let computeSections: [MenuBarDashboardSection] = [.cpu, .memory, .gpu]
        let storageSections: [MenuBarDashboardSection] = [.storage, .network]
        let coolingSections: [MenuBarDashboardSection] = [.fans, .sensors]

        if computeSections.contains(where: visibleSections.contains) {
            MenuOverviewSectionHeader(title: text("计算资源", "Compute Resources"))
            if visibleSections.contains(.cpu) { cpuOverviewRow }
            if visibleSections.contains(.memory) { memoryOverviewRow }
            if visibleSections.contains(.gpu) { gpuOverviewRow }
        }

        if storageSections.contains(where: visibleSections.contains) {
            MenuOverviewSectionHeader(title: text("存储与连接", "Storage & Connectivity"))
            if visibleSections.contains(.storage) { storageOverviewRow }
            if visibleSections.contains(.network) {
                networkOverviewRow(networkProjection: networkProjection)
            }
        }

        if coolingSections.contains(where: visibleSections.contains) {
            MenuOverviewSectionHeader(title: text("散热状态", "Thermal Status"), height: 35)
            if visibleSections.contains(.fans) { fansOverviewRow }
            if visibleSections.contains(.sensors) { sensorsOverviewRow }
        }

        if visibleSections.contains(.battery),
           model.snapshot.battery.availability.isAvailable {
            MenuOverviewSectionHeader(title: text("电源", "Power"))
            batteryOverviewRow
        }
    }

    private var cpuOverviewRow: some View {
        compactOverviewRow(
            section: .cpu,
            symbol: "cpu",
            tint: MenuOverviewPalette.blue,
            height: MenuBarDashboardLayout.cpuRowHeight
        ) {
            MenuOverviewPrimaryMetric(
                title: "CPU",
                value: model.hasLoadedSnapshot
                    ? MetricFormatter.percent(model.snapshot.cpu.totalPercent, locale: locale)
                    : "—"
            )
        } secondary: {
            VStack(alignment: .leading, spacing: 3) {
                MenuOverviewPairedValue(
                    label: text("用户", "User"),
                    value: model.hasLoadedSnapshot
                        ? MetricFormatter.percent(model.snapshot.cpu.userPercent, locale: locale)
                        : "—"
                )
                MenuOverviewPairedValue(
                    label: text("系统", "System"),
                    value: model.hasLoadedSnapshot
                        ? MetricFormatter.percent(model.snapshot.cpu.systemPercent, locale: locale)
                        : "—"
                )
            }
        } visual: {
            MenuBarHistogram(
                values: nonemptyHistory(
                    .cpuTotal,
                    fallback: model.snapshot.cpu.totalPercent
                ),
                ceiling: 100,
                color: MenuOverviewPalette.blue,
                maximumBarCount: 24
            )
            .frame(height: 24)
        }
    }

    private var memoryOverviewRow: some View {
        compactOverviewRow(
            section: .memory,
            symbol: "memorychip",
            tint: MenuOverviewPalette.violet,
            height: MenuBarDashboardLayout.memoryRowHeight
        ) {
            MenuOverviewPrimaryMetric(
                title: text("内存", "Memory"),
                value: model.hasLoadedSnapshot
                    ? MetricFormatter.percent(model.snapshot.memory.pressurePercent, locale: locale)
                    : "—"
            )
        } secondary: {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.hasLoadedSnapshot
                    ? MetricFormatter.bytes(model.snapshot.memory.usedBytes, locale: locale)
                    : "—")
                Text(
                    model.hasLoadedSnapshot
                        ? "/ \(MetricFormatter.bytes(model.snapshot.memory.totalBytes, locale: locale))"
                        : "/ —"
                )
            }
            .font(.system(size: 9.5, weight: .medium, design: .rounded))
            .foregroundStyle(MenuOverviewPalette.secondaryText)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.74)
        } visual: {
            MenuProgressBar(
                fraction: model.snapshot.memory.pressurePercent / 100,
                tint: MenuOverviewPalette.violet
            )
        }
    }

    private var gpuOverviewRow: some View {
        let gpu = model.snapshot.gpus.first
        let usage = gpu?.utilizationPercent
        return compactOverviewRow(
            section: .gpu,
            symbol: "display",
            tint: MenuOverviewPalette.cyan,
            height: MenuBarDashboardLayout.gpuRowHeight
        ) {
            MenuOverviewPrimaryMetric(
                title: "GPU",
                value: model.hasLoadedSnapshot
                    ? usage.map { MetricFormatter.percent($0, locale: locale) } ?? "—"
                    : "—"
            )
        } secondary: {
            VStack(alignment: .leading, spacing: 3) {
                Text(gpu?.name ?? text("未检测到 GPU", "No GPU detected"))
                    .truncationMode(.middle)
                    .help(gpu?.name ?? text("未检测到 GPU", "No GPU detected"))
                Text(format(
                    "统一内存 %@",
                    "Unified memory %@",
                    gpu?.usedMemoryBytes.map {
                        MetricFormatter.bytes($0, locale: locale)
                    } ?? "—"
                ))
            }
            .font(.system(size: 9.1, weight: .medium))
            .foregroundStyle(MenuOverviewPalette.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
        } visual: {
            MenuBarHistogram(
                values: nonemptyHistory(.gpuUsage, fallback: usage ?? 0),
                ceiling: 100,
                color: MenuOverviewPalette.cyan,
                maximumBarCount: 24
            )
            .frame(height: 24)
        }
    }

    private var storageOverviewRow: some View {
        let volume = rootVolume
        return compactOverviewRow(
            section: .storage,
            symbol: "internaldrive",
            tint: MenuOverviewPalette.cyan,
            height: MenuBarDashboardLayout.storageRowHeight
        ) {
            MenuOverviewPrimaryMetric(
                title: text("存储", "Storage"),
                value: volume.map {
                    MetricFormatter.percent($0.usedFraction * 100, locale: locale)
                } ?? "—"
            )
        } secondary: {
            VStack(alignment: .leading, spacing: 3) {
                Text(volume?.name ?? text("未检测到存储卷", "No storage volume detected"))
                    .truncationMode(.middle)
                    .help(volume?.name ?? text("未检测到存储卷", "No storage volume detected"))
                Text(volume.map {
                    format(
                        "%@ 可用",
                        "%@ available",
                        MetricFormatter.bytes($0.availableBytes, locale: locale)
                    )
                } ?? "—")
            }
            .font(.system(size: 9.2, weight: .medium))
            .foregroundStyle(MenuOverviewPalette.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.76)
        } visual: {
            MenuProgressBar(
                fraction: volume?.usedFraction ?? 0,
                tint: MenuOverviewPalette.cyan
            )
        }
    }

    private func networkOverviewRow(
        networkProjection: MenuNetworkProjection
    ) -> some View {
        let activeServices = networkProjection.services.filter(\.isActive)
        let primaryService = activeServices.first ?? networkProjection.services.first
        let received = networkProjection.totalReceivedRate
        let sent = networkProjection.totalSentRate

        return MenuOverviewSelectableRow(
            height: MenuBarDashboardLayout.networkRowHeight,
            tint: MenuOverviewPalette.amber,
            isHighlighted: isOverviewHighlighted(.network),
            isExpanded: selection.selectedSection == .network,
            accessibilityLabel: format(
                "网络服务，%@",
                "Network Services, %@",
                sectionAccessibilitySummary(.network, networkProjection: networkProjection)
            ),
            action: { toggleSelection(.network) }
        ) {
            HStack(spacing: 0) {
                MenuOverviewIcon(symbol: "network", tint: MenuOverviewPalette.amber)
                    .frame(width: 24)
                Color.clear.frame(width: 19.5)

                VStack(alignment: .leading, spacing: 3) {
                    Text(text("网络服务", "Network Services"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(MenuOverviewPalette.secondaryText)
                    Text(
                        "\(count(networkProjection.services.count, unit: .service)) · "
                            + count(activeServices.count, unit: .activeService)
                    )
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(MenuOverviewPalette.primaryText)
                    Text(networkServiceSummary(primaryService))
                        .font(.system(size: 9.2, weight: .medium))
                        .foregroundStyle(MenuOverviewPalette.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(networkServiceSummary(primaryService))
                    HStack(spacing: 6) {
                        MenuOverviewRate(
                            symbol: "arrow.down",
                            value: received.map {
                                MetricFormatter.rate(bytesPerSecond: $0, locale: locale)
                            } ?? "—",
                            tint: MenuOverviewPalette.amber
                        )
                        MenuOverviewRate(
                            symbol: "arrow.up",
                            value: sent.map {
                                MetricFormatter.rate(bytesPerSecond: $0, locale: locale)
                            } ?? "—",
                            tint: MenuOverviewPalette.green
                        )
                    }
                }
                .frame(width: 125.25, alignment: .leading)
                .layoutPriority(2)

                MenuBarHistogram(
                    values: nonemptyHistory(
                        .networkReceived,
                        fallback: received ?? 0
                    ),
                    ceiling: nil,
                    color: MenuOverviewPalette.amber,
                    maximumBarCount: 20
                )
                .frame(width: 56, height: 28)

                Color.clear.frame(width: 7)
                MenuOverviewChevron()
                    .frame(width: 20)
            }
            .padding(.leading, 9)
            .padding(.trailing, 10.25)
        }
    }

    private var fansOverviewRow: some View {
        let fans = Array(model.snapshot.cooling.fans.prefix(2))
        return MenuOverviewSelectableRow(
            height: MenuBarDashboardLayout.fansRowHeight,
            tint: MenuOverviewPalette.cyan,
            isHighlighted: isOverviewHighlighted(.fans),
            isExpanded: selection.selectedSection == .fans,
            accessibilityLabel: format(
                "风扇，%@",
                "Fans, %@",
                sectionAccessibilitySummary(.fans)
            ),
            action: { toggleSelection(.fans) }
        ) {
            HStack(spacing: 0) {
                MenuOverviewIcon(symbol: "fan", tint: MenuOverviewPalette.cyan)
                    .frame(width: 24)
                Color.clear.frame(width: 19.5)
                Text(text("风扇", "Fans"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(MenuOverviewPalette.secondaryText)
                    .frame(width: 49, alignment: .leading)

                VStack(spacing: 4) {
                    ForEach(0..<2, id: \.self) { index in
                        HStack(spacing: 2) {
                            Text(index < fans.count ? fans[index].name : "Fan \(index + 1)")
                                .frame(width: 28, alignment: .leading)
                            Spacer(minLength: 0)
                            Text(index < fans.count
                                ? "\(fans[index].currentRPM.formatted(.number.locale(locale))) RPM"
                                : "—")
                                .fontWeight(.semibold)
                        }
                    }
                }
                .font(.system(size: 9.2, design: .rounded))
                .foregroundStyle(MenuOverviewPalette.secondaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 95)

                Color.clear.frame(width: 5)

                VStack(spacing: 9) {
                    ForEach(0..<2, id: \.self) { index in
                        MenuProgressBar(
                            fraction: fanFraction(fans, at: index),
                            tint: MenuOverviewPalette.cyan
                        )
                    }
                }
                .frame(width: 37)

                Color.clear.frame(width: 7)
                MenuOverviewChevron()
                    .frame(width: 20)
            }
            .padding(.leading, 9)
            .padding(.trailing, 10.5)
        }
    }

    private var sensorsOverviewRow: some View {
        let temperature = model.snapshot.cpu.temperatureCelsius
        return MenuOverviewSelectableRow(
            height: MenuBarDashboardLayout.sensorsRowHeight,
            tint: MenuOverviewPalette.green,
            isHighlighted: isOverviewHighlighted(.sensors),
            isExpanded: selection.selectedSection == .sensors,
            accessibilityLabel: format(
                "温度传感器，%@",
                "Temperature Sensors, %@",
                sectionAccessibilitySummary(.sensors)
            ),
            action: { toggleSelection(.sensors) }
        ) {
            HStack(spacing: 0) {
                MenuOverviewIcon(symbol: "thermometer.medium", tint: MenuOverviewPalette.green)
                    .frame(width: 24)
                Color.clear.frame(width: 19.5)

                VStack(alignment: .leading, spacing: 3) {
                    Text(text("温度传感器", "Temperature Sensors"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(MenuOverviewPalette.secondaryText)
                    Text(temperature.map {
                        model.temperatureUnit.formatted(celsius: $0, locale: locale)
                    } ?? "—")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(MenuOverviewPalette.primaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                    Text(format(
                        "CPU 平均 · %@",
                        "CPU average · %@",
                        count(model.snapshot.cooling.sensors.count, unit: .sensor)
                    ))
                        .font(.system(size: 9.1, weight: .medium))
                        .foregroundStyle(MenuOverviewPalette.tertiaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(width: 125.25, alignment: .leading)
                .layoutPriority(2)

                MenuOverviewAreaChart(
                    values: nonemptyHistory(.temperature, fallback: temperature ?? 0),
                    ceiling: 100,
                    color: MenuOverviewPalette.green,
                    maximumPointCount: 24
                )
                .frame(width: 56, height: 34)

                Color.clear.frame(width: 7)
                MenuOverviewChevron()
                    .frame(width: 20)
            }
            .padding(.leading, 9)
            .padding(.trailing, 10.25)
        }
    }

    private var batteryOverviewRow: some View {
        let battery = model.snapshot.battery
        return compactOverviewRow(
            section: .battery,
            symbol: "battery.75percent",
            tint: MenuOverviewPalette.green,
            height: MenuBarDashboardLayout.storageRowHeight
        ) {
            MenuOverviewPrimaryMetric(
                title: text("电池", "Battery"),
                value: battery.chargePercent.map {
                    MetricFormatter.percent($0, locale: locale)
                } ?? "—"
            )
        } secondary: {
            VStack(alignment: .leading, spacing: 3) {
                Text(battery.isCharging
                    ? text("正在充电", "Charging")
                    : text("电池供电", "On Battery"))
                Text(format(
                    "健康 · %@",
                    "Health · %@",
                    localizedBatteryHealth(battery.health)
                ))
            }
            .font(.system(size: 9.2, weight: .medium))
            .foregroundStyle(MenuOverviewPalette.secondaryText)
            .lineLimit(1)
        } visual: {
            MenuProgressBar(
                fraction: (battery.chargePercent ?? 0) / 100,
                tint: MenuOverviewPalette.green
            )
        }
    }

    private func compactOverviewRow<Primary: View, Secondary: View, Visual: View>(
        section: MenuBarDashboardSection,
        symbol: String,
        tint: Color,
        height: CGFloat,
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary,
        @ViewBuilder visual: () -> Visual
    ) -> some View {
        MenuOverviewSelectableRow(
            height: height,
            tint: tint,
            isHighlighted: isOverviewHighlighted(section),
            isExpanded: selection.selectedSection == section,
            accessibilityLabel: format(
                "%@，%@",
                "%@, %@",
                section.localizedTitle(locale: locale),
                sectionAccessibilitySummary(section)
            ),
            action: { toggleSelection(section) }
        ) {
            HStack(spacing: 0) {
                MenuOverviewIcon(symbol: symbol, tint: tint)
                    .frame(width: 24)
                Color.clear.frame(width: 19.5)
                primary()
                    .frame(width: 53.5, alignment: .leading)
                    .layoutPriority(3)
                Rectangle()
                    .fill(MenuOverviewPalette.divider)
                    .frame(width: 0.75, height: 31)
                Color.clear.frame(width: 6)
                secondary()
                    .frame(width: 69, alignment: .leading)
                    .layoutPriority(2)
                visual()
                    .frame(width: 56)
                    .layoutPriority(1)
                Color.clear.frame(width: 7)
                MenuOverviewChevron()
                    .frame(width: 20)
            }
            .padding(.leading, 9)
            .padding(.trailing, 11.25)
        }
    }

    private func networkServiceSummary(_ service: NetworkInterfaceState?) -> String {
        guard let service else { return text("暂无活跃连接", "No active connection") }
        if let speed = service.linkSpeedMbps {
            let formattedSpeed = speed.formatted(
                .number.precision(.fractionLength(0)).locale(locale)
            )
            return "\(service.displayName) \(formattedSpeed) Mbps"
        }
        return service.displayName
    }

    private func isOverviewHighlighted(_ section: MenuBarDashboardSection) -> Bool {
        selection.selectedSection == section
            || (selection.selectedSection == nil && section == .cpu)
    }

    private func fanFraction(_ fans: [FanState], at index: Int) -> Double {
        guard fans.indices.contains(index) else { return 0 }
        let fan = fans[index]
        let ceiling = max(fan.maximumRPM ?? max(fan.currentRPM, 1), 1)
        return Double(fan.currentRPM) / Double(ceiling)
    }

    private var emptyModulesCard: some View {
        VStack(spacing: 9) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(CalmTheme.secondaryText)
            Text(text("尚未选择监控模块", "No Monitoring Modules Selected"))
                .font(.callout.weight(.semibold))
            Text(text(
                "请在 TraceHalo 的实时监控设置中启用至少一个模块。",
                "Enable at least one module in TraceHalo's real-time monitor settings."
            ))
                .font(.caption)
                .foregroundStyle(CalmTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 14)
        .background(CalmTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(CalmTheme.hairline, lineWidth: 0.8)
        }
    }

    private func detailColumn(networkProjection: MenuNetworkProjection) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 9) {
                if let selectedSection = selection.selectedSection {
                    detailSummaryCard(
                        for: selectedSection,
                        networkProjection: networkProjection
                    )
                    if loadedDetailSection == selectedSection {
                        detailSupportingCards(
                            for: selectedSection,
                            networkProjection: networkProjection
                        )
                    }
                }
            }
        }
        .frame(
            width: MenuBarDashboardLayout.detailColumnWidth,
            height: maximumColumnHeight
        )
        .accessibilityLabel(
            selection.selectedSection.map {
                format(
                    "TraceHalo %@详细监控",
                    "TraceHalo %@ details",
                    $0.localizedTitle(locale: locale)
                )
            } ?? text("TraceHalo 详细监控", "TraceHalo monitor details")
        )
    }

    private func toggleSelection(_ section: MenuBarDashboardSection) {
        if presentationMode == .embeddedPreview {
            selectSection(section)
            return
        }
        selection.toggle(
            section,
            loadedDetailSection: &loadedDetailSection
        )
        onSelectionChange?(selection.selectedSection)
    }

    private func selectSection(_ section: MenuBarDashboardSection?) {
        selection.select(section)
        loadedDetailSection = section
        onSelectionChange?(section)
    }

    private func sectionAccessibilitySummary(
        _ section: MenuBarDashboardSection,
        networkProjection: MenuNetworkProjection? = nil
    ) -> String {
        guard model.hasLoadedSnapshot else { return text("正在读取数据", "Loading data") }

        switch section {
        case .cpu:
            let cpu = model.snapshot.cpu
            return format(
                "总使用 %@，用户 %@，系统 %@",
                "Total %@, user %@, system %@",
                MetricFormatter.percent(cpu.totalPercent, locale: locale),
                MetricFormatter.percent(cpu.userPercent, locale: locale),
                MetricFormatter.percent(cpu.systemPercent, locale: locale)
            )
        case .memory:
            let memory = model.snapshot.memory
            return format(
                "内存使用估算 %@，已使用 %@，可用 %@",
                "Memory usage estimate %@, %@ used, %@ available",
                MetricFormatter.percent(memory.pressurePercent, locale: locale),
                MetricFormatter.bytes(memory.usedBytes, locale: locale),
                MetricFormatter.bytes(memory.availableBytes, locale: locale)
            )
        case .gpu:
            guard let gpu = model.snapshot.gpus.first else {
                return text("未检测到图形设备数据", "No GPU data detected")
            }
            let usage = gpu.utilizationPercent.map {
                MetricFormatter.percent($0, locale: locale)
            }
                ?? text("使用率不可用", "Usage unavailable")
            let memory = gpu.usedMemoryBytes.map {
                MetricFormatter.bytes($0, locale: locale)
            }
                ?? text("内存数据不可用", "Memory data unavailable")
            return format(
                "%@，%@，统一内存 %@",
                "%@, %@, unified memory %@",
                gpu.name,
                usage,
                memory
            )
        case .storage:
            guard let volume = rootVolume else {
                return text("存储卷数据不可用", "Storage volume data unavailable")
            }
            return format(
                "%@，已使用 %@，可用 %@",
                "%@, %@ used, %@ available",
                volume.name,
                MetricFormatter.percent(volume.usedFraction * 100, locale: locale),
                MetricFormatter.bytes(volume.availableBytes, locale: locale)
            )
        case .network:
            let projection = networkProjection ?? makeNetworkProjection()
            let activeCount = projection.services.filter(\.isActive).count
            let received = projection.totalReceivedRate.map {
                MetricFormatter.rate(bytesPerSecond: $0, locale: locale)
            }
                ?? text("不可用", "Unavailable")
            let sent = projection.totalSentRate.map {
                MetricFormatter.rate(bytesPerSecond: $0, locale: locale)
            }
                ?? text("不可用", "Unavailable")
            return format(
                "%@，%@，下载 %@，上传 %@",
                "%@, %@, download %@, upload %@",
                count(projection.services.count, unit: .service),
                count(activeCount, unit: .connectedService),
                received,
                sent
            )
        case .fans:
            let fans = model.snapshot.cooling.fans
            guard !fans.isEmpty else {
                return model.snapshot.cooling.sensorAvailability.message.map(serviceMessage)
                    ?? text("风扇转速不可用", "Fan speeds unavailable")
            }
            let values = fans.prefix(2)
                .map { "\($0.name) \($0.currentRPM.formatted(.number.locale(locale))) RPM" }
                .joined(separator: "，")
            return format(
                "%@，%@",
                "%@, %@",
                count(fans.count, unit: .fan),
                values
            )
        case .sensors:
            let temperature = model.snapshot.cpu.temperatureCelsius
                .map { model.temperatureUnit.formatted(celsius: $0, locale: locale) }
                ?? text("不可用", "Unavailable")
            return format(
                "CPU 平均 %@，已读取 %@",
                "CPU average %@, %@ read",
                temperature,
                count(model.snapshot.cooling.sensors.count, unit: .sensor)
            )
        case .battery:
            let battery = model.snapshot.battery
            guard battery.availability.isAvailable else {
                return battery.availability.message.map(serviceMessage)
                    ?? text("当前设备没有可用的内置电池", "This device has no available built-in battery")
            }
            let charge = battery.chargePercent.map {
                MetricFormatter.percent($0, locale: locale)
            }
                ?? text("电量不可用", "Charge unavailable")
            let cycles = battery.cycleCount.map {
                count($0, unit: .cycle)
            } ?? text("循环次数不可用", "Cycle count unavailable")
            return format(
                "%@，健康 %@，%@",
                "%@, health %@, %@",
                charge,
                localizedBatteryHealth(battery.health),
                cycles
            )
        }
    }

    @ViewBuilder
    private func detailSummaryCard(
        for section: MenuBarDashboardSection,
        networkProjection: MenuNetworkProjection
    ) -> some View {
        switch section {
        case .cpu:
            cpuDetailSummaryCard
        case .memory:
            memoryDetailSummaryCard
        case .gpu:
            gpuDetailCard
        case .storage:
            storageDetailSummaryCard
        case .network:
            networkTrafficCard(networkProjection: networkProjection)
        case .fans:
            coolingDetailSummaryCard
        case .sensors:
            temperatureDetailSummaryCard
        case .battery:
            batteryDetailSummaryCard
        }
    }

    @ViewBuilder
    private func detailSupportingCards(
        for section: MenuBarDashboardSection,
        networkProjection: MenuNetworkProjection
    ) -> some View {
        switch section {
        case .cpu:
            cpuCoresCard
            cpuProcessesCard
        case .memory:
            memoryBreakdownCard
            memoryProcessesCard
        case .gpu:
            gpuDevicesCard
            displayDevicesCard
        case .storage:
            storageVolumesCard
            storageIOCard
        case .network:
            networkInterfacesCard(networkProjection: networkProjection)
        case .fans:
            fanDetailsCard
        case .sensors:
            thermalSensorsCard
        case .battery:
            if model.snapshot.battery.availability.isAvailable {
                batteryCapacityCard
                batteryPowerCard
            }
        }
    }

    private var cpuDetailSummaryCard: some View {
        MenuMetricCard(title: "CPU", symbol: "cpu", tint: MenuPalette.blue) {
            cpuSummaryContent
        }
    }

    @ViewBuilder
    private var cpuSummaryContent: some View {
        if model.hasLoadedSnapshot {
            MenuBarHistogram(
                values: nonemptyHistory(.cpuTotal, fallback: model.snapshot.cpu.totalPercent),
                ceiling: 100,
                color: MenuPalette.blue,
                maximumBarCount: 48
            )
            .frame(height: 24)

            MenuProgressRow(
                label: "用户",
                value: MetricFormatter.percent(model.snapshot.cpu.userPercent, locale: locale),
                fraction: model.snapshot.cpu.userPercent / 100,
                tint: MenuPalette.blue
            )
            MenuProgressRow(
                label: "系统",
                value: MetricFormatter.percent(model.snapshot.cpu.systemPercent, locale: locale),
                fraction: model.snapshot.cpu.systemPercent / 100,
                tint: MenuPalette.blue
            )
        } else {
            MenuUnavailableText(message: "正在读取 CPU 状态。")
        }
    }

    private var cpuCoresCard: some View {
        MenuMetricCard(title: "CPU 核心", symbol: "cpu", tint: MenuPalette.blue) {
            if !model.hasLoadedSnapshot {
                MenuUnavailableText(message: "正在读取逐核心占用。")
            } else if model.snapshot.cpu.perCorePercent.isEmpty {
                MenuUnavailableText(message: "系统未返回逐核心占用数据。")
            } else {
                LazyVStack(spacing: 3) {
                    ForEach(model.snapshot.cpu.perCorePercent.indices, id: \.self) { index in
                        MenuCoreRow(
                            index: index + 1,
                            percent: model.snapshot.cpu.perCorePercent[index]
                        )
                    }
                }
            }
        }
    }

    private var cpuProcessesCard: some View {
        MenuMetricCard(title: "CPU 使用进程", symbol: "list.bullet.rectangle", tint: MenuPalette.blue) {
            if !model.hasLoadedSnapshot {
                MenuUnavailableText(message: "正在读取进程占用。")
            } else if model.snapshot.cpu.topProcesses.isEmpty {
                MenuUnavailableText(message: "当前没有可显示的进程占用数据。")
            } else {
                LazyVStack(spacing: 1) {
                    ForEach(model.snapshot.cpu.topProcesses.prefix(10)) { process in
                        MenuProcessRow(
                            process: process,
                            icon: iconRepository.processIcon(for: process)
                        )
                    }
                }
            }
        }
        .task(
            id: MenuBarIconPrefetchKey.processIdentities(
                cpuProcesses: model.snapshot.cpu.topProcesses,
                memoryProcesses: []
            )
        ) {
            await Task.yield()
            guard !Task.isCancelled else { return }
            iconRepository.prefetchProcessIcons(
                MenuBarIconPrefetchKey.processIdentities(
                    cpuProcesses: model.snapshot.cpu.topProcesses,
                    memoryProcesses: []
                )
            )
        }
    }

    private var gpuDetailCard: some View {
        MenuMetricCard(title: "GPU", symbol: "display", tint: MenuPalette.cyan) {
            gpuSummaryContent
        }
    }

    @ViewBuilder
    private var gpuSummaryContent: some View {
        if !model.hasLoadedSnapshot {
            MenuUnavailableText(message: "正在读取 GPU 状态。")
        } else if let gpu = model.snapshot.gpus.first {
            Text(gpu.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            if let usage = gpu.utilizationPercent {
                MenuProgressBar(fraction: usage / 100, tint: MenuPalette.cyan)
                MenuValueRow(
                    label: "GPU 使用率",
                    value: MetricFormatter.percent(usage, locale: locale)
                )
            } else {
                MenuValueRow(label: "使用率", value: "—")
            }

            MenuValueRow(
                label: "统一内存",
                value: gpu.usedMemoryBytes.map {
                    MetricFormatter.bytes($0, locale: locale)
                } ?? "—"
            )
            if let used = gpu.usedMemoryBytes,
               let allocated = gpu.allocatedMemoryBytes,
               allocated > 0 {
                MenuProgressBar(fraction: Double(used) / Double(allocated), tint: MenuPalette.cyan)
            } else if let capacity = gpu.memoryDescription {
                MenuValueRow(label: "工作集上限", value: capacity)
            }
        } else {
            MenuUnavailableText(message: "未检测到可显示的图形设备数据。")
        }
    }

    private var memoryDetailSummaryCard: some View {
        let memory = model.snapshot.memory
        return MenuMetricCard(title: "内存概览", symbol: "memorychip", tint: MenuPalette.violet) {
            if !model.hasLoadedSnapshot {
                MenuUnavailableText(message: "正在读取内存状态。")
            } else {
                MenuBarHistogram(
                    values: nonemptyHistory(.memoryPressure, fallback: memory.pressurePercent),
                    ceiling: 100,
                    color: MenuPalette.violet,
                    maximumBarCount: 48
                )
                .frame(height: 24)
                MenuProgressRow(
                    label: "使用估算",
                    value: MetricFormatter.percent(memory.pressurePercent, locale: locale),
                    fraction: memory.pressurePercent / 100,
                    tint: MenuPalette.violet
                )
                MenuValueRow(
                    label: "已使用",
                    value: MetricFormatter.bytes(memory.usedBytes, locale: locale)
                )
                MenuValueRow(
                    label: "可用",
                    value: MetricFormatter.bytes(memory.availableBytes, locale: locale)
                )
                Text(text(
                    "当前百分比为内存占用估算，不代表 macOS 原生内存压力等级。",
                    "This percentage estimates memory usage; it is not the native macOS memory-pressure level."
                ))
                    .font(.system(size: 8.5))
                    .foregroundStyle(CalmTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var memoryBreakdownCard: some View {
        let memory = model.snapshot.memory
        return MenuMetricCard(title: "内存构成", symbol: "chart.bar.xaxis", tint: MenuPalette.violet) {
            if !model.hasLoadedSnapshot {
                MenuUnavailableText(message: "正在读取内存构成。")
            } else {
                MenuValueRow(label: "总容量", value: MetricFormatter.bytes(memory.totalBytes, locale: locale))
                MenuValueRow(label: "活跃", value: MetricFormatter.bytes(memory.activeBytes, locale: locale))
                MenuValueRow(label: "联动", value: MetricFormatter.bytes(memory.wiredBytes, locale: locale))
                MenuValueRow(label: "压缩", value: MetricFormatter.bytes(memory.compressedBytes, locale: locale))
                MenuValueRow(label: "非活跃", value: MetricFormatter.bytes(memory.inactiveBytes, locale: locale))
                MenuValueRow(
                    label: "交换空间",
                    value: "\(MetricFormatter.bytes(memory.swapUsedBytes, locale: locale)) / \(MetricFormatter.bytes(memory.swapTotalBytes, locale: locale))"
                )
                if memory.swapTotalBytes > 0 {
                    MenuProgressBar(
                        fraction: Double(memory.swapUsedBytes) / Double(memory.swapTotalBytes),
                        tint: MenuPalette.violet
                    )
                }
            }
        }
    }

    private var memoryProcessesCard: some View {
        MenuMetricCard(title: "内存使用进程", symbol: "list.bullet.rectangle", tint: MenuPalette.violet) {
            if !model.hasLoadedSnapshot {
                MenuUnavailableText(message: "正在读取进程内存。")
            } else if model.snapshot.memory.topProcesses.isEmpty {
                MenuUnavailableText(message: "当前没有可显示的进程内存数据。")
            } else {
                LazyVStack(spacing: 1) {
                    ForEach(model.snapshot.memory.topProcesses.prefix(10)) { process in
                        MenuProcessMetricRow(
                            process: process,
                            icon: iconRepository.processIcon(for: process),
                            value: MetricFormatter.bytes(process.memoryBytes, locale: locale),
                            metricName: "内存"
                        )
                    }
                }
            }
        }
        .task(
            id: MenuBarIconPrefetchKey.processIdentities(
                cpuProcesses: [],
                memoryProcesses: model.snapshot.memory.topProcesses
            )
        ) {
            await Task.yield()
            guard !Task.isCancelled else { return }
            iconRepository.prefetchProcessIcons(
                MenuBarIconPrefetchKey.processIdentities(
                    cpuProcesses: [],
                    memoryProcesses: model.snapshot.memory.topProcesses
                )
            )
        }
    }

    private var gpuDevicesCard: some View {
        MenuMetricCard(title: "图形设备", symbol: "rectangle.3.group", tint: MenuPalette.cyan) {
            if !model.hasLoadedSnapshot {
                MenuUnavailableText(message: "正在读取图形设备。")
            } else if model.snapshot.gpus.isEmpty {
                MenuUnavailableText(message: "系统未返回图形设备信息。")
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(model.snapshot.gpus.enumerated()), id: \.offset) { index, gpu in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(gpu.name)
                                .font(.system(size: 10.5, weight: .semibold))
                                .lineLimit(1)
                            MenuValueRow(label: "厂商", value: gpu.vendor)
                            MenuValueRow(label: "硬件标识", value: gpu.modelIdentifier ?? "—")
                            MenuValueRow(
                                label: "图形核心",
                                value: gpu.coreCount.map {
                                    count($0, unit: .core)
                                } ?? "—"
                            )
                            MenuValueRow(label: "内存架构", value: gpu.family ?? "—")
                            MenuValueRow(label: "Metal", value: gpu.metalSupport ?? "—")
                            MenuValueRow(label: "驱动", value: gpu.driver ?? "—")
                            MenuValueRow(
                                label: "温度",
                                value: gpu.temperatureCelsius.map {
                                    model.temperatureUnit.formatted(celsius: $0, locale: locale)
                                } ?? "—"
                            )
                        }
                        if index < model.snapshot.gpus.count - 1 {
                            CalmDivider()
                        }
                    }
                }
            }
        }
    }

    private var displayDevicesCard: some View {
        let displays = model.snapshot.gpus.flatMap(\.displays)
        return MenuMetricCard(title: "显示器", symbol: "display.2", tint: MenuPalette.cyan) {
            if !model.hasLoadedSnapshot {
                MenuUnavailableText(message: "正在读取显示器信息。")
            } else if displays.isEmpty {
                MenuUnavailableText(message: "系统未返回显示器信息。")
            } else {
                VStack(spacing: 7) {
                    ForEach(Array(displays.enumerated()), id: \.offset) { index, display in
                        MenuDisplayDetailRow(display: display)
                        if index < displays.count - 1 {
                            CalmDivider()
                        }
                    }
                }
            }
        }
    }

    private var storageDetailSummaryCard: some View {
        MenuMetricCard(title: "存储概览", symbol: "internaldrive", tint: MenuPalette.cyan) {
            if !model.hasLoadedSnapshot {
                MenuUnavailableText(message: "正在读取存储状态。")
            } else if let volume = rootVolume {
                Text(volume.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                MenuProgressBar(fraction: volume.usedFraction, tint: MenuPalette.cyan)
                MenuValueRow(label: "已使用", value: MetricFormatter.bytes(volume.usedBytes, locale: locale))
                MenuValueRow(label: "可用", value: MetricFormatter.bytes(volume.availableBytes, locale: locale))
                MenuValueRow(label: "总容量", value: MetricFormatter.bytes(volume.totalBytes, locale: locale))
                MenuValueRow(label: "文件系统", value: volume.fileSystem ?? "—")
            } else {
                MenuUnavailableText(message: "系统未返回存储卷信息。")
            }
        }
    }

    private var storageVolumesCard: some View {
        MenuMetricCard(title: "存储卷", symbol: "externaldrive.connected.to.line.below", tint: MenuPalette.cyan) {
            if !model.hasLoadedSnapshot {
                MenuUnavailableText(message: "正在读取存储卷。")
            } else if model.snapshot.volumes.isEmpty {
                MenuUnavailableText(message: "系统未返回存储卷信息。")
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(model.snapshot.volumes.enumerated()), id: \.offset) { index, volume in
                        MenuStorageVolumeDetail(volume: volume)
                        if index < model.snapshot.volumes.count - 1 {
                            CalmDivider()
                        }
                    }
                }
            }
        }
    }

    private var storageIOCard: some View {
        let io = model.snapshot.storageIO
        return MenuMetricCard(title: "物理磁盘 I/O", symbol: "arrow.left.arrow.right", tint: MenuPalette.cyan) {
            if !model.hasLoadedSnapshot {
                MenuUnavailableText(message: "正在读取物理磁盘 I/O。")
            } else if !io.availability.isAvailable {
                MenuUnavailableText(message: io.availability.message.map(serviceMessage)
                    ?? text("系统未返回块存储统计。", "The system did not return block-storage statistics."))
            } else {
                MenuValueRow(
                    label: "当前读取",
                    value: io.readBytesPerSecond.map {
                        MetricFormatter.rate(bytesPerSecond: $0, locale: locale)
                    }
                        ?? text("正在建立基线", "Establishing baseline")
                )
                MenuValueRow(
                    label: "当前写入",
                    value: io.writeBytesPerSecond.map {
                        MetricFormatter.rate(bytesPerSecond: $0, locale: locale)
                    }
                        ?? text("正在建立基线", "Establishing baseline")
                )
                MenuValueRow(
                    label: "读取操作",
                    value: io.readOperationsPerSecond.map {
                        format("%.0f 次/秒", "%.0f ops/s", $0)
                    } ?? "—"
                )
                MenuValueRow(
                    label: "写入操作",
                    value: io.writeOperationsPerSecond.map {
                        format("%.0f 次/秒", "%.0f ops/s", $0)
                    } ?? "—"
                )
                CalmDivider()
                MenuValueRow(
                    label: "驱动启动以来读取",
                    value: MetricFormatter.bytes(io.totalReadBytes, locale: locale)
                )
                MenuValueRow(
                    label: "驱动启动以来写入",
                    value: MetricFormatter.bytes(io.totalWrittenBytes, locale: locale)
                )
                if !io.deviceNames.isEmpty {
                    Text(io.deviceNames.joined(separator: "、"))
                        .font(.system(size: 9.5))
                        .foregroundStyle(CalmTheme.secondaryText)
                        .lineLimit(2)
                }
            }
        }
    }

    private func networkTrafficCard(networkProjection: MenuNetworkProjection) -> some View {
        let received = networkProjection.totalReceivedRate
        let sent = networkProjection.totalSentRate
        return MenuMetricCard(title: "实时流量", symbol: "arrow.up.arrow.down", tint: MenuPalette.amber) {
            if !model.hasLoadedSnapshot {
                MenuUnavailableText(message: "正在读取网络流量。")
            } else {
                MenuValueRow(
                    label: "总下载",
                    value: received.map {
                        MetricFormatter.rate(bytesPerSecond: $0, locale: locale)
                    } ?? "—"
                )
                MenuBarHistogram(
                    values: model.history(for: .networkReceived),
                    ceiling: nil,
                    color: MenuPalette.cyan,
                    maximumBarCount: 48
                )
                .frame(height: 20)
                MenuValueRow(
                    label: "总上传",
                    value: sent.map {
                        MetricFormatter.rate(bytesPerSecond: $0, locale: locale)
                    } ?? "—"
                )
                MenuBarHistogram(
                    values: model.history(for: .networkSent),
                    ceiling: nil,
                    color: MenuPalette.amber,
                    maximumBarCount: 48
                )
                .frame(height: 20)
            }
        }
    }

    private func networkInterfacesCard(networkProjection: MenuNetworkProjection) -> some View {
        let services = networkProjection.services
        return MenuMetricCard(title: "网络接口", symbol: "network", tint: MenuPalette.amber) {
            if !model.hasLoadedSnapshot {
                MenuUnavailableText(message: "正在读取网络接口。")
            } else if services.isEmpty {
                MenuUnavailableText(message: "没有可显示的物理网络接口。")
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(services.enumerated()), id: \.offset) { index, interface in
                        MenuNetworkInterfaceDetail(interface: interface, symbol: networkSymbol(for: interface))
                        if index < services.count - 1 {
                            CalmDivider()
                        }
                    }
                }
            }
        }
    }

    private var coolingDetailSummaryCard: some View {
        let cooling = model.snapshot.cooling
        return MenuMetricCard(title: "散热状态", symbol: "fan", tint: MenuPalette.cyan) {
            if !model.hasLoadedSnapshot {
                MenuUnavailableText(message: "正在读取散热状态。")
            } else {
                MenuValueRow(label: "系统热状态", value: localizedThermalCondition(cooling.condition))
                MenuValueRow(
                    label: "检测到风扇",
                    value: format("%lld 个", "%lld", Int64(cooling.fans.count))
                )
                if let firstFan = cooling.fans.first {
                    MenuValueRow(
                        label: format("%@ 当前", "%@ current", firstFan.name),
                        value: "\(firstFan.currentRPM.formatted(.number.locale(locale))) RPM"
                    )
                    MenuBarHistogram(
                        values: nonemptyHistory(.fanSpeed, fallback: Double(firstFan.currentRPM)),
                        ceiling: firstFan.maximumRPM.map(Double.init),
                        color: MenuPalette.cyan,
                        maximumBarCount: 48
                    )
                    .frame(height: 22)
                } else {
                    MenuUnavailableText(
                        message: cooling.sensorAvailability.message.map(serviceMessage)
                            ?? text(
                                "当前机型或系统接口未提供风扇转速。",
                                "This Mac model or system interface does not provide fan speeds."
                            )
                    )
                }
            }
        }
    }

    private var fanDetailsCard: some View {
        MenuMetricCard(title: "风扇详情", symbol: "gauge.with.dots.needle.67percent", tint: MenuPalette.cyan) {
            if !model.hasLoadedSnapshot {
                MenuUnavailableText(message: "正在读取风扇详情。")
            } else if model.snapshot.cooling.fans.isEmpty {
                MenuUnavailableText(
                    message: model.snapshot.cooling.sensorAvailability.message.map(serviceMessage)
                        ?? text("没有可显示的风扇详情。", "No fan details are available.")
                )
                if requiresSensorPermission {
                    SensorAccessActionView(compact: true)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(model.snapshot.cooling.fans.enumerated()), id: \.offset) { index, fan in
                        MenuFanDetail(fan: fan)
                        if index < model.snapshot.cooling.fans.count - 1 {
                            CalmDivider()
                        }
                    }
                }
            }
        }
    }

    private var temperatureDetailSummaryCard: some View {
        MenuMetricCard(title: "温度概览", symbol: "thermometer.medium", tint: MenuPalette.green) {
            if !model.hasLoadedSnapshot {
                MenuUnavailableText(message: "正在读取温度状态。")
            } else {
                MenuValueRow(
                    label: "系统热状态",
                    value: localizedThermalCondition(model.snapshot.cooling.condition)
                )
                MenuProgressRow(
                    label: "CPU 平均",
                    value: model.snapshot.cpu.temperatureCelsius.map {
                        model.temperatureUnit.formatted(celsius: $0, locale: locale)
                    } ?? "—",
                    fraction: (model.snapshot.cpu.temperatureCelsius ?? 0) / 100,
                    tint: MenuPalette.green
                )
                MenuValueRow(
                    label: "GPU",
                    value: model.snapshot.gpus.first?.temperatureCelsius.map {
                        model.temperatureUnit.formatted(celsius: $0, locale: locale)
                    } ?? "—"
                )
                MenuValueRow(
                    label: "电池",
                    value: model.snapshot.battery.temperatureCelsius.map {
                        model.temperatureUnit.formatted(celsius: $0, locale: locale)
                    } ?? "—"
                )
                MenuBarHistogram(
                    values: model.history(for: .temperature),
                    ceiling: 100,
                    color: MenuPalette.green,
                    maximumBarCount: 48
                )
                .frame(height: 22)
                Text(text("趋势仅代表 CPU 平均温度。", "The trend shows average CPU temperature only."))
                    .font(.system(size: 8.5))
                    .foregroundStyle(CalmTheme.tertiaryText)
            }
        }
    }

    private var thermalSensorsCard: some View {
        let sensors = model.snapshot.cooling.sensors.sorted {
            if $0.group != $1.group { return $0.group.localizedStandardCompare($1.group) == .orderedAscending }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return MenuMetricCard(title: "全部传感器", symbol: "thermometer.variable.and.figure", tint: MenuPalette.green) {
            if !model.hasLoadedSnapshot {
                MenuUnavailableText(message: "正在读取温度传感器。")
            } else if sensors.isEmpty {
                MenuUnavailableText(
                    message: model.snapshot.cooling.sensorAvailability.message.map(serviceMessage)
                        ?? text("没有可显示的温度传感器。", "No temperature sensors are available.")
                )
                if requiresSensorPermission {
                    SensorAccessActionView(compact: true)
                }
            } else {
                LazyVStack(spacing: 5) {
                    ForEach(sensors) { sensor in
                        MenuThermalSensorRow(sensor: sensor, unit: model.temperatureUnit)
                    }
                }
            }
        }
    }

    private var batteryDetailSummaryCard: some View {
        let battery = model.snapshot.battery
        return MenuMetricCard(title: "电池概览", symbol: "battery.75percent", tint: CalmTheme.mint) {
            if !model.hasLoadedSnapshot {
                MenuUnavailableText(message: "正在读取电池状态。")
            } else if !battery.availability.isAvailable {
                MenuUnavailableText(message: battery.availability.message.map(serviceMessage)
                    ?? text("当前设备没有可用的内置电池。", "This device has no available built-in battery."))
            } else {
                if let charge = battery.chargePercent {
                    MenuProgressRow(
                        label: battery.isCharging ? "正在充电" : "当前电量",
                        value: MetricFormatter.percent(charge, locale: locale),
                        fraction: charge / 100,
                        tint: CalmTheme.mint
                    )
                }
                MenuValueRow(label: "健康", value: localizedBatteryHealth(battery.health))
                MenuValueRow(
                    label: "循环",
                    value: battery.cycleCount.map {
                        count($0, unit: .cycle)
                    } ?? "—"
                )
                MenuValueRow(label: "剩余时间", value: batteryTimeRemaining(battery.timeRemainingMinutes))
                if let temperature = battery.temperatureCelsius {
                    MenuValueRow(
                        label: "温度",
                        value: model.temperatureUnit.formatted(celsius: temperature, locale: locale)
                    )
                }
            }
        }
    }

    private var batteryCapacityCard: some View {
        let battery = model.snapshot.battery
        return MenuMetricCard(title: "容量与循环", symbol: "heart.circle", tint: CalmTheme.mint) {
            if !battery.availability.isAvailable {
                MenuUnavailableText(message: battery.availability.message.map(serviceMessage)
                    ?? text("容量数据不可用。", "Capacity data unavailable."))
            } else {
                MenuValueRow(
                    label: "健康依据",
                    value: battery.healthBasis == .systemReported
                        ? text("macOS 系统状态", "macOS System Status")
                        : text("原始容量估算", "Raw Capacity Estimate")
                )
                if let current = battery.currentCapacityMAh {
                    MenuValueRow(
                        label: "当前原始容量",
                        value: "\(current.formatted(.number.locale(locale))) mAh"
                    )
                }
                if let maximum = battery.maximumCapacityMAh {
                    MenuValueRow(
                        label: "原始满充容量",
                        value: "\(maximum.formatted(.number.locale(locale))) mAh"
                    )
                }
                if let design = battery.designCapacityMAh {
                    MenuValueRow(
                        label: "原始设计容量",
                        value: "\(design.formatted(.number.locale(locale))) mAh"
                    )
                }
                if let estimate = battery.rawCapacityEstimatePercent {
                    MenuProgressRow(
                        label: "原始容量参考",
                        value: format(
                            "约 %@",
                            "About %@",
                            MetricFormatter.percent(estimate, locale: locale)
                        ),
                        fraction: estimate / 100,
                        tint: CalmTheme.mint
                    )
                }
                MenuValueRow(
                    label: "设计循环",
                    value: battery.designCycleCount.map {
                        count($0, unit: .cycle)
                    } ?? "—"
                )
            }
        }
    }

    private var batteryPowerCard: some View {
        let battery = model.snapshot.battery
        return MenuMetricCard(title: "实时供电", symbol: "bolt.circle", tint: CalmTheme.amber) {
            if !battery.availability.isAvailable {
                MenuUnavailableText(message: battery.availability.message.map(serviceMessage)
                    ?? text("供电数据不可用。", "Power data unavailable."))
            } else {
                MenuValueRow(
                    label: "电压",
                    value: battery.voltageMV.map {
                        String(format: "%.2f V", locale: locale, Double($0) / 1_000)
                    } ?? "—"
                )
                MenuValueRow(
                    label: "电流",
                    value: battery.amperageMA.map {
                        "\($0.formatted(.number.locale(locale))) mA"
                    } ?? "—"
                )
                MenuValueRow(
                    label: "电池功率",
                    value: battery.powerWatts.map {
                        String(format: "%.1f W", locale: locale, abs($0))
                    } ?? "—"
                )
                MenuValueRow(label: "制造商", value: battery.manufacturer ?? "—")
            }
        }
    }

    private var quickLaunchFooter: some View {
        let quickItems = visibleQuickItems
        return HStack(spacing: 10.5) {
            ForEach(quickItems) { item in
                MenuQuickLaunchButton(
                    item: item,
                    icon: iconRepository.applicationIcon(for: item.action)
                ) {
                    perform(item.action)
                }
            }

            MenuQuitApplicationButton {
                quitApplication()
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, 10.5)
        .padding(.top, 17)
        .padding(.bottom, 9)
        .frame(
            width: MenuBarDashboardLayout.primaryColumnWidth,
            height: MenuBarDashboardLayout.footerHeight
        )
        .background(MenuOverviewPalette.background)
        .overlay {
            Rectangle()
                .fill(MenuOverviewPalette.divider)
                .frame(height: 1)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text(
            "系统快捷入口与退出 TraceHalo",
            "System quick actions and quit TraceHalo"
        ))
    }

    private var visibleQuickItems: [MonitorQuickItem] {
        Array(
            MenuBarQuickActionLayout
                .visibleItems(from: model.monitorConfiguration.quickItems)
                .prefix(MenuBarDashboardLayout.maximumQuickActionCount)
        )
    }

    private var rootVolume: StorageVolume? {
        preferredStorageVolume(in: model.snapshot.volumes)
    }

    private func makeNetworkProjection() -> MenuNetworkProjection {
        let interfaces = model.snapshot.networkInterfaces
        let services = interfaces.filter { interface in
            let name = interface.name.lowercased()
            let excludedPrefixes = ["lo", "utun", "awdl", "llw", "bridge", "gif", "stf", "anpi", "ap", "pktap"]
            return !excludedPrefixes.contains(where: name.hasPrefix)
                && (name.hasPrefix("en") || isNamedHardwareService(interface))
        }
        .sorted { lhs, rhs in
            let lhsPriority = networkServicePriority(lhs)
            let rhsPriority = networkServicePriority(rhs)
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            if lhs.isActive != rhs.isActive { return lhs.isActive }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }

        return MenuNetworkProjection(
            services: services,
            totalReceivedRate: sumIfAvailable(interfaces.compactMap(\.receivedBytesPerSecond)),
            totalSentRate: sumIfAvailable(interfaces.compactMap(\.sentBytesPerSecond))
        )
    }

    private func isNamedHardwareService(_ interface: NetworkInterfaceState) -> Bool {
        let label = interface.displayName.lowercased()
        return label.contains("wi-fi")
            || label.contains("wifi")
            || label.contains("wireless")
            || label.contains("ethernet")
            || label.contains("以太网")
    }

    private func networkServicePriority(_ interface: NetworkInterfaceState) -> Int {
        let label = interface.displayName.lowercased()
        if label.contains("ethernet") || label.contains("以太网") { return 0 }
        if label.contains("wi-fi") || label.contains("wifi") || label.contains("wireless") { return 1 }
        if interface.isActive, interface.localAddress != nil { return 2 }
        if interface.isActive { return 3 }
        return 4
    }

    private var maximumColumnHeight: CGFloat {
        if let maximumColumnHeightOverride {
            return min(
                max(maximumColumnHeightOverride, MenuBarDashboardLayout.minimumColumnHeight),
                MenuBarDashboardLayout.maximumColumnHeight
            )
        }
        let available = NSScreen.main?.visibleFrame.height ?? 900
        return min(
            max(available - 84, MenuBarDashboardLayout.minimumColumnHeight),
            MenuBarDashboardLayout.maximumColumnHeight
        )
    }

    private var dashboardContentWidth: CGFloat {
        presentationMode == .embeddedPreview || selection.isExpanded
            ? MenuBarDashboardLayout.expandedDashboardWidth
            : MenuBarDashboardLayout.primaryColumnWidth
    }

    private var requiresSensorPermission: Bool {
        if case .permissionRequired = model.snapshot.cooling.sensorAvailability {
            return true
        }
        return false
    }

    private func nonemptyHistory(_ metric: MonitorMetric, fallback: Double) -> [Double] {
        let values = model.history(for: metric)
        return values.isEmpty ? [fallback] : values
    }

    private func batteryTimeRemaining(_ minutes: Int?) -> String {
        guard let minutes, minutes >= 0 else { return "—" }
        if minutes < 60 {
            return format("%lld 分钟", "%lld min", Int64(minutes))
        }
        return format(
            "%lld 小时 %lld 分钟",
            "%lld hr %lld min",
            Int64(minutes / 60),
            Int64(minutes % 60)
        )
    }

    private func networkSymbol(for interface: NetworkInterfaceState) -> String {
        let label = "\(interface.name) \(interface.displayName)".lowercased()
        return label.contains("wi") || label.contains("wireless") || label.contains("无线")
            ? "wifi"
            : "cable.connector"
    }

    private func quitApplication() {
        if let quitApplicationAction {
            quitApplicationAction()
        } else {
            NSApplication.shared.terminate(nil)
        }
    }

    private func perform(_ action: MonitorQuickAction) {
        if action == .systemScope {
            navigationRouter.navigate(to: .dashboard)
            if let openMainWindowAction {
                openMainWindowAction()
            } else {
                openWindow(id: "main")
            }
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        guard let applicationURL = applicationURL(for: action) else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration)
    }

    private func applicationURL(for action: MonitorQuickAction) -> URL? {
        if let bundleIdentifier = bundleIdentifier(for: action),
           let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return applicationURL
        }

        guard let fallbackPath = fallbackApplicationPath(for: action),
              FileManager.default.fileExists(atPath: fallbackPath) else {
            return nil
        }
        return URL(fileURLWithPath: fallbackPath, isDirectory: true)
    }

    private func fallbackApplicationPath(for action: MonitorQuickAction) -> String? {
        switch action {
        case .systemScope: nil
        case .activityMonitor: "/System/Applications/Utilities/Activity Monitor.app"
        case .console: "/System/Applications/Utilities/Console.app"
        case .terminal: "/System/Applications/Utilities/Terminal.app"
        case .systemInformation: "/System/Applications/Utilities/System Information.app"
        case .systemSettings: "/System/Applications/System Settings.app"
        }
    }

    private func bundleIdentifier(for action: MonitorQuickAction) -> String? {
        switch action {
        case .systemScope: nil
        case .activityMonitor: "com.apple.ActivityMonitor"
        case .console: "com.apple.Console"
        case .terminal: "com.apple.Terminal"
        case .systemInformation: "com.apple.SystemProfiler"
        case .systemSettings: "com.apple.systempreferences"
        }
    }

    private func text(_ key: String, _ english: String) -> String {
        MenuMonitorLocalization.string(key, english: english, locale: locale)
    }

    private func format(
        _ key: String,
        _ english: String,
        _ arguments: CVarArg...
    ) -> String {
        String(
            format: text(key, english),
            locale: locale,
            arguments: arguments
        )
    }

    private func serviceMessage(_ message: String) -> String {
        MenuMonitorLocalization.serviceMessage(message, locale: locale)
    }

    private func count(_ value: Int, unit: MenuMonitorCountUnit) -> String {
        MenuMonitorLocalization.count(value, unit: unit, locale: locale)
    }

    private func localizedBatteryHealth(_ health: BatteryHealth) -> String {
        switch health {
        case .excellent: text("优秀", "Excellent")
        case .good: text("正常", "Normal")
        case .aging: text("逐渐老化", "Aging")
        case .serviceRecommended: text("建议检修", "Service Recommended")
        case .unknown: text("未知", "Unknown")
        }
    }

    private func localizedThermalCondition(_ condition: ThermalCondition) -> String {
        switch condition {
        case .nominal: text("正常", "Normal")
        case .fair: text("温度升高", "Elevated")
        case .serious: text("温度较高", "High")
        case .critical: text("需要关注", "Critical")
        case .unavailable: text("未知", "Unknown")
        }
    }
}

private struct MenuCoreRow: View {
    @Environment(\.locale) private var locale
    let index: Int
    let percent: Double

    var body: some View {
        HStack(spacing: 7) {
            Text(MenuMonitorLocalization.format(
                "核心 #%lld",
                english: "Core #%lld",
                locale: locale,
                Int64(index)
            ))
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
                .frame(width: 70, alignment: .leading)
            MenuProgressBar(fraction: percent / 100, tint: MenuPalette.blue)
            Text(MetricFormatter.percent(percent, locale: locale))
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(CalmTheme.secondaryText)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 35, alignment: .trailing)
        }
        .frame(height: 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(MenuMonitorLocalization.format(
            "核心 %lld，%@",
            english: "Core %lld, %@",
            locale: locale,
            Int64(index),
            MetricFormatter.percent(percent, locale: locale)
        ))
    }
}

private struct MenuProcessRow: View {
    @Environment(\.locale) private var locale
    let process: ProcessUsage
    let icon: NSImage?

    var body: some View {
        HStack(spacing: 7) {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(CalmTheme.secondaryText)
                }
            }
            .frame(width: 14, height: 14)

            Text(process.name)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text(MetricFormatter.percent(
                process.cpuPercent,
                fractionDigits: 1,
                locale: locale
            ))
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(height: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(MenuMonitorLocalization.format(
            "%@，CPU %@",
            english: "%@, CPU %@",
            locale: locale,
            process.name,
            MetricFormatter.percent(
                process.cpuPercent,
                fractionDigits: 1,
                locale: locale
            )
        ))
    }
}

private struct MenuProcessMetricRow: View {
    @Environment(\.locale) private var locale
    let process: ProcessUsage
    let icon: NSImage?
    let value: String
    let metricName: String

    var body: some View {
        HStack(spacing: 7) {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(CalmTheme.secondaryText)
                }
            }
            .frame(width: 14, height: 14)

            Text(process.name)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(height: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(MenuMonitorLocalization.format(
            "%@，%@ %@",
            english: "%@, %@ %@",
            locale: locale,
            process.name,
            MenuMonitorLocalization.catalogString(metricName, locale: locale),
            value
        ))
    }
}

private struct MenuDisplayDetailRow: View {
    @Environment(\.locale) private var locale
    let display: DisplayDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(MenuMonitorLocalization.catalogString(display.name, locale: locale))
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if display.isMain {
                    Text(MenuMonitorLocalization.string(
                        "主显示器",
                        english: "Main Display",
                        locale: locale
                    ))
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(MenuPalette.cyan)
                }
            }
            MenuValueRow(label: "有效分辨率", value: display.resolution)
            MenuValueRow(
                label: "刷新率",
                value: display.refreshRateHz.map {
                    "\($0.formatted(.number.precision(.fractionLength(0)).locale(locale))) Hz"
                } ?? "—"
            )
            MenuValueRow(
                label: "连接类型",
                value: MenuMonitorLocalization.string(
                    display.isBuiltIn ? "内置" : "外接",
                    english: display.isBuiltIn ? "Built-in" : "External",
                    locale: locale
                )
            )
            if let vendorID = display.vendorID {
                MenuValueRow(label: "厂商 ID", value: String(format: "0x%04X", vendorID))
            }
            if let productID = display.productID {
                MenuValueRow(label: "产品 ID", value: String(format: "0x%04X", productID))
            }
            if let pixelDimensions = display.pixelDimensions {
                MenuValueRow(label: "物理像素", value: pixelDimensions)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct MenuStorageVolumeDetail: View {
    @Environment(\.locale) private var locale
    let volume: StorageVolume

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(volume.name)
                .font(.system(size: 10.5, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(volume.path)
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundStyle(CalmTheme.tertiaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            MenuProgressBar(fraction: volume.usedFraction, tint: MenuPalette.cyan)
            MenuValueRow(
                label: "容量",
                value: "\(MetricFormatter.bytes(volume.usedBytes, locale: locale)) / \(MetricFormatter.bytes(volume.totalBytes, locale: locale))"
            )
            MenuValueRow(
                label: "可用",
                value: MetricFormatter.bytes(volume.availableBytes, locale: locale)
            )
            MenuValueRow(label: "文件系统", value: volume.fileSystem ?? "—")
            MenuValueRow(label: "属性", value: attributes)
        }
        .accessibilityElement(children: .contain)
    }

    private var attributes: String {
        var values: [String] = []
        if volume.isInternal == true {
            values.append(MenuMonitorLocalization.string("内置", english: "Built-in", locale: locale))
        }
        if volume.isRemovable == true {
            values.append(MenuMonitorLocalization.string("可移除", english: "Removable", locale: locale))
        }
        if volume.isEncrypted == true {
            values.append(MenuMonitorLocalization.string("已加密", english: "Encrypted", locale: locale))
        }
        if volume.isReadOnly == true {
            values.append(MenuMonitorLocalization.string("只读", english: "Read-only", locale: locale))
        }
        return values.isEmpty ? "—" : values.joined(separator: " · ")
    }
}

private struct MenuNetworkInterfaceDetail: View {
    @Environment(\.locale) private var locale
    let interface: NetworkInterfaceState
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(interface.isActive ? MenuPalette.amber : CalmTheme.secondaryText)
                    .frame(width: 16)
                Text(MenuMonitorLocalization.catalogString(interface.displayName, locale: locale))
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(MenuMonitorLocalization.string(
                    interface.isActive ? "已连接" : "未连接",
                    english: interface.isActive ? "Connected" : "Disconnected",
                    locale: locale
                ))
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(interface.isActive ? CalmTheme.mint : CalmTheme.secondaryText)
            }
            MenuValueRow(label: "接口", value: interface.name)
            MenuValueRow(label: "本地地址", value: interface.localAddress ?? "—")
            MenuValueRow(
                label: "链路速率",
                value: interface.linkSpeedMbps.map {
                    "\($0.formatted(.number.precision(.fractionLength(0)).locale(locale))) Mbps"
                } ?? "—"
            )
            MenuValueRow(
                label: "下载",
                value: interface.receivedBytesPerSecond.map {
                    MetricFormatter.rate(bytesPerSecond: $0, locale: locale)
                } ?? "—"
            )
            MenuValueRow(
                label: "上传",
                value: interface.sentBytesPerSecond.map {
                    MetricFormatter.rate(bytesPerSecond: $0, locale: locale)
                } ?? "—"
            )
            if interface.rssi != nil || interface.noise != nil {
                MenuValueRow(
                    label: "无线信号",
                    value: "\(interface.rssi.map(String.init) ?? "—") / \(interface.noise.map(String.init) ?? "—") dBm"
                )
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct MenuFanDetail: View {
    @Environment(\.locale) private var locale
    let fan: FanState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(fan.name)
                    .font(.system(size: 10.5, weight: .semibold))
                Spacer(minLength: 4)
                Text("\(fan.currentRPM.formatted(.number.locale(locale))) RPM")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            if let maximum = fan.maximumRPM, maximum > 0 {
                MenuProgressBar(
                    fraction: Double(fan.currentRPM) / Double(maximum),
                    tint: MenuPalette.cyan
                )
            }
            MenuValueRow(
                label: "最低",
                value: fan.minimumRPM.map {
                    "\($0.formatted(.number.locale(locale))) RPM"
                } ?? "—"
            )
            MenuValueRow(
                label: "目标",
                value: fan.targetRPM.map {
                    "\($0.formatted(.number.locale(locale))) RPM"
                } ?? "—"
            )
            MenuValueRow(
                label: "最高",
                value: fan.maximumRPM.map {
                    "\($0.formatted(.number.locale(locale))) RPM"
                } ?? "—"
            )
        }
        .accessibilityElement(children: .contain)
    }
}

private struct MenuThermalSensorRow: View {
    @Environment(\.locale) private var locale
    let sensor: ThermalSensor
    let unit: TemperatureUnit

    var body: some View {
        HStack(spacing: 7) {
            VStack(alignment: .leading, spacing: 1) {
                Text(sensor.name)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                Text(MenuMonitorLocalization.catalogString(sensor.group, locale: locale))
                    .font(.system(size: 8.5))
                    .foregroundStyle(CalmTheme.tertiaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 5)
            Text(unit.formatted(celsius: sensor.temperatureCelsius, locale: locale))
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(MenuPalette.green)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(MenuMonitorLocalization.format(
            "%@，%@，%@",
            english: "%@, %@, %@",
            locale: locale,
            MenuMonitorLocalization.catalogString(sensor.group, locale: locale),
            sensor.name,
            unit.formatted(celsius: sensor.temperatureCelsius, locale: locale)
        ))
    }
}

private struct MenuOverviewTopMetric: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 18, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(MenuOverviewPalette.secondaryText)
                Text(value)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(MenuOverviewPalette.primaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .layoutPriority(3)
                    .contentTransition(.numericText())
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: value)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
    }
}

private struct MenuOverviewTopMetricDivider: View {
    var body: some View {
        Rectangle()
            .fill(MenuOverviewPalette.divider)
            .frame(width: 0.75, height: 46)
            .accessibilityHidden(true)
    }
}

private struct MenuOverviewSectionHeader: View {
    let title: String
    var height: CGFloat = MenuBarDashboardLayout.sectionHeaderHeight

    var body: some View {
        Text(title)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(MenuOverviewPalette.tertiaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.leading, 9)
            .background(MenuOverviewPalette.background)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(MenuOverviewPalette.divider)
                    .frame(height: 1)
            }
            .frame(
                width: MenuBarDashboardLayout.primaryColumnWidth,
                height: height
            )
            .accessibilityAddTraits(.isHeader)
    }
}

private struct MenuOverviewSelectableRow<Content: View>: View {
    @Environment(\.locale) private var locale
    let height: CGFloat
    let tint: Color
    let isHighlighted: Bool
    let isExpanded: Bool
    let accessibilityLabel: String
    let action: () -> Void
    @ViewBuilder let content: Content

    init(
        height: CGFloat,
        tint: Color,
        isHighlighted: Bool,
        isExpanded: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.height = height
        self.tint = tint
        self.isHighlighted = isHighlighted
        self.isExpanded = isExpanded
        self.accessibilityLabel = accessibilityLabel
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .leading) {
                (isHighlighted ? MenuOverviewPalette.selectedRow : MenuOverviewPalette.row)
                content
                if isHighlighted {
                    Rectangle()
                        .fill(tint)
                        .frame(width: 3, height: max(height - 2, 0))
                        .offset(x: -0.75)
                }
            }
            .frame(
                width: MenuBarDashboardLayout.primaryColumnWidth,
                height: height
            )
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(MenuOverviewPalette.divider)
                    .frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuOverviewRowButtonStyle())
        .help(MenuMonitorLocalization.string(
            isExpanded ? "收起详情" : "查看详情",
            english: isExpanded ? "Collapse details" : "View details",
            locale: locale
        ))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(MenuMonitorLocalization.string(
            isExpanded ? "已展开" : "已折叠",
            english: isExpanded ? "Expanded" : "Collapsed",
            locale: locale
        ))
        .accessibilityHint(MenuMonitorLocalization.string(
            isExpanded ? "按下以收起右侧详情" : "按下以在右侧显示详情",
            english: isExpanded ? "Press to collapse the details on the right" : "Press to show details on the right",
            locale: locale
        ))
    }
}

private struct MenuOverviewIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
    }
}

private struct MenuOverviewPrimaryMetric: View {
    let title: String
    let value: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(MenuOverviewPalette.secondaryText)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(MenuOverviewPalette.primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .layoutPriority(3)
                .contentTransition(.numericText())
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: value)
    }
}

private struct MenuOverviewPairedValue: View {
    let label: String
    let value: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .foregroundStyle(MenuOverviewPalette.secondaryText)
            Spacer(minLength: 1)
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(MenuOverviewPalette.primaryText)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(.system(size: 9.5, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.78)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: value)
    }
}

private struct MenuOverviewRate: View {
    let symbol: String
    let value: String
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 7.8, weight: .bold))
            Text(value)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(.system(size: 8.2, weight: .medium, design: .rounded))
        .foregroundStyle(tint)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: value)
    }
}

private struct MenuOverviewChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(MenuOverviewPalette.secondaryText)
            .frame(width: 20, height: 24)
            .accessibilityHidden(true)
    }
}

private struct MenuOverviewAreaChart: View {
    let values: [Double]
    let ceiling: Double?
    let color: Color
    let maximumPointCount: Int

    var body: some View {
        Canvas { context, size in
            let limit = max(maximumPointCount, 2)
            let recent = Array(values.suffix(limit))
            guard !recent.isEmpty else {
                context.fill(
                    Path(CGRect(x: 0, y: size.height / 2, width: size.width, height: 1)),
                    with: .color(color.opacity(0.5))
                )
                return
            }

            let samples = Array(repeating: recent[0], count: max(limit - recent.count, 0)) + recent
            let upperBound = max(ceiling ?? samples.max() ?? 1, 0.001)
            let points = samples.enumerated().map { index, value in
                CGPoint(
                    x: CGFloat(index) / CGFloat(samples.count - 1) * size.width,
                    y: size.height - size.height * min(max(value / upperBound, 0.04), 1)
                )
            }

            var area = Path()
            area.move(to: CGPoint(x: 0, y: size.height))
            area.addLine(to: points[0])
            for point in points.dropFirst() { area.addLine(to: point) }
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .linearGradient(
                Gradient(colors: [color.opacity(0.34), color.opacity(0.03)]),
                startPoint: CGPoint(x: size.width / 2, y: 0),
                endPoint: CGPoint(x: size.width / 2, y: size.height)
            ))

            var line = Path()
            line.move(to: points[0])
            for point in points.dropFirst() { line.addLine(to: point) }
            context.stroke(line, with: .color(color.opacity(0.96)), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct MenuOverviewRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct MenuQuickLaunchButton: View {
    @Environment(\.locale) private var locale
    let item: MonitorQuickItem
    let icon: NSImage?
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: 22, height: 22)
            .frame(width: 34, height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuQuickLaunchButtonStyle(isHovering: isHovering))
        .onHover { isHovering = $0 }
        .help(localizedTitle)
        .accessibilityLabel(localizedTitle)
    }

    private var localizedTitle: String {
        if item.action == .systemScope {
            return MenuMonitorLocalization.string(
                "打开 TraceHalo",
                english: "Open TraceHalo",
                locale: locale
            )
        }
        return MenuMonitorLocalization.quickItemTitle(
            item.action,
            fallback: item.title,
            locale: locale
        )
    }
}

private struct MenuQuitApplicationButton: View {
    @Environment(\.locale) private var locale
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "power")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MenuOverviewPalette.rose)
                .frame(width: 22, height: 22)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(MenuQuickLaunchButtonStyle(isHovering: isHovering))
        .onHover { isHovering = $0 }
        .help(MenuMonitorLocalization.string(
            "彻底退出 TraceHalo",
            english: "Quit TraceHalo Completely",
            locale: locale
        ))
        .accessibilityLabel(MenuMonitorLocalization.string(
            "彻底退出 TraceHalo",
            english: "Quit TraceHalo Completely",
            locale: locale
        ))
        .accessibilityHint(MenuMonitorLocalization.string(
            "关闭 TraceHalo 并停止菜单栏实时监控",
            english: "Close TraceHalo and stop real-time menu bar monitoring",
            locale: locale
        ))
    }
}

private struct MenuMetricCard<Content: View>: View {
    @Environment(\.locale) private var locale
    let title: String
    let symbol: String
    let tint: Color
    let trailing: String?
    let isSelected: Bool
    let selectionAction: (() -> Void)?
    let accessibilitySummary: String?
    @ViewBuilder let content: Content

    init(
        title: String,
        symbol: String,
        tint: Color,
        trailing: String? = nil,
        isSelected: Bool = false,
        selectionAction: (() -> Void)? = nil,
        accessibilitySummary: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.trailing = trailing
        self.isSelected = isSelected
        self.selectionAction = selectionAction
        self.accessibilitySummary = accessibilitySummary
        self.content = content()
    }

    var body: some View {
        Group {
            if let selectionAction {
                Button(action: selectionAction) {
                    cardBody(showsDisclosure: true)
                }
                .buttonStyle(MenuMetricCardButtonStyle())
                .help(MenuMonitorLocalization.format(
                    isSelected ? "收起%@详情" : "查看%@详情",
                    english: isSelected ? "Collapse %@ details" : "View %@ details",
                    locale: locale,
                    MenuMonitorLocalization.catalogString(title, locale: locale)
                ))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    accessibilitySummary.map {
                        MenuMonitorLocalization.format(
                            "%@，%@",
                            english: "%@, %@",
                            locale: locale,
                            MenuMonitorLocalization.catalogString(title, locale: locale),
                            $0
                        )
                    } ?? MenuMonitorLocalization.catalogString(title, locale: locale)
                )
                .accessibilityValue(MenuMonitorLocalization.string(
                    isSelected ? "已展开" : "已折叠",
                    english: isSelected ? "Expanded" : "Collapsed",
                    locale: locale
                ))
                .accessibilityHint(MenuMonitorLocalization.string(
                    isSelected ? "按下以收起右侧详情" : "按下以在右侧显示详情",
                    english: isSelected ? "Press to collapse the details on the right" : "Press to show details on the right",
                    locale: locale
                ))
            } else {
                cardBody(showsDisclosure: false)
            }
        }
    }

    private func cardBody(showsDisclosure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            headerLabel(showsDisclosure: showsDisclosure)
            content
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected ? tint.opacity(0.075) : CalmTheme.surface,
            in: RoundedRectangle(cornerRadius: CalmTheme.cardRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CalmTheme.cardRadius, style: .continuous)
                .stroke(isSelected ? tint.opacity(0.9) : CalmTheme.hairline, lineWidth: isSelected ? 1.2 : 0.75)
        }
        .contentShape(RoundedRectangle(cornerRadius: CalmTheme.cardRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func headerLabel(showsDisclosure: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 17)
            Text(MenuMonitorLocalization.catalogString(title, locale: locale))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(isSelected ? Color.primary : CalmTheme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 5)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if showsDisclosure {
                Image(systemName: isSelected ? "rectangle.righthalf.inset.filled" : "chevron.right")
                    .font(.system(size: isSelected ? 10.5 : 9.5, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : CalmTheme.secondaryText)
                    .frame(width: 23, height: 23)
                    .background(
                        isSelected ? tint.opacity(0.92) : CalmTheme.controlBackground,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(isSelected ? tint : CalmTheme.hairline, lineWidth: 0.75)
                    }
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 23, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct MenuProgressRow: View {
    @Environment(\.locale) private var locale
    let label: String
    let value: String
    let fraction: Double
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 7) {
            Text(MenuMonitorLocalization.catalogString(label, locale: locale))
                .font(.system(size: 10.5))
                .foregroundStyle(CalmTheme.secondaryText)
                .lineLimit(1)
                .frame(width: 52, alignment: .leading)
            MenuProgressBar(fraction: fraction, tint: tint)
            Text(value)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .frame(minWidth: 37, alignment: .trailing)
                .contentTransition(.numericText())
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: value)
    }
}

private struct MenuProgressBar: View {
    let fraction: Double
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(MenuOverviewPalette.primaryText.opacity(0.10))
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 4)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: fraction)
        .accessibilityHidden(true)
    }
}

private struct MenuValueRow: View {
    @Environment(\.locale) private var locale
    let label: String
    let value: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(MenuMonitorLocalization.catalogString(label, locale: locale))
                .foregroundStyle(CalmTheme.secondaryText)
            Spacer(minLength: 5)
            Text(value)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .contentTransition(.numericText())
        }
        .font(.system(size: 10.5))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: value)
    }
}

private struct MenuUnavailableText: View {
    @Environment(\.locale) private var locale
    let message: String

    var body: some View {
        Text(MenuMonitorLocalization.catalogString(message, locale: locale))
            .font(.system(size: 9.5))
            .foregroundStyle(CalmTheme.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct MenuBarHistogram: View {
    let values: [Double]
    let ceiling: Double?
    let color: Color
    let maximumBarCount: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let limit = max(maximumBarCount, 1)
            let recent = Array(values.suffix(limit))
            if recent.isEmpty {
                Rectangle()
                    .fill(Color.secondary.opacity(0.45))
                    .frame(height: 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                let samples = Array(repeating: recent[0], count: max(limit - recent.count, 0)) + recent
                let upperBound = max(ceiling ?? samples.max() ?? 1, 0.001)

                HStack(alignment: .bottom, spacing: samples.count > 1 ? 1 : 0) {
                    ForEach(samples.indices, id: \.self) { index in
                        let normalized = min(max(samples[index] / upperBound, 0.04), 1)
                        Capsule()
                            .fill(color)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: 1,
                                maxHeight: max(proxy.size.height * normalized, 1)
                            )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.28),
                    value: samples
                )
            }
        }
        .accessibilityHidden(true)
    }
}

private struct MenuMetricCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.992 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct MenuQuickLaunchButtonStyle: ButtonStyle {
    let isHovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        configuration.isPressed
                            ? MenuOverviewPalette.selectedRow
                            : (isHovering ? CalmTheme.sidebarHover : MenuOverviewPalette.row)
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(
                        isHovering ? CalmTheme.accent.opacity(0.7) : CalmTheme.strongHairline,
                        lineWidth: isHovering ? 1 : 0.75
                    )
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
