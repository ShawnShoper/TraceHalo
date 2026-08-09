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

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @AppStorage("launchDestination") private var launchDestination = AppDestination.dashboard.rawValue
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage(AppLanguagePreference.storageKey)
    private var appLanguagePreference = AppLanguagePreference.defaultValue.rawValue
    @State private var launchAtLogin = false
    @State private var settingsMessage: String?

    var isStandalone = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !isStandalone {
                    PageHeader(
                        title: localized("设置"),
                        subtitle: localized("调整采样、显示、菜单栏和隐私偏好"),
                        symbol: "gearshape"
                    )
                } else {
                    Text(localized("TraceHalo 设置"))
                        .font(.title2.weight(.semibold))
                }

                settingsSection(localized("监测"), symbol: "waveform.path.ecg") {
                    Toggle(
                        localized("在菜单栏显示摘要"),
                        isOn: model.binding(\.showMenuBarSummary)
                    )
                    settingsDivider
                    Toggle(
                        localized("登录时启动 TraceHalo"),
                        isOn: Binding(
                            get: { launchAtLogin },
                            set: { updateLaunchAtLogin($0) }
                        )
                    )
                    settingsDivider
                    Picker(localized("刷新间隔"), selection: model.binding(\.refreshInterval)) {
                        Text(localized("1 秒")).tag(1.0)
                        Text(localized("2 秒")).tag(2.0)
                        Text(localized("5 秒")).tag(5.0)
                        Text(localized("10 秒")).tag(10.0)
                    }
                    .pickerStyle(.menu)
                    settingsDivider
                    Toggle(
                        localized("使用电池供电时降低采样频率"),
                        isOn: model.binding(\.pauseWhenOnBattery)
                    )
                }

                settingsSection(localized("显示"), symbol: "paintbrush") {
                    Picker(
                        localized("应用语言"),
                        selection: Binding(
                            get: {
                                SettingsLanguagePickerPolicy.selection(
                                    storedValue: appLanguagePreference
                                )
                            },
                            set: { appLanguagePreference = $0 }
                        )
                    ) {
                        ForEach(SettingsLanguagePickerPolicy.options, id: \.rawValue) { preference in
                            languageOption(preference)
                                .tag(preference.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    if SettingsLanguagePickerPolicy.selection(
                        storedValue: appLanguagePreference
                    ) == AppLanguagePreference.system.rawValue {
                        Text(localized("不支持的系统语言将使用英文"))
                            .font(.caption)
                            .foregroundStyle(CalmTheme.secondaryText)
                    }
                    settingsDivider
                    Picker(localized("外观"), selection: $appearanceMode) {
                        Text(localized("跟随系统")).tag("system")
                        Text(localized("浅色")).tag("light")
                        Text(localized("深色")).tag("dark")
                    }
                    .pickerStyle(.menu)
                    settingsDivider
                    Picker(localized("温度单位"), selection: model.binding(\.temperatureUnit)) {
                        Text(localized("摄氏度（°C）")).tag(TemperatureUnit.celsius)
                        Text(localized("华氏度（°F）")).tag(TemperatureUnit.fahrenheit)
                        Text(localized("开尔文（K）")).tag(TemperatureUnit.kelvin)
                    }
                    .pickerStyle(.menu)
                    settingsDivider
                    Picker(localized("打开时显示"), selection: $launchDestination) {
                        Text(localized("系统概览")).tag(AppDestination.dashboard.rawValue)
                        Text(localized("监视器")).tag(AppDestination.monitor.rawValue)
                        Text(localized("上次页面")).tag("last")
                    }
                    .pickerStyle(.menu)
                }

                settingsSection(localized("报告与隐私"), symbol: "hand.raised") {
                    Toggle(
                        localized("在报告中包含进程名称"),
                        isOn: model.binding(\.includeProcessNamesInReport)
                    )
                    settingsDivider
                    Toggle(
                        localized("在报告中包含卷名称"),
                        isOn: model.binding(\.includeVolumeNamesInReport)
                    )
                    settingsDivider
                    LabeledContent(localized("敏感标识")) {
                        Text(localized("默认隐藏"))
                            .foregroundStyle(CalmTheme.secondaryText)
                    }
                    settingsDivider
                    LabeledContent(localized("数据处理")) {
                        Text(localized("仅在本机"))
                            .foregroundStyle(CalmTheme.secondaryText)
                    }
                }

                settingsSection(localized("数据状态"), symbol: "cylinder") {
                    LabeledContent(localized("当前来源")) {
                        StatusPill(
                            text: ReportSettingsLocalization.dataSourceTitle(
                                model.dataSource,
                                locale: locale
                            ),
                            color: model.dataSource == .live ? CalmTheme.mint : CalmTheme.cyan
                        )
                    }
                    settingsDivider
                    LabeledContent(localized("上次更新")) {
                        Text(
                            ReportSettingsLocalization.updateTimestamp(
                                model.snapshot.capturedAt,
                                locale: locale
                            )
                        )
                        .foregroundStyle(CalmTheme.secondaryText)
                    }
                    settingsDivider
                    HStack {
                        Text(localized("刷新实时状态"))
                        Spacer()
                        Button(localized("刷新")) { Task { await model.refreshAll() } }
                            .buttonStyle(CalmButtonStyle())
                            .disabled(model.isRefreshing)
                    }
                }

                settingsSection(localized("关于"), symbol: "info.circle") {
                    LabeledContent(localized("应用")) {
                        Text("TraceHalo — System Monitor for Mac")
                    }
                    settingsDivider
                    LabeledContent(localized("运行模式")) {
                        Text(
                            ReportSettingsLocalization.runtimeModeTitle(
                                isSafeTest: RuntimeSafetyMode.current == .safeTest,
                                locale: locale
                            )
                        )
                    }
                    settingsDivider
                    Text(localized("一款原创 macOS 系统状态工具。界面和数据层分离，可在演示数据与本机只读服务之间切换。"))
                        .font(.caption)
                        .foregroundStyle(CalmTheme.secondaryText)
                }
            }
            .padding(isStandalone ? 20 : 24)
            .frame(maxWidth: 850, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .calmPage()
        .navigationTitle(localized("设置"))
        .onAppear { launchAtLogin = LaunchAtLoginController.isEnabled }
        .alert(
            localized("设置未更改"),
            isPresented: Binding(
                get: { settingsMessage != nil },
                set: { if !$0 { settingsMessage = nil } }
            )
        ) {
            Button(localized("知道了")) { settingsMessage = nil }
        } message: {
            Text(settingsMessage ?? "")
        }
    }

    private var settingsDivider: some View {
        CalmDivider()
            .padding(.vertical, 4)
    }

    private func localized(_ key: String) -> String {
        ReportSettingsLocalization.text(key, locale: locale)
    }

    @ViewBuilder
    private func languageOption(_ preference: AppLanguagePreference) -> some View {
        Text(SettingsLanguagePickerPolicy.title(for: preference, locale: locale))
    }

    private func settingsSection<Content: View>(
        _ title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: title, symbol: symbol)
            content()
        }
        .calmCard()
    }

    @MainActor
    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginController.setEnabled(enabled)
            launchAtLogin = LaunchAtLoginController.isEnabled
        } catch {
            launchAtLogin = LaunchAtLoginController.isEnabled
            settingsMessage = error.localizedDescription
        }
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
