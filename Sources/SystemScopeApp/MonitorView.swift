import SwiftUI
import SystemScopeCore

private func monitorModuleToggleBinding(
    _ module: MonitorModule,
    configuration: Binding<MonitorConfiguration>
) -> Binding<Bool> {
    Binding(
        get: { configuration.wrappedValue.isModuleEnabled(module) },
        set: { isEnabled in
            var updatedConfiguration = configuration.wrappedValue
            guard isEnabled || updatedConfiguration.enabledModules.count > 1 else { return }
            updatedConfiguration.setModule(module, isEnabled: isEnabled)
            configuration.wrappedValue = updatedConfiguration
        }
    )
}

enum MonitorConfigurationTab: String, CaseIterable, Identifiable {
    case modules
    case statusBar
    case quickItems

    var id: String { rawValue }

    /// Source-language compatibility used by existing pure layout tests and
    /// persisted diagnostics. UI presentation must call `localizedTitle`.
    var title: String {
        switch self {
        case .modules: "模块"
        case .statusBar: "状态区"
        case .quickItems: "快捷入口"
        }
    }

    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .modules:
            MenuMonitorLocalization.string("模块", english: "Modules", locale: locale)
        case .statusBar:
            MenuMonitorLocalization.string("状态区", english: "Status Area", locale: locale)
        case .quickItems:
            MenuMonitorLocalization.string("快捷入口", english: "Quick Actions", locale: locale)
        }
    }
}

enum MonitorWorkspaceLayout {
    static let minimumConfigurationWidth: CGFloat = 440
    static let preferredConfigurationWidth: CGFloat = 634
    static let minimumPreviewWidth: CGFloat = 593
    static let referenceContentWidth: CGFloat = 1_394

    static func configurationWidth(totalWidth: CGFloat) -> CGFloat {
        let proportional = totalWidth * (preferredConfigurationWidth / referenceContentWidth)
        let previewSafeMaximum = max(totalWidth - minimumPreviewWidth - 1, minimumConfigurationWidth)
        return min(max(proportional, minimumConfigurationWidth), previewSafeMaximum)
    }
}

