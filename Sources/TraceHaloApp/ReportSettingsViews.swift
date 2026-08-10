import AppKit
import SwiftUI
import TraceHaloCore
import UniformTypeIdentifiers

enum ReportSettingsLocalization {
    typealias Lookup = (_ key: String, _ defaultValue: String, _ locale: Locale) -> String

    static func text(_ key: String, locale: Locale) -> String {
        AppLocalization.string(key, defaultValue: key, locale: locale)
    }

    static func text(
        _ key: String,
        locale: Locale,
        lookup: Lookup
    ) -> String {
        lookup(key, key, locale)
    }

    static func exportAlertKey(succeeded: Bool) -> String {
        succeeded ? "PDF 已导出" : "无法导出 PDF"
    }

    static func exportAlertTitle(succeeded: Bool, locale: Locale) -> String {
        text(exportAlertKey(succeeded: succeeded), locale: locale)
    }

    static func dataSourceKey(_ source: AppDataSource) -> String {
        switch source {
        case .fixture:
            "演示数据"
        case .live:
            "本机数据"
        }
    }

    static func dataSourceTitle(_ source: AppDataSource, locale: Locale) -> String {
        text(dataSourceKey(source), locale: locale)
    }

    static func runtimeModeKey(isSafeTest: Bool) -> String {
        isSafeTest ? "安全测试（修改全部拒绝）" : "实时监测与受控修改"
    }

    static func runtimeModeTitle(isSafeTest: Bool, locale: Locale) -> String {
        text(runtimeModeKey(isSafeTest: isSafeTest), locale: locale)
    }

    static func integer(_ value: Int, locale: Locale) -> String {
        value.formatted(.number.locale(locale))
    }

    static func shortTime(_ date: Date, locale: Locale) -> String {
        date.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened)
                .locale(locale)
        )
    }

    static func updateTimestamp(_ date: Date, locale: Locale) -> String {
        date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .standard)
                .locale(locale)
        )
    }
}

struct ReportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @State private var report = ""
    @State private var generatedAt: Date?
    @State private var exportMessage: String?
    @State private var exportSucceeded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: localized("系统报告"),
                    subtitle: localized("生成适合排障和归档的只读硬件状态摘要"),
                    symbol: "doc.text.magnifyingglass",
                    trailing: AnyView(generateButton)
                )

                privacyCard

                HStack(alignment: .top, spacing: 16) {
                    reportSummary
                        .frame(width: 270)
                    reportPreview
                }
            }
            .padding(24)
            .frame(maxWidth: 1_220, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .calmPage()
        .navigationTitle(localized("系统报告"))
        .onAppear {
            if report.isEmpty { generateReport() }
        }
        .onChange(of: locale.identifier) { _, _ in
            generateReport()
        }
        .alert(
            ReportSettingsLocalization.exportAlertTitle(
                succeeded: exportSucceeded,
                locale: locale
            ),
            isPresented: Binding(
                get: { exportMessage != nil },
                set: { if !$0 { exportMessage = nil } }
            )
        ) {
            Button(localized("知道了")) { exportMessage = nil }
        } message: {
            Text(exportMessage ?? "")
        }
    }

    private var generateButton: some View {
        Button(action: generateReport) {
            Label(localized("重新生成"), systemImage: "arrow.clockwise")
        }
        .buttonStyle(CalmButtonStyle(prominent: true))
    }

    private var privacyCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "hand.raised.fill")
                .font(.title2)
                .foregroundStyle(CalmTheme.mint)
            VStack(alignment: .leading, spacing: 3) {
                Text(localized("默认保护敏感信息"))
                    .font(.headline)
                Text(localized("默认隐藏电脑名、卷名、序列号、网络地址、进程名称和文件内容。"))
                    .font(.callout)
                    .foregroundStyle(CalmTheme.secondaryText)
            }
            Spacer()
            StatusPill(
                text: localized("本地生成"),
                color: CalmTheme.mint,
                symbol: "lock.fill"
            )
        }
        .calmCard()
    }

    private var reportSummary: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionTitle(title: localized("包含内容"), symbol: "checklist")
            reportItem(localized("设备与系统"), "desktopcomputer")
            reportItem(localized("资源状态"), "gauge.with.dots.needle.50percent")
            reportItem(localized("存储卷"), "internaldrive")
            reportItem(localized("图形与显示器"), "display")
            reportItem(localized("散热与电池"), "thermometer.medium")

            CalmDivider()

            DetailRow(
                label: localized("数据来源"),
                value: ReportSettingsLocalization.dataSourceTitle(
                    model.dataSource,
                    locale: locale
                )
            )
            DetailRow(
                label: localized("卷数量"),
                value: ReportSettingsLocalization.integer(
                    model.snapshot.volumes.count,
                    locale: locale
                )
            )
            DetailRow(
                label: localized("显示器"),
                value: ReportSettingsLocalization.integer(
                    model.snapshot.gpus.flatMap(\.displays).count,
                    locale: locale
                )
            )
            if let generatedAt {
                DetailRow(
                    label: localized("生成于"),
                    value: ReportSettingsLocalization.shortTime(
                        generatedAt,
                        locale: locale
                    )
                )
            }
        }
        .calmCard()
    }

    private var reportPreview: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                SectionTitle(
                    title: localized("预览"),
                    subtitle: localized("可选择文字后复制"),
                    symbol: "doc.plaintext"
                )
                Spacer()
                ShareLink(item: report) {
                    Label(localized("共享"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(CalmButtonStyle())
                .disabled(report.isEmpty)
                Button(localized("导出 PDF…")) { exportPDF() }
                    .buttonStyle(CalmButtonStyle(prominent: true))
                    .disabled(report.isEmpty)
            }

            ScrollView([.vertical, .horizontal]) {
                Text(report)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(16)
            }
            .frame(minHeight: 480)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(.primary.opacity(0.07))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .calmCard()
    }

    private func reportItem(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.callout)
            .foregroundStyle(CalmTheme.secondaryText)
    }

    private func generateReport() {
        report = model.reportText(locale: locale)
        generatedAt = Date()
    }

    private func localized(_ key: String) -> String {
        ReportSettingsLocalization.text(key, locale: locale)
    }

    @MainActor
    private func exportPDF() {
        let panel = NSSavePanel()
        panel.title = localized("导出 TraceHalo 系统报告")
        panel.prompt = localized("导出")
        panel.message = localized("选择 PDF 报告的保存位置。")
        panel.nameFieldStringValue = "TraceHalo-System-Report.pdf"
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            try ReportPDFExporter.write(report, to: destination)
            exportSucceeded = true
            exportMessage = localized("报告已保存到你选择的位置。")
        } catch {
            exportSucceeded = false
            exportMessage = error.localizedDescription
        }
    }
}

