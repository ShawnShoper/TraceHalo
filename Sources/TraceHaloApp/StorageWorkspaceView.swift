import SwiftUI
import TraceHaloCore

enum StorageWorkspaceLayout {
    static let volumeMenuMaximumWidth: CGFloat = 300
}

struct StorageHealthPresentation: Equatable {
    enum Tone: Equatable {
        case normal
        case warning
        case critical
        case neutral

        var color: Color {
            switch self {
            case .normal: CalmTheme.mint
            case .warning: CalmTheme.amber
            case .critical: CalmTheme.rose
            case .neutral: CalmTheme.tertiaryText
            }
        }
    }

    let title: String
    let detail: String
    let tone: Tone

    static func make(
        from health: StorageHealth,
        locale: Locale = TraceHaloLocalization.currentLocale()
    ) -> Self {
        let status = health.status?.trimmingCharacters(in: .whitespacesAndNewlines)
        let smartDetail = health.metrics.first { $0.kind == .smart }?.value
        let detail = smartDetail.map {
            HardwareStorageLocalization.format("SMART %@", locale: locale, $0)
        } ?? status

        let condition = StorageHealthSemanticCondition.classify(health)
        guard health.availability.isAvailable else {
            return Self(
                title: availabilityTitle(health.availability, locale: locale),
                detail: detail
                    ?? health.availability.message
                    ?? HardwareStorageLocalization.text("系统未提供健康状态", locale: locale),
                tone: .neutral
            )
        }

        switch condition {
        case .critical:
            let fallback = HardwareStorageLocalization.text("需要维护", locale: locale)
            return Self(title: status ?? fallback, detail: detail ?? fallback, tone: .critical)
        case .warning:
            let fallback = HardwareStorageLocalization.text("需要关注", locale: locale)
            return Self(title: status ?? fallback, detail: detail ?? fallback, tone: .warning)
        case .normal:
            let normal = HardwareStorageLocalization.text("正常", locale: locale)
            return Self(title: normal, detail: detail ?? normal, tone: .normal)
        case .unknown:
            return Self(
                title: status ?? HardwareStorageLocalization.text("已读取", locale: locale),
                detail: detail ?? HardwareStorageLocalization.text("健康状态已读取", locale: locale),
                tone: .neutral
            )
        }
    }

    private static func availabilityTitle(
        _ availability: CapabilityAvailability,
        locale: Locale
    ) -> String {
        switch availability {
        case .available: HardwareStorageLocalization.text("可用", locale: locale)
        case .unavailable: HardwareStorageLocalization.text("不可用", locale: locale)
        case .permissionRequired: HardwareStorageLocalization.text("需要权限", locale: locale)
        case .failed: HardwareStorageLocalization.text("读取失败", locale: locale)
        }
    }
}

struct StorageVolumePresentation: Equatable {
    let fileSystem: String
    let storageType: String
    let access: String
    let encryption: String
    let device: String
    let connection: String
    let medium: String

    static func make(
        volume: StorageVolume,
        health: StorageHealth?,
        locale: Locale = TraceHaloLocalization.currentLocale()
    ) -> Self {
        let metrics = Dictionary(
            uniqueKeysWithValues: health?.metrics.compactMap { metric in
                metric.kind.map { ($0, metric.value) }
            } ?? []
        )

        func metric(_ kind: StorageHealthMetric.Kind) -> String? {
            metrics[kind]
        }

        let unavailable = HardwareStorageLocalization.text("系统未提供", locale: locale)
        let storageType: String
        if let isInternal = volume.isInternal {
            storageType = HardwareStorageLocalization.text(
                isInternal ? "内置存储" : "外置存储",
                locale: locale
            )
        } else {
            storageType = metric(.location) ?? unavailable
        }

        let medium: String
        if let reported = metric(.mediaType) ?? metric(.media) {
            medium = reported
        } else if let isRemovable = volume.isRemovable, isRemovable {
            medium = HardwareStorageLocalization.text("可移除存储", locale: locale)
        } else {
            medium = unavailable
        }

        return Self(
            fileSystem: volume.fileSystem ?? metric(.fileSystem)
                ?? HardwareStorageLocalization.text("未知", locale: locale),
            storageType: storageType,
            access: volume.isReadOnly.map {
                HardwareStorageLocalization.text($0 ? "只读" : "读写", locale: locale)
            } ?? metric(.access) ?? unavailable,
            encryption: volume.isEncrypted.map {
                HardwareStorageLocalization.text($0 ? "已加密" : "未加密", locale: locale)
            } ?? metric(.encryption) ?? unavailable,
            device: metric(.device) ?? unavailable,
            connection: metric(.connection) ?? unavailable,
            medium: medium
        )
    }
}

