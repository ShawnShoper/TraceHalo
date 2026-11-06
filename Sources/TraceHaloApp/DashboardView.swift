import AppKit
import SwiftUI
import TraceHaloCore

private enum DashboardHistoryLayout {
    static let labelWidth: CGFloat = 76
    static let valueWidth: CGFloat = 74
    static let rowInset: CGFloat = 9
    static let rowSpacing: CGFloat = 10
    static let plotLeading = labelWidth + rowInset + rowSpacing
    static let plotTrailing = valueWidth + rowInset + rowSpacing
}

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigationRouter.self) private var navigationRouter
    @Environment(\.locale) private var locale
    @State private var historyHoverLocation: CGPoint?
    @State private var historyWindowMinutes = 60
    @State private var isShowingAllEvents = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedResource: DashboardResource?
    @State private var expandedSection: MenuBarDashboardSection = .cpu

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        healthHeader
                        healthStatus
                        resourceGrid(availableWidth: min(proxy.size.width - 48, 1_432))

                        if proxy.size.width >= 1_000 {
                            HStack(alignment: .top, spacing: 16) {
                                resourceHistory.frame(maxWidth: .infinity)
                                insightRail.frame(width: 286)
                            }
                        } else {
                            resourceHistory
                            insightRail
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 1_480, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: navigationRouter.dashboardSectionRequest, initial: true) { _, request in
                    guard let request else { return }
                    let resource = DashboardResource(section: request.section)
                    guard resource != .battery || PowerPresentationPolicy.isAvailable(in: model.snapshot) else { return }
                    expandedSection = request.section
                    expandedResource = resource
                    // The detail view is inserted before scrolling so a menu-bar
                    // shortcut also works when the requested resource was closed.
                    Task { @MainActor in
                        await Task.yield()
                        guard expandedResource == resource else { return }
                        scroll.scrollTo(resource.id, anchor: .top)
                    }
                }
            }
        }
        .foregroundStyle(CalmTheme.primaryText)
        .background(CalmTheme.canvas.ignoresSafeArea())
        .navigationTitle(localized("实时监控"))
        .sheet(isPresented: $isShowingAllEvents) {
            DashboardEventListSheet(events: model.dashboardEvents)
        }
    }

    private var timelineSamples: [DashboardTelemetrySample] {
        model.dashboardHistory
    }

    private var healthHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                healthIdentity
                Spacer(minLength: 20)
                headerActions
            }
            VStack(alignment: .leading, spacing: 16) {
                healthIdentity
                headerActions
            }
        }
    }

    private var healthIdentity: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localized("实时监控"))
                .font(.system(size: 27, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text("\(deviceDisplayName) · \(model.snapshot.identity.chipName)")
                .font(.system(size: 12))
                .foregroundStyle(CalmTheme.secondaryText)
                .lineLimit(1)
        }
    }

    private var healthStatus: some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: model.overallState.symbol)
                .foregroundStyle(model.overallState.color)
            Text(healthTitle)
                .font(.system(size: 12, weight: .medium))
            if let healthStatusDetail {
                Text(healthStatusDetail)
                    .font(.system(size: 12))
                    .foregroundStyle(CalmTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(model.snapshot.capturedAt, style: .time)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(CalmTheme.tertiaryText)
                .help(localized("最近更新"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(model.overallState.color.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .combine)
    }

    private var healthStatusDetail: String? {
        if model.overallState == .critical { return statusExplanation }
        return model.lastError ?? (model.overallState == .normal ? nil : statusExplanation)
    }

    private var headerActions: some View {
        HStack(spacing: 12) {
            Button {
                navigationRouter.navigate(to: .report)
            } label: {
                Label(localized("系统报告"), systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(CalmButtonStyle())
            .help("打开系统报告")

            Button {
                navigationRouter.openMonitor(.menuBarLayout)
            } label: {
                Label(localized("菜单栏布局"), systemImage: "menubar.rectangle")
            }
            .buttonStyle(CalmButtonStyle())
            .help("打开菜单栏监视器布局")
        }
    }

    private func resourceGrid(availableWidth: CGFloat) -> some View {
        let columnCount = availableWidth >= 840 ? 3 : (availableWidth >= 520 ? 2 : 1)
        let metrics: [DashboardResource] = [.cpu, .memory, .gpu, .storage, .network, .cooling]
            + (PowerPresentationPolicy.isAvailable(in: model.snapshot) ? [.battery] : [])
        let rows = stride(from: 0, to: metrics.count, by: columnCount).map {
            Array(metrics[$0 ..< min($0 + columnCount, metrics.count)])
        }
        return VStack(spacing: 14) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(alignment: .top, spacing: 14) {
                    ForEach(rows[row]) { metric in
                        resourceCard(for: metric).id(metric.id)
                    }
                    ForEach(rows[row].count ..< columnCount, id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
                if let expandedResource, rows[row].contains(expandedResource) {
                    resourceDetails(for: expandedResource)
                }
            }
        }
    }

    private func resourceCard(for metric: DashboardResource) -> some View {
        let content = resourceContent(for: metric)
        return Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                if expandedResource == metric {
                    expandedResource = nil
                } else {
                    expandedResource = metric
                    expandedSection = metric.section
                }
            }
        } label: {
            DashboardResourceCard(
                content: content,
                detailTitle: localized(metric.detailTitle),
                isExpanded: expandedResource == metric,
                storageFraction: metric == .storage ? primaryVolume?.usedFraction
                    : (metric == .battery ? model.snapshot.battery.chargePercent.map { $0 / 100 } : nil),
                isBattery: metric == .battery,
                chartMaximum: metric == .network ? nil : 100
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localized(content.title))
        .accessibilityValue("\(content.value)，\(content.detail)")
        .accessibilityHint(localized(expandedResource == metric ? "收起详情" : metric.detailTitle))
        .help(localized(expandedResource == metric ? "收起详情" : metric.detailTitle))
    }

    private func resourceDetails(for metric: DashboardResource) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(localized(metric.detailTitle), systemImage: resourceContent(for: metric).symbol)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                        expandedResource = nil
                    }
                } label: {
                    Label(localized("收起"), systemImage: "chevron.up")
                }
                .buttonStyle(.plain)
                .foregroundStyle(CalmTheme.accent)
                .help(localized("收起详情"))
            }
            MonitorResourceDetails(section: expandedSection)
        }
        .padding(18)
        .dashboardPanel()
        .transition(.opacity)
    }

    private func resourceContent(for metric: DashboardResource) -> DashboardResourceContent {
        switch metric {
        case .cpu:
            DashboardResourceContent(
                title: "CPU",
                value: MetricFormatter.percent(model.snapshot.cpu.totalPercent),
                detail: AppLocalization.format(
                    "dashboard.cpu.detail",
                    defaultValue: "用户 %@ · 系统 %@",
                    locale: locale,
                    MetricFormatter.percent(model.snapshot.cpu.userPercent),
                    MetricFormatter.percent(model.snapshot.cpu.systemPercent)
                ),
                symbol: "cpu",
                tint: CalmTheme.accent,
                points: model.history(for: .cpuTotal)
            )
        case .gpu:
            DashboardResourceContent(
                title: "GPU",
                value: model.snapshot.gpus.first?.utilizationPercent.map { MetricFormatter.percent($0) } ?? "—",
                detail: gpuDetail,
                symbol: "display",
                tint: CalmTheme.cyan,
                points: model.history(for: .gpuUsage)
            )
        case .memory:
            DashboardResourceContent(
                title: "内存",
                value: MetricFormatter.percent(model.snapshot.memory.pressurePercent),
                detail: AppLocalization.format(
                    "dashboard.memory.used",
                    defaultValue: "已用 %@ / %@",
                    locale: locale,
                    MetricFormatter.bytes(model.snapshot.memory.usedBytes),
                    MetricFormatter.bytes(model.snapshot.memory.totalBytes)
                ),
                symbol: "memorychip",
                tint: CalmTheme.violet,
                points: model.history(for: .memoryPressure)
            )
        case .cooling:
            DashboardResourceContent(
                title: "散热",
                value: temperatureValue,
                detail: coolingDetail,
                symbol: "fan",
                tint: CalmTheme.mint,
                points: model.history(for: .temperature)
            )
        case .storage:
            DashboardResourceContent(
                title: "存储",
                value: primaryVolume.map { MetricFormatter.bytes($0.availableBytes) } ?? "—",
                detail: primaryVolume.map {
                    AppLocalization.format(
                        "dashboard.storage.summary",
                        defaultValue: "可用空间 · 已用 %@",
                        locale: locale,
                        MetricFormatter.percent($0.usedFraction * 100)
                    )
                } ?? localized("没有已挂载卷"),
                symbol: "internaldrive",
                tint: CalmTheme.cyan,
                points: timelineSamples.compactMap(\.storageUsedPercent)
            )
        case .battery:
            DashboardResourceContent(
                title: "电池与电源",
                value: model.snapshot.battery.chargePercent.map { MetricFormatter.percent($0) } ?? "—",
                detail: batteryPowerDescription,
                symbol: "battery.100", tint: CalmTheme.mint, points: []
            )
        case .network:
            DashboardResourceContent(
                title: "网络",
                value: "↓ \(aggregateRate(networkReceivedRates))",
                detail: "↑ \(aggregateRate(networkSentRates)) · \(activeInterfaceSummary)",
                symbol: "globe",
                tint: CalmTheme.amber,
                points: timelineSamples.compactMap(\.networkReceivedBytesPerSecond)
            )
        }
    }

    private var batteryPowerDescription: String {
        let battery = model.snapshot.battery
        if battery.isCharging { return localized("正在充电") }
        switch battery.isOnExternalPower {
        case true?: return localized("已连接电源")
        case false?: return localized("使用电池")
        case nil: return localized("电源状态不可用")
        }
    }

    private var resourceHistory: some View {
        let visibleSamples = visibleTimelineSamples
        let plottedSamples = downsampledTimelineSamples(visibleSamples, limit: 240)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(localized("资源历史"))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)

                Menu {
                    ForEach([15, 30, 60], id: \.self) { minutes in
                        Button(minutesLabel(minutes)) {
                            historyWindowMinutes = minutes
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(minutesLabel(historyWindowMinutes))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CalmTheme.secondaryText)
                    .padding(.horizontal, 9)
                    .frame(height: 25)
                    .background(CalmTheme.controlBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(CalmTheme.hairline)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()


            }

            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 3) {
                        historyRow(
                            title: "CPU",
                            color: CalmTheme.accent,
                            value: MetricFormatter.percent(model.snapshot.cpu.totalPercent),
                            values: plottedSamples.map { TimelinePoint(date: $0.date, value: $0.cpuPercent) },
                            domain: 0 ... 100
                        )
                        historyRow(
                            title: "GPU",
                            color: CalmTheme.cyan,
                            value: model.snapshot.gpus.first?.utilizationPercent.map { MetricFormatter.percent($0) } ?? "—",
                            values: plottedSamples.map { TimelinePoint(date: $0.date, value: $0.gpuPercent) },
                            domain: 0 ... 100
                        )
                        historyRow(
                            title: "内存占用",
                            color: CalmTheme.violet,
                            value: MetricFormatter.percent(model.snapshot.memory.pressurePercent),
                            values: plottedSamples.map {
                                TimelinePoint(date: $0.date, value: $0.memoryPressurePercent)
                            },
                            domain: 0 ... 100
                        )
                        historyRow(
                            title: "存储",
                            color: CalmTheme.cyan,
                            value: primaryVolume.map { MetricFormatter.percent($0.usedFraction * 100) } ?? "—",
                            values: plottedSamples.map { TimelinePoint(date: $0.date, value: $0.storageUsedPercent) },
                            domain: 0 ... 100
                        )
                        historyRow(
                            title: "网络",
                            color: CalmTheme.amber,
                            value: "↑ \(aggregateRate(networkSentRates))\n↓ \(aggregateRate(networkReceivedRates))",
                            values: plottedSamples.map {
                                TimelinePoint(date: $0.date, value: $0.networkBytesPerSecond)
                            },
                            domain: nil
                        )
                        historyRow(
                            title: "温度",
                            color: CalmTheme.mint,
                            value: temperatureValue,
                            values: plottedSamples.map { TimelinePoint(date: $0.date, value: $0.temperatureCelsius) },
                            domain: 0 ... 100
                        )
                    }

                    if let location = historyHoverLocation,
                       let sample = selectedTimelineSample(
                           at: location.x,
                           width: proxy.size.width,
                           samples: visibleSamples
                       ) {
                        historySelectionOverlay(sample: sample, x: location.x, size: proxy.size)
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case let .active(location):
                        let snappedLocation = CGPoint(x: location.x.rounded(), y: location.y.rounded())
                        if historyHoverLocation != snappedLocation {
                            historyHoverLocation = snappedLocation
                        }
                    case .ended:
                        historyHoverLocation = nil
                    }
                }
            }
            .frame(height: 186)

            historyAxis
        }
        .padding(16)
        .dashboardPanel()
    }

    private var historyAxis: some View {
        HStack {
            Text(minutesAgoLabel(historyWindowMinutes))
            Spacer()
            Text(minutesAgoLabel(historyWindowMinutes * 3 / 4))
            Spacer()
            Text(minutesAgoLabel(historyWindowMinutes / 2))
            Spacer()
            Text(minutesAgoLabel(historyWindowMinutes / 4))
            Spacer()
            Text(localized("刚刚"))
        }
        .font(.system(size: 9, design: .monospaced))
        .foregroundStyle(CalmTheme.tertiaryText)
        .padding(.leading, DashboardHistoryLayout.plotLeading)
        .padding(.trailing, DashboardHistoryLayout.plotTrailing)
    }

    private var visibleTimelineSamples: [DashboardTelemetrySample] {
        let latest = model.snapshot.capturedAt
        let cutoff = latest.addingTimeInterval(-TimeInterval(historyWindowMinutes * 60))
        return timelineSamples.filter { $0.date >= cutoff && $0.date <= latest }
    }

    private func downsampledTimelineSamples(
        _ samples: [DashboardTelemetrySample],
        limit: Int
    ) -> [DashboardTelemetrySample] {
        guard limit > 1, samples.count > limit else { return samples }
        let lastIndex = samples.count - 1
        return (0 ..< limit).map { outputIndex in
            let fraction = Double(outputIndex) / Double(limit - 1)
            let sourceIndex = Int((fraction * Double(lastIndex)).rounded())
            return samples[sourceIndex]
        }
    }

    private func selectedTimelineSample(
        at x: CGFloat,
        width: CGFloat,
        samples: [DashboardTelemetrySample]
    ) -> DashboardTelemetrySample? {
        guard !samples.isEmpty else { return nil }
        let latest = model.snapshot.capturedAt
        let plotStart = DashboardHistoryLayout.plotLeading
        let plotEnd = max(width - DashboardHistoryLayout.plotTrailing, plotStart + 1)
        let clampedX = min(max(x, plotStart), plotEnd)
        let fraction = Double((clampedX - plotStart) / (plotEnd - plotStart))
        let target = latest.addingTimeInterval(
            -TimeInterval(historyWindowMinutes * 60) * (1 - fraction)
        )

        var lowerBound = 0
        var upperBound = samples.count
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if samples[middle].date < target {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        let nearest: DashboardTelemetrySample
        if lowerBound == 0 {
            nearest = samples[0]
        } else if lowerBound == samples.count {
            nearest = samples[samples.count - 1]
        } else {
            let previous = samples[lowerBound - 1]
            let next = samples[lowerBound]
            nearest = abs(previous.date.timeIntervalSince(target)) <= abs(next.date.timeIntervalSince(target))
                ? previous : next
        }
        // Do not present an old sample as if it occurred under a blank part of the chart.
        return abs(nearest.date.timeIntervalSince(target)) <= DashboardHistoryStore.persistenceSampleInterval ? nearest : nil
    }

    private func historySelectionOverlay(
        sample: DashboardTelemetrySample,
        x: CGFloat,
        size: CGSize
    ) -> some View {
        let plotStart = DashboardHistoryLayout.plotLeading
        let plotEnd = max(size.width - DashboardHistoryLayout.plotTrailing, plotStart + 1)
        let clampedX = min(max(x, plotStart), plotEnd)
        let tooltipWidth: CGFloat = 148
        let tooltipX = min(max(clampedX + 12, tooltipWidth / 2), size.width - tooltipWidth / 2)

        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(CalmTheme.secondaryText.opacity(0.5))
                .frame(width: 1, height: size.height + 14)
                .position(x: clampedX, y: size.height / 2)

            Circle()
                .fill(CalmTheme.accent)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(CalmTheme.canvas, lineWidth: 1.5))
                .position(x: clampedX, y: size.height + 3)

            DashboardHistoryTooltip(
                sample: sample,
                temperatureUnit: model.temperatureUnit,
                latestDate: model.snapshot.capturedAt
            )
            .frame(width: tooltipWidth)
            .position(x: tooltipX, y: 92)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func historyRow(
        title: String,
        color: Color,
        value: String,
        values: [TimelinePoint],
        domain: ClosedRange<Double>?
    ) -> some View {
        HStack(spacing: DashboardHistoryLayout.rowSpacing) {
            Text(localized(title))
                .font(.caption.weight(.semibold))
                .foregroundStyle(CalmTheme.primaryText)
                .lineLimit(2)
                .frame(width: DashboardHistoryLayout.labelWidth, alignment: .leading)

            TimelineTrace(
                values: values,
                color: color,
                domain: domain,
                windowSeconds: TimeInterval(historyWindowMinutes * 60),
                latestDate: model.snapshot.capturedAt
            )
            .equatable()
            .frame(height: 22)

            Text(value)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .frame(width: DashboardHistoryLayout.valueWidth, alignment: .trailing)
        }
        .padding(.horizontal, DashboardHistoryLayout.rowInset)
        .frame(height: 28)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CalmTheme.hairline.opacity(0.45))
                .frame(height: 1)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            AppLocalization.format(
                "dashboard.trend.accessibility",
                defaultValue: "%@，当前 %@，%ld 分钟趋势图",
                locale: locale,
                localized(title),
                value,
                historyWindowMinutes
            )
        )
    }

    private var insightRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            memoryChangeCard
            eventLogCard

        }
    }

    private var memoryChangeCard: some View {
        HStack(spacing: 9) {
            Image(systemName: memoryChangeSymbol)
                .foregroundStyle(memoryChangeColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(memoryChangeTitle)
                    .font(.system(size: 10.5, weight: .medium))
                Text(memoryChangeDetail)
                    .font(.system(size: 9))
                    .foregroundStyle(CalmTheme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .dashboardPanel(cornerRadius: 9)
        .accessibilityElement(children: .combine)
    }

    private var eventLogCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(localized("事件记录"))
                .font(.system(size: 12, weight: .semibold))
                .padding(.bottom, 7)

            if model.dashboardEvents.isEmpty {
                Text(localized("暂无新的状态变化"))
                    .font(.system(size: 10))
                    .foregroundStyle(CalmTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 92, alignment: .center)
            } else {
                ForEach(Array(model.dashboardEvents.prefix(5).enumerated()), id: \.element.id) { index, event in
                    DashboardEventRow(event: event)
                    if index < min(model.dashboardEvents.count, 5) - 1 {
                        Rectangle()
                            .fill(CalmTheme.hairline)
                            .frame(height: 1)
                            .padding(.leading, 17)
                    }
                }
            }

            Button {
                isShowingAllEvents = true
            } label: {
                Text(localized("查看全部事件"))
                    .font(.system(size: 10, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(CalmTheme.controlBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(CalmTheme.hairline)
                    }
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .dashboardPanel(cornerRadius: 10)
    }

    private var healthTitle: String {
        localized(rawHealthTitle)
    }

    private var rawHealthTitle: String {
        switch model.overallState {
        case .normal: "系统运行平稳"
        case .attention: "系统需要关注"
        case .critical: "系统需要处理"
        case .limited: "部分数据受限"
        case .monitoring: "正在建立监测"
        }
    }

    private var statusExplanation: String {
        localized(rawStatusExplanation)
    }

    private var rawStatusExplanation: String {
        switch model.overallState {
        case .normal: "关键资源与传感器状态正常。"
        case .attention: "检测到需要关注的硬件状态。"
        case .critical: "检测到严重的散热状态。"
        case .limited: "部分数据暂时无法读取。"
        case .monitoring: "正在采集足够的数据以判断状态。"
        }
    }

    private var primaryVolume: StorageVolume? {
        model.snapshot.volumes.first(where: { $0.isInternal == true }) ?? model.snapshot.volumes.first
    }

    private var networkReceivedRates: [Double] {
        DashboardNetworkReading(interfaces: model.snapshot.networkInterfaces).receivedBytesPerSecond.map { [$0] } ?? []
    }

    private var networkSentRates: [Double] {
        DashboardNetworkReading(interfaces: model.snapshot.networkInterfaces).sentBytesPerSecond.map { [$0] } ?? []
    }

    private var activeInterfaceSummary: String {
        let names = relevantNetworkInterfaces.filter(\.isActive).map(\.displayName)
        return names.isEmpty ? localized("无活动连接") : names.prefix(2).joined(separator: " · ")
    }

    private var relevantNetworkInterfaces: [NetworkInterfaceState] {
        DashboardNetworkReading(interfaces: model.snapshot.networkInterfaces).activeInterfaces
    }

    private var deviceDisplayName: String {
        let computerName = model.snapshot.identity.computerName
        if computerName.localizedCaseInsensitiveContains("Mac Studio") { return "Mac Studio" }
        if computerName.localizedCaseInsensitiveContains("MacBook") { return "MacBook" }
        if computerName.localizedCaseInsensitiveContains("Mac mini") { return "Mac mini" }
        if computerName.localizedCaseInsensitiveContains("iMac") { return "iMac" }
        return model.snapshot.identity.modelName
    }

    private var measuredTemperature: Double? {
        if let value = model.snapshot.cpu.temperatureCelsius { return value }
        let CPUSensors = model.snapshot.cooling.sensors.filter {
            $0.group.localizedCaseInsensitiveContains("CPU")
                || $0.name.localizedCaseInsensitiveContains("CPU")
        }
        let values = CPUSensors.isEmpty
            ? model.snapshot.cooling.sensors.map(\.temperatureCelsius)
            : CPUSensors.map(\.temperatureCelsius)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var temperatureValue: String {
        measuredTemperature.map {
            model.temperatureUnit.formatted(celsius: $0, locale: locale)
        } ?? "—"
    }

    private var coolingDetail: String {
        let condition: String
        switch model.snapshot.cooling.condition {
        case .nominal: condition = localized("正常")
        case .fair: condition = localized("温度升高")
        case .serious: condition = localized("温度较高")
        case .critical: condition = localized("需要关注")
        case .unavailable: condition = localized("未知")
        }
        guard !model.snapshot.cooling.fans.isEmpty else {
            return AppLocalization.format(
                "dashboard.fan.unavailable",
                defaultValue: "风扇转速不可用 · %@",
                locale: locale,
                condition
            )
        }
        let fanCount = model.snapshot.cooling.fans.count
        return AppCountLocalization.format(
            count: fanCount,
            oneKey: "dashboard.fan.count.one",
            otherKey: "dashboard.fan.count.other",
            oneDefaultValue: "%ld 个风扇 · %@",
            otherDefaultValue: "%ld 个风扇 · %@",
            locale: locale,
            fanCount,
            condition
        )
    }

    private var gpuDetail: String {
        model.snapshot.gpus.first?.name ?? localized("没有图形设备数据")
    }

    private func aggregateRate(_ rates: [Double]) -> String {
        guard !rates.isEmpty else { return "—" }
        return MetricFormatter.rate(bytesPerSecond: rates.reduce(0, +))
    }

    private var memoryChange: Double? {
        let samples = visibleTimelineSamples
        guard let first = samples.first?.memoryPressurePercent,
              let last = samples.last?.memoryPressurePercent,
              samples.count > 1
        else { return nil }
        return last - first
    }

    private var memoryChangeTitle: String {
        guard let memoryChange else { return localized("正在建立变化基线") }
        if abs(memoryChange) < 0.5 { return localized("内存占用保持稳定") }
        let direction = localized(memoryChange > 0 ? "上升" : "下降")
        return AppLocalization.format(
            "dashboard.memory.change",
            defaultValue: "内存占用%@ %@ 个百分点",
            locale: locale,
            direction,
            String(Int(abs(memoryChange).rounded()))
        )
    }

    private var memoryChangeDetail: String {
        let samples = visibleTimelineSamples
        guard samples.count > 1, let first = samples.first?.date else { return localized("等待下一次真实采样") }
        return AppLocalization.format(
            "dashboard.compare.time",
            defaultValue: "与 %@ 的记录相比",
            locale: locale,
            first.formatted(
                Date.FormatStyle(date: .omitted, time: .shortened)
                    .locale(locale)
            )
        )
    }

    private var memoryChangeSymbol: String {
        guard let memoryChange, abs(memoryChange) >= 0.5 else { return "arrow.right" }
        return memoryChange > 0 ? "arrow.up.right" : "arrow.down.right"
    }

    private var memoryChangeColor: Color {
        guard let memoryChange, abs(memoryChange) >= 0.5 else { return CalmTheme.mint }
        return memoryChange > 0 ? CalmTheme.amber : CalmTheme.mint
    }

    private func minutesLabel(_ minutes: Int) -> String {
        AppLocalization.format(
            "dashboard.minutes",
            defaultValue: "%ld 分钟",
            locale: locale,
            minutes
        )
    }

    private func minutesAgoLabel(_ minutes: Int) -> String {
        AppLocalization.format(
            "dashboard.minutes.ago",
            defaultValue: "%ld 分钟前",
            locale: locale,
            minutes
        )
    }

    private func localized(_ value: String) -> String {
        AppLocalization.string(value, defaultValue: value, locale: locale)
    }

}

private enum DashboardResource: String, CaseIterable, Identifiable {
    case cpu
    case gpu
    case memory
    case cooling
    case storage
    case network
    case battery

    var id: String { rawValue }

    var section: MenuBarDashboardSection {
        switch self {
        case .cpu: .cpu
        case .memory: .memory
        case .gpu: .gpu
        case .storage: .storage
        case .network: .network
        case .cooling: .fans
        case .battery: .battery
        }
    }

    init(section: MenuBarDashboardSection) {
        switch section {
        case .cpu: self = .cpu
        case .memory: self = .memory
        case .gpu: self = .gpu
        case .storage: self = .storage
        case .network: self = .network
        case .fans, .sensors: self = .cooling
        case .battery: self = .battery
        }
    }

    var detailTitle: String {
        switch self {
        case .cpu: "核心与进程"
        case .memory: "内存明细"
        case .gpu: "图形详情"
        case .storage: "磁盘明细"
        case .network: "网络接口"
        case .cooling: "传感器明细"
        case .battery: "电池与电源"
        }
    }

}

private struct DashboardResourceContent {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color
    let points: [Double]
}

struct TimelinePoint: Identifiable, Equatable {
    let date: Date
    let value: Double?

    var id: Date { date }
}

/// Persistent history has one observation per minute; live history is denser.
/// Keep those valid samples connected while preserving missing readings and downtime.
enum DashboardTimelinePolicy {
    static func segments(_ values: [TimelinePoint]) -> [[TimelinePoint]] {
        let maximumGap = 2 * DashboardHistoryStore.persistenceSampleInterval
            + DashboardHistoryPolicy.minimumSampleInterval
        var segments: [[TimelinePoint]] = []
        var current: [TimelinePoint] = []
        for point in values {
            guard let value = point.value, value.isFinite else {
                if !current.isEmpty { segments.append(current); current = [] }
                continue
            }
            if let previous = current.last,
               point.date.timeIntervalSince(previous.date) > maximumGap {
                segments.append(current)
                current = []
            }
            current.append(point)
        }
        if !current.isEmpty { segments.append(current) }
        return segments
    }

    static func normalizedX(date: Date, latestDate: Date, windowSeconds: TimeInterval) -> Double {
        1 - min(max(latestDate.timeIntervalSince(date) / max(windowSeconds, 1), 0), 1)
    }
}

private struct DashboardResourceCard: View {
    @Environment(\.locale) private var locale
    @State private var isHovered = false
    let content: DashboardResourceContent
    let detailTitle: String
    let isExpanded: Bool
    let storageFraction: Double?
    let isBattery: Bool
    let chartMaximum: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: content.symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(content.tint)
                    .frame(width: 24)
                Text(localized(content.title))
                    .font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
            }
            Text(content.value)
                .font(.system(size: 31, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.top, 12)
            Text(content.detail)
                .font(.system(size: 11.5))
                .foregroundStyle(CalmTheme.secondaryText)
                .lineLimit(1)
                .help(content.detail)
                .padding(.top, 3)

            Group {
                if let storageFraction {
                    VStack(spacing: 6) {
                        DashboardProgressBar(
                            value: storageFraction, tint: content.tint,
                            accessibilityLabel: localized(isBattery ? "电量" : "存储"),
                            accessibilityValue: MetricFormatter.percent(storageFraction * 100)
                        )
                        HStack {
                            Text(localized(isBattery ? "电量" : "已用"))
                            Spacer()
                            Text(localized(isBattery ? "满电" : "可用"))
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(CalmTheme.tertiaryText)
                    }
                } else if content.points.count > 1, !content.value.contains("—") {
                    DashboardMiniTrend(values: content.points, tint: content.tint, maximum: chartMaximum)
                } else {
                    Text(localized(content.value.contains("—") ? "暂无可用数据" : "正在积累趋势"))
                        .font(.system(size: 11))
                        .foregroundStyle(CalmTheme.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: 42)
            .padding(.vertical, 14)

            Rectangle().fill(CalmTheme.hairline.opacity(0.6)).frame(height: 1)
            HStack {
                Text(detailTitle).font(.system(size: 11.5, weight: .medium))
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(isExpanded ? content.tint : CalmTheme.secondaryText)
            .padding(.top, 11)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isExpanded ? content.tint.opacity(0.65) : (isHovered ? content.tint.opacity(0.4) : CalmTheme.hairline.opacity(0.7)), lineWidth: 1)
        }
        .onHover { isHovered = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private func localized(_ value: String) -> String {
        AppLocalization.string(value, defaultValue: value, locale: locale)
    }
}

private struct DashboardMiniTrend: View {
    let values: [Double]
    let tint: Color
    let maximum: Double?

    var body: some View {
        Canvas { context, size in
            let samples = Array(values.suffix(60))
            guard samples.count > 1 else { return }
            let ceiling = max(maximum ?? ((samples.max() ?? 1) * 1.15), 1)
            var grid = Path()
            for index in 0 ... 6 {
                let x = size.width * Double(index) / 6
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            context.stroke(grid, with: .color(CalmTheme.hairline.opacity(0.4)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
            let points = samples.enumerated().map { index, value in
                CGPoint(x: size.width * Double(index) / Double(samples.count - 1),
                        y: size.height - 2 - (size.height - 4) * min(max(value / ceiling, 0), 1))
            }
            var line = Path()
            line.addLines(points)
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .linearGradient(Gradient(colors: [tint.opacity(0.18), tint.opacity(0.02)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

private struct DashboardHistoryTooltip: View {
    @Environment(\.locale) private var locale
    let sample: DashboardTelemetrySample
    let temperatureUnit: TemperatureUnit
    let latestDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(
                AppLocalization.format(
                    "dashboard.minutes.ago",
                    defaultValue: "%ld 分钟前",
                    locale: locale,
                    minutesAgo
                )
            )
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(CalmTheme.secondaryText)
                .padding(.bottom, 2)
            tooltipRow("CPU", value: MetricFormatter.percent(sample.cpuPercent), color: CalmTheme.accent)
            tooltipRow("GPU", value: optionalPercent(sample.gpuPercent), color: CalmTheme.cyan)
            tooltipRow("内存占用", value: MetricFormatter.percent(sample.memoryPressurePercent), color: CalmTheme.violet)
            tooltipRow("存储", value: optionalPercent(sample.storageUsedPercent), color: CalmTheme.cyan)
            tooltipRow(
                "网络",
                value: sample.networkBytesPerSecond.map { MetricFormatter.rate(bytesPerSecond: $0) } ?? "—",
                color: CalmTheme.amber
            )
            tooltipRow(
                "温度",
                value: sample.temperatureCelsius.map {
                    temperatureUnit.formatted(celsius: $0, locale: locale)
                } ?? "—",
                color: CalmTheme.mint
            )
        }
        .padding(10)
        .background(
            Color(lightHex: "FFFFFF", darkHex: "252D32").opacity(0.98),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(CalmTheme.hairline.opacity(0.65))
        }
        .shadow(color: Color.black.opacity(0.24), radius: 12, y: 5)
    }

    private var minutesAgo: Int {
        max(0, Int(latestDate.timeIntervalSince(sample.date) / 60))
    }

    private func optionalPercent(_ value: Double?) -> String {
        value.map { MetricFormatter.percent($0) } ?? "—"
    }

    private func tooltipRow(_ title: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(AppLocalization.string(title, defaultValue: title, locale: locale))
                .font(.system(size: 9.5))
            Spacer(minLength: 5)
            Text(value)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}

private struct DashboardEventRow: View {
    @Environment(\.locale) private var locale
    let event: DashboardEventRecord

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(event.color)
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.localizedTitle(locale: locale))
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                Text(event.localizedDetail(locale: locale))
                    .font(.system(size: 10))
                    .foregroundStyle(CalmTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
            Text(event.occurredAt, style: .relative)
                .font(.system(size: 10))
                .foregroundStyle(CalmTheme.tertiaryText)
                .lineLimit(1)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

private struct DashboardEventListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    let events: [DashboardEventRecord]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(AppLocalization.string("全部事件", defaultValue: "全部事件", locale: locale))
                        .font(.system(size: 18, weight: .semibold))
                    Text(AppLocalization.string("本次监控期间观测到的真实状态变化", defaultValue: "本次监控期间观测到的真实状态变化", locale: locale))
                        .font(.system(size: 11))
                        .foregroundStyle(CalmTheme.secondaryText)
                }
                Spacer()
                Button(AppLocalization.string("完成", defaultValue: "完成", locale: locale)) {
                    dismiss()
                }
                .buttonStyle(CalmButtonStyle(prominent: true))
            }
            .padding(18)

            Rectangle()
                .fill(CalmTheme.hairline)
                .frame(height: 1)

            if events.isEmpty {
                ContentUnavailableView(
                    AppLocalization.string("暂无事件", defaultValue: "暂无事件", locale: locale),
                    systemImage: "clock.arrow.circlepath",
                    description: Text(AppLocalization.string("继续监控后，状态变化会显示在这里。", defaultValue: "继续监控后，状态变化会显示在这里。", locale: locale))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                            DashboardEventRow(event: event)
                                .padding(.horizontal, 18)
                            if index < events.count - 1 {
                                Rectangle()
                                    .fill(CalmTheme.hairline)
                                    .frame(height: 1)
                                    .padding(.leading, 40)
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 460, minHeight: 420)
        .background(CalmTheme.canvas)
        .foregroundStyle(CalmTheme.primaryText)
    }
}

private struct TimelineTrace: View, Equatable {
    let values: [TimelinePoint]
    let color: Color
    let domain: ClosedRange<Double>?
    let windowSeconds: TimeInterval
    let latestDate: Date

    nonisolated static func == (lhs: TimelineTrace, rhs: TimelineTrace) -> Bool {
        lhs.values == rhs.values
            && lhs.domain == rhs.domain
            && lhs.windowSeconds == rhs.windowSeconds
            && lhs.latestDate == rhs.latestDate
    }

    var body: some View {
        Canvas { context, size in
            for fraction in [0.25, 0.5, 0.75] {
                let x = size.width * fraction
                var gridLine = Path()
                gridLine.move(to: CGPoint(x: x, y: 0))
                gridLine.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(gridLine, with: .color(.primary.opacity(0.045)), lineWidth: 1)
            }

            guard !values.isEmpty else { return }
            let range = resolvedDomain
            let valueSpan = max(range.upperBound - range.lowerBound, 0.001)
            var path = Path()

            for segment in DashboardTimelinePolicy.segments(values) {
                for (index, point) in segment.enumerated() {
                    guard let value = point.value else { continue }
                    let x = size.width * DashboardTimelinePolicy.normalizedX(
                        date: point.date, latestDate: latestDate, windowSeconds: windowSeconds
                    )
                    let normalized = min(max((value - range.lowerBound) / valueSpan, 0), 1)
                    let y = size.height - CGFloat(normalized) * max(size.height - 3, 1) - 1.5
                    let position = CGPoint(x: x, y: y)
                    if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
                }
            }

            context.stroke(path, with: .color(color.opacity(0.38)), lineWidth: 4)
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))

            if let last = values.last, let value = last.value {
                let normalized = min(max((value - range.lowerBound) / valueSpan, 0), 1)
                let y = size.height - CGFloat(normalized) * max(size.height - 3, 1) - 1.5
                let x = size.width * DashboardTimelinePolicy.normalizedX(
                    date: last.date, latestDate: latestDate, windowSeconds: windowSeconds
                )
                let dot = CGRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5)
                context.fill(Path(ellipseIn: dot), with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }

    private var resolvedDomain: ClosedRange<Double> {
        if let domain { return domain }
        let maximum = max(values.compactMap(\.value).max() ?? 1, 1)
        return 0 ... maximum * 1.08
    }
}

private struct DashboardProgressBar: View {
    let value: Double
    let tint: Color
    let accessibilityLabel: String
    let accessibilityValue: String

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(CalmTheme.controlBackground)
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }
}

private struct DashboardPanelModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(CalmTheme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(CalmTheme.hairline)
            }
    }
}

private extension View {
    func dashboardPanel(cornerRadius: CGFloat = 16) -> some View {
        modifier(DashboardPanelModifier(cornerRadius: cornerRadius))
    }
}