enum SettingsUsageMode: String, CaseIterable, Identifiable {
    case powerSaving
    case balanced
    case realtime
    case custom

    var id: String { rawValue }
}

enum SettingsBatteryCapability: Equatable {
    case checking
    case available
    case unavailable
}

struct SettingsUsageModeConfiguration: Equatable {
    let refreshInterval: Double
    let pauseWhenOnBattery: Bool
}

enum SettingsUsageModePolicy {
    static func capability(
        hasLoadedSnapshot: Bool,
        hasBattery: Bool
    ) -> SettingsBatteryCapability {
        guard hasLoadedSnapshot else { return .checking }
        return hasBattery ? .available : .unavailable
    }

    static func availableModes(
        for capability: SettingsBatteryCapability
    ) -> [SettingsUsageMode] {
        capability == .unavailable
            ? [.balanced, .realtime]
            : [.powerSaving, .balanced, .realtime]
    }

    static func configuration(
        for mode: SettingsUsageMode
    ) -> SettingsUsageModeConfiguration {
        switch mode {
        case .powerSaving:
            SettingsUsageModeConfiguration(
                refreshInterval: 5,
                pauseWhenOnBattery: true
            )
        case .balanced:
            SettingsUsageModeConfiguration(
                refreshInterval: 2,
                pauseWhenOnBattery: true
            )
        case .realtime:
            SettingsUsageModeConfiguration(
                refreshInterval: 1,
                pauseWhenOnBattery: false
            )
        case .custom:
            // `custom` is a presentation-only result for values chosen in
            // Advanced Settings. It is never offered as a usage-mode card.
            SettingsUsageModeConfiguration(
                refreshInterval: 2,
                pauseWhenOnBattery: true
            )
        }
    }

    static func selection(
        refreshInterval: Double,
        pauseWhenOnBattery: Bool,
        capability: SettingsBatteryCapability
    ) -> SettingsUsageMode {
        if matches(refreshInterval, 1), !pauseWhenOnBattery {
            return .realtime
        }
        if matches(refreshInterval, 2), pauseWhenOnBattery {
            return .balanced
        }
        if matches(refreshInterval, 5), pauseWhenOnBattery {
            return capability == .unavailable ? .custom : .powerSaving
        }

        if refreshInterval <= 1.5, !pauseWhenOnBattery {
            return .realtime
        }
        if capability != .unavailable,
           refreshInterval >= 4,
           pauseWhenOnBattery {
            return .powerSaving
        }
        return .custom
    }