enum StorageIOWindow: Int, CaseIterable, Identifiable {
    case fifteenSeconds = 15
    case thirtySeconds = 30
    case sixtySeconds = 60

    var id: Int { rawValue }
    func title(locale: Locale) -> String {
        HardwareStorageLocalization.format("过去 %lld 秒", locale: locale, Int64(rawValue))
    }
}

struct StorageView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @State private var selectedVolumeID = ""
    @State private var showsCumulativeDetails = false
    @State private var ioWindow = StorageIOWindow.sixtySeconds

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    title: localized("存储"),
                    subtitle: localized("查看卷使用情况、设备信息、健康指标与 I/O 活动"),
                    symbol: "internaldrive",
                    trailing: model.snapshot.volumes.isEmpty ? nil : AnyView(volumeMenu)
                )

                if let volume = selectedVolume {
                    overviewCard(volume)
                        .frame(height: 196)

                    GeometryReader { proxy in
                        let spacing: CGFloat = 16
                        let informationWidth = min(max(proxy.size.width * 0.35, 318), 380)

                        HStack(alignment: .top, spacing: spacing) {
                            ioActivityCard
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            volumeInformationCard(volume)
                                .frame(width: informationWidth)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(height: 380)

                    cumulativeCard
                        .frame(height: 88)
                } else {
                    EmptyCapabilityView(
                        title: localized("没有可用卷"),
                        message: localized("系统暂未返回已挂载存储卷。"),
                        symbol: "internaldrive.fill"
                    )
                    .frame(maxWidth: .infinity, minHeight: 520)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .calmPage()
        .navigationTitle(localized("存储"))
        .onAppear(perform: selectInitialVolume)
        .onChange(of: model.snapshot.volumes.map(\.id)) { _, _ in
            selectInitialVolume()
        }
        .task {
            await model.loadStorageHealthIfNeeded()
        }
        .sheet(isPresented: $showsCumulativeDetails) {
            StorageCumulativeDetailsView(
                io: model.snapshot.storageIO,
                volume: selectedVolume
            )
            .frame(width: 620, height: 470)
        }
    }

    private var volumeMenu: some View {
        Menu {
            ForEach(model.snapshot.volumes) { volume in
                Button {
                    selectedVolumeID = volume.id
                } label: {
                    Label(
                        volume.name,
                        systemImage: selectedVolumeID == volume.id ? "checkmark" : "internaldrive"
                    )
                }
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: selectedVolume?.isInternal == true ? "internaldrive" : "externaldrive")
                Text(selectedVolume?.name ?? localized("选择卷"))
                    .lineLimit(1)
                Text("·")
                    .foregroundStyle(CalmTheme.tertiaryText)
                Text(selectedVolume?.fileSystem ?? localized("格式未知"))
                    .foregroundStyle(CalmTheme.secondaryText)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CalmTheme.tertiaryText)
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .frame(maxWidth: StorageWorkspaceLayout.volumeMenuMaximumWidth)
            .frame(height: 40)
            .background(CalmTheme.controlBackground, in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(CalmTheme.strongHairline)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(localized("选择存储卷"))
    }

    private func overviewCard(_ volume: StorageVolume) -> some View {
        GeometryReader { proxy in
            let ringWidth = min(max(proxy.size.width * 0.21, 190), 230)
            let healthWidth = min(max(proxy.size.width * 0.25, 238), 280)

            HStack(spacing: 0) {
                RingGauge(
                    value: volume.usedFraction,
                    label: localized("已用"),
                    tint: CalmTheme.cyan,
                    size: 146
                )
                .frame(width: ringWidth)
                .frame(maxHeight: .infinity)

                verticalDivider

                capacitySummary(volume)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                verticalDivider

                healthSummary(volume)
                    .frame(width: healthWidth)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .storagePanel()
    }

    private func capacitySummary(_ volume: StorageVolume) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Text(volume.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("·")
                    .foregroundStyle(CalmTheme.tertiaryText)
                Text(volume.path)
                    .font(.callout.monospaced())
                    .foregroundStyle(CalmTheme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if volume.isInternal == true {
                    StatusPill(text: localized("内置"), color: CalmTheme.cyan)
                }
                if let fileSystem = volume.fileSystem {
                    StatusPill(text: fileSystem, color: CalmTheme.accent)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(storageValueParts(volume.availableBytes).number)
                    .font(.system(size: 39, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(storageValueParts(volume.availableBytes).unit)
                    .font(.title2.weight(.semibold))
            }
            .contentTransition(.numericText())
            .animation(metricAnimation, value: volume.availableBytes)

            Text(localized("可用空间"))
                .font(.callout.weight(.medium))

            GeometryReader { bar in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(CalmTheme.cyan)
                        .frame(width: bar.size.width * volume.usedFraction)
                    Rectangle()
                        .fill(CalmTheme.mint)
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            .background(CalmTheme.controlBackground, in: Capsule())
            .animation(metricAnimation, value: volume.usedFraction)

            HStack(spacing: 20) {
                capacityLegend(localized("已用"), bytes: volume.usedBytes, color: CalmTheme.cyan)
                capacityLegend(localized("可用"), bytes: volume.availableBytes, color: CalmTheme.mint)
                capacityLegend(localized("总容量"), bytes: volume.totalBytes, color: CalmTheme.tertiaryText)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private func healthSummary(_ volume: StorageVolume) -> some View {
        let health = model.storageHealth[volume.id]

        VStack(alignment: .leading, spacing: 13) {
            if model.isLoadingStorageHealth && health == nil {
                StorageHealthSkeleton()
            } else if let health {
                let presentation = StorageHealthPresentation.make(from: health, locale: locale)
                HStack(spacing: 10) {
                    Circle()
                        .fill(presentation.tone.color)
                        .frame(width: 10, height: 10)
                    Text(presentation.title)
                        .font(.title3.weight(.semibold))
                }

                Text(presentation.detail)
                    .font(.callout)
                    .foregroundStyle(CalmTheme.secondaryText)

                CalmDivider()

                DetailRow(
                    label: localized("设备温度"),
                    value: health.temperatureCelsius.map {
                        model.temperatureUnit.formatted(celsius: $0, locale: locale)
                    } ?? "—"
                )
                DetailRow(
                    label: localized("预计寿命"),
                    value: health.lifeRemainingPercent.map {
                        MetricFormatter.percent($0, locale: locale)
                    } ?? "—"
                )

                if !health.availability.isAvailable,
                   let message = health.availability.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(CalmTheme.tertiaryText)
                        .lineLimit(2)
                }
            } else {
                HStack(spacing: 10) {
                    Circle()
                        .fill(CalmTheme.tertiaryText)
                        .frame(width: 10, height: 10)
                    Text(localized("等待检测"))
                        .font(.title3.weight(.semibold))
                }
                Text(localized("健康数据将在后台读取，不会阻塞页面。"))
                    .font(.callout)
                    .foregroundStyle(CalmTheme.secondaryText)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
    }

    private var ioActivityCard: some View {
        let io = model.snapshot.storageIO
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                SectionTitle(
                    title: localized("I/O 活动"),
                    subtitle: localized("IOKit 报告的物理块存储汇总"),
                    symbol: "arrow.left.arrow.right"
                )
                Spacer()
                HStack(spacing: 8) {
                    Circle()
                        .fill(CalmTheme.mint)
                        .frame(width: 7, height: 7)
                    Text(localized("数据持续刷新"))
                        .font(.caption)
                        .foregroundStyle(CalmTheme.secondaryText)
                    Menu {
                        ForEach(StorageIOWindow.allCases) { option in
                            Button {
                                ioWindow = option
                            } label: {
                                if option == ioWindow {
                                    Label(option.title(locale: locale), systemImage: "checkmark")
                                } else {
                                    Text(option.title(locale: locale))
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(ioWindow.title(locale: locale))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(CalmTheme.controlBackground, in: RoundedRectangle(cornerRadius: 7))
                    }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                }
            }
            .padding(.bottom, 18)

            if io.availability.isAvailable {
                HStack(spacing: 20) {
                    liveIOMetric(
                        title: localized("当前读取"),
                        value: io.readBytesPerSecond,
                        operations: io.readOperationsPerSecond,
                        symbol: "arrow.down.to.line",
                        color: CalmTheme.cyan
                    )
                    verticalMetricDivider
                    liveIOMetric(
                        title: localized("当前写入"),
                        value: io.writeBytesPerSecond,
                        operations: io.writeOperationsPerSecond,
                        symbol: "arrow.up.to.line",
                        color: CalmTheme.violet
                    )
                }
                .padding(.bottom, 14)

                StorageIOHistoryChart(
                    samples: model.storageIOHistory,
                    window: ioWindow,
                    reduceMotion: reduceMotion
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyCapabilityView(
                    title: localized("块存储 I/O 不可用"),
                    message: io.availability.message ?? localized("IOKit 没有返回可靠的物理设备读写计数。"),
                    symbol: "waveform.path.ecg"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(22)
        .storagePanel()
    }

    private func volumeInformationCard(_ volume: StorageVolume) -> some View {
        let presentation = StorageVolumePresentation.make(
            volume: volume,
            health: model.storageHealth[volume.id],
            locale: locale
        )
        return VStack(alignment: .leading, spacing: 0) {
            Text(localized("卷与设备"))
                .font(.headline.weight(.semibold))
                .padding(.bottom, 18)

            storageInformationRow(localized("文件系统"), presentation.fileSystem)
            storageInformationRow(localized("类型"), presentation.storageType)
            storageInformationRow(localized("访问"), presentation.access)
            storageInformationRow(localized("加密"), presentation.encryption)
            storageInformationRow(localized("设备"), presentation.device)
            storageInformationRow(localized("连接"), presentation.connection)
            storageInformationRow(localized("介质类型"), presentation.medium, showsDivider: false)

            Spacer(minLength: 8)
            Text(localized("APFS 卷可能共享同一物理设备，I/O 不能可靠拆分到单个卷。"))
                .font(.caption)
                .foregroundStyle(CalmTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .storagePanel()
    }

    private var cumulativeCard: some View {
        let io = model.snapshot.storageIO
        return Button {
            showsCumulativeDetails = true
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "square.3.layers.3d.top.filled")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(CalmTheme.accent)
                    .frame(width: 42)

                VStack(alignment: .leading, spacing: 5) {
                    Text(localized("累计 I/O 与设备标识"))
                        .font(.headline.weight(.semibold))
                    Text(HardwareStorageLocalization.format(
                        "读取 %@ · 写入 %@",
                        locale: locale,
                        MetricFormatter.bytes(io.totalReadBytes, locale: locale),
                        MetricFormatter.bytes(io.totalWrittenBytes, locale: locale)
                    ))
                        .font(.callout)
                        .foregroundStyle(CalmTheme.secondaryText)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CalmTheme.tertiaryText)
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .storagePanel()
        .accessibilityHint(localized("打开累计读写与设备详情"))
    }

    private func liveIOMetric(
        title: String,
        value: Double?,
        operations: Double?,
        symbol: String,
        color: Color
    ) -> some View {
        HStack(alignment: .center, spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(value.map {
                        MetricFormatter.rate(bytesPerSecond: $0, locale: locale)
                    } ?? localized("正在建立基线"))
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .contentTransition(.numericText())
                    Text(operations.map {
                        HardwareStorageLocalization.format("· %.0f 次/秒", locale: locale, $0)
                    } ?? "")
                        .font(.caption)
                        .foregroundStyle(CalmTheme.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(metricAnimation, value: value)
    }

    private func storageInformationRow(
        _ label: String,
        _ value: String,
        showsDivider: Bool = true
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(label)
                    .foregroundStyle(CalmTheme.secondaryText)
                Spacer(minLength: 12)
                Text(value)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.callout)
            .frame(height: 43)

            if showsDivider { CalmDivider() }
        }
    }

    private func capacityLegend(_ title: String, bytes: UInt64, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title)
                    .foregroundStyle(CalmTheme.secondaryText)
            }
            Text(MetricFormatter.bytes(bytes, locale: locale))
                .font(.callout.monospacedDigit().weight(.semibold))
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(CalmTheme.hairline)
            .frame(width: 1)
            .padding(.vertical, 20)
    }

    private var verticalMetricDivider: some View {
        Rectangle()
            .fill(CalmTheme.hairline)
            .frame(width: 1, height: 48)
    }

    private var selectedVolume: StorageVolume? {
        model.snapshot.volumes.first { $0.id == selectedVolumeID }
            ?? model.snapshot.volumes.first
    }

    private var metricAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.22)
    }

    private func selectInitialVolume() {
        guard !model.snapshot.volumes.isEmpty else {
            selectedVolumeID = ""
            return
        }
        if !model.snapshot.volumes.contains(where: { $0.id == selectedVolumeID }) {
            selectedVolumeID = model.snapshot.volumes.first?.id ?? ""
        }
    }

    private func storageValueParts(_ bytes: UInt64) -> (number: String, unit: String) {
        let formatted = MetricFormatter.bytes(bytes, locale: locale)
        let components = formatted.split(
            maxSplits: 1,
            whereSeparator: \Character.isWhitespace
        )
        guard components.count == 2 else { return (formatted, "") }
        return (String(components[0]), String(components[1]))
    }

    private func localized(_ key: String) -> String {
        HardwareStorageLocalization.text(key, locale: locale)
    }
}

private struct StorageHealthSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @State private var isBright = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle().fill(CalmTheme.controlBackground).frame(width: 10, height: 10)
                skeleton(width: 84, height: 18)
            }
            skeleton(width: 132, height: 12)
            CalmDivider()
            skeleton(width: 176, height: 15)
            skeleton(width: 162, height: 15)
            Text(localized("正在后台读取设备健康状态…"))
                .font(.caption)
                .foregroundStyle(CalmTheme.secondaryText)
        }
        .opacity(reduceMotion ? 0.72 : (isBright ? 1 : 0.58))
        .onAppear(perform: updateAnimation)
        .onChange(of: reduceMotion) { _, _ in updateAnimation() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localized("正在后台读取设备健康状态"))
    }

    private func skeleton(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2)
            .fill(CalmTheme.controlBackground)
            .frame(width: width, height: height)
    }

    private func updateAnimation() {
        if reduceMotion {
            withAnimation(nil) { isBright = false }
        } else {
            isBright = false
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isBright = true
            }
        }
    }

    private func localized(_ key: String) -> String {
        HardwareStorageLocalization.text(key, locale: locale)
    }
}

private struct StorageIOHistoryChart: View {
    let samples: [StorageIOHistorySample]
    let window: StorageIOWindow
    let reduceMotion: Bool
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(localized("读取"))
                    .foregroundStyle(CalmTheme.cyan)
                Spacer()
                Text(localized("写入"))
                    .foregroundStyle(CalmTheme.violet)
            }
            .font(.caption.weight(.semibold))

            GeometryReader { proxy in
                let chartInsets = EdgeInsets(top: 8, leading: 52, bottom: 24, trailing: 58)
                let chartRect = CGRect(
                    x: chartInsets.leading,
                    y: chartInsets.top,
                    width: max(proxy.size.width - chartInsets.leading - chartInsets.trailing, 1),
                    height: max(proxy.size.height - chartInsets.top - chartInsets.bottom, 1)
                )

                ZStack {
                    StorageIOGrid(
                        rect: chartRect,
                        readMaximum: readMaximum,
                        writeMaximum: writeMaximum,
                        windowDuration: TimeInterval(window.rawValue)
                    )

                    AnimatedStorageIOLine(
                        samples: visibleSamples,
                        series: .read,
                        maximum: readMaximum,
                        chartRect: chartRect,
                        windowDuration: TimeInterval(window.rawValue),
                        color: CalmTheme.cyan,
                        reduceMotion: reduceMotion
                    )

                    AnimatedStorageIOLine(
                        samples: visibleSamples,
                        series: .write,
                        maximum: writeMaximum,
                        chartRect: chartRect,
                        windowDuration: TimeInterval(window.rawValue),
                        color: CalmTheme.violet,
                        reduceMotion: reduceMotion
                    )

                    if visibleSamples.count < 2 {
                        Label(localized("正在收集实时 I/O 趋势…"), systemImage: "waveform.path")
                            .font(.caption)
                            .foregroundStyle(CalmTheme.secondaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(CalmTheme.controlBackground, in: Capsule())
                            .position(x: chartRect.midX, y: chartRect.midY)
                    }
                }
            }
            .frame(minHeight: 150)

            HStack(spacing: 24) {
                Spacer()
                Label(localized("读取"), systemImage: "circle.fill")
                    .foregroundStyle(CalmTheme.cyan)
                Label(localized("写入"), systemImage: "circle.fill")
                    .foregroundStyle(CalmTheme.violet)
                Spacer()
            }
            .font(.caption)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var readMaximum: Double {
        pleasantMaximum(visibleSamples.map(\.readBytesPerSecond).max() ?? 0)
    }

    private var writeMaximum: Double {
        pleasantMaximum(visibleSamples.map(\.writeBytesPerSecond).max() ?? 0)
    }

    private var visibleSamples: [StorageIOHistorySample] {
        guard let latest = samples.last?.capturedAt else { return [] }
        let cutoff = latest.addingTimeInterval(-TimeInterval(window.rawValue))
        return samples.filter { $0.capturedAt >= cutoff && $0.capturedAt <= latest }
    }

    private func pleasantMaximum(_ raw: Double) -> Double {
        guard raw > 0 else { return 1 }
        let magnitude = pow(10, floor(log10(raw)))
        return ceil(raw / magnitude) * magnitude
    }

    private var accessibilitySummary: String {
        guard let latest = visibleSamples.last else {
            return HardwareStorageLocalization.format(
                "%@尚无 I/O 历史",
                locale: locale,
                window.title(locale: locale)
            )
        }
        return HardwareStorageLocalization.format(
            "%@ I/O，最新读取 %@，写入 %@",
            locale: locale,
            window.title(locale: locale),
            MetricFormatter.rate(bytesPerSecond: latest.readBytesPerSecond, locale: locale),
            MetricFormatter.rate(bytesPerSecond: latest.writeBytesPerSecond, locale: locale)
        )
    }

    private func localized(_ key: String) -> String {
        HardwareStorageLocalization.text(key, locale: locale)
    }
}

private struct StorageIOGrid: View {
    let rect: CGRect
    let readMaximum: Double
    let writeMaximum: Double
    let windowDuration: TimeInterval
    @Environment(\.locale) private var locale

    var body: some View {
        Canvas { context, _ in
            for row in 0...4 {
                let y = rect.minY + rect.height * CGFloat(row) / 4
                var line = Path()
                line.move(to: CGPoint(x: rect.minX, y: y))
                line.addLine(to: CGPoint(x: rect.maxX, y: y))
                context.stroke(
                    line,
                    with: .color(CalmTheme.hairline),
                    style: StrokeStyle(lineWidth: 0.7, dash: [3, 3])
                )
            }
            for column in 0...4 {
                let x = rect.minX + rect.width * CGFloat(column) / 4
                var line = Path()
                line.move(to: CGPoint(x: x, y: rect.minY))
                line.addLine(to: CGPoint(x: x, y: rect.maxY))
                context.stroke(
                    line,
                    with: .color(CalmTheme.hairline.opacity(0.7)),
                    style: StrokeStyle(lineWidth: 0.6, dash: [3, 3])
                )
            }
        }
        .overlay {
            ZStack {
                ForEach(0...4, id: \.self) { row in
                    let fraction = Double(4 - row) / 4
                    Text(compactRate(readMaximum * fraction))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(CalmTheme.tertiaryText)
                        .position(x: rect.minX - 27, y: rect.minY + rect.height * CGFloat(row) / 4)
                    Text(compactRate(writeMaximum * fraction))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(CalmTheme.tertiaryText)
                        .position(x: rect.maxX + 30, y: rect.minY + rect.height * CGFloat(row) / 4)
                }

                let labels = (0...4).map { index -> String in
                    guard index < 4 else { return localized("现在") }
                    let seconds = Int(windowDuration * Double(4 - index) / 4)
                    return HardwareStorageLocalization.format(
                        "%lld 秒前",
                        locale: locale,
                        Int64(seconds)
                    )
                }
                ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                    Text(label)
                        .font(.system(size: 9.5))
                        .foregroundStyle(CalmTheme.tertiaryText)
                        .position(
                            x: rect.minX + rect.width * CGFloat(index) / 4,
                            y: rect.maxY + 16
                        )
                }
            }
        }
    }

    private func compactRate(_ value: Double) -> String {
        value == 0 ? "0" : MetricFormatter.rate(bytesPerSecond: value, locale: locale)
    }

    private func localized(_ key: String) -> String {
        HardwareStorageLocalization.text(key, locale: locale)
    }
}

private enum StorageIOSeries: Sendable {
    case read
    case write
}

enum StorageIOLineAnimationPolicy {
    static func shouldRevealLatestSegment(
        oldSamples: [StorageIOHistorySample],
        newSamples: [StorageIOHistorySample],
        reduceMotion: Bool
    ) -> Bool {
        !reduceMotion
            && newSamples.count > 1
            && newSamples.last != oldSamples.last
    }
}

private struct AnimatedStorageIOLine: View {
    let samples: [StorageIOHistorySample]
    let series: StorageIOSeries
    let maximum: Double
    let chartRect: CGRect
    let windowDuration: TimeInterval
    let color: Color
    let reduceMotion: Bool

    @State private var reveal: CGFloat = 1

    var body: some View {
        StorageIOLineShape(
            samples: samples,
            series: series,
            maximum: maximum,
            chartRect: chartRect,
            windowDuration: windowDuration
        )
        .trim(from: 0, to: reveal)
        .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        .onChange(of: samples) { oldValue, newValue in
            guard StorageIOLineAnimationPolicy.shouldRevealLatestSegment(
                oldSamples: oldValue,
                newSamples: newValue,
                reduceMotion: reduceMotion
            ) else {
                reveal = 1
                return
            }
            let completedSegments = CGFloat(max(newValue.count - 2, 0))
            let totalSegments = CGFloat(max(newValue.count - 1, 1))
            reveal = completedSegments / totalSegments
            withAnimation(.easeOut(duration: 0.24)) {
                reveal = 1
            }
        }
        .onChange(of: reduceMotion) { _, isReduced in
            if isReduced { withAnimation(nil) { reveal = 1 } }
        }
    }
}

private struct StorageIOLineShape: Shape {

    let samples: [StorageIOHistorySample]
    let series: StorageIOSeries
    let maximum: Double
    let chartRect: CGRect
    let windowDuration: TimeInterval

    func path(in _: CGRect) -> Path {
        var path = Path()
        guard !samples.isEmpty else { return path }

        let latest = samples.last?.capturedAt ?? Date()
        for (index, sample) in samples.enumerated() {
            let secondsAgo = max(0, latest.timeIntervalSince(sample.capturedAt))
            let xFraction = min(max(1 - secondsAgo / max(windowDuration, 1), 0), 1)
            let value = series == .read ? sample.readBytesPerSecond : sample.writeBytesPerSecond
            let valueFraction = min(max(value / max(maximum, 1), 0), 1)
            let point = CGPoint(
                x: chartRect.minX + chartRect.width * xFraction,
                y: chartRect.maxY - chartRect.height * valueFraction
            )
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

private struct StorageCumulativeDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let io: StorageIOState
    let volume: StorageVolume?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                PageHeader(
                    title: localized("累计 I/O 与设备标识"),
                    subtitle: localized("IOBlockStorageDriver 本次启动以来的只读统计"),
                    symbol: "square.3.layers.3d.top.filled"
                )
                Spacer()
                Button(localized("完成")) { dismiss() }
                    .buttonStyle(CalmButtonStyle())
            }

            VStack(spacing: 0) {
                detail(localized("累计读取"), MetricFormatter.bytes(io.totalReadBytes, locale: locale))
                detail(localized("累计写入"), MetricFormatter.bytes(io.totalWrittenBytes, locale: locale))
                detail(
                    localized("读取操作"),
                    io.totalReadOperations.formatted(.number.locale(locale))
                )
                detail(
                    localized("写入操作"),
                    io.totalWriteOperations.formatted(.number.locale(locale))
                )
                detail(
                    localized("设备"),
                    io.deviceNames.isEmpty
                        ? localized("系统未提供")
                        : io.deviceNames.joined(separator: localized("列表分隔符"))
                )
                detail(localized("卷标识"), volume?.uuid ?? localized("系统未提供"), divider: false)
            }
            .storagePanel()

            Text(localized("累计值从对应驱动实例启动时开始，并非设备全生命周期总量。APFS 卷共享物理设备时，macOS 不会把读写计数可靠拆分到单个卷。"))
                .font(.callout)
                .foregroundStyle(CalmTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(24)
        .calmPage()
    }

    private func detail(_ label: String, _ value: String, divider: Bool = true) -> some View {
        VStack(spacing: 0) {
            DetailRow(label: label, value: value)
                .frame(height: 50)
            if divider { CalmDivider() }
        }
        .padding(.horizontal, 18)
    }

    private func localized(_ key: String) -> String {
        HardwareStorageLocalization.text(key, locale: locale)
    }
}

private extension View {
    func storagePanel() -> some View {
        background {
            RoundedRectangle(cornerRadius: CalmTheme.cardRadius, style: .continuous)
                .fill(CalmTheme.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: CalmTheme.cardRadius, style: .continuous)
                .strokeBorder(CalmTheme.hairline)
        }
    }
}