struct MonitorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @State private var showsAdvancedStatusConfiguration = false
    @State private var selectedTab: MonitorConfigurationTab = .modules
    @State private var selectedModule: MonitorModule = .cpuAndGPU
    @State private var selectedPreviewSection: MenuBarDashboardSection? = .cpu

    var body: some View {
        GeometryReader { proxy in
            let configurationWidth = MonitorWorkspaceLayout.configurationWidth(
                totalWidth: proxy.size.width
            )

            HStack(spacing: 0) {
                configurationPane
                    .frame(width: configurationWidth)

                Rectangle()
                    .fill(CalmTheme.hairline)
                    .frame(width: 1)

                previewPane(availableHeight: proxy.size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .calmPage()
        .navigationTitle(text("监视器", "Monitor"))
        .onAppear {
            normalizePreviewSelection()
        }
        .onChange(of: model.monitorConfiguration.enabledModules) { _, _ in
            normalizePreviewSelection()
        }
        .onChange(of: PowerPresentationPolicy.isAvailable(in: model.snapshot)) { _, _ in
            normalizePreviewSelection()
        }
    }

    private var configurationPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                monitorHeader
                monitorStatusCard
                configurationTabs

                switch selectedTab {
                case .modules:
                    monitorModulesCard
                case .statusBar:
                    statusBarLayoutCard
                case .quickItems:
                    quickItemsCard
                }
            }
            .padding(.leading, 20)
            .padding(.trailing, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.never)
        .background(CalmTheme.canvas.opacity(0.36))
    }

    private var monitorHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(text("菜单栏监视器", "Menu Bar Monitor"))
                    .font(.system(size: 20, weight: .semibold))
                Text(text(
                    "按模块选择想看的内容，菜单栏会立即同步更新",
                    "Choose modules to show. The menu bar updates immediately."
                ))
                    .font(.system(size: 12))
                    .foregroundStyle(CalmTheme.secondaryText)
            }

            Spacer(minLength: 12)

            Button {
                selectedTab = .modules
                normalizePreviewSelection()
            } label: {
                Label(text("配置与预览", "Configure & Preview"), systemImage: "rectangle.3.group")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(CalmButtonStyle(prominent: true))
        }
        .frame(minHeight: 48, alignment: .top)
    }

    private var configurationTabs: some View {
        HStack(spacing: 0) {
            ForEach(MonitorConfigurationTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.localizedTitle(locale: locale))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(
                            selectedTab == tab ? Color.white : CalmTheme.secondaryText
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    selectedTab == tab ? CalmTheme.primaryAction : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            }
        }
        .frame(height: 46)
        .padding(4)
        .background(CalmTheme.controlBackground.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(CalmTheme.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text("配置类别", "Configuration category"))
    }

    private func previewPane(availableHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "eye")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CalmTheme.accent)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 3) {
                    Text(text("实时预览", "Live Preview"))
                        .font(.system(size: 15, weight: .semibold))
                    Text(text(
                        "这是菜单栏窗口的真实布局；点击卡片可查看对应详情",
                        "This is the actual menu window layout. Select a card to see its details."
                    ))
                        .font(.system(size: 11.5))
                        .foregroundStyle(CalmTheme.secondaryText)
                }

                Spacer(minLength: 12)

                HStack(spacing: 7) {
                    Circle()
                        .fill(model.hasLoadedSnapshot ? CalmTheme.mint : CalmTheme.amber)
                        .frame(width: 7, height: 7)
                    Text(model.hasLoadedSnapshot
                        ? text("数据持续刷新", "Live data updating")
                        : text("正在读取数据", "Loading data"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CalmTheme.secondaryText)
                }
                .padding(.top, 4)
            }

            previewSummaryStrip

            GeometryReader { proxy in
                let previewScale = min(max(proxy.size.width / 552, 0.9), 1.285)
                let viewportHeight = min(max(availableHeight - 148, 450), 760)
                let dashboardColumnHeight = min(
                    max(
                        viewportHeight / previewScale - (MenuBarDashboardLayout.verticalChrome * 2),
                        MenuBarDashboardLayout.minimumColumnHeight
                    ),
                    MenuBarDashboardLayout.maximumColumnHeight
                )
                let scaledWidth = MenuBarDashboardLayout.expandedContentWidth * previewScale
                let scaledHeight = (
                    dashboardColumnHeight + (MenuBarDashboardLayout.verticalChrome * 2)
                ) * previewScale
                let horizontalInset = max((proxy.size.width - scaledWidth) / 2, 0)

                ScrollView(.vertical, showsIndicators: false) {
                    MenuBarDashboardView(
                        initialSection: selectedPreviewSection,
                        maximumColumnHeightOverride: dashboardColumnHeight,
                        showsQuickLaunchFooter: false,
                        resetsSelectionOnPopoverClose: false,
                        presentationMode: .embeddedPreview,
                        onSelectionChange: handlePreviewSelection
                    )
                    .environment(model)
                    .scaleEffect(previewScale, anchor: .topLeading)
                    .frame(width: scaledWidth, height: scaledHeight, alignment: .topLeading)
                    .padding(.horizontal, horizontalInset)
                    .padding(.bottom, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.top, -10)
        }
        .padding(.leading, 22)
        .padding(.trailing, 29)
        .padding(.vertical, 18)
        .background(CalmTheme.canvasElevated.opacity(0.26))
    }

    private var previewSummaryStrip: some View {
        HStack(spacing: 12) {
            Image(systemName: selectedModule.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(selectedModule.tint)
                .frame(width: 24, height: 24)

            Text(selectedModule.localizedTitle(locale: locale))
                .font(.system(size: 13, weight: .semibold))

            Text(selectedModule.localizedSummary(locale: locale))
                .font(.system(size: 11))
                .foregroundStyle(CalmTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(CalmTheme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(CalmTheme.hairline)
        }
    }

    private func selectModule(_ module: MonitorModule) {
        selectedModule = module
        if model.monitorConfiguration.isModuleEnabled(module) {
            selectedPreviewSection = .previewSection(for: module)
        }
    }

    private func handlePreviewSelection(_ section: MenuBarDashboardSection?) {
        guard let section else { return }
        selectedPreviewSection = section
        selectedModule = section.module
    }

    private func normalizePreviewSelection() {
        let visibleSections = MenuBarDashboardSection.visibleSections(
            in: model.monitorConfiguration,
            snapshot: model.snapshot
        )
        if let selectedPreviewSection,
           visibleSections.contains(selectedPreviewSection) {
            selectedModule = selectedPreviewSection.module
            return
        }
        let section = visibleSections.first
        selectedPreviewSection = section
        if let section {
            selectedModule = section.module
        }
    }

    private func moduleBinding(_ module: MonitorModule) -> Binding<Bool> {
        let binding = monitorModuleToggleBinding(
            module,
            configuration: model.binding(\.monitorConfiguration)
        )
        return Binding(
            get: { binding.wrappedValue },
            set: { isEnabled in
                let previous = binding.wrappedValue
                binding.wrappedValue = isEnabled
                guard previous != binding.wrappedValue else { return }
                if isEnabled {
                    selectModule(module)
                } else {
                    normalizePreviewSelection()
                }
            }
        )
    }

    private var monitorStatusCard: some View {
        let refreshSeconds = Int(model.refreshInterval)
        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CalmTheme.mint.opacity(0.1))
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(CalmTheme.mint)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(model.showMenuBarSummary
                        ? text("监视器正在显示", "Monitor is visible")
                        : text("监视器已隐藏", "Monitor is hidden"))
                        .font(.headline)
                    StatusPill(
                        text: model.showMenuBarSummary
                            ? text("运行中", "Running")
                            : text("已暂停", "Paused"),
                        color: model.showMenuBarSummary ? CalmTheme.mint : .secondary
                    )
                }
                Text(pluralFormat(
                    count: refreshSeconds,
                    oneKey: "monitor.refresh.description.one",
                    otherKey: "monitor.refresh.description.other",
                    oneDefaultValue: "每 %lld 秒读取一次状态；当前使用%@。",
                    otherDefaultValue: "每 %lld 秒读取一次状态；当前使用%@。",
                    Int64(model.refreshInterval),
                    localizedDataSourceTitle
                ))
                    .font(.system(size: 11.5))
                    .foregroundStyle(CalmTheme.secondaryText)
            }

            Spacer()

            Toggle(text("显示在菜单栏", "Show in Menu Bar"), isOn: model.binding(\.showMenuBarSummary))
                .toggleStyle(.switch)
        }
        .calmCard(padding: 14)
    }

    private var monitorModulesCard: some View {
        let modules = MonitorModule.presentableCases(in: model.snapshot)
        return VStack(alignment: .leading, spacing: 10) {
            Text(text("选择要在菜单栏显示的模块", "Choose modules to show in the menu window"))
                .font(.system(size: 12))
                .foregroundStyle(CalmTheme.secondaryText)

            VStack(spacing: 0) {
                ForEach(modules) { module in
                    moduleToggleRow(module)
                    if module != modules.last {
                        CalmDivider()
                            .padding(.leading, 50)
                    }
                }
            }
            .calmCard(padding: 0)
        }
    }

    private func moduleToggleRow(_ module: MonitorModule) -> some View {
        let isEnabled = model.monitorConfiguration.isModuleEnabled(module)
        let enabledPresentableModules = MonitorModule.presentableCases(in: model.snapshot)
            .filter(model.monitorConfiguration.isModuleEnabled)
        let isLastEnabled = isEnabled && enabledPresentableModules.count == 1

        return HStack(spacing: 12) {
            Button {
                selectModule(module)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: module.symbol)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(module.tint)
                        .frame(width: 34, height: 34)
                        .background(module.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(module.localizedTitle(locale: locale))
                            .font(.system(size: 13, weight: .semibold))
                        Text(module.localizedSummary(locale: locale))
                            .font(.system(size: 10.5))
                            .foregroundStyle(CalmTheme.secondaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle(
                format(
                    "显示 %@",
                    "Show %@",
                    module.localizedTitle(locale: locale)
                ),
                isOn: moduleBinding(module)
            )
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(CalmTheme.accent)
                .disabled(isLastEnabled)
                .help(isLastEnabled
                    ? text("至少保留一个实时监控模块", "Keep at least one monitoring module enabled")
                    : format(
                        "在菜单栏窗口中显示 %@",
                        "Show %@ in the menu window",
                        module.localizedTitle(locale: locale)
                    ))
        }
        .padding(.horizontal, 14)
        .frame(height: 62)
        .background(selectedModule == module ? module.tint.opacity(0.055) : Color.clear)
        .opacity(isEnabled ? 1 : 0.72)
    }

    private var statusBarLayoutCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                SectionTitle(
                    title: text("菜单栏状态区", "Menu Bar Status Area"),
                    subtitle: text(
                        "参考 Sensei 的紧凑信息布局，可实时预览并自由定制",
                        "Preview and customize a compact status layout inspired by Sensei"
                    ),
                    symbol: "menubar.rectangle"
                )
                Spacer()
                statusBarModePicker(width: 230)
            }

            statusBarPreview

            HStack(spacing: 14) {
                Toggle(
                    text("显示 TraceHalo 标记", "Show TraceHalo Mark"),
                    isOn: model.binding(\.monitorConfiguration).showsStatusBarIcon
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(model.monitorConfiguration.statusBarLayoutMode == .iconOnly)

                Spacer()

                Label(
                    format(
                        "预计占用约 %lld pt",
                        "Estimated width: about %lld pt",
                        Int64(estimatedStatusBarWidth)
                    ),
                    systemImage: estimatedStatusBarWidth > 280 ? "exclamationmark.triangle" : "ruler"
                )
                .font(.caption)
                .foregroundStyle(estimatedStatusBarWidth > 280 ? CalmTheme.amber : CalmTheme.secondaryText)
            }

            CalmDivider()

            DisclosureGroup(isExpanded: $showsAdvancedStatusConfiguration) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(text(
                        "需要精确调整菜单栏短标签、数据和样式时再使用这里；普通使用保持推荐布局即可。",
                        "Use these controls only when you need precise labels, metrics, or styles. The recommended layout works for most people."
                    ))
                        .font(.caption)
                        .foregroundStyle(CalmTheme.secondaryText)

                    HStack(spacing: 10) {
                        Text(text("显示", "Show")).frame(width: 34, alignment: .leading)
                        Text(text("标签", "Label")).frame(width: 72, alignment: .leading)
                        Text(text("显示内容", "Metric")).frame(width: 190, alignment: .leading)
                        Text(text("样式", "Style")).frame(width: 105, alignment: .leading)
                        Spacer()
                        Text(text("顺序", "Order")).frame(width: 68, alignment: .center)
                        Text(text("移除", "Remove")).frame(width: 34, alignment: .center)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CalmTheme.secondaryText)

                    ForEach(presentableStatusBarComponentIndices, id: \.self) { index in
                        statusBarComponentRow(at: index)
                        if index != presentableStatusBarComponentIndices.last {
                            CalmDivider()
                        }
                    }

                    CalmDivider()

                    HStack {
                        Menu {
                            ForEach(presentableMonitorMetrics) { metric in
                                Button {
                                    addStatusBarComponent(metric)
                                } label: {
                                    Text(metric.localizedTitle(locale: locale))
                                }
                            }
                        } label: {
                            Label(text("添加显示内容", "Add Metric"), systemImage: "plus")
                        }
                        .menuStyle(.borderlessButton)
                        .disabled(model.monitorConfiguration.statusBarComponents.count >= 8)

                        Spacer()

                        Button(text("恢复推荐布局", "Restore Recommended Layout")) {
                            restoreSenseiStatusBarLayout()
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.top, 10)
            } label: {
                let visibleCount = presentableStatusBarComponentIndices.filter {
                    model.monitorConfiguration.statusBarComponents[$0].isVisible
                }.count
                HStack {
                    Label(text("高级自定义（可选）", "Advanced Customization (Optional)"), systemImage: "slider.horizontal.3")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text(pluralFormat(
                        count: visibleCount,
                        oneKey: "monitor.visible.count.one",
                        otherKey: "monitor.visible.count.other",
                        oneDefaultValue: "当前显示 %lld 项",
                        otherDefaultValue: "当前显示 %lld 项",
                        Int64(visibleCount)
                    ))
                        .font(.caption)
                        .foregroundStyle(CalmTheme.secondaryText)
                }
            }
            .tint(CalmTheme.primaryText)
        }
        .calmCard()
    }

    private var statusBarPreview: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(text("实时预览", "Live Preview"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CalmTheme.secondaryText)
                Spacer()
                Text(text("真实菜单栏尺寸", "Actual menu bar size"))
                    .font(.caption2)
                    .foregroundStyle(CalmTheme.tertiaryText)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                MenuBarStatusStrip()
                    .environment(model)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(CalmTheme.hairline, lineWidth: 0.75)
            }
        }
        .padding(12)
        .background(CalmTheme.controlBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
    }

    private func statusBarModePicker(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(MonitorStatusBarLayoutMode.allCases, id: \.self) { mode in
                Button {
                    model.monitorConfiguration.statusBarLayoutMode = mode
                } label: {
                    Text(modeTitle(mode))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(
                            model.monitorConfiguration.statusBarLayoutMode == mode
                                ? Color.white
                                : CalmTheme.secondaryText
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    model.monitorConfiguration.statusBarLayoutMode == mode
                        ? CalmTheme.primaryAction
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
            }
        }
        .frame(width: width, height: 28)
        .padding(2)
        .background(CalmTheme.controlBackground.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(CalmTheme.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text("菜单栏显示模式", "Menu bar display mode"))
    }

    private func modeTitle(_ mode: MonitorStatusBarLayoutMode) -> String {
        switch mode {
        case .full: text("完整", "Full")
        case .compact: text("精简", "Compact")
        case .iconOnly: text("仅图标", "Icon Only")
        }
    }

    private func statusBarComponentRow(at index: Int) -> some View {
        let configuration = model.binding(\.monitorConfiguration)
        let component = configuration.statusBarComponents[index]
        let displayTitle = component.wrappedValue.localizedDisplayTitle(locale: locale)
        return HStack(spacing: 10) {
            Toggle(
                format("显示 %@", "Show %@", displayTitle),
                isOn: component.isVisible
            )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel(format(
                    "在菜单栏显示 %@",
                    "Show %@ in the menu bar",
                    displayTitle
                ))

            TextField(text("标题", "Label"), text: component.title)
                .textFieldStyle(.plain)
                .font(.callout.weight(.medium))
                .frame(width: 72)

            Picker(text("指标", "Metric"), selection: component.metric) {
                ForEach(presentableMetrics(including: component.wrappedValue.metric)) { metric in
                    Text(metric.localizedTitle(locale: locale)).tag(metric)
                }
            }
            .labelsHidden()
            .frame(width: 190)

            Picker(text("样式", "Style"), selection: component.style) {
                Text(text("数值", "Value")).tag(MonitorStatusBarComponentStyle.value)
                Text(text("迷你图", "Mini Chart")).tag(MonitorStatusBarComponentStyle.miniChart)
                Text(text("量表", "Gauge")).tag(MonitorStatusBarComponentStyle.verticalGaugeValue)
            }
            .labelsHidden()
            .frame(width: 105)

            Spacer()

            reorderButtons(index: index, count: model.monitorConfiguration.statusBarComponents.count) {
                model.monitorConfiguration.statusBarComponents.swapAt(index, index - 1)
            } moveDown: {
                model.monitorConfiguration.statusBarComponents.swapAt(index, index + 1)
            }
            .frame(width: 68)

            Button {
                model.monitorConfiguration.statusBarComponents.remove(at: index)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(CalmTheme.secondaryText)
            .frame(width: 34)
            .disabled(model.monitorConfiguration.statusBarComponents.count <= 1)
            .help(text("移除该菜单栏指标", "Remove this menu bar metric"))
            .accessibilityLabel(format(
                "移除 %@",
                "Remove %@",
                displayTitle
            ))
        }
    }

    private var estimatedStatusBarWidth: Int {
        var configuration = model.monitorConfiguration
        configuration.statusBarComponents = presentableStatusBarComponentIndices.map {
            model.monitorConfiguration.statusBarComponents[$0]
        }
        return Int(MenuBarStatusLayout.estimatedStatusItemWidth(for: configuration))
    }

    private var presentableMonitorMetrics: [MonitorMetric] {
        MonitorMetric.allCases.filter(isMonitorMetricPresentable)
    }

    private var presentableStatusBarComponentIndices: [Int] {
        model.monitorConfiguration.statusBarComponents.indices.filter { index in
            isMonitorMetricPresentable(
                model.monitorConfiguration.statusBarComponents[index].metric
            )
        }
    }

    private func presentableMetrics(including selected: MonitorMetric) -> [MonitorMetric] {
        let metrics = presentableMonitorMetrics
        return metrics.contains(selected) ? metrics : [selected] + metrics
    }

    private func isMonitorMetricPresentable(_ metric: MonitorMetric) -> Bool {
        switch metric {
        case .batteryCharge, .batteryHealth:
            PowerPresentationPolicy.isAvailable(in: model.snapshot)
        default:
            true
        }
    }

    private func addStatusBarComponent(_ metric: MonitorMetric) {
        guard model.monitorConfiguration.statusBarComponents.count < 8 else { return }
        model.monitorConfiguration.statusBarComponents.append(
            MonitorStatusBarComponent(
                style: defaultStatusBarStyle(for: metric),
                metric: metric,
                title: defaultStatusBarTitle(for: metric),
                accentHex: "F2F4F7"
            )
        )
    }

    private func restoreSenseiStatusBarLayout() {
        model.monitorConfiguration.statusBarLayoutMode = .full
        model.monitorConfiguration.showsStatusBarIcon = false
        model.monitorConfiguration.statusBarComponents = MonitorConfiguration.defaultStatusBarComponents
    }

    private func defaultStatusBarStyle(for metric: MonitorMetric) -> MonitorStatusBarComponentStyle {
        switch metric {
        case .cpuTotal, .cpuUser, .cpuSystem, .gpuUsage, .networkReceived, .networkSent:
            .miniChart
        case .memoryPressure, .memoryUsed, .storageUsed, .batteryCharge:
            .verticalGaugeValue
        case .temperature, .fanSpeed, .batteryHealth, .uptime:
            .value
        }
    }

    private func defaultStatusBarTitle(for metric: MonitorMetric) -> String {
        switch metric {
        case .cpuTotal, .cpuUser, .cpuSystem: "CPU"
        case .gpuUsage: "GPU"
        case .memoryPressure, .memoryUsed: "RAM"
        case .storageUsed: "SSD"
        case .temperature: "CPU"
        case .fanSpeed: "FAN"
        case .networkReceived: "RX"
        case .networkSent: "TX"
        case .batteryCharge, .batteryHealth: "BAT"
        case .uptime: "UP"
        }
    }

    private var quickItemsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(
                title: text("快捷应用", "Quick Apps"),
                subtitle: text("弹窗底部的常用系统工具入口", "Common system tools shown at the bottom of the menu window"),
                symbol: "square.grid.3x2"
            )
            CalmDivider()

            ForEach(model.monitorConfiguration.quickItems.indices, id: \.self) { index in
                quickItemRow(at: index)
                if index < model.monitorConfiguration.quickItems.count - 1 {
                    CalmDivider()
                }
            }
        }
        .calmCard()
    }

    private func quickItemRow(at index: Int) -> some View {
        let configuration = model.binding(\.monitorConfiguration)
        let item = configuration.quickItems[index]
        let localizedTitle = MenuMonitorLocalization.quickItemTitle(
            item.wrappedValue.action,
            fallback: item.wrappedValue.title,
            locale: locale
        )
        return HStack(spacing: 10) {
            Toggle(format("显示 %@", "Show %@", localizedTitle), isOn: item.isVisible)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel(format(
                    "在快捷栏显示 %@",
                    "Show %@ in quick actions",
                    localizedTitle
                ))
            Image(systemName: item.wrappedValue.systemImage)
                .foregroundStyle(CalmTheme.cyan)
                .frame(width: 22)
            Text(localizedTitle)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Spacer()
            reorderButtons(index: index, count: model.monitorConfiguration.quickItems.count) {
                model.monitorConfiguration.quickItems.swapAt(index, index - 1)
            } moveDown: {
                model.monitorConfiguration.quickItems.swapAt(index, index + 1)
            }
        }
    }

    private func reorderButtons(
        index: Int,
        count: Int,
        moveUp: @escaping () -> Void,
        moveDown: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 2) {
            Button(action: moveUp) {
                Image(systemName: "chevron.up")
            }
            .disabled(index == 0)
            .help(text("向前移动", "Move earlier"))
            .accessibilityLabel(text("向前移动", "Move earlier"))
            Button(action: moveDown) {
                Image(systemName: "chevron.down")
            }
            .disabled(index >= count - 1)
            .help(text("向后移动", "Move later"))
            .accessibilityLabel(text("向后移动", "Move later"))
        }
        .buttonStyle(.borderless)
        .controlSize(.mini)
    }

    private var localizedDataSourceTitle: String {
        switch model.dataSource {
        case .fixture: text("演示数据", "Demo Data")
        case .live: text("本机数据", "This Mac")
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

    private func pluralFormat(
        count: Int,
        oneKey: String,
        otherKey: String,
        oneDefaultValue: String,
        otherDefaultValue: String,
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

extension MonitorModule {
    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .cpuAndGPU: MenuMonitorLocalization.string("CPU 与 GPU", english: "CPU & GPU", locale: locale)
        case .memory: MenuMonitorLocalization.string("内存", english: "Memory", locale: locale)
        case .storage: MenuMonitorLocalization.string("存储", english: "Storage", locale: locale)
        case .sensors: MenuMonitorLocalization.string("传感器", english: "Sensors", locale: locale)
        case .network: MenuMonitorLocalization.string("网络", english: "Network", locale: locale)
        case .power: MenuMonitorLocalization.string("电源", english: "Power", locale: locale)
        }
    }

    var symbol: String {
        switch self {
        case .cpuAndGPU: "cpu"
        case .memory: "memorychip"
        case .storage: "internaldrive"
        case .sensors: "thermometer.medium"
        case .network: "network"
        case .power: "bolt.circle"
        }
    }

    func localizedSummary(locale: Locale) -> String {
        switch self {
        case .cpuAndGPU: MenuMonitorLocalization.string("处理器、图形设备型号、负载与高占用进程", english: "Processor and GPU models, load, and top processes", locale: locale)
        case .memory: MenuMonitorLocalization.string("内存压力、用量、交换空间与进程", english: "Memory pressure, usage, swap, and processes", locale: locale)
        case .storage: MenuMonitorLocalization.string("磁盘容量、可用空间、卷状态与实时 I/O", english: "Capacity, free space, volumes, and live I/O", locale: locale)
        case .sensors: MenuMonitorLocalization.string("风扇转速、CPU 温度与传感器", english: "Fan speeds, CPU temperature, and sensors", locale: locale)
        case .network: MenuMonitorLocalization.string("网络服务、连接状态与实时收发速率", english: "Network services, connections, and live transfer rates", locale: locale)
        case .power: MenuMonitorLocalization.string("电量、健康度、循环次数与供电状态", english: "Charge, health, cycles, and power status", locale: locale)
        }
    }

    func localizedShortContents(locale: Locale) -> String {
        switch self {
        case .cpuAndGPU: MenuMonitorLocalization.string("CPU、核心、进程、GPU 型号、显存", english: "CPU, cores, processes, GPU model, memory", locale: locale)
        case .memory: MenuMonitorLocalization.string("压力、用量、交换空间、进程", english: "Pressure, usage, swap, processes", locale: locale)
        case .storage: MenuMonitorLocalization.string("容量、可用空间、卷、读写 I/O", english: "Capacity, free space, volumes, read/write I/O", locale: locale)
        case .sensors: MenuMonitorLocalization.string("风扇、温度、传感器列表", english: "Fans, temperatures, sensor list", locale: locale)
        case .network: MenuMonitorLocalization.string("服务、连接、下载、上传", english: "Services, connections, download, upload", locale: locale)
        case .power: MenuMonitorLocalization.string("电量、健康、循环、功率", english: "Charge, health, cycles, power", locale: locale)
        }
    }

    var tint: Color {
        switch self {
        case .cpuAndGPU: CalmTheme.accent
        case .memory: CalmTheme.violet
        case .storage: CalmTheme.cyan
        case .sensors: CalmTheme.mint
        case .network: CalmTheme.amber
        case .power: CalmTheme.rose
        }
    }
}

extension MonitorMetric {
    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .cpuTotal: MenuMonitorLocalization.string("CPU 总负载", english: "Total CPU Load", locale: locale)
        case .cpuUser: MenuMonitorLocalization.string("CPU 用户", english: "CPU User", locale: locale)
        case .cpuSystem: MenuMonitorLocalization.string("CPU 系统", english: "CPU System", locale: locale)
        case .gpuUsage: MenuMonitorLocalization.string("GPU 使用率", english: "GPU Usage", locale: locale)
        case .memoryPressure: MenuMonitorLocalization.string("内存占用估算", english: "Memory Usage Estimate", locale: locale)
        case .memoryUsed: MenuMonitorLocalization.string("已用内存", english: "Memory Used", locale: locale)
        case .storageUsed: MenuMonitorLocalization.string("已用存储", english: "Storage Used", locale: locale)
        case .temperature: MenuMonitorLocalization.string("温度", english: "Temperature", locale: locale)
        case .fanSpeed: MenuMonitorLocalization.string("风扇转速", english: "Fan Speed", locale: locale)
        case .networkReceived: MenuMonitorLocalization.string("接收速率", english: "Download Rate", locale: locale)
        case .networkSent: MenuMonitorLocalization.string("发送速率", english: "Upload Rate", locale: locale)
        case .batteryCharge: MenuMonitorLocalization.string("电池电量", english: "Battery Charge", locale: locale)
        case .batteryHealth: MenuMonitorLocalization.string("电池健康", english: "Battery Health", locale: locale)
        case .uptime: MenuMonitorLocalization.string("运行时间", english: "Uptime", locale: locale)
        }
    }
}