    private static func matches(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 0.001
    }
}

enum SettingsHistoryRetentionPresentation {
    static func retention(storedDays: Int) -> DashboardHistoryRetention {
        DashboardHistoryRetention(rawValue: storedDays) ?? .defaultValue
    }

    static func title(
        retention: DashboardHistoryRetention,
        locale: Locale
    ) -> String {
        let format = AppLocalization.string(
            "settings.historyRetention.days.format",
            defaultValue: "%ld days",
            locale: locale
        )
        return String(
            format: format,
            locale: locale,
            retention.rawValue
        )
    }
}

private enum SettingsPresentedSheet: String, Identifiable {
    case diagnostics
    case advanced
    case about

    var id: String { rawValue }
}

private enum SettingsPresentedAlert: Identifiable {
    case reset
    case error(String)

    var id: String {
        switch self {
        case .reset: "reset"
        case let .error(message): "error-\(message)"
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @AppStorage("launchDestination") private var launchDestination = AppDestination.dashboard.rawValue
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage(DashboardHistoryRetention.storageKey)
    private var historyRetentionDays = DashboardHistoryRetention.defaultValue.rawValue
    @AppStorage(AppLanguagePreference.storageKey)
    private var appLanguagePreference = AppLanguagePreference.defaultValue.rawValue
    @State private var launchAtLogin = false
    @State private var presentedSheet: SettingsPresentedSheet?
    @State private var presentedAlert: SettingsPresentedAlert?

    var isStandalone = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                settingsHeader
                usageModeSection
                settingsColumns
            }
            .padding(pageInsets)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .calmPage()
        .tint(CalmTheme.accent)
        .navigationTitle(localized("设置"))
        .onAppear {
            launchAtLogin = LaunchAtLoginController.isEnabled
            normalizeHistoryRetentionDays()
        }
        .onChange(of: historyRetentionDays) { _, days in
            let normalized = SettingsHistoryRetentionPresentation.retention(
                storedDays: days
            ).rawValue
            guard normalized == days else {
                historyRetentionDays = normalized
                return
            }
            model.updateDashboardHistoryRetentionDays(days)
        }
        .sheet(item: $presentedSheet) { sheet in
            Group {
                switch sheet {
                case .diagnostics:
                    SettingsDiagnosticsSheet()
                case .advanced:
                    SettingsAdvancedSheet()
                case .about:
                    SettingsAboutSheet()
                }
            }
            .environment(model)
            .traceHaloLanguageEnvironment()
        }
        .alert(item: $presentedAlert) { alert in
            switch alert {
            case .reset:
                Alert(
                    title: Text(localized("settings.reset.confirm.title")),
                    message: Text(localized("settings.reset.confirm.message")),
                    primaryButton: .destructive(
                        Text(localized("settings.reset.confirm.action")),
                        action: restoreDefaults
                    ),
                    secondaryButton: .cancel(
                        Text(localized("settings.reset.cancel"))
                    )
                )
            case let .error(message):
                Alert(
                    title: Text(localized("设置未更改")),
                    message: Text(message),
                    dismissButton: .default(Text(localized("知道了")))
                )
            }
        }
    }

    private var settingsHeader: some View {
        HStack(spacing: 29) {
            Image(systemName: "gearshape")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(CalmTheme.accent)
                .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text(localized("设置"))
                    .font(.system(size: 26, weight: .bold))
                Text(localized("settings.subtitle"))
                    .font(.system(size: 14))
                    .foregroundStyle(CalmTheme.secondaryText)
            }

            Spacer(minLength: 16)

            Button(localized("settings.reset")) {
                presentedAlert = .reset
            }
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(CalmTheme.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
        .padding(.bottom, isStandalone ? 7 : 0)
    }

    private var usageModeSection: some View {
        SettingsPanel(
            title: localized("settings.usage.title"),
            contentSpacing: 14,
            contentPadding: 20
        ) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    usageModeCards(minimumWidth: 210)
                }
                VStack(spacing: 10) {
                    usageModeCards(minimumWidth: 0)
                }
            }

