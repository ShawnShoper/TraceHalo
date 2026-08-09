import AppKit
import SwiftUI
import TraceHaloCore

private enum DashboardPalette {
    static let canvas = Color(lightHex: "F3F5F6", darkHex: "20282D")
    static let rail = Color(lightHex: "EEF2F4", darkHex: "222A2F")
    static let card = Color(lightHex: "FFFFFF", darkHex: "282F33")
    static let raisedCard = Color(lightHex: "F6F8F9", darkHex: "2A3237")
    static let historyRow = Color(lightHex: "F7F9FA", darkHex: "252D31")
}

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigationRouter.self) private var navigationRouter
    @Environment(\.locale) private var locale
    @State private var historyHoverLocation: CGPoint?
    @State private var historyWindowMinutes = 60
    @State private var isShowingAllEvents = false

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width >= 960 {
                HStack(spacing: 0) {
                    primaryColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    Rectangle()
                        .fill(CalmTheme.hairline)
                        .frame(width: 1)

                    ScrollView {
                        insightRail
                            .padding(.horizontal, 19)
                            .padding(.top, 20)
                            .padding(.bottom, 20)
                    }
                    .scrollIndicators(.hidden)
                    .frame(width: 308)
                    .background(DashboardPalette.rail)
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        primaryColumn
                        Rectangle()
                            .fill(CalmTheme.hairline)
                            .frame(height: 1)
                        insightRail
                            .padding(22)
                    }
                }
            }
        }
        .foregroundStyle(CalmTheme.primaryText)
        .background(DashboardPalette.canvas.ignoresSafeArea())
        .navigationTitle("TraceHalo")
        .onAppear {
            if model.dataSource == .fixture, historyHoverLocation == nil {
                historyHoverLocation = CGPoint(x: 450, y: 104)
            }
        }
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
        .padding(.horizontal, 34)
        .frame(height: 92)
    }

    private var healthIdentity: some View {
        HStack(spacing: 15) {
            ZStack {
                Circle()
                    .fill(model.overallState.color.opacity(0.16))
                Image(systemName: model.overallState.symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(model.overallState.color)
            }
            .frame(width: 42, height: 42)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(healthTitle)
                    .font(.system(size: 20, weight: .semibold))
                Text("\(deviceDisplayName) · \(model.snapshot.identity.chipName)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(CalmTheme.secondaryText)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            AppLocalization.format(
                "dashboard.health.accessibility",
                defaultValue: "%@，%@，%@",
                locale: locale,
                healthTitle,
                deviceDisplayName,
                model.snapshot.identity.chipName
            )
        )
    }

    private var headerActions: some View {
        HStack(spacing: 12) {
            Button {
                navigationRouter.navigate(to: .report)
            } label: {
                Label("展开诊断", systemImage: "waveform.path.ecg")
            }
            .buttonStyle(CalmButtonStyle(prominent: true))
            .help("打开系统报告")

            Button {
                navigationRouter.navigate(to: .monitor)
            } label: {
                Label("菜单栏布局", systemImage: "menubar.rectangle")
            }
            .buttonStyle(CalmButtonStyle())
            .help("打开菜单栏监视器布局")
        }
    }

    private var primaryColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            healthHeader
            topologySection
            resourceHistory
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var topologySection: some View {
        ViewThatFits(in: .horizontal) {
            wideTopology
                .frame(minWidth: 650)
            compactTopology
                .padding(.horizontal, 24)
        }
        .padding(.horizontal, 34)
        .padding(.bottom, 10)
    }

    private var wideTopology: some View {
        GeometryReader { proxy in
            let cardWidth = min(240.0, max(220.0, (proxy.size.width - 228) / 2))
            let leftX = cardWidth / 2
            let rightX = proxy.size.width - cardWidth / 2
            let centerX = proxy.size.width / 2
            let rowY: [CGFloat] = [43, 144, 245]

            ZStack {
                TopologyConnectors(
                    leftEdgeX: cardWidth,
                    rightEdgeX: proxy.size.width - cardWidth,
                    centerX: centerX,
                    rowY: rowY,
                    leftColors: [CalmTheme.accent, CalmTheme.violet, CalmTheme.cyan],
                    rightColors: [CalmTheme.cyan, CalmTheme.mint, CalmTheme.amber]
                )
                .accessibilityHidden(true)

                topologyCard(for: .cpu)
                    .frame(width: cardWidth, height: 78)
                    .position(x: leftX, y: rowY[0])
                topologyCard(for: .memory)
                    .frame(width: cardWidth, height: 78)
                    .position(x: leftX, y: rowY[1])
                topologyCard(for: .storage)
                    .frame(width: cardWidth, height: 78)
                    .position(x: leftX, y: rowY[2])

                TopologyCenterNode(
                    modelName: deviceDisplayName,
                    modelIdentifier: model.snapshot.identity.modelIdentifier,
                    chipName: model.snapshot.identity.chipName,
                    stateColor: model.overallState.color
                )
                .position(x: centerX, y: rowY[1])

                topologyCard(for: .gpu)
                    .frame(width: cardWidth, height: 78)
                    .position(x: rightX, y: rowY[0])
                topologyCard(for: .cooling)
                    .frame(width: cardWidth, height: 78)
                    .position(x: rightX, y: rowY[1])
                topologyCard(for: .network)
                    .frame(width: cardWidth, height: 78)
                    .position(x: rightX, y: rowY[2])
            }
        }
        .frame(height: 312)
    }

    private var compactTopology: some View {
        VStack(spacing: 16) {
            TopologyCenterNode(
                modelName: deviceDisplayName,
                modelIdentifier: model.snapshot.identity.modelIdentifier,
                chipName: model.snapshot.identity.chipName,
                stateColor: model.overallState.color
            )

            ZStack {
                Rectangle()
                    .fill(.primary.opacity(0.09))
                    .frame(width: 1)
                    .padding(.vertical, 8)
                    .accessibilityHidden(true)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 196), spacing: 12)], spacing: 12) {
                    ForEach(TopologyMetric.allCases) { metric in
                        topologyCard(for: metric)
                            .frame(minHeight: 104)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func topologyCard(for metric: TopologyMetric) -> some View {
        let content = topologyContent(for: metric)
        Button {
            navigationRouter.navigate(to: topologyDestination(for: metric))
        } label: {
            if metric == .network {
                NetworkTopologyMetricCard(
                    received: aggregateRate(networkReceivedRates),
                    sent: aggregateRate(networkSentRates),
                    detail: activeInterfaceSummary,
                    points: content.points
                )
            } else {
                TopologyMetricCard(
                    title: content.title,
                    value: content.value,
                    detail: content.detail,
                    symbol: content.symbol,
                    tint: content.tint,
                    points: content.points
                )
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .accessibilityHint(openDestinationLabel(for: metric))
        .help(openDestinationLabel(for: metric))
    }

    private func topologyDestination(for metric: TopologyMetric) -> AppDestination {
        switch metric {
        case .cpu, .memory, .network: .monitor
        case .gpu: .graphics
        case .cooling: .cooling
        case .storage: .storage
        }
    }

    private func topologyContent(for metric: TopologyMetric) -> TopologyCardContent {
        switch metric {
        case .cpu:
            TopologyCardContent(
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
            TopologyCardContent(
                title: "GPU",
                value: model.snapshot.gpus.first?.utilizationPercent.map { MetricFormatter.percent($0) } ?? "—",
                detail: gpuDetail,
                symbol: "display",
                tint: CalmTheme.cyan,
                points: model.history(for: .gpuUsage)
            )
        case .memory:
            TopologyCardContent(
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
            TopologyCardContent(
                title: "散热",
                value: temperatureValue,
                detail: coolingDetail,
                symbol: "fan",
                tint: CalmTheme.mint,
                points: model.history(for: .temperature)
            )
        case .storage:
            TopologyCardContent(
                title: "存储",
                value: primaryVolume.map { MetricFormatter.percent($0.usedFraction * 100) } ?? "—",
                detail: primaryVolume.map {
                    AppLocalization.format(
                        "dashboard.storage.available",
                        defaultValue: "可用 %@",
                        locale: locale,
                        MetricFormatter.bytes($0.availableBytes)
                    )
                } ?? localized("没有已挂载卷"),
                symbol: "internaldrive",
                tint: CalmTheme.cyan,
                points: timelineSamples.compactMap(\.storageUsedPercent)
            )
        case .network:
            TopologyCardContent(
                title: "网络",
                value: aggregateRate(networkReceivedRates),
                detail: "↑ \(aggregateRate(networkSentRates)) · \(activeInterfaceSummary)",
                symbol: "globe",
                tint: CalmTheme.amber,
                points: model.history(for: .networkReceived)
            )
        }
    }

    private var resourceHistory: some View {
        let visibleSamples = visibleTimelineSamples
        let plottedSamples = downsampledTimelineSamples(visibleSamples, limit: 240)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Menu {
                    ForEach([15, 30, 60], id: \.self) { minutes in
                        Button(minutesLabel(minutes)) {
                            historyWindowMinutes = minutes
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(historyTitle)
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(CalmTheme.primaryText)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer(minLength: 6)
                historyLegend
                Spacer(minLength: 6)

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

                Button {
                    navigationRouter.navigate(to: .monitor)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 25, height: 25)
                        .background(CalmTheme.controlBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(CalmTheme.hairline)
                        }
                }
                .buttonStyle(.plain)
                .help("打开实时监控")
                .accessibilityLabel("打开实时监控")
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
                            values: plottedSamples.compactMap { sample in
                                sample.gpuPercent.map { TimelinePoint(date: sample.date, value: $0) }
                            },
                            domain: 0 ... 100
                        )
                        historyRow(
                            title: "内存",
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
                            values: plottedSamples.compactMap { sample in
                                sample.storageUsedPercent.map { TimelinePoint(date: sample.date, value: $0) }
                            },
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
                            values: plottedSamples.compactMap { sample in
                                sample.temperatureCelsius.map { TimelinePoint(date: sample.date, value: $0) }
                            },
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
                        historyHoverLocation = model.dataSource == .fixture
                            ? CGPoint(x: proxy.size.width * 0.62, y: proxy.size.height / 2)
                            : nil
                    }
                }
            }
            .frame(height: 186)

            historyAxis
        }
        .padding(.horizontal, 18)
        .padding(.top, 15)
        .padding(.bottom, 12)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(CalmTheme.hairline)
                .frame(height: 1)
        }
    }

    private var historyLegend: some View {
        HStack(spacing: 10) {
            legendItem("CPU", color: CalmTheme.accent)
            legendItem("GPU", color: CalmTheme.cyan)
            legendItem("内存", color: CalmTheme.violet)
            legendItem("存储", color: CalmTheme.cyan)
            legendItem("网络", color: CalmTheme.amber)
            legendItem("温度", color: CalmTheme.mint)
        }
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(localized(title))
                .font(.system(size: 9.5))
                .foregroundStyle(CalmTheme.secondaryText)
        }
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
            Text("刚刚")
        }
        .font(.system(size: 9, design: .monospaced))
        .foregroundStyle(CalmTheme.tertiaryText)
        .padding(.leading, 58)
        .padding(.trailing, 63)
    }

    private var visibleTimelineSamples: [DashboardTelemetrySample] {
        guard let latest = timelineSamples.last?.date else { return [] }
        let cutoff = latest.addingTimeInterval(-TimeInterval(historyWindowMinutes * 60))
        return timelineSamples.filter { $0.date >= cutoff }
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
        guard let latest = samples.last?.date, !samples.isEmpty else { return nil }
        let plotStart: CGFloat = 58
        let plotEnd = max(width - 68, plotStart + 1)
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
        if lowerBound == 0 { return samples[0] }
        if lowerBound == samples.count { return samples[samples.count - 1] }
        let previous = samples[lowerBound - 1]
        let next = samples[lowerBound]
        return abs(previous.date.timeIntervalSince(target)) <= abs(next.date.timeIntervalSince(target))
            ? previous
            : next
    }

    private func historySelectionOverlay(
        sample: DashboardTelemetrySample,
        x: CGFloat,
        size: CGSize
    ) -> some View {
        let plotStart: CGFloat = 58
        let plotEnd = max(size.width - 68, plotStart + 1)
        let clampedX = min(max(x, plotStart), plotEnd)
        let tooltipWidth: CGFloat = 148
        let tooltipX = min(max(clampedX + 12, tooltipWidth / 2), size.width - tooltipWidth / 2)

        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.white.opacity(0.72))
                .frame(width: 1, height: size.height + 14)
                .position(x: clampedX, y: size.height / 2)

            Circle()
                .fill(Color.white)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(CalmTheme.canvas, lineWidth: 1.5))
                .position(x: clampedX, y: size.height + 3)

            DashboardHistoryTooltip(
                sample: sample,
                temperatureUnit: model.temperatureUnit,
                latestDate: timelineSamples.last?.date ?? sample.date
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
        HStack(spacing: 10) {
            Text(localized(title))
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 48, alignment: .leading)

            TimelineTrace(
                values: values,
                color: color,
                domain: domain,
                windowSeconds: TimeInterval(historyWindowMinutes * 60)
            )
            .equatable()
            .frame(height: 22)

            Text(value)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .frame(width: 68, alignment: .trailing)
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(DashboardPalette.historyRow, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.primary.opacity(0.055))
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
        VStack(alignment: .leading, spacing: 10) {
            Text("此刻与变化")
                .font(.system(size: 14, weight: .semibold))

            currentStatusCard
            memoryChangeCard
            fanCard
            temperatureCard
            eventLogCard
        }
    }

    private var currentStatusCard: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: model.overallState.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(model.overallState.color)
                .frame(width: 34, height: 34)
                .background(model.overallState.color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(statusRailTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(model.overallState.color)
                Text(model.lastError ?? statusExplanation)
                    .font(.system(size: 9.5))
                    .foregroundStyle(CalmTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .dashboardPanel(cornerRadius: 10)
        .accessibilityElement(children: .combine)
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

    private var fanCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("风扇转速", systemImage: "fan")
                .font(.system(size: 12, weight: .semibold))

            if model.snapshot.cooling.fans.isEmpty {
                Text(
                    localized(
                        model.snapshot.cooling.sensorAvailability.message
                            ?? "未读取到风扇转速"
                    )
                )
                    .font(.system(size: 12))
                    .foregroundStyle(CalmTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(model.snapshot.cooling.fans.prefix(4)) { fan in
                    VStack(spacing: 5) {
                        HStack {
                            Text(fan.name)
                                .lineLimit(1)
                            Spacer()
                            Text(
                                "\(fan.currentRPM.formatted(.number.locale(locale))) RPM"
                            )
                                .font(.caption.monospacedDigit().weight(.semibold))
                        }
                        .font(.system(size: 10))
                        DashboardProgressBar(
                            value: fanProgress(fan),
                            tint: CalmTheme.cyan,
                            accessibilityLabel: AppLocalization.format(
                                "dashboard.fan.accessibility",
                                defaultValue: "%@ 转速",
                                locale: locale,
                                fan.name
                            ),
                            accessibilityValue: "\(fan.currentRPM) RPM"
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .dashboardPanel(cornerRadius: 10)
    }

    private var temperatureCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("温度概览", systemImage: "thermometer.medium")
                .font(.system(size: 12, weight: .semibold))
            HStack {
                Text("CPU 平均")
                    .font(.system(size: 10))
                    .foregroundStyle(CalmTheme.secondaryText)
                Spacer()
                Text(temperatureValue)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            DashboardProgressBar(
                value: temperatureProgress,
                tint: temperatureColor,
                accessibilityLabel: localized("CPU 平均温度"),
                accessibilityValue: temperatureValue
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .dashboardPanel(cornerRadius: 10)
        .accessibilityElement(children: .combine)
    }

    private var eventLogCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("事件记录")
                .font(.system(size: 12, weight: .semibold))
                .padding(.bottom, 7)

            if model.dashboardEvents.isEmpty {
                Text("暂无新的状态变化")
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
                Text("查看全部事件")
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

    private var statusRailTitle: String {
        localized(rawStatusRailTitle)
    }

    private var rawStatusRailTitle: String {
        switch model.overallState {
        case .normal: "暂无异常"
        case .attention: "需要关注"
        case .critical: "需要处理"
        case .limited: "部分数据受限"
        case .monitoring: "正在监测"
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
        relevantNetworkInterfaces.compactMap(\.receivedBytesPerSecond)
    }

    private var networkSentRates: [Double] {
        relevantNetworkInterfaces.compactMap(\.sentBytesPerSecond)
    }

    private var activeInterfaceSummary: String {
        let names = relevantNetworkInterfaces.filter(\.isActive).map(\.displayName)
        return names.isEmpty ? localized("无活动连接") : names.prefix(2).joined(separator: " · ")
    }

    private var relevantNetworkInterfaces: [NetworkInterfaceState] {
        model.snapshot.networkInterfaces.filter { interface in
            let name = interface.name.lowercased()
            let excludedPrefixes = [
                "lo", "utun", "awdl", "llw", "bridge", "gif", "stf", "anpi", "ap", "pktap"
            ]
            return !excludedPrefixes.contains(where: name.hasPrefix)
                && (name.hasPrefix("en") || interface.isActive)
        }
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

    private var temperatureProgress: Double {
        min(max((measuredTemperature ?? 0) / 100, 0), 1)
    }

    private var temperatureColor: Color {
        guard let value = measuredTemperature else { return .secondary }
        if value >= 85 { return CalmTheme.rose }
        if value >= 70 { return CalmTheme.amber }
        return CalmTheme.mint
    }

    private var coolingDetail: String {
        let condition = thermalConditionTitle(model.snapshot.cooling.condition)
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
        guard let GPU = model.snapshot.gpus.first else { return localized("没有图形设备数据") }
        let temperature = GPU.temperatureCelsius.map {
            model.temperatureUnit.formatted(celsius: $0, locale: locale)
        }
            ?? localized("温度不可用")
        return "\(GPU.name) · \(temperature)"
    }

    private func aggregateRate(_ rates: [Double]) -> String {
        guard !rates.isEmpty else { return "—" }
        return MetricFormatter.rate(bytesPerSecond: rates.reduce(0, +))
    }

    private func fanProgress(_ fan: FanState) -> Double {
        let maximum = fan.maximumRPM ?? max(fan.currentRPM, 1)
        guard maximum > 0 else { return 0 }
        return min(max(Double(fan.currentRPM) / Double(maximum), 0), 1)
    }

    private var memoryChange: Double? {
        guard let first = timelineSamples.first?.memoryPressurePercent,
              let last = timelineSamples.last?.memoryPressurePercent,
              timelineSamples.count > 1
        else { return nil }
        return last - first
    }

    private var memoryChangeTitle: String {
        guard let memoryChange else { return localized("正在建立变化基线") }
        if abs(memoryChange) < 0.5 { return localized("内存压力保持稳定") }
        let direction = localized(memoryChange > 0 ? "上升" : "下降")
        return AppLocalization.format(
            "dashboard.memory.change",
            defaultValue: "内存压力%@ %@",
            locale: locale,
            direction,
            MetricFormatter.percent(abs(memoryChange))
        )
    }

    private var memoryChangeDetail: String {
        guard let first = timelineSamples.first?.date else { return localized("等待下一次真实采样") }
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

    private var historyTitle: String {
        AppLocalization.format(
            "dashboard.history.title",
            defaultValue: "资源历史（%ld 分钟）",
            locale: locale,
            historyWindowMinutes
        )
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

    private func openDestinationLabel(for metric: TopologyMetric) -> String {
        AppLocalization.format(
            "dashboard.open.destination",
            defaultValue: "打开%@",
            locale: locale,
            topologyDestination(for: metric).title
        )
    }

    private func localized(_ value: String) -> String {
        AppLocalization.string(value, defaultValue: value, locale: locale)
    }

}

private enum TopologyMetric: String, CaseIterable, Identifiable {
    case cpu
    case gpu
    case memory
    case cooling
    case storage
    case network

    var id: String { rawValue }
}

private struct TopologyCardContent {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color
    let points: [Double]
}

private struct TimelinePoint: Identifiable, Equatable {
    let date: Date
    let value: Double

    var id: Date { date }
}

private struct TopologyMetricCard: View {
    @Environment(\.locale) private var locale
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color
    let points: [Double]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 11) {
                metricIcon
                metricLabels
                Spacer(minLength: 2)
                if !points.isEmpty {
                    Sparkline(values: points, color: tint, fill: false)
                        .frame(width: 42, height: 27)
                }
            }
            .frame(minWidth: 202)

            HStack(spacing: 11) {
                metricIcon
                metricLabels
                Spacer(minLength: 0)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(DashboardPalette.raisedCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(CalmTheme.strongHairline)
        }
        .accessibilityElement(children: .combine)
    }

    private var metricIcon: some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var metricLabels: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(localized(title))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(CalmTheme.secondaryText)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(localized(detail))
                .font(.system(size: 8.5))
                .foregroundStyle(CalmTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .layoutPriority(1)
    }

    private func localized(_ value: String) -> String {
        AppLocalization.string(value, defaultValue: value, locale: locale)
    }
}

private struct NetworkTopologyMetricCard: View {
    @Environment(\.locale) private var locale
    let received: String
    let sent: String
    let detail: String
    let points: [Double]

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "globe")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(CalmTheme.amber)
                .frame(width: 44, height: 44)
                .background(
                    CalmTheme.amber.opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("网络")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(CalmTheme.secondaryText)
                VStack(alignment: .leading, spacing: 0) {
                    Text("↑ \(sent)")
                    Text("↓ \(received)")
                }
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Text(AppLocalization.string(detail, defaultValue: detail, locale: locale))
                    .font(.system(size: 8.5))
                    .foregroundStyle(CalmTheme.secondaryText)
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 2)
            if !points.isEmpty {
                Sparkline(values: points, color: CalmTheme.amber, fill: false)
                    .frame(width: 42, height: 27)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(DashboardPalette.raisedCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(CalmTheme.strongHairline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            AppLocalization.format(
                "dashboard.network.accessibility",
                defaultValue: "网络，上行 %@，下行 %@，%@",
                locale: locale,
                sent,
                received,
                AppLocalization.string(detail, defaultValue: detail, locale: locale)
            )
        )
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
            tooltipRow("内存", value: MetricFormatter.percent(sample.memoryPressurePercent), color: CalmTheme.violet)
            tooltipRow("存储", value: optionalPercent(sample.storageUsedPercent), color: CalmTheme.cyan)
            tooltipRow(
                "网络",
                value: MetricFormatter.rate(bytesPerSecond: sample.networkBytesPerSecond),
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
                .strokeBorder(CalmTheme.strongHairline)
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
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(1)
                Text(event.localizedDetail(locale: locale))
                    .font(.system(size: 8.5))
                    .foregroundStyle(CalmTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
            Text(event.occurredAt, style: .relative)
                .font(.system(size: 8.5))
                .foregroundStyle(CalmTheme.tertiaryText)
                .lineLimit(1)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

private struct DashboardEventListSheet: View {
    @Environment(\.dismiss) private var dismiss

    let events: [DashboardEventRecord]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("全部事件")
                        .font(.system(size: 18, weight: .semibold))
                    Text("本次监控期间观测到的真实状态变化")
                        .font(.system(size: 11))
                        .foregroundStyle(CalmTheme.secondaryText)
                }
                Spacer()
                Button("完成") {
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
                    "暂无事件",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("继续监控后，状态变化会显示在这里。")
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
        .background(DashboardPalette.canvas)
        .foregroundStyle(CalmTheme.primaryText)
    }
}

private struct TopologyCenterNode: View {
    @Environment(\.locale) private var locale
    let modelName: String
    let modelIdentifier: String
    let chipName: String
    let stateColor: Color

    var body: some View {
        let artwork = SystemDeviceArtworkResolver.shared.artwork(
            modelIdentifier: modelIdentifier,
            modelName: modelName
        )

        ZStack {
            Circle()
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                .frame(width: 130, height: 130)
            Circle()
                .strokeBorder(CalmTheme.accent.opacity(0.68), lineWidth: 2)
                .frame(width: 118, height: 118)
            Circle()
                .fill(DashboardPalette.raisedCard)
                .frame(width: 108, height: 108)
                .shadow(color: CalmTheme.accent.opacity(0.16), radius: 14)

            VStack(spacing: 3) {
                if let deviceImage = artwork.image {
                    Image(nsImage: deviceImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 70, height: 35)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: artwork.symbolName)
                        .font(.system(size: 34, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(CalmTheme.secondaryText)
                        .accessibilityHidden(true)
                }
                Text(modelName)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                Text(chipName)
                    .font(.system(size: 8.5))
                    .foregroundStyle(CalmTheme.secondaryText)
                    .lineLimit(1)
            }
            .frame(width: 94)

            Circle()
                .fill(stateColor)
                .frame(width: 9, height: 9)
                .overlay(Circle().stroke(CalmTheme.canvas, lineWidth: 2))
                .offset(x: 41, y: -41)
        }
        .frame(width: 130, height: 130)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            AppLocalization.format(
                "dashboard.center.accessibility",
                defaultValue: "系统中心，%@，%@",
                locale: locale,
                modelName,
                chipName
            )
        )
    }
}

private struct TopologyConnectors: View {
    let leftEdgeX: CGFloat
    let rightEdgeX: CGFloat
    let centerX: CGFloat
    let rowY: [CGFloat]
    let leftColors: [Color]
    let rightColors: [Color]

    var body: some View {
        Canvas { context, size in
            guard rowY.count == 3 else { return }
            let centerRadius = 59.0

            for y in rowY {
                var leftPath = Path()
                leftPath.move(to: CGPoint(x: leftEdgeX, y: y))
                leftPath.addCurve(
                    to: CGPoint(x: centerX - centerRadius, y: rowY[1]),
                    control1: CGPoint(x: leftEdgeX + 44, y: y),
                    control2: CGPoint(x: centerX - centerRadius - 34, y: rowY[1])
                )
                context.stroke(leftPath, with: .color(.primary.opacity(0.14)), lineWidth: 1.5)

                var rightPath = Path()
                rightPath.move(to: CGPoint(x: rightEdgeX, y: y))
                rightPath.addCurve(
                    to: CGPoint(x: centerX + centerRadius, y: rowY[1]),
                    control1: CGPoint(x: rightEdgeX - 44, y: y),
                    control2: CGPoint(x: centerX + centerRadius + 34, y: rowY[1])
                )
                context.stroke(rightPath, with: .color(.primary.opacity(0.14)), lineWidth: 1.5)
            }

            let pointsAndColors = zip(
                [
                    CGPoint(x: leftEdgeX, y: rowY[0]),
                    CGPoint(x: leftEdgeX, y: rowY[1]),
                    CGPoint(x: leftEdgeX, y: rowY[2]),
                    CGPoint(x: rightEdgeX, y: rowY[0]),
                    CGPoint(x: rightEdgeX, y: rowY[1]),
                    CGPoint(x: rightEdgeX, y: rowY[2])
                ],
                leftColors + rightColors
            )
            for (point, color) in pointsAndColors {
                let rect = CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7)
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
    }
}

private struct TimelineTrace: View, Equatable {
    let values: [TimelinePoint]
    let color: Color
    let domain: ClosedRange<Double>?
    let windowSeconds: TimeInterval

    nonisolated static func == (lhs: TimelineTrace, rhs: TimelineTrace) -> Bool {
        lhs.values == rhs.values
            && lhs.domain == rhs.domain
            && lhs.windowSeconds == rhs.windowSeconds
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
            let latestDate = values.last?.date ?? Date()
            let range = resolvedDomain
            let valueSpan = max(range.upperBound - range.lowerBound, 0.001)
            var path = Path()

            for (index, point) in values.enumerated() {
                let age = latestDate.timeIntervalSince(point.date)
                let x = size.width * (1 - min(max(age / max(windowSeconds, 1), 0), 1))
                let normalized = min(max((point.value - range.lowerBound) / valueSpan, 0), 1)
                let y = size.height - CGFloat(normalized) * max(size.height - 3, 1) - 1.5
                let position = CGPoint(x: x, y: y)
                if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
            }

            context.stroke(path, with: .color(color.opacity(0.38)), lineWidth: 4)
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))

            if let last = values.last {
                let normalized = min(max((last.value - range.lowerBound) / valueSpan, 0), 1)
                let y = size.height - CGFloat(normalized) * max(size.height - 3, 1) - 1.5
                let dot = CGRect(x: size.width - 2.5, y: y - 2.5, width: 5, height: 5)
                context.fill(Path(ellipseIn: dot), with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }

    private var resolvedDomain: ClosedRange<Double> {
        if let domain { return domain }
        let maximum = max(values.map(\.value).max() ?? 1, 1)
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
            .background(DashboardPalette.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
