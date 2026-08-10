import Foundation
import Observation
import SwiftUI
import TraceHaloCore

enum AppDestination: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case monitor
    case optimizer
    case uninstaller
    case storage
    case graphics
    case inputDevices
    case cooling
    case battery
    case report
    case settings

    var id: String { rawValue }

    var title: String {
        AppLocalization.currentString(rawTitle)
    }

    private var rawTitle: String {
        switch self {
        case .dashboard: "概览"
        case .monitor: "监视器"
        case .optimizer: "启动优化"
        case .uninstaller: "应用管理"
        case .storage: "存储"
        case .graphics: "图形"
        case .inputDevices: "键盘鼠标"
        case .cooling: "散热"
        case .battery: "电池"
        case .report: "系统报告"
        case .settings: "设置"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .monitor: "waveform.path.ecg"
        case .optimizer: "power"
        case .uninstaller: "app.badge.checkmark"
        case .storage: "internaldrive"
        case .graphics: "display"
        case .inputDevices: "keyboard"
        case .cooling: "fan"
        case .battery: "battery.75percent"
        case .report: "doc.text.magnifyingglass"
        case .settings: "gearshape"
        }
    }
}

enum AppDataSource: String, CaseIterable, Identifiable {
    case fixture
    case live

    var id: String { rawValue }
    var title: String {
        AppLocalization.currentString(self == .fixture ? "演示数据" : "本机数据")
    }
}

enum OverallSystemState {
    case normal
    case attention
    case critical
    case limited
    case monitoring

    var title: String {
        AppLocalization.currentString(rawTitle)
    }

    private var rawTitle: String {
        switch self {
        case .normal: "状态正常"
        case .attention: "需要关注"
        case .critical: "需要处理"
        case .limited: "部分数据受限"
        case .monitoring: "监测中"
        }
    }

    var symbol: String {
        switch self {
        case .normal: "checkmark.circle.fill"
        case .attention: "exclamationmark.circle.fill"
        case .critical: "exclamationmark.triangle.fill"
        case .limited: "questionmark.circle.fill"
        case .monitoring: "waveform.path.ecg"
        }
    }

    var color: Color {
        switch self {
        case .normal: CalmTheme.mint
        case .attention: CalmTheme.amber
        case .critical: CalmTheme.rose
        case .limited, .monitoring: CalmTheme.cyan
        }
    }
}

struct DashboardTelemetrySample: Identifiable, Equatable, Codable, Sendable {
    let date: Date
    let cpuPercent: Double
    let gpuPercent: Double?
    let memoryPressurePercent: Double
    let storageUsedPercent: Double?
    let networkReceivedBytesPerSecond: Double
    let networkSentBytesPerSecond: Double
    let temperatureCelsius: Double?

    var id: Date { date }
    var networkBytesPerSecond: Double {
        networkReceivedBytesPerSecond + networkSentBytesPerSecond
    }
}

private struct DashboardEventText {
    let key: String
    let defaultValue: String
    let arguments: [String]
    let localizedArgumentIndices: Set<Int>

    static func literal(_ value: String) -> DashboardEventText {
        DashboardEventText(
            key: value,
            defaultValue: value,
            arguments: [],
            localizedArgumentIndices: []
        )
    }

    static func formatted(
        _ key: String,
        defaultValue: String,
        arguments: [String],
        localizedArgumentIndices: Set<Int> = []
    ) -> DashboardEventText {
        DashboardEventText(
            key: key,
            defaultValue: defaultValue,
            arguments: arguments,
            localizedArgumentIndices: localizedArgumentIndices
        )
    }

    func localized(locale: Locale) -> String {
        if arguments.isEmpty {
            return AppLocalization.string(
                key,
                defaultValue: defaultValue,
                locale: locale
            )
        }
        return AppLocalization.format(
            key,
            defaultValue: defaultValue,
            locale: locale,
            arguments: arguments.enumerated().map { index, value in
                guard localizedArgumentIndices.contains(index) else { return value }
                return AppLocalization.string(
                    value,
                    defaultValue: value,
                    locale: locale
                )
            }
        )
    }
}

struct DashboardEventRecord: Identifiable {
    let id = UUID()
    private let titleText: DashboardEventText
    private let detailText: DashboardEventText
    let occurredAt: Date
    let color: Color

    init(title: String, detail: String, occurredAt: Date, color: Color) {
        titleText = .literal(title)
        detailText = .literal(detail)
        self.occurredAt = occurredAt
        self.color = color
    }

    init(
        titleKey: String,
        titleDefaultValue: String,
        titleArguments: [String],
        titleLocalizedArgumentIndices: Set<Int> = [],
        detailKey: String,
        detailDefaultValue: String,
        detailArguments: [String] = [],
        detailLocalizedArgumentIndices: Set<Int> = [],
        occurredAt: Date,
        color: Color
    ) {
        titleText = .formatted(
            titleKey,
            defaultValue: titleDefaultValue,
            arguments: titleArguments,
            localizedArgumentIndices: titleLocalizedArgumentIndices
        )
        detailText = .formatted(
            detailKey,
            defaultValue: detailDefaultValue,
            arguments: detailArguments,
            localizedArgumentIndices: detailLocalizedArgumentIndices
        )
        self.occurredAt = occurredAt
        self.color = color
    }

    var title: String { localizedTitle(locale: AppLocalization.currentLocale) }
    var detail: String { localizedDetail(locale: AppLocalization.currentLocale) }

    func localizedTitle(locale: Locale) -> String {
        titleText.localized(locale: locale)
    }

    func localizedDetail(locale: Locale) -> String {
        detailText.localized(locale: locale)
    }
}

struct StartupPreloadSchedule: Equatable, Sendable {
    let initialDelay: Duration
    let delayBetweenBatches: Duration

    static let standard = StartupPreloadSchedule(
        initialDelay: .zero,
        delayBetweenBatches: .zero
    )
    static let immediate = StartupPreloadSchedule(
        initialDelay: .zero,
        delayBetweenBatches: .zero
    )
}

enum StartupPreloadStage: String, CaseIterable, Hashable, Sendable {
    case telemetry
    case startupItems
    case applications
    case storageHealth
}

enum StartupPreloadPhase: Equatable, Sendable {
    case idle
    case loading
    case ready
}

struct StartupPreloadStatus: Equatable, Sendable {
    var phase: StartupPreloadPhase = .idle
    var activeStage: StartupPreloadStage?
    var completedStages: Set<StartupPreloadStage> = []
    var degradedStages: Set<StartupPreloadStage> = []

    var completedStageCount: Int { completedStages.count }
    var totalStageCount: Int { StartupPreloadStage.allCases.count }
    var progress: Double {
        guard totalStageCount > 0 else { return 1 }
        return Double(completedStageCount) / Double(totalStageCount)
    }
    var isLoading: Bool { phase == .loading }

    mutating func beginIfNeeded() {
        guard phase == .idle else { return }
        phase = .loading
        activeStage = .telemetry
    }

    mutating func begin(_ stage: StartupPreloadStage) {
        guard phase == .loading else { return }
        activeStage = stage
    }

    mutating func complete(_ stage: StartupPreloadStage, degraded: Bool) {
        guard phase == .loading else { return }
        completedStages.insert(stage)
        if degraded {
            degradedStages.insert(stage)
        } else {
            degradedStages.remove(stage)
        }
        activeStage = nil
    }

    mutating func finish() {
        guard phase == .loading else { return }
        phase = .ready
        activeStage = nil
    }

    mutating func reconcile(_ stage: StartupPreloadStage, degraded: Bool) {
        guard phase == .ready else { return }
        if degraded {
            degradedStages.insert(stage)
        } else {
            degradedStages.remove(stage)
        }
    }
}