            SettingsInlineInfo(
                symbol: "info.circle",
                text: usageModeSummary,
                color: CalmTheme.secondaryText
            )
        }
    }

    @ViewBuilder
    private func usageModeCards(minimumWidth: CGFloat) -> some View {
        ForEach(availableUsageModes) { mode in
            SettingsUsageModeCard(
                mode: mode,
                title: usageModeTitle(mode),
                subtitle: usageModeSubtitle(mode),
                symbol: usageModeSymbol(mode),
                isSelected: selectedUsageMode == mode,
                recommendedText: mode == .balanced
                    ? localized("settings.usage.recommended")
                    : nil,
                action: { applyUsageMode(mode) }
            )
            .frame(minWidth: minimumWidth, maxWidth: .infinity)
        }
    }

    private var settingsColumns: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 14) {
                    startupAndMenuBarPanel
                    displayAndLanguagePanel
                }
                .frame(minWidth: 430, maxWidth: .infinity)

                VStack(spacing: 14) {
                    privacyPanel
                    morePanel
                }
                .frame(minWidth: 430, maxWidth: .infinity)
            }

            VStack(spacing: 14) {
                startupAndMenuBarPanel
                privacyPanel
                displayAndLanguagePanel
                morePanel
            }
        }
    }

    private var startupAndMenuBarPanel: some View {
        SettingsPanel(title: localized("settings.startup.title")) {
            SettingsToggleRow(
                symbol: "menubar.rectangle",
                title: localized("settings.menuBar.title"),
                subtitle: localized("settings.menuBar.subtitle"),
                minimumHeight: 68,
                isOn: model.binding(\.showMenuBarSummary)
            )
            SettingsRowDivider()
            SettingsToggleRow(
                symbol: "person.crop.circle",
                title: localized("settings.login.title"),
                subtitle: localized("settings.login.subtitle"),
                minimumHeight: 68,
                isOn: Binding(
                    get: { launchAtLogin },
                    set: { updateLaunchAtLogin($0) }
                )
            )
        }
    }

    private var privacyPanel: some View {
        SettingsPanel(title: localized("settings.privacy.title")) {
            SettingsToggleRow(
                symbol: "list.bullet.rectangle",
                title: localized("settings.report.processNames"),
                minimumHeight: 52,
                isOn: model.binding(\.includeProcessNamesInReport)
            )
            SettingsRowDivider()
            SettingsToggleRow(
                symbol: "internaldrive",
                title: localized("settings.report.volumeNames"),
                minimumHeight: 52,
                isOn: model.binding(\.includeVolumeNamesInReport)
            )
            SettingsInlineInfo(
                symbol: "lock.fill",
                text: localized("settings.privacy.localOnly"),
                color: CalmTheme.mint
            )
        }
    }

    private var displayAndLanguagePanel: some View {
        SettingsPanel(title: localized("settings.display.title")) {
            VStack(spacing: 0) {
                SettingsSelectionRow(
                    symbol: "globe",
                    title: localized("应用语言"),
                    value: languageTitle,
                    minimumHeight: 66,
                    selection: $appLanguagePreference,
                    options: SettingsLanguagePickerPolicy.options.map { preference in
                        SettingsSelectionOption(
                            value: preference.rawValue,
                            title: SettingsLanguagePickerPolicy.title(
                                for: preference,
                                locale: locale
                            )
                        )
                    }
                )

                SettingsRowDivider()

                SettingsSelectionRow(
                    symbol: "paintbrush",
                    title: localized("外观"),
                    value: appearanceTitle,
                    minimumHeight: 66,
                    selection: $appearanceMode,
                    options: [
                        SettingsSelectionOption(value: "system", title: localized("跟随系统")),
                        SettingsSelectionOption(value: "light", title: localized("浅色")),
                        SettingsSelectionOption(value: "dark", title: localized("深色")),
                    ]
                )

                SettingsRowDivider()

                SettingsSelectionRow(
                    symbol: "thermometer.medium",
                    title: localized("温度单位"),
                    value: temperatureTitle,
                    minimumHeight: 66,
                    selection: model.binding(\.temperatureUnit),
                    options: [
                        SettingsSelectionOption(value: .celsius, title: localized("摄氏度（°C）")),
                        SettingsSelectionOption(value: .fahrenheit, title: localized("华氏度（°F）")),
                        SettingsSelectionOption(value: .kelvin, title: localized("开尔文（K）")),
                    ]
                )
            }

            if SettingsLanguagePickerPolicy.selection(
                storedValue: appLanguagePreference
            ) == AppLanguagePreference.system.rawValue {
                Text(localized("不支持的系统语言将使用英文"))
                    .font(.caption)
                    .foregroundStyle(CalmTheme.tertiaryText)
            }
        }
    }

    private var morePanel: some View {
        SettingsPanel(title: localized("settings.more.title")) {
            VStack(spacing: 0) {
                SettingsSelectionRow(
                    symbol: "rectangle.split.3x1",
                    title: localized("settings.launchDestination.title"),
                    value: launchDestinationTitle,
                    minimumHeight: 34,
                    selection: $launchDestination,
                    options: [
                        SettingsSelectionOption(
                            value: AppDestination.dashboard.rawValue,
                            title: localized("系统概览")
                        ),
                        SettingsSelectionOption(
                            value: AppDestination.monitor.rawValue,
                            title: localized("监视器")
                        ),
                        SettingsSelectionOption(value: "last", title: localized("上次页面")),
                    ]
                )
                SettingsRowDivider()
                SettingsSelectionRow(
                    symbol: "clock.arrow.circlepath",
                    title: localized("settings.historyRetention.title"),
                    value: SettingsHistoryRetentionPresentation.title(
                        retention: historyRetention,
                        locale: locale
                    ),
                    minimumHeight: 34,
                    selection: $historyRetentionDays,
                    options: DashboardHistoryRetention.allCases.map { retention in
                        SettingsSelectionOption(
                            value: retention.rawValue,
                            title: SettingsHistoryRetentionPresentation.title(
                                retention: retention,
                                locale: locale
                            )
                        )
                    }
                )
                SettingsRowDivider()
                settingsSheetButton(
                    .diagnostics,
                    symbol: "wrench.and.screwdriver",
                    title: localized("settings.diagnostics.title"),
                    minimumHeight: 34
                )
                SettingsRowDivider()
                settingsSheetButton(
                    .advanced,
                    symbol: "gearshape",
                    title: localized("settings.advanced.title"),
                    minimumHeight: 34
                )
                SettingsRowDivider()
                settingsSheetButton(
                    .about,
                    symbol: "info.circle",
                    title: localized("settings.about.title"),
                    minimumHeight: 34
                )
            }
        }
    }

    private var batteryCapability: SettingsBatteryCapability {
        SettingsUsageModePolicy.capability(
            hasLoadedSnapshot: model.hasLoadedSnapshot,
            hasBattery: PowerPresentationPolicy.isAvailable(in: model.snapshot)
        )
    }

    private var pageInsets: EdgeInsets {
        isStandalone
            ? EdgeInsets(top: 17, leading: 40, bottom: 32, trailing: 40)
            : EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24)
    }

    private var availableUsageModes: [SettingsUsageMode] {
        SettingsUsageModePolicy.availableModes(for: batteryCapability)
    }

    private var selectedUsageMode: SettingsUsageMode {
        SettingsUsageModePolicy.selection(
            refreshInterval: model.refreshInterval,
            pauseWhenOnBattery: model.pauseWhenOnBattery,
            capability: batteryCapability
        )
    }

    private var historyRetention: DashboardHistoryRetention {
        SettingsHistoryRetentionPresentation.retention(
            storedDays: historyRetentionDays
        )
    }

    private var usageModeSummary: String {
        let seconds = model.refreshInterval.formatted(
            .number.precision(.fractionLength(0...1)).locale(locale)
        )
        let key = batteryCapability != .unavailable && model.pauseWhenOnBattery
            ? "settings.usage.summary.battery"
            : "settings.usage.summary.standard"
        return String(format: localized(key), locale: locale, seconds)
    }

    private var languageTitle: String {
        let preference = AppLanguagePreference.storedPreference(
            from: appLanguagePreference
        )
        return SettingsLanguagePickerPolicy.title(for: preference, locale: locale)
    }

    private var appearanceTitle: String {
        switch appearanceMode {
        case "light": localized("浅色")
        case "dark": localized("深色")
        default: localized("跟随系统")
        }
    }

    private var temperatureTitle: String {
        switch model.temperatureUnit {
        case .celsius: localized("摄氏度（°C）")
        case .fahrenheit: localized("华氏度（°F）")
        case .kelvin: localized("开尔文（K）")
        }
    }

    private var launchDestinationTitle: String {
        switch launchDestination {
        case AppDestination.monitor.rawValue: localized("监视器")
        case "last": localized("上次页面")
        default: localized("系统概览")
        }
    }

    private func localized(_ key: String) -> String {
        ReportSettingsLocalization.text(key, locale: locale)
    }

    private func usageModeTitle(_ mode: SettingsUsageMode) -> String {
        switch mode {
        case .powerSaving: localized("settings.usage.powerSaving.title")
        case .balanced: localized("settings.usage.balanced.title")
        case .realtime: localized("settings.usage.realtime.title")
        case .custom: localized("settings.usage.custom.title")
        }
    }

    private func usageModeSubtitle(_ mode: SettingsUsageMode) -> String {
        switch mode {
        case .powerSaving: localized("settings.usage.powerSaving.subtitle")
        case .balanced: localized("settings.usage.balanced.subtitle")
        case .realtime: localized("settings.usage.realtime.subtitle")
        case .custom: localized("settings.usage.custom.subtitle")
        }
    }

    private func usageModeSymbol(_ mode: SettingsUsageMode) -> String {
        switch mode {
        case .powerSaving: "battery.75percent"
        case .balanced: "scalemass"
        case .realtime: "waveform.path.ecg"
        case .custom: "slider.horizontal.3"
        }
    }

    private func settingsSheetButton(
        _ sheet: SettingsPresentedSheet,
        symbol: String,
        title: String,
        minimumHeight: CGFloat = 34
    ) -> some View {
        Button {
            presentedSheet = sheet
        } label: {
            SettingsValueRow(
                symbol: symbol,
                title: title,
                value: nil,
                minimumHeight: minimumHeight
            )
        }
        .buttonStyle(.plain)
    }

    private func applyUsageMode(_ mode: SettingsUsageMode) {
        guard availableUsageModes.contains(mode) else { return }
        let configuration = SettingsUsageModePolicy.configuration(for: mode)
        model.refreshInterval = configuration.refreshInterval
        model.pauseWhenOnBattery = configuration.pauseWhenOnBattery
    }

    private func normalizeHistoryRetentionDays() {
        historyRetentionDays = historyRetention.rawValue
    }

    private func restoreDefaults() {
        applyUsageMode(.balanced)
        model.showMenuBarSummary = true
        model.includeProcessNamesInReport = false
        model.includeVolumeNamesInReport = false
        model.temperatureUnit = .celsius
        historyRetentionDays = DashboardHistoryRetention.defaultValue.rawValue
        launchDestination = AppDestination.dashboard.rawValue
        appearanceMode = "system"
        appLanguagePreference = AppLanguagePreference.defaultValue.rawValue

        guard LaunchAtLoginController.isEnabled else {
            launchAtLogin = false
            return
        }
        updateLaunchAtLogin(false)
    }

    @MainActor
    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginController.setEnabled(enabled)
            launchAtLogin = LaunchAtLoginController.isEnabled
        } catch {
            launchAtLogin = LaunchAtLoginController.isEnabled
            presentedAlert = .error(error.localizedDescription)
        }
    }
}

private struct SettingsUsageModeCard: View {
    let mode: SettingsUsageMode
    let title: String
    let subtitle: String
    let symbol: String
    let isSelected: Bool
    let recommendedText: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(isSelected ? CalmTheme.accent : CalmTheme.secondaryText)
                    .frame(height: 42)

                HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    if let recommendedText {
                        Text(recommendedText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CalmTheme.mint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                CalmTheme.mint.opacity(0.13),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                    }
                }

                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(CalmTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 179)
            .padding(.horizontal, 12)
            .background(
                isSelected ? CalmTheme.accent.opacity(0.075) : CalmTheme.surfaceRaised,
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        isSelected ? CalmTheme.accent : CalmTheme.strongHairline,
                        lineWidth: isSelected ? 1.4 : 0.8
                    )
            }
            .overlay(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(isSelected ? CalmTheme.accent : .clear)
                    Circle()
                        .strokeBorder(
                            isSelected ? CalmTheme.accent : CalmTheme.tertiaryText,
                            lineWidth: 1.3
                        )
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 22, height: 22)
                .padding(13)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SettingsPanel<Content: View>: View {
    let title: String
    let contentSpacing: CGFloat
    let contentPadding: CGFloat
    let content: Content

    init(
        title: String,
        contentSpacing: CGFloat = 10,
        contentPadding: CGFloat = 14,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.contentSpacing = contentSpacing
        self.contentPadding = contentPadding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            Text(title)
                .font(.system(size: 16.5, weight: .semibold))
            content
        }
        .padding(contentPadding)
        .background(
            CalmTheme.surface.opacity(0.92),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(CalmTheme.hairline, lineWidth: 0.8)
        }
    }
}