enum MonitoringRefreshPolicy {
    static func effectiveInterval(
        baseInterval: Double,
        reducesFrequencyOnBattery: Bool,
        battery: BatteryState
    ) -> Double {
        guard reducesFrequencyOnBattery,
              battery.availability.isAvailable,
              isUsingBatteryPower(battery)
        else {
            return baseInterval
        }
        return max(baseInterval, 10)
    }

    static func isUsingBatteryPower(_ battery: BatteryState) -> Bool {
        guard battery.availability.isAvailable else { return false }
        if let isOnExternalPower = battery.isOnExternalPower {
            return !isOnExternalPower
        }
        // Older cached snapshots did not record the source state. Retain the
        // previous best-effort behavior only as a compatibility fallback.
        return !battery.isCharging
    }
}

enum DashboardHistoryPolicy {
    static let minimumSampleInterval: TimeInterval = 5
    static let displayWindowDuration: TimeInterval = 60 * 60
    static let capacity = 720

    static func appending(
        _ sample: DashboardTelemetrySample,
        to history: [DashboardTelemetrySample]
    ) -> [DashboardTelemetrySample]? {
        if let previousDate = history.last?.date,
           sample.date.timeIntervalSince(previousDate) < minimumSampleInterval {
            return nil
        }

        var next = history
        next.append(sample)
        if next.count > capacity {
            next = Array(next.suffix(capacity))
        }
        return next
    }

    static func restoring(
        _ samples: [DashboardTelemetrySample],
        now: Date
    ) -> [DashboardTelemetrySample] {
        let cutoff = now.addingTimeInterval(-displayWindowDuration)
        var sampleByDate: [Date: DashboardTelemetrySample] = [:]
        for sample in samples where sample.date >= cutoff && sample.date <= now {
            sampleByDate[sample.date] = sample
        }
        let sorted = sampleByDate.values.sorted { $0.date < $1.date }
        return Array(sorted.suffix(capacity))
    }
}

enum StorageHealthRefreshPolicy {
    static let defaultStaleInterval: TimeInterval = 5 * 60

    static func isStale(
        lastLoadedAt: Date?,
        now: Date,
        staleInterval: TimeInterval = defaultStaleInterval
    ) -> Bool {
        guard let lastLoadedAt else { return true }
        return now.timeIntervalSince(lastLoadedAt) >= max(staleInterval, 0)
    }
}

enum AppCountLocalization {
    static func key(
        count: Int,
        one: String,
        other: String
    ) -> String {
        count == 1 ? one : other
    }

    static func format(
        count: Int,
        oneKey: String,
        otherKey: String,
        oneDefaultValue: String,
        otherDefaultValue: String,
        locale: Locale,
        _ arguments: CVarArg...
    ) -> String {
        let usesSingular = count == 1
        let localizedFormat = AppLocalization.string(
            usesSingular ? oneKey : otherKey,
            defaultValue: usesSingular ? oneDefaultValue : otherDefaultValue,
            locale: locale
        )
        return String(
            format: localizedFormat,
            locale: locale,
            arguments: arguments
        )
    }
}

enum AppOperationError: LocalizedError {
    case partialStartupUpdate(succeeded: Int, failures: [String])

    var errorDescription: String? {
        switch self {
        case let .partialStartupUpdate(succeeded, failures):
            let prefix = succeeded > 0
                ? AppCountLocalization.format(
                    count: succeeded,
                    oneKey: "dashboard.event.applied.prefix.one",
                    otherKey: "dashboard.event.applied.prefix.other",
                    oneDefaultValue: "已应用 %ld 项；",
                    otherDefaultValue: "已应用 %ld 项；",
                    locale: AppLocalization.currentLocale,
                    succeeded
                )
                : ""
            return prefix + failures.joined(separator: "\n")
        }
    }
}

@MainActor
@Observable
final class AppModel {
    private struct TelemetryFrame {
        var snapshot: SystemSnapshot
        var history: [MonitorMetric: [Double]]
    }

    private struct DashboardObservation: Equatable {
        let memoryPressure: Double
        let activeInterfaces: [String: String]
        let fanCount: Int
        let thermalCondition: String
    }

    private struct StartupInventory: Sendable {
        let items: [StartupItem]
        let baselineStates: [String: Bool]
        let editableIDs: Set<String>
    }

    private var telemetry: TelemetryFrame
    private(set) var dashboardHistory: [DashboardTelemetrySample]
    private(set) var dashboardEvents: [DashboardEventRecord]
    private(set) var storageIOHistory: [StorageIOHistorySample] = []
    var snapshot: SystemSnapshot { telemetry.snapshot }
    var monitorConfiguration: MonitorConfiguration
    var startupItems: [StartupItem] = []
    var applications: [ApplicationCandidate] = []
    var storageHealth: [String: StorageHealth] = [:]
    var selectedApplicationID: String?
    var isRefreshing = false
    var lastError: String?
    var dataSource: AppDataSource = .fixture
    var refreshInterval: Double = 2
    var temperatureUnit: TemperatureUnit = .celsius
    var showMenuBarSummary = true
    var pauseWhenOnBattery = true
    var includeProcessNamesInReport = false
    var includeVolumeNamesInReport = false
    private(set) var dashboardHistoryRetention = DashboardHistoryRetention.defaultValue
    var dashboardHistoryRetentionDays: Int { dashboardHistoryRetention.rawValue }
    private(set) var isLoadingStartupItems = false
    private(set) var isLoadingApplications = false
    private(set) var isLoadingStorageHealth = false
    private var loadingApplicationDetailIDs = Set<String>()
    private(set) var startupItemsError: String?
    private(set) var applicationsError: String?
    private(set) var startupItemsLastLoadedAt: Date?
    private(set) var applicationsLastLoadedAt: Date?
    private(set) var applicationDetailsLastLoadedAt: [String: Date] = [:]
    private(set) var storageHealthLastLoadedAt: Date?
    private(set) var hasLoadedSnapshot = true
    private(set) var hasLoadedStartupItems = false
    private(set) var hasLoadedApplications = false
    private(set) var hasLoadedStorageHealth = false
    private(set) var hasAttemptedStartupItems = false
    private(set) var hasAttemptedApplications = false
    private(set) var hasAttemptedStorageHealth = false
    private(set) var startupPreloadStatus = StartupPreloadStatus()
    private(set) var hasLoadedPersistedDashboardHistory = false
    private(set) var stagedStartupChangeCount = 0

    private let metricsProvider: any SystemMetricsProviding
    private let startupProvider: any StartupItemProviding
    private let applicationProvider: any ApplicationProviding
    private let healthProvider: any StorageHealthProviding
    private let startupMutator: any StartupItemMutating
    private let uninstallExecutor: any UninstallExecuting
    private let supplementalSensorProvider: any SupplementalSensorProviding
    private let dashboardHistoryStore: any DashboardHistoryPersisting
    private let dashboardHistoryNow: () -> Date
    private let startupPreloadSchedule: StartupPreloadSchedule
    private let storageHealthStaleInterval: TimeInterval
    private let storageHealthNow: () -> Date
    private let editableLaunchAgentsDirectory: String
    private var baselineStartupItems: [StartupItem] = []
    private var baselineStartupStates: [String: Bool] = [:]
    private var editableStartupItemIDs = Set<String>()
    private var enrichedApplicationIDs = Set<String>()
    private var refreshLoopTask: Task<Void, Never>?
    @ObservationIgnored private var storageHealthSyncTask: Task<Void, Never>?
    @ObservationIgnored private var dashboardHistoryWriteTask: Task<Void, Never>?
    @ObservationIgnored private var dashboardHistoryRetentionTask: Task<Void, Never>?
    @ObservationIgnored private var isSnapshotRefreshInFlight = false
    private var pendingDashboardHistorySample: DashboardTelemetrySample?
    private var lastPersistedDashboardHistoryDate: Date?
    private var dashboardHistoryRetentionGeneration = 0
    private var isLoadingPersistedDashboardHistory = false
    private var dashboardObservation: DashboardObservation?