private struct SettingsToggleRow: View {
    let symbol: String
    let title: String
    var subtitle: String?
    let minimumHeight: CGFloat
    @Binding var isOn: Bool

    init(
        symbol: String,
        title: String,
        subtitle: String? = nil,
        minimumHeight: CGFloat = 42,
        isOn: Binding<Bool>
    ) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.minimumHeight = minimumHeight
        _isOn = isOn
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(CalmTheme.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15.5, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13.5))
                        .foregroundStyle(CalmTheme.secondaryText)
                }
            }

            Spacer(minLength: 10)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(CalmTheme.accent)
        }
        .frame(minHeight: minimumHeight)
    }
}

private struct SettingsValueRow: View {
    let symbol: String
    let title: String
    let value: String?
    var minimumHeight: CGFloat = 34

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(CalmTheme.accent)
                .frame(width: 28)

            Text(title)
                .font(.system(size: 15.5, weight: .medium))
                .foregroundStyle(CalmTheme.primaryText)
                .lineLimit(1)

            Spacer(minLength: 12)

            if let value {
                Text(value)
                    .font(.system(size: 15))
                    .foregroundStyle(CalmTheme.secondaryText)
                    .lineLimit(1)
                    .layoutPriority(2)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CalmTheme.tertiaryText)
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .leading)
    }
}

private struct SettingsSelectionOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String

    var id: Value { value }
}

/// A visible button owns the entire hit target and presents a conventional
/// list of options. Avoiding a transparent `Menu` overlay keeps real mouse,
/// keyboard, and accessibility activation on the same control.
private struct SettingsSelectionRow<Value: Hashable>: View {
    @Environment(\.locale) private var locale
    let symbol: String
    let title: String
    let value: String
    let minimumHeight: CGFloat
    @Binding var selection: Value
    let options: [SettingsSelectionOption<Value>]
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            SettingsValueRow(
                symbol: symbol,
                title: title,
                value: value,
                minimumHeight: minimumHeight
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: minimumHeight)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityHint(ReportSettingsLocalization.text(
            "settings.selection.hint",
            locale: locale
        ))
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(CalmTheme.primaryText)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)

                ForEach(options) { option in
                    Button {
                        selection = option.value
                        isPresented = false
                    } label: {
                        HStack(spacing: 12) {
                            Text(option.title)
                                .foregroundStyle(CalmTheme.primaryText)
                            Spacer(minLength: 24)
                            if selection == option.value {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(CalmTheme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal, 10)
                        .frame(minHeight: 34)
                        .background(
                            selection == option.value
                                ? CalmTheme.accent.opacity(0.12)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(
                        selection == option.value
                            ? ReportSettingsLocalization.text(
                                "settings.selection.selected",
                                locale: locale
                            )
                            : ""
                    )
                }
            }
            .padding(10)
            .frame(minWidth: 260)
            .calmPage()
        }
    }
}

private struct SettingsRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(CalmTheme.hairline)
            .frame(height: 1)
    }
}

private struct SettingsInlineInfo: View {
    let symbol: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
        .background(
            color.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(color.opacity(0.35), lineWidth: 0.8)
        }
    }
}

private struct SettingsDetailContainer<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let title: String
    let symbol: String
    let content: Content

    init(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: symbol)
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(CalmTheme.accent)
                        Text(title)
                            .font(.title2.weight(.bold))
                    }
                    content
                }
                .padding(22)
            }
            .calmPage()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("settings.done")) { dismiss() }
                }
            }
        }
        .frame(width: 560, height: 430)
    }

    private func localized(_ key: String) -> String {
        ReportSettingsLocalization.text(key, locale: locale)
    }
}