    var isLoadingApplicationDetails: Bool {
        selectedApplicationID.map(loadingApplicationDetailIDs.contains) ?? false
    }

    init(
        metricsProvider: any SystemMetricsProviding = FixtureSystemMetricsProvider(),
        startupProvider: any StartupItemProviding = FixtureStartupItemProvider(),
        applicationProvider: any ApplicationProviding = FixtureApplicationProvider(),
        healthProvider: any StorageHealthProviding = FixtureStorageHealthProvider(),
        startupMutator: any StartupItemMutating = DenyAllStartupItemMutator(),
        uninstallExecutor: any UninstallExecuting = DenyAllUninstallExecutor(),
        supplementalSensorProvider: any SupplementalSensorProviding = NoSupplementalSensorProvider(),
        dashboardHistoryStore: any DashboardHistoryPersisting = DisabledDashboardHistoryStore(),
        dashboardHistoryNow: @escaping () -> Date = Date.init,
        startupPreloadSchedule: StartupPreloadSchedule = .standard,
        storageHealthStaleInterval: TimeInterval = StorageHealthRefreshPolicy.defaultStaleInterval,
        storageHealthNow: @escaping () -> Date = Date.init
    ) {
        self.metricsProvider = metricsProvider
        self.startupProvider = startupProvider
        self.applicationProvider = applicationProvider
        self.healthProvider = healthProvider
        self.startupMutator = startupMutator
        self.uninstallExecutor = uninstallExecutor
        self.supplementalSensorProvider = supplementalSensorProvider
        self.dashboardHistoryStore = dashboardHistoryStore
        self.dashboardHistoryNow = dashboardHistoryNow
        self.startupPreloadSchedule = startupPreloadSchedule
        self.storageHealthStaleInterval = storageHealthStaleInterval
        self.storageHealthNow = storageHealthNow
        editableLaunchAgentsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .standardizedFileURL.path
        telemetry = TelemetryFrame(snapshot: .fixture, history: Self.seedHistory)
        dashboardHistory = Self.seedDashboardHistory(
            snapshot: .fixture,
            history: Self.seedHistory
        )
        dashboardEvents = Self.seedDashboardEvents(snapshot: .fixture)
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "monitorConfiguration"),
           let saved = try? JSONDecoder().decode(MonitorConfiguration.self, from: data) {
            monitorConfiguration = saved
        } else {
            monitorConfiguration = .standard
        }
        if defaults.object(forKey: "refreshInterval") != nil {
            refreshInterval = defaults.double(forKey: "refreshInterval")
        }
        if let rawUnit = defaults.string(forKey: "temperatureUnit"),
           let unit = TemperatureUnit(rawValue: rawUnit) {
            temperatureUnit = unit
        }
        if defaults.object(forKey: "showMenuBarSummary") != nil {
            showMenuBarSummary = defaults.bool(forKey: "showMenuBarSummary")
        }
        if defaults.object(forKey: "pauseWhenOnBattery") != nil {
            pauseWhenOnBattery = defaults.bool(forKey: "pauseWhenOnBattery")
        }
        includeProcessNamesInReport = defaults.bool(forKey: "includeProcessNamesInReport")
        includeVolumeNamesInReport = defaults.bool(forKey: "includeVolumeNamesInReport")
        if let retention = DashboardHistoryRetention(
            rawValue: defaults.integer(forKey: DashboardHistoryRetention.storageKey)
        ) {
            dashboardHistoryRetention = retention
        }
    }

    static func configured(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppModel {
        if arguments.contains("--fixture-data") {
            return AppModel()
        }

        let allowsControlledChanges = RuntimeSafetyMode.current == .live
        let model = AppModel(
            metricsProvider: LiveSystemService(),
            startupProvider: StartupItemScanner(),
            applicationProvider: ApplicationScanner(),
            healthProvider: StorageHealthService(),
            startupMutator: allowsControlledChanges ? LaunchctlStartupItemMutator() : DenyAllStartupItemMutator(),
            uninstallExecutor: allowsControlledChanges ? TrashUninstallExecutor() : DenyAllUninstallExecutor(),
            supplementalSensorProvider: SensorHelperClient(),
            dashboardHistoryStore: DashboardHistoryStore()
        )
        model.dataSource = .live
        model.telemetry.history = [:]
        model.dashboardHistory = []
        model.dashboardEvents = []
        model.dashboardObservation = nil
        model.hasLoadedSnapshot = false
        model.startupPreloadStatus.beginIfNeeded()
        return model
    }

    /// Starts the telemetry lifecycle independently of any particular window.
    /// Closing the main window must not freeze the menu-bar monitor.
    func startMonitoring() {
        guard refreshLoopTask == nil else { return }
        startupPreloadStatus.beginIfNeeded()
        refreshLoopTask = Task { [weak self] in
            await self?.runRefreshLoop()
        }
    }

    func stopMonitoring() {
        refreshLoopTask?.cancel()
        refreshLoopTask = nil
        storageHealthSyncTask?.cancel()
        storageHealthSyncTask = nil
        dashboardHistoryWriteTask?.cancel()
        dashboardHistoryWriteTask = nil
        dashboardHistoryRetentionTask?.cancel()
        dashboardHistoryRetentionTask = nil
        pendingDashboardHistorySample = nil
    }

    func runRefreshLoop() async {
        startupPreloadStatus.beginIfNeeded()
        startupPreloadStatus.begin(.telemetry)
        await loadPersistedDashboardHistoryIfNeeded()
        guard !Task.isCancelled else { return }
        await refreshSnapshot()
        guard !Task.isCancelled else { return }
        startupPreloadStatus.complete(.telemetry, degraded: !hasLoadedSnapshot)
        let preloadTask = Task(priority: .utility) { [weak self] in
            await self?.preloadToolData()
        }
        defer { preloadTask.cancel() }
        while !Task.isCancelled {
            let batteryAwareInterval = MonitoringRefreshPolicy.effectiveInterval(
                baseInterval: refreshInterval,
                reducesFrequencyOnBattery: pauseWhenOnBattery,
                battery: snapshot.battery
            )
            let nanoseconds = UInt64(max(batteryAwareInterval, 1) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { break }
            await refreshSnapshot()
        }
    }

    /// Prepares slower inventories sequentially. Each stage is settled even
    /// when its provider fails, so the startup overlay can enter a documented
    /// degraded state instead of blocking forever.
    func preloadToolData() async {
        startupPreloadStatus.beginIfNeeded()
        if !startupPreloadStatus.completedStages.contains(.telemetry) {
            startupPreloadStatus.complete(.telemetry, degraded: !hasLoadedSnapshot)
        }

        guard await waitForNextPreloadBatch(startupPreloadSchedule.initialDelay) else { return }
        startupPreloadStatus.begin(.startupItems)
        await loadStartupItemsIfNeeded()
        guard !Task.isCancelled else { return }
        startupPreloadStatus.complete(
            .startupItems,
            degraded: !hasLoadedStartupItems
        )

        guard await waitForNextPreloadBatch(startupPreloadSchedule.delayBetweenBatches) else { return }
        startupPreloadStatus.begin(.applications)
        await loadApplicationsIfNeeded()
        guard !Task.isCancelled else { return }
        startupPreloadStatus.complete(
            .applications,
            degraded: !hasLoadedApplications
        )

        guard await waitForNextPreloadBatch(startupPreloadSchedule.delayBetweenBatches) else { return }
        startupPreloadStatus.begin(.storageHealth)
        await loadStorageHealthIfNeeded()
        guard !Task.isCancelled else { return }
        startupPreloadStatus.complete(
            .storageHealth,
            degraded: !hasLoadedStorageHealth
        )
        startupPreloadStatus.finish()
    }

    private func waitForNextPreloadBatch(_ delay: Duration) async -> Bool {
        guard delay > .zero else { return !Task.isCancelled }
        do {
            try await Task.sleep(for: delay)
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    func persistPreferences() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(monitorConfiguration) {
            defaults.set(data, forKey: "monitorConfiguration")
        }
        defaults.set(refreshInterval, forKey: "refreshInterval")
        defaults.set(temperatureUnit.rawValue, forKey: "temperatureUnit")
        defaults.set(showMenuBarSummary, forKey: "showMenuBarSummary")
        defaults.set(pauseWhenOnBattery, forKey: "pauseWhenOnBattery")
        defaults.set(includeProcessNamesInReport, forKey: "includeProcessNamesInReport")
        defaults.set(includeVolumeNamesInReport, forKey: "includeVolumeNamesInReport")
        defaults.set(
            dashboardHistoryRetention.rawValue,
            forKey: DashboardHistoryRetention.storageKey
        )
    }

    func updateDashboardHistoryRetentionDays(_ days: Int) {
        guard let retention = DashboardHistoryRetention(rawValue: days),
              retention != dashboardHistoryRetention
        else { return }

        dashboardHistoryRetention = retention
        UserDefaults.standard.set(
            retention.rawValue,
            forKey: DashboardHistoryRetention.storageKey
        )
        dashboardHistoryRetentionGeneration += 1
        let generation = dashboardHistoryRetentionGeneration
        dashboardHistoryRetentionTask?.cancel()
        dashboardHistoryRetentionTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.dashboardHistoryStore.updateRetention(
                retention,
                now: self.dashboardHistoryNow()
            )
            guard !Task.isCancelled,
                  self.dashboardHistoryRetentionGeneration == generation
            else { return }
            self.lastPersistedDashboardHistoryDate = result.lastPersistedAt
            self.dashboardHistoryRetentionTask = nil
        }
    }

    func loadPersistedDashboardHistoryIfNeeded() async {
        guard dataSource == .live else {
            hasLoadedPersistedDashboardHistory = true
            return
        }
        if isLoadingPersistedDashboardHistory {
            while isLoadingPersistedDashboardHistory, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(10))
            }
            return
        }
        guard !hasLoadedPersistedDashboardHistory else { return }

        isLoadingPersistedDashboardHistory = true
        defer { isLoadingPersistedDashboardHistory = false }
        let now = dashboardHistoryNow()
        let result = await dashboardHistoryStore.load(
            retention: dashboardHistoryRetention,
            now: now
        )
        guard !Task.isCancelled else { return }

        dashboardHistory = DashboardHistoryPolicy.restoring(
            result.samples,
            now: now
        )
        lastPersistedDashboardHistoryDate = result.lastPersistedAt
        hasLoadedPersistedDashboardHistory = true
    }

    func binding<Value>(_ keyPath: ReferenceWritableKeyPath<AppModel, Value>) -> Binding<Value> {
        Binding(
            get: { self[keyPath: keyPath] },
            set: { self[keyPath: keyPath] = $0 }
        )
    }

    func refreshAll() async {
        await refreshSnapshot(showsActivity: true)
    }

    func loadStartupItemsIfNeeded(force: Bool = false) async {
        if isLoadingStartupItems {
            await waitForLoadToFinish(\.isLoadingStartupItems)
            return
        }
        guard force || !hasAttemptedStartupItems else { return }
        guard !force || stagedStartupChangeCount == 0 else {
            startupItemsError = AppLocalization.currentString(
                "请先应用或撤销待确认的启动设置，再刷新清单。"
            )
            return
        }
        isLoadingStartupItems = true
        startupItemsError = nil
        defer { isLoadingStartupItems = false }
        do {
            let items = try await startupProvider.items()
            guard !Task.isCancelled else { return }
            let inventory = Self.prepareStartupInventory(
                items,
                editableDirectory: editableLaunchAgentsDirectory
            )
            startupItems = inventory.items
            baselineStartupItems = inventory.items
            baselineStartupStates = inventory.baselineStates
            editableStartupItemIDs = inventory.editableIDs
            stagedStartupChangeCount = 0
            hasAttemptedStartupItems = true
            hasLoadedStartupItems = true
            startupItemsLastLoadedAt = Date()
            clearLoadError(AppLocalization.currentString("启动项目"))
            startupPreloadStatus.reconcile(.startupItems, degraded: false)
        } catch {
            guard !(error is CancellationError) else { return }
            hasAttemptedStartupItems = true
            startupItemsError = error.localizedDescription
            recordLoadError(AppLocalization.currentString("启动项目"), error)
            startupPreloadStatus.reconcile(.startupItems, degraded: true)
        }
    }

    func loadApplicationsIfNeeded(force: Bool = false) async {
        if isLoadingApplications {
            await waitForLoadToFinish(\.isLoadingApplications)
            return
        }
        guard force || !hasAttemptedApplications else { return }
        isLoadingApplications = true
        applicationsError = nil
        defer { isLoadingApplications = false }
        do {
            let loadedApplications = try await applicationProvider.applications()
            guard !Task.isCancelled else { return }
            applications = loadedApplications
            enrichedApplicationIDs.removeAll(keepingCapacity: true)
            applicationDetailsLastLoadedAt.removeAll(keepingCapacity: true)
            if selectedApplicationID == nil || !loadedApplications.contains(where: { $0.id == selectedApplicationID }) {
                selectedApplicationID = loadedApplications.first?.id
            }
            hasAttemptedApplications = true
            hasLoadedApplications = true
            applicationsLastLoadedAt = Date()
            clearLoadError(AppLocalization.currentString("应用清单"))
            startupPreloadStatus.reconcile(.applications, degraded: false)
        } catch {
            guard !(error is CancellationError) else { return }
            hasAttemptedApplications = true
            applicationsError = error.localizedDescription
            recordLoadError(AppLocalization.currentString("应用清单"), error)
            startupPreloadStatus.reconcile(.applications, degraded: true)
        }
    }

    func loadStorageHealthIfNeeded(force: Bool = false) async {
        if isLoadingStorageHealth {
            await waitForLoadToFinish(\.isLoadingStorageHealth)
            return
        }

        let currentVolumeIDs = Set(snapshot.volumes.map(\.id))
        let cachedVolumeIDs = Set(storageHealth.keys)
        guard force || !hasAttemptedStorageHealth || currentVolumeIDs != cachedVolumeIDs else { return }

        let recordsFullRefresh = force || !hasAttemptedStorageHealth

        isLoadingStorageHealth = true
        defer { isLoadingStorageHealth = false }

        var shouldForceReload = force
        while !Task.isCancelled {
            let targetVolumes = snapshot.volumes
            let targetVolumeIDs = Set(targetVolumes.map(\.id))
            var healthByVolume = shouldForceReload
                ? [:]
                : storageHealth.filter { targetVolumeIDs.contains($0.key) }
            let volumesToLoad = shouldForceReload
                ? targetVolumes
                : targetVolumes.filter { healthByVolume[$0.id] == nil }

            for volume in volumesToLoad {
                guard !Task.isCancelled else { return }
                let health = await healthProvider.health(for: volume)
                guard !Task.isCancelled else { return }
                healthByVolume[volume.id] = health
            }

            let latestVolumeIDs = Set(snapshot.volumes.map(\.id))
            storageHealth = healthByVolume.filter { latestVolumeIDs.contains($0.key) }
            hasAttemptedStorageHealth = true
            hasLoadedStorageHealth = true
            shouldForceReload = false

            guard latestVolumeIDs != targetVolumeIDs else {
                if recordsFullRefresh {
                    storageHealthLastLoadedAt = storageHealthNow()
                }
                startupPreloadStatus.reconcile(.storageHealth, degraded: false)
                return
            }
        }
    }

    private func waitForLoadToFinish(_ keyPath: KeyPath<AppModel, Bool>) async {
        while self[keyPath: keyPath], !Task.isCancelled {
            do {
                try await Task.sleep(for: .milliseconds(10))
            } catch {
                return
            }
        }
    }

    func loadSelectedApplicationDetails(force: Bool = false) async {
        await loadApplicationsIfNeeded()
        guard !Task.isCancelled else { return }
        guard dataSource == .live, let application = selectedApplication else { return }
        guard force || !enrichedApplicationIDs.contains(application.id) else { return }

        let requestedID = application.id
        guard !loadingApplicationDetailIDs.contains(requestedID) else { return }
        loadingApplicationDetailIDs.insert(requestedID)
        defer {
            loadingApplicationDetailIDs.remove(requestedID)
        }
        let enriched = await applicationProvider.enrichedApplication(application)
        guard !Task.isCancelled else { return }
        guard let index = applications.firstIndex(where: { $0.id == requestedID }) else {
            return
        }
        applications[index] = enriched
        enrichedApplicationIDs.insert(requestedID)
        applicationDetailsLastLoadedAt[requestedID] = Date()
    }

    private func refreshSnapshot(showsActivity: Bool = false) async {
        guard !isSnapshotRefreshInFlight else { return }
        isSnapshotRefreshInFlight = true
        if showsActivity { isRefreshing = true }
        defer {
            isSnapshotRefreshInFlight = false
            if showsActivity { isRefreshing = false }
        }

        let previousVolumeIDs = Set(snapshot.volumes.map(\.id))
        var newSnapshot = await metricsProvider.snapshot()
        guard !Task.isCancelled else { return }
        if newSnapshot.cooling.fans.isEmpty || !newSnapshot.cooling.sensorAvailability.isAvailable {
            let supplemental = await supplementalSensorProvider.snapshot()
            guard !Task.isCancelled else { return }
            if let supplemental {
                Self.mergeSupplementalSensors(supplemental, into: &newSnapshot)
            }
        }
        var nextHistory = telemetry.history
        Self.appendHistory(.cpuTotal, newSnapshot.cpu.totalPercent, to: &nextHistory)
        Self.appendHistory(.cpuUser, newSnapshot.cpu.userPercent, to: &nextHistory)
        Self.appendHistory(.cpuSystem, newSnapshot.cpu.systemPercent, to: &nextHistory)
        Self.appendHistory(.memoryPressure, newSnapshot.memory.pressurePercent, to: &nextHistory)
        if newSnapshot.memory.totalBytes > 0 {
            let used = Double(newSnapshot.memory.usedBytes) / Double(newSnapshot.memory.totalBytes) * 100
            Self.appendHistory(.memoryUsed, used, to: &nextHistory)
        }
        if let value = newSnapshot.gpus.first?.utilizationPercent {
            Self.appendHistory(.gpuUsage, value, to: &nextHistory)
        }
        if let value = newSnapshot.cpu.temperatureCelsius {
            Self.appendHistory(.temperature, value, to: &nextHistory)
        }
        if let value = newSnapshot.cooling.fans.first?.currentRPM {
            Self.appendHistory(.fanSpeed, Double(value), to: &nextHistory)
        }
        let receivedRates = newSnapshot.networkInterfaces.compactMap(\.receivedBytesPerSecond)
        if !receivedRates.isEmpty {
            Self.appendHistory(.networkReceived, receivedRates.reduce(0, +), to: &nextHistory)
        }
        let sentRates = newSnapshot.networkInterfaces.compactMap(\.sentBytesPerSecond)
        if !sentRates.isEmpty {
            Self.appendHistory(.networkSent, sentRates.reduce(0, +), to: &nextHistory)
        }
        if let value = newSnapshot.battery.chargePercent {
            Self.appendHistory(.batteryCharge, value, to: &nextHistory)
        }
        Self.appendHistory(.uptime, newSnapshot.identity.uptime, to: &nextHistory)

        guard !Task.isCancelled else { return }
        telemetry = TelemetryFrame(snapshot: newSnapshot, history: nextHistory)
        appendStorageIOHistory(from: newSnapshot)
        appendDashboardHistory(from: newSnapshot)
        recordDashboardEvents(from: newSnapshot)
        if !hasLoadedSnapshot { hasLoadedSnapshot = true }

        let currentVolumeIDs = Set(newSnapshot.volumes.map(\.id))
        let storageHealthIsStale = hasLoadedStorageHealth && StorageHealthRefreshPolicy.isStale(
            lastLoadedAt: storageHealthLastLoadedAt,
            now: storageHealthNow(),
            staleInterval: storageHealthStaleInterval
        )
        if hasLoadedStorageHealth,
           currentVolumeIDs != previousVolumeIDs || storageHealthIsStale {
            scheduleStorageHealthSync(force: storageHealthIsStale)
        }
    }

    /// Storage health may invoke slow system tooling or wait on an unhealthy
    /// external device. Keep it outside the telemetry refresh chain so menu-bar
    /// CPU, memory and temperature values continue to advance independently.
    private func scheduleStorageHealthSync(force: Bool = false) {
        guard storageHealthSyncTask == nil else { return }
        storageHealthSyncTask = Task { [weak self] in
            guard let self else { return }
            await self.loadStorageHealthIfNeeded(force: force)
            self.storageHealthSyncTask = nil
        }
    }

    private func appendDashboardHistory(from snapshot: SystemSnapshot) {
        let sample = Self.dashboardSample(from: snapshot)
        if let nextHistory = DashboardHistoryPolicy.appending(sample, to: dashboardHistory) {
            dashboardHistory = nextHistory
        }
        scheduleDashboardHistoryPersistence(sample)
    }

    private func scheduleDashboardHistoryPersistence(
        _ sample: DashboardTelemetrySample
    ) {
        guard dataSource == .live, hasLoadedPersistedDashboardHistory else { return }
        if let lastPersistedDashboardHistoryDate {
            let elapsed = sample.date.timeIntervalSince(lastPersistedDashboardHistoryDate)
            guard elapsed < 0 || elapsed >= DashboardHistoryStore.persistenceSampleInterval else {
                return
            }
        }

        lastPersistedDashboardHistoryDate = sample.date
        pendingDashboardHistorySample = sample
        guard dashboardHistoryWriteTask == nil else { return }

        dashboardHistoryWriteTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled,
                  let pendingSample = self.pendingDashboardHistorySample {
                self.pendingDashboardHistorySample = nil
                await self.dashboardHistoryStore.record(
                    pendingSample,
                    retention: self.dashboardHistoryRetention,
                    now: self.dashboardHistoryNow()
                )
            }
            self.dashboardHistoryWriteTask = nil
        }
    }

    private func appendStorageIOHistory(from snapshot: SystemSnapshot) {
        guard let sample = StorageIOHistoryPolicy.sample(
            capturedAt: snapshot.capturedAt,
            storageIO: snapshot.storageIO
        ), let nextHistory = StorageIOHistoryPolicy.appending(
            sample,
            to: storageIOHistory
        ) else {
            return
        }
        storageIOHistory = nextHistory
    }

    private func recordDashboardEvents(from snapshot: SystemSnapshot) {
        guard dataSource == .live else { return }
        let interfaces = Self.dashboardEventInterfaces(from: snapshot)
        let current = DashboardObservation(
            memoryPressure: snapshot.memory.pressurePercent,
            activeInterfaces: Dictionary(
                uniqueKeysWithValues: interfaces
                    .filter(\.isActive)
                    .map { ($0.name, $0.displayName) }
            ),
            fanCount: snapshot.cooling.fans.count,
            thermalCondition: snapshot.cooling.condition.rawValue
        )
        let now = snapshot.capturedAt

        guard let previous = dashboardObservation else {
            dashboardObservation = current
            var initialEvents = [
                DashboardEventRecord(
                    title: "系统启动",
                    detail: "根据本机运行时间计算",
                    occurredAt: now.addingTimeInterval(-snapshot.identity.uptime),
                    color: CalmTheme.mint
                )
            ]
            for interface in interfaces.filter(\.isActive) {
                let detailKey = interface.linkSpeedMbps == nil
                    ? "当前连接"
                    : "dashboard.event.speed"
                let detailDefaultValue = interface.linkSpeedMbps == nil
                    ? "当前连接"
                    : "速度 %@ Mbps"
                let detailArguments = interface.linkSpeedMbps.map {
                    [String(Int($0.rounded()))]
                } ?? []
                initialEvents.append(
                    DashboardEventRecord(
                        titleKey: "dashboard.event.connected.current",
                        titleDefaultValue: "%@ 当前已连接",
                        titleArguments: [interface.displayName],
                        detailKey: detailKey,
                        detailDefaultValue: detailDefaultValue,
                        detailArguments: detailArguments,
                        occurredAt: now,
                        color: CalmTheme.accent
                    )
                )
            }
            if !snapshot.cooling.fans.isEmpty {
                let fanCount = snapshot.cooling.fans.count
                initialEvents.append(
                    DashboardEventRecord(
                        titleKey: "风扇传感器在线",
                        titleDefaultValue: "风扇传感器在线",
                        titleArguments: [],
                        detailKey: AppCountLocalization.key(
                            count: fanCount,
                            one: "dashboard.event.fans.read.one",
                            other: "dashboard.event.fans.read.other"
                        ),
                        detailDefaultValue: "已读取 %@ 个风扇",
                        detailArguments: [String(fanCount)],
                        occurredAt: now,
                        color: CalmTheme.mint
                    )
                )
            }
            dashboardEvents = initialEvents.sorted { $0.occurredAt > $1.occurredAt }
            return
        }

        let memoryDelta = current.memoryPressure - previous.memoryPressure
        if abs(memoryDelta) >= 1 {
            insertDashboardEvent(
                DashboardEventRecord(
                    titleKey: "dashboard.event.memory.change",
                    titleDefaultValue: "内存压力%@ %@",
                    titleArguments: [
                        memoryDelta > 0 ? "上升" : "下降",
                        MetricFormatter.percent(abs(memoryDelta))
                    ],
                    titleLocalizedArgumentIndices: [0],
                    detailKey: "与上一次采样相比",
                    detailDefaultValue: "与上一次采样相比",
                    occurredAt: now,
                    color: memoryDelta > 0 ? CalmTheme.amber : CalmTheme.mint
                )
            )
        }

        let currentInterfaceIDs = Set(current.activeInterfaces.keys)
        let previousInterfaceIDs = Set(previous.activeInterfaces.keys)
        for interfaceID in currentInterfaceIDs.subtracting(previousInterfaceIDs).sorted() {
            let name = current.activeInterfaces[interfaceID] ?? interfaceID
            insertDashboardEvent(
                DashboardEventRecord(
                    titleKey: "dashboard.event.interface.connected",
                    titleDefaultValue: "%@ 已连接",
                    titleArguments: [name],
                    detailKey: "网络状态发生变化",
                    detailDefaultValue: "网络状态发生变化",
                    occurredAt: now,
                    color: CalmTheme.accent
                )
            )
        }
        for interfaceID in previousInterfaceIDs.subtracting(currentInterfaceIDs).sorted() {
            let name = previous.activeInterfaces[interfaceID] ?? interfaceID
            insertDashboardEvent(
                DashboardEventRecord(
                    titleKey: "dashboard.event.interface.disconnected",
                    titleDefaultValue: "%@ 已断开",
                    titleArguments: [name],
                    detailKey: "网络状态发生变化",
                    detailDefaultValue: "网络状态发生变化",
                    occurredAt: now,
                    color: CalmTheme.amber
                )
            )
        }

        if current.fanCount > 0,
           previous.fanCount == 0 || previous.thermalCondition != current.thermalCondition {
            insertDashboardEvent(
                DashboardEventRecord(
                    titleKey: "风扇状态已更新",
                    titleDefaultValue: "风扇状态已更新",
                    titleArguments: [],
                    detailKey: AppCountLocalization.key(
                        count: current.fanCount,
                        one: "dashboard.event.fan.detail.one",
                        other: "dashboard.event.fan.detail.other"
                    ),
                    detailDefaultValue: "%@ 个风扇 · %@",
                    detailArguments: [
                        String(current.fanCount),
                        rawThermalConditionTitle(snapshot.cooling.condition)
                    ],
                    detailLocalizedArgumentIndices: [1],
                    occurredAt: now,
                    color: CalmTheme.mint
                )
            )
        }
        dashboardObservation = current
    }

    private func insertDashboardEvent(_ event: DashboardEventRecord) {
        dashboardEvents.insert(event, at: 0)
        if dashboardEvents.count > 20 {
            dashboardEvents = Array(dashboardEvents.prefix(20))
        }
    }

    private static func mergeSupplementalSensors(
        _ payload: SensorHelperPayload,
        into snapshot: inout SystemSnapshot
    ) {
        guard payload.hasMeasurements else {
            if let reason = SensorHelperErrorPresentation.reason(
                code: payload.errorCode,
                legacyMessage: payload.errorMessage,
                locale: AppLocalization.currentLocale
            ) {
                let requiresPermission = payload.errorCode == .permissionRequired
                    || payload.permissionRequired
                snapshot.cooling.sensorAvailability = requiresPermission
                    ? .permissionRequired(reason: reason)
                    : .failed(reason: reason)
            }
            return
        }

        if !payload.temperatures.isEmpty {
            snapshot.cooling.sensors = payload.temperatures.map {
                ThermalSensor(
                    key: $0.key,
                    name: $0.name,
                    group: $0.group,
                    temperatureCelsius: $0.temperatureCelsius
                )
            }
        }
        if !payload.fans.isEmpty {
            snapshot.cooling.fans = payload.fans.map {
                FanState(
                    name: $0.name,
                    currentRPM: $0.currentRPM,
                    minimumRPM: $0.minimumRPM,
                    maximumRPM: $0.maximumRPM,
                    targetRPM: $0.targetRPM
                )
            }
        }
        snapshot.cpu.temperatureCelsius = payload.cpuTemperatureCelsius
            ?? snapshot.cpu.temperatureCelsius
        if !snapshot.gpus.isEmpty {
            snapshot.gpus[0].temperatureCelsius = payload.gpuTemperatureCelsius
                ?? snapshot.gpus[0].temperatureCelsius
        }
        snapshot.cooling.sensorAvailability = .available
    }

    var memoryUsedPercent: Double {
        guard snapshot.memory.totalBytes > 0 else { return 0 }
        return Double(snapshot.memory.usedBytes) / Double(snapshot.memory.totalBytes) * 100
    }

    var overallState: OverallSystemState {
        if lastError != nil { return .limited }
        switch snapshot.cooling.condition {
        case .critical: return .critical
        case .serious: return .attention
        case .nominal, .fair, .unavailable: break
        }
        if snapshot.battery.health == .serviceRecommended { return .attention }
        if storageHealth.values.contains(where: { health in
            let condition = StorageHealthSemanticCondition.classify(health)
            return condition == .critical || condition == .warning
        }) {
            return .attention
        }
        if snapshot.cooling.condition == .nominal { return .normal }
        return .monitoring
    }

    var selectedApplication: ApplicationCandidate? {
        applications.first { $0.id == selectedApplicationID }
    }

    func setStartupItem(_ id: String, enabled: Bool) {
        guard let index = startupItems.firstIndex(where: { $0.id == id }) else { return }
        guard isStartupItemEditable(startupItems[index]) else { return }
        startupItems[index].isEnabled = enabled
        updateStagedStartupChangeCount()
    }

    func isStartupItemEditable(_ item: StartupItem) -> Bool {
        dataSource == .fixture || editableStartupItemIDs.contains(item.id)
    }

    nonisolated private static func prepareStartupInventory(
        _ items: [StartupItem],
        editableDirectory: String
    ) -> StartupInventory {
        StartupInventory(
            items: items,
            baselineStates: Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.isEnabled) }),
            editableIDs: Set(items.lazy.filter {
                isEditableStartupItem($0, editableDirectory: editableDirectory)
            }.map(\.id))
        )
    }

    nonisolated private static func isEditableStartupItem(
        _ item: StartupItem,
        editableDirectory: String
    ) -> Bool {
        guard item.kind == .launchAgent, item.scopeKind == .currentUser else { return false }
        let URL = URL(fileURLWithPath: item.path).standardizedFileURL
        return URL.deletingLastPathComponent().path == editableDirectory
            && URL.pathExtension.lowercased() == "plist"
    }

    func resetStartupChanges() {
        startupItems = baselineStartupItems
        stagedStartupChangeCount = 0
    }

    func applyStartupChanges() async throws -> Int {
        let baselineByID = Dictionary(uniqueKeysWithValues: baselineStartupItems.map { ($0.id, $0.isEnabled) })
        let changes = startupItems.filter { item in
            baselineByID[item.id].map { $0 != item.isEnabled } ?? false
        }
        guard !changes.isEmpty else { return 0 }

        var succeeded = 0
        var failures: [String] = []
        for item in changes {
            do {
                try await startupMutator.setEnabled(item.isEnabled, item: item)
                if let index = baselineStartupItems.firstIndex(where: { $0.id == item.id }) {
                    baselineStartupItems[index].isEnabled = item.isEnabled
                }
                baselineStartupStates[item.id] = item.isEnabled
                succeeded += 1
            } catch {
                failures.append("\(item.displayName)：\(error.localizedDescription)")
            }
        }
        if !failures.isEmpty {
            updateStagedStartupChangeCount()
            throw AppOperationError.partialStartupUpdate(succeeded: succeeded, failures: failures)
        }
        updateStagedStartupChangeCount()
        return succeeded
    }

    func setAssociatedFile(_ id: String, selected: Bool, applicationID: String) {
        guard let applicationIndex = applications.firstIndex(where: { $0.id == applicationID }),
              let fileIndex = applications[applicationIndex].associatedFiles.firstIndex(where: { $0.id == id })
        else { return }
        applications[applicationIndex].associatedFiles[fileIndex].isSelected = selected
    }

    func uninstall(_ application: ApplicationCandidate) async throws -> Int {
        let selectedFiles = application.associatedFiles.filter(\.isSelected)
        let plan = UninstallPlan(application: application, selectedFiles: selectedFiles)
        try await uninstallExecutor.execute(plan: plan)
        applications.removeAll { $0.id == application.id }
        selectedApplicationID = applications.first?.id
        return plan.totalItemCount
    }

    func history(for metric: MonitorMetric) -> [Double] {
        telemetry.history[metric] ?? []
    }

    func formattedValue(for metric: MonitorMetric) -> String {
        switch metric {
        case .cpuTotal: MetricFormatter.percent(snapshot.cpu.totalPercent)
        case .cpuUser: MetricFormatter.percent(snapshot.cpu.userPercent)
        case .cpuSystem: MetricFormatter.percent(snapshot.cpu.systemPercent)
        case .gpuUsage: snapshot.gpus.first?.utilizationPercent.map { MetricFormatter.percent($0) } ?? "—"
        case .memoryPressure: MetricFormatter.percent(snapshot.memory.pressurePercent)
        case .memoryUsed: MetricFormatter.percent(memoryUsedPercent)
        case .storageUsed: snapshot.volumes.first.map { MetricFormatter.bytes($0.usedBytes) } ?? "—"
        case .temperature: snapshot.cpu.temperatureCelsius.map { temperatureUnit.formatted(celsius: $0) } ?? "—"
        case .fanSpeed: snapshot.cooling.fans.first.map { "\($0.currentRPM) RPM" } ?? "—"
        case .networkReceived:
            aggregateRate(snapshot.networkInterfaces.compactMap(\.receivedBytesPerSecond))
        case .networkSent:
            aggregateRate(snapshot.networkInterfaces.compactMap(\.sentBytesPerSecond))
        case .batteryCharge: snapshot.battery.chargePercent.map { MetricFormatter.percent($0) } ?? "—"
        case .batteryHealth: batteryHealthTitle(snapshot.battery.health)
        case .uptime: MetricFormatter.duration(snapshot.identity.uptime)
        }
    }

    func reportText(locale: Locale? = nil) -> String {
        SystemReportBuilder().text(
            snapshot: snapshot,
            options: SystemReportOptions(
                includeNetworkAddresses: false,
                includeProcessNames: includeProcessNamesInReport,
                includeVolumeNames: includeVolumeNamesInReport
            ),
            locale: locale
        )
    }

    private static func appendHistory(
        _ metric: MonitorMetric,
        _ value: Double,
        to history: inout [MonitorMetric: [Double]]
    ) {
        var values = history[metric] ?? []
        values.append(value)
        history[metric] = Array(values.suffix(32))
    }

    private func updateStagedStartupChangeCount() {
        stagedStartupChangeCount = startupItems.reduce(into: 0) { count, item in
            if baselineStartupStates[item.id].map({ $0 != item.isEnabled }) ?? false {
                count += 1
            }
        }
    }

    private func recordLoadError(_ source: String, _ error: Error) {
        let message = "\(source)：\(error.localizedDescription)"
        guard let lastError else {
            self.lastError = message
            return
        }

        let messages = lastError
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        guard !messages.contains(message) else { return }
        self.lastError = (messages + [message]).joined(separator: "\n")
    }

    private func clearLoadError(_ source: String) {
        guard let lastError else { return }
        let prefix = "\(source)："
        let remaining = lastError
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !$0.hasPrefix(prefix) }
        self.lastError = remaining.isEmpty ? nil : remaining.joined(separator: "\n")
    }

    private func aggregateRate(_ values: [Double]) -> String {
        guard !values.isEmpty else { return "—" }
        return MetricFormatter.rate(bytesPerSecond: values.reduce(0, +))
    }

    private static func dashboardSample(from snapshot: SystemSnapshot) -> DashboardTelemetrySample {
        let volume = snapshot.volumes.first(where: { $0.isInternal == true }) ?? snapshot.volumes.first
        let interfaces = snapshot.networkInterfaces.filter(isDashboardInterfaceRelevant)
        return DashboardTelemetrySample(
            date: snapshot.capturedAt,
            cpuPercent: snapshot.cpu.totalPercent,
            gpuPercent: snapshot.gpus.first?.utilizationPercent,
            memoryPressurePercent: snapshot.memory.pressurePercent,
            storageUsedPercent: volume.map { $0.usedFraction * 100 },
            networkReceivedBytesPerSecond: interfaces.compactMap(\.receivedBytesPerSecond).reduce(0, +),
            networkSentBytesPerSecond: interfaces.compactMap(\.sentBytesPerSecond).reduce(0, +),
            temperatureCelsius: dashboardTemperature(from: snapshot)
        )
    }

    private static func seedDashboardHistory(
        snapshot: SystemSnapshot,
        history: [MonitorMetric: [Double]]
    ) -> [DashboardTelemetrySample] {
        let cpu = history[.cpuTotal] ?? []
        let gpu = history[.gpuUsage] ?? []
        let memory = history[.memoryPressure] ?? []
        let received = history[.networkReceived] ?? []
        let sent = history[.networkSent] ?? []
        let temperature = history[.temperature] ?? []
        let sourceCount = [cpu.count, gpu.count, memory.count, received.count, sent.count, temperature.count].max() ?? 0
        let sampleCount = max(sourceCount, 181)
        guard sampleCount > 1 else { return [dashboardSample(from: snapshot)] }

        let volume = snapshot.volumes.first(where: { $0.isInternal == true }) ?? snapshot.volumes.first
        return (0 ..< sampleCount).map { index in
            let fraction = Double(index) / Double(sampleCount - 1)
            return DashboardTelemetrySample(
                date: snapshot.capturedAt.addingTimeInterval(-3_600 * (1 - fraction)),
                cpuPercent: min(max(
                    (interpolatedDashboardHistoryValue(cpu, fraction: fraction) ?? snapshot.cpu.totalPercent)
                        + fixtureHistoryVariation(index: index, amplitude: 2.4, phase: 0.3),
                    0
                ), 100),
                gpuPercent: interpolatedDashboardHistoryValue(gpu, fraction: fraction).map {
                    min(max($0 + fixtureHistoryVariation(index: index, amplitude: 2.1, phase: 1.1), 0), 100)
                },
                memoryPressurePercent: min(max(
                    (interpolatedDashboardHistoryValue(memory, fraction: fraction)
                        ?? snapshot.memory.pressurePercent)
                        + fixtureHistoryVariation(index: index, amplitude: 0.65, phase: 2.0),
                    0
                ), 100),
                storageUsedPercent: volume.map { $0.usedFraction * 100 },
                networkReceivedBytesPerSecond: max(
                    (interpolatedDashboardHistoryValue(received, fraction: fraction) ?? 0)
                        * (1 + fixtureHistoryVariation(index: index, amplitude: 0.12, phase: 0.7)),
                    0
                ),
                networkSentBytesPerSecond: max(
                    (interpolatedDashboardHistoryValue(sent, fraction: fraction) ?? 0)
                        * (1 + fixtureHistoryVariation(index: index, amplitude: 0.1, phase: 1.7)),
                    0
                ),
                temperatureCelsius: interpolatedDashboardHistoryValue(
                    temperature,
                    fraction: fraction
                ).map {
                    $0 + fixtureHistoryVariation(index: index, amplitude: 0.5, phase: 2.6)
                }
            )
        }
    }

    private static func interpolatedDashboardHistoryValue(
        _ values: [Double],
        fraction: Double
    ) -> Double? {
        guard !values.isEmpty else { return nil }
        guard values.count > 1 else { return values[0] }
        let position = min(max(fraction, 0), 1) * Double(values.count - 1)
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = min(lowerIndex + 1, values.count - 1)
        let interpolation = position - Double(lowerIndex)
        return values[lowerIndex] + (values[upperIndex] - values[lowerIndex]) * interpolation
    }

    private static func fixtureHistoryVariation(index: Int, amplitude: Double, phase: Double) -> Double {
        let value = Double(index)
        return amplitude * (
            sin(value * 0.71 + phase) * 0.58
                + sin(value * 1.93 + phase * 0.7) * 0.29
                + sin(value * 3.17 + phase * 1.3) * 0.13
        )
    }

    private static func isDashboardInterfaceRelevant(_ interface: NetworkInterfaceState) -> Bool {
        let name = interface.name.lowercased()
        let excludedPrefixes = [
            "lo", "utun", "awdl", "llw", "bridge", "gif", "stf", "anpi", "ap", "pktap"
        ]
        return !excludedPrefixes.contains(where: name.hasPrefix)
            && (name.hasPrefix("en") || interface.isActive)
    }

    private static func dashboardEventInterfaces(from snapshot: SystemSnapshot) -> [NetworkInterfaceState] {
        let candidates = snapshot.networkInterfaces.filter(isDashboardInterfaceRelevant)
        let wifi = candidates.first { interface in
            let displayName = interface.displayName.lowercased()
            return displayName.contains("wi-fi") || displayName.contains("wifi")
        }
        let ethernet = candidates.first { interface in
            let displayName = interface.displayName.lowercased()
            let isEthernet = displayName.contains("ethernet") || displayName.contains("以太网")
            let isAdapter = displayName.contains("adapter") || displayName.contains("适配器")
            return isEthernet && !isAdapter
        }
        return [ethernet, wifi].compactMap { $0 }
    }

    private static func dashboardTemperature(from snapshot: SystemSnapshot) -> Double? {
        if let value = snapshot.cpu.temperatureCelsius { return value }
        let cpuSensors = snapshot.cooling.sensors.filter {
            $0.group.localizedCaseInsensitiveContains("CPU")
                || $0.name.localizedCaseInsensitiveContains("CPU")
        }
        let values = cpuSensors.isEmpty
            ? snapshot.cooling.sensors.map(\.temperatureCelsius)
            : cpuSensors.map(\.temperatureCelsius)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func seedDashboardEvents(snapshot: SystemSnapshot) -> [DashboardEventRecord] {
        let now = snapshot.capturedAt
        return [
            DashboardEventRecord(
                title: "内存压力上升 8%",
                detail: "与 1 小时前相比",
                occurredAt: now.addingTimeInterval(-3_600),
                color: CalmTheme.amber
            ),
            DashboardEventRecord(
                title: "系统启动",
                detail: "监控已开始记录",
                occurredAt: now.addingTimeInterval(-10_800),
                color: CalmTheme.mint
            ),
            DashboardEventRecord(
                title: "以太网已连接",
                detail: "速度 1,000 Mbps",
                occurredAt: now.addingTimeInterval(-10_860),
                color: CalmTheme.accent
            ),
            DashboardEventRecord(
                title: "Wi‑Fi 已连接",
                detail: "速度 1,200 Mbps",
                occurredAt: now.addingTimeInterval(-10_920),
                color: CalmTheme.accent
            ),
            DashboardEventRecord(
                title: "风扇转速恢复正常",
                detail: "双风扇",
                occurredAt: now.addingTimeInterval(-21_600),
                color: CalmTheme.mint
            )
        ]
    }

    private static let seedHistory: [MonitorMetric: [Double]] = [
        .cpuTotal: [18, 23, 21, 27, 34, 31, 38, 29, 33, 35, 34],
        .cpuUser: [12, 16, 14, 20, 24, 22, 29, 19, 23, 25, 24],
        .cpuSystem: [6, 7, 7, 7, 10, 9, 9, 10, 10, 10, 10],
        .gpuUsage: [8, 12, 18, 26, 31, 42, 35, 29, 33, 39, 38],
        .memoryPressure: [26, 27, 27, 28, 29, 29, 30, 30, 31, 31, 31],
        .networkReceived: [80_000, 140_000, 920_000, 1_400_000, 760_000, 2_200_000, 2_840_000],
        .networkSent: [36_000, 48_000, 120_000, 240_000, 182_000, 410_000, 364_000],
        .temperature: [43, 44, 45, 46, 45, 47, 48],
        .fanSpeed: [1_200, 1_210, 1_238, 1_280, 1_310, 1_326]
    ]
}

func batteryHealthTitle(_ health: BatteryHealth) -> String {
    AppLocalization.currentString(rawBatteryHealthTitle(health))
}

private func rawBatteryHealthTitle(_ health: BatteryHealth) -> String {
    switch health {
    case .excellent: "优秀"
    case .good: "正常"
    case .aging: "逐渐老化"
    case .serviceRecommended: "建议检修"
    case .unknown: "未知"
    }
}

func thermalConditionTitle(_ condition: ThermalCondition) -> String {
    AppLocalization.currentString(rawThermalConditionTitle(condition))
}

private func rawThermalConditionTitle(_ condition: ThermalCondition) -> String {
    switch condition {
    case .nominal: "正常"
    case .fair: "温度升高"
    case .serious: "温度较高"
    case .critical: "需要关注"
    case .unavailable: "未知"
    }
}