private struct SettingsDiagnosticsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale

    var body: some View {
        SettingsDetailContainer(
            title: localized("settings.diagnostics.title"),
            symbol: "wrench.and.screwdriver"
        ) {
            SettingsPanel(title: localized("settings.diagnostics.data.title")) {
                sheetRow(
                    localized("settings.diagnostics.source"),
                    ReportSettingsLocalization.dataSourceTitle(model.dataSource, locale: locale)
                )
                SettingsRowDivider()
                sheetRow(
                    localized("settings.diagnostics.snapshot"),
                    model.hasLoadedSnapshot
                        ? localized("settings.diagnostics.loaded")
                        : localized("settings.diagnostics.loading")
                )
                SettingsRowDivider()
                sheetRow(
                    localized("settings.diagnostics.updated"),
                    ReportSettingsLocalization.updateTimestamp(
                        model.snapshot.capturedAt,
                        locale: locale
                    )
                )
                SettingsRowDivider()
                sheetRow(
                    localized("settings.diagnostics.battery"),
                    batteryStatus
                )
            }

            Button {
                Task { await model.refreshAll() }
            } label: {
                Label(
                    model.isRefreshing
                        ? localized("settings.diagnostics.refreshing")
                        : localized("settings.diagnostics.refresh"),
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(CalmButtonStyle(prominent: true))
            .disabled(model.isRefreshing)
        }
    }

    private var batteryStatus: String {
        guard model.hasLoadedSnapshot else {
            return localized("settings.diagnostics.loading")
        }
        return PowerPresentationPolicy.isAvailable(in: model.snapshot)
            ? localized("settings.diagnostics.available")
            : localized("settings.diagnostics.unavailable")
    }

    private func sheetRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer(minLength: 16)
            Text(value)
                .foregroundStyle(CalmTheme.secondaryText)
                .multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }

    private func localized(_ key: String) -> String {
        ReportSettingsLocalization.text(key, locale: locale)
    }
}

private struct SettingsAdvancedSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale

    var body: some View {
        SettingsDetailContainer(
            title: localized("settings.advanced.title"),
            symbol: "gearshape"
        ) {
            SettingsPanel(title: localized("settings.advanced.sampling.title")) {
                Picker(
                    localized("settings.advanced.refreshInterval"),
                    selection: model.binding(\.refreshInterval)
                ) {
                    Text(localized("1 秒")).tag(1.0)
                    Text(localized("2 秒")).tag(2.0)
                    Text(localized("5 秒")).tag(5.0)
                    Text(localized("10 秒")).tag(10.0)
                }
                .pickerStyle(.menu)

                if showsBatteryOptions {
                    SettingsRowDivider()
                    Toggle(
                        localized("settings.advanced.batteryThrottle"),
                        isOn: model.binding(\.pauseWhenOnBattery)
                    )
                    .toggleStyle(.switch)
                }
            }

            SettingsInlineInfo(
                symbol: "info.circle",
                text: localized("settings.advanced.description"),
                color: CalmTheme.secondaryText
            )
        }
    }

    private var showsBatteryOptions: Bool {
        !model.hasLoadedSnapshot
            || PowerPresentationPolicy.isAvailable(in: model.snapshot)
    }

    private func localized(_ key: String) -> String {
        ReportSettingsLocalization.text(key, locale: locale)
    }
}

private struct SettingsAboutSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale

    var body: some View {
        SettingsDetailContainer(
            title: localized("settings.about.title"),
            symbol: "info.circle"
        ) {
            SettingsPanel(title: "TraceHalo") {
                aboutRow(localized("settings.about.version"), version)
                SettingsRowDivider()
                aboutRow(localized("settings.about.build"), build)
                SettingsRowDivider()
                aboutRow(
                    localized("settings.about.dataSource"),
                    ReportSettingsLocalization.dataSourceTitle(model.dataSource, locale: locale)
                )
                SettingsRowDivider()
                aboutRow(
                    localized("运行模式"),
                    ReportSettingsLocalization.runtimeModeTitle(
                        isSafeTest: RuntimeSafetyMode.current == .safeTest,
                        locale: locale
                    )
                )
            }

            Text(localized("settings.about.description"))
                .font(.callout)
                .foregroundStyle(CalmTheme.secondaryText)
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "—"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "—"
    }

    private func aboutRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: 16)
            Text(value)
                .foregroundStyle(CalmTheme.secondaryText)
        }
        .font(.callout)
    }

    private func localized(_ key: String) -> String {
        ReportSettingsLocalization.text(key, locale: locale)
    }
}

enum SettingsLanguagePickerPolicy {
    static let options: [AppLanguagePreference] = [
        .system,
        .english,
        .simplifiedChinese
    ]

    static func selection(storedValue: String) -> String {
        AppLanguagePreference.storedPreference(from: storedValue).rawValue
    }

    static func title(
        for preference: AppLanguagePreference,
        locale: Locale
    ) -> String {
        switch preference {
        case .system:
            AppLocalization.string("跟随系统", defaultValue: "跟随系统", locale: locale)
        case .english:
            AppLocalization.string("English", defaultValue: "English", locale: locale)
        case .simplifiedChinese:
            AppLocalization.string("简体中文", defaultValue: "简体中文", locale: locale)
        }
    }
}
