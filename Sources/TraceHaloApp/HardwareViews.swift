import SwiftUI
import TraceHaloCore

enum HardwareStorageLocalization {
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

    static func format(
        _ key: String,
        locale: Locale,
        _ arguments: CVarArg...
    ) -> String {
        format(key, locale: locale, arguments: arguments)
    }

    static func format(
        _ key: String,
        locale: Locale,
        lookup: Lookup,
        _ arguments: CVarArg...
    ) -> String {
        format(key, locale: locale, lookup: lookup, arguments: arguments)
    }

    static func format(
        _ key: String,
        locale: Locale,
        lookup: Lookup = { key, defaultValue, locale in
            AppLocalization.string(key, defaultValue: defaultValue, locale: locale)
        },
        arguments: [CVarArg]
    ) -> String {
        String(
            format: text(key, locale: locale, lookup: lookup),
            locale: locale,
            arguments: arguments
        )
    }

    static func integer(_ value: Int, locale: Locale) -> String {
        value.formatted(.number.locale(locale))
    }

    static func inputKindTitle(_ kind: InputDeviceKind, locale: Locale) -> String {
        switch kind {
        case .keyboard: text("键盘", locale: locale)
        case .mouse: text("鼠标", locale: locale)
        case .trackpad: text("触控板", locale: locale)
        case .pointingDevice: text("指针", locale: locale)
        }
    }

    static func chargingTitle(_ state: InputDeviceChargingState, locale: Locale) -> String {
        switch state {
        case .charging: text("正在充电", locale: locale)
        case .notCharging: text("未在充电", locale: locale)
        case .unknown: text("系统未明确报告", locale: locale)
        }
    }

    static func batteryHealthTitle(_ health: BatteryHealth, locale: Locale) -> String {
        switch health {
        case .excellent: text("优秀", locale: locale)
        case .good: text("正常", locale: locale)
        case .aging: text("逐渐老化", locale: locale)
        case .serviceRecommended: text("建议检修", locale: locale)
        case .unknown: text("未知", locale: locale)
        }
    }

    static func thermalConditionTitle(_ condition: ThermalCondition, locale: Locale) -> String {
        switch condition {
        case .nominal: text("正常", locale: locale)
        case .fair: text("温度升高", locale: locale)
        case .serious: text("温度较高", locale: locale)
        case .critical: text("需要关注", locale: locale)
        case .unavailable: text("未知", locale: locale)
        }
    }
}

enum InputDevicePrivacyFormatter {
    static func maskedSerialNumber(_ serialNumber: String) -> String {
        let trimmed = serialNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 4 else { return "••••" }
        return "•••• \(trimmed.suffix(4))"
    }
}

struct GraphicsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: localized("图形"),
                    subtitle: localized("查看图形处理器、驱动能力、使用率与显示器连接"),
                    symbol: "display"
                )

                if model.snapshot.gpus.isEmpty {
                    EmptyCapabilityView(
                        title: localized("没有图形数据"),
                        message: localized("系统暂未返回图形设备信息。"),
                        symbol: "display"
                    )
                } else {
                    ForEach(model.snapshot.gpus) { gpu in
                        gpuCard(gpu)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1_180, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .calmPage()
        .navigationTitle(localized("图形"))
    }

    private func gpuCard(_ gpu: GPUState) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Image(systemName: "rectangle.3.group.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(CalmTheme.violet)
                    .frame(width: 62, height: 62)
                    .background(CalmTheme.violet.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 5) {
                    Text(gpu.name)
                        .font(.title3.weight(.semibold))
                    Text(HardwareStorageLocalization.format(
                        "%@ · %@",
                        locale: locale,
                        gpu.vendor,
                        gpu.family ?? localized("系列未知")
                    ))
                        .font(.callout)
                        .foregroundStyle(CalmTheme.secondaryText)
                }
                Spacer()
                RingGauge(value: gpu.utilizationPercent.map { $0 / 100 }, label: "GPU", tint: CalmTheme.violet, size: 94)
            }

            CalmDivider()

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 12) {
                graphicDetail(localized("设备型号"), gpu.name, "cpu")
                graphicDetail(localized("硬件标识"), gpu.modelIdentifier ?? localized("系统未提供"), "number")
                graphicDetail(
                    localized("图形核心"),
                    gpu.coreCount.map {
                        AppCountLocalization.format(
                            count: $0,
                            oneKey: "hardware.core.count.one",
                            otherKey: "hardware.core.count.other",
                            oneDefaultValue: "%lld 核",
                            otherDefaultValue: "%lld 核",
                            locale: locale,
                            Int64($0)
                        )
                    } ?? localized("系统未提供"),
                    "square.grid.3x3"
                )
                graphicDetail("Metal Family", gpu.metalSupport ?? localized("系统未提供"), "sparkles")
                graphicDetail(
                    localized("内存架构"),
                    gpu.hasUnifiedMemory.map {
                        localized($0 ? "统一内存" : "独立显存")
                    } ?? localized("系统未提供"),
                    "memorychip"
                )
                graphicDetail(localized("建议工作集上限"), gpu.memoryDescription ?? localized("系统未提供"), "gauge.with.dots.needle.67percent")
                graphicDetail(localized("驱动组件"), gpu.driver ?? localized("系统未提供"), "gearshape")
                graphicDetail(
                    "Registry ID",
                    gpu.registryID.map { String(format: "0x%llX", $0) } ?? localized("系统未提供"),
                    "barcode"
                )
                graphicDetail(
                    localized("温度"),
                    gpu.temperatureCelsius.map {
                        model.temperatureUnit.formatted(celsius: $0, locale: locale)
                    } ?? localized("当前不可用"),
                    "thermometer.medium"
                )
            }

            SectionTitle(
                title: localized("设备能力"),
                subtitle: localized("由 Metal 直接报告"),
                symbol: "checklist"
            )
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 12) {
                graphicDetail(localized("计算管线光线追踪 API"), capabilityTitle(gpu.supportsRayTracing), "scope")
                graphicDetail(
                    localized("渲染管线光线追踪 API"),
                    capabilityTitle(gpu.supportsRayTracingInRenderPipelines),
                    "scope"
                )
                graphicDetail(localized("计算管线动态库"), capabilityTitle(gpu.supportsDynamicLibraries), "shippingbox")
                graphicDetail(
                    localized("渲染管线动态库"),
                    capabilityTitle(gpu.supportsRenderDynamicLibraries),
                    "shippingbox"
                )
                graphicDetail("Argument Buffer", gpu.argumentBufferTier ?? localized("系统未提供"), "square.stack.3d.up")
                graphicDetail(
                    localized("最大缓冲区"),
                    gpu.maximumBufferLengthBytes.map {
                        MetricFormatter.bytes($0, locale: locale)
                    } ?? localized("系统未提供"),
                    "rectangle.stack"
                )
                graphicDetail(
                    localized("线程组内存"),
                    gpu.maximumThreadgroupMemoryBytes.map {
                        MetricFormatter.bytes($0, locale: locale)
                    } ?? localized("系统未提供"),
                    "memorychip"
                )
                graphicDetail(
                    localized("线程组每轴上限"),
                    gpu.maximumThreadsPerThreadgroup ?? localized("系统未提供"),
                    "circle.grid.3x3"
                )
                graphicDetail(localized("低功耗设备"), booleanTitle(gpu.isLowPower), "leaf")
                graphicDetail(localized("可移除设备"), booleanTitle(gpu.isRemovable), "eject")
            }

            if !gpu.displays.isEmpty {
                SectionTitle(title: localized("连接的显示器"), symbol: "rectangle.connected.to.line.below")
                ForEach(gpu.displays) { display in
                    HStack(spacing: 13) {
                        Image(systemName: "display")
                            .font(.title3)
                            .foregroundStyle(CalmTheme.cyan)
                            .frame(width: 42, height: 38)
                            .background(CalmTheme.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(display.name).font(.callout.weight(.medium))
                                if display.isMain { StatusPill(text: localized("主显示器"), color: CalmTheme.cyan) }
                                if display.isBuiltIn { StatusPill(text: localized("内置"), color: .secondary) }
                            }
                            Text(HardwareStorageLocalization.format(
                                "有效分辨率 %@ · %@",
                                locale: locale,
                                display.resolution,
                                display.refreshRateHz.map {
                                    "\(HardwareStorageLocalization.integer(Int($0), locale: locale)) Hz"
                                } ?? localized("刷新率未知")
                            ))
                                .font(.caption)
                                .foregroundStyle(CalmTheme.secondaryText)
                            Text(displayHardwareIdentifier(display))
                                .font(.caption2.monospaced())
                                .foregroundStyle(CalmTheme.tertiaryText)
                        }
                        Spacer()
                        Text(display.pixelDimensions ?? "")
                            .font(.caption)
                            .foregroundStyle(CalmTheme.secondaryText)
                    }
                    .padding(13)
                    .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .calmCard(padding: 20)
    }

    private func graphicDetail(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(CalmTheme.violet)
                .frame(width: 28, height: 28)
                .background(CalmTheme.violet.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(CalmTheme.secondaryText)
                Text(value).font(.callout.weight(.medium))
            }
            Spacer()
        }
    }

    private func capabilityTitle(_ value: Bool?) -> String {
        guard let value else { return localized("系统未提供") }
        return localized(value ? "支持" : "不支持")
    }

    private func booleanTitle(_ value: Bool?) -> String {
        guard let value else { return localized("系统未提供") }
        return localized(value ? "是" : "否")
    }

    private func displayHardwareIdentifier(_ display: DisplayDevice) -> String {
        let vendor = display.vendorID.map { String(format: "0x%04X", $0) } ?? "—"
        let product = display.productID.map { String(format: "0x%04X", $0) } ?? "—"
        return HardwareStorageLocalization.format(
            "厂商 %@ · 产品 %@",
            locale: locale,
            vendor,
            product
        )
    }

    private func localized(_ key: String) -> String {
        HardwareStorageLocalization.text(key, locale: locale)
    }
}

enum InputDeviceBatteryPresentation {
    static func visibleLevel(for battery: InputDeviceBatteryState) -> Double? {
        guard battery.availability.isAvailable,
              let level = battery.levelPercent,
              level.isFinite,
              (0...100).contains(level) else {
            return nil
        }
        return level
    }

    static func showsChargingState(_ state: InputDeviceChargingState) -> Bool {
        state != .unknown
    }
}

struct InputDevicesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: localized("键盘与鼠标"),
                    subtitle: localized("查看键盘、鼠标、触控板与指针设备的只读硬件信息"),
                    symbol: "keyboard"
                )

                if model.snapshot.inputDevices.availability.isAvailable {
                    if model.snapshot.inputDevices.devices.isEmpty {
                        EmptyCapabilityView(
                            title: localized("没有发现输入设备"),
                            message: localized("IORegistry 暂未返回可识别的物理键盘、鼠标或触控板；设备变化会在约 30 秒内重新读取。"),
                            symbol: "keyboard.badge.ellipsis"
                        )
                    } else {
                        inventoryOverview
                        InputDeviceCardGridLayout {
                            ForEach(model.snapshot.inputDevices.devices) { device in
                                deviceCard(device)
                            }
                        }
                        privacyNote
                    }
                } else {
                    EmptyCapabilityView(
                        title: localizedAvailabilityTitle(model.snapshot.inputDevices.availability),
                        message: model.snapshot.inputDevices.availability.message
                            ?? localized("系统没有返回可读取的 IORegistry 输入设备清单。"),
                        symbol: "keyboard.badge.ellipsis"
                    )
                }
            }
            .padding(24)
            .frame(maxWidth: 1_180, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .calmPage()
        .navigationTitle(localized("键盘与鼠标"))
    }

    private var inventoryOverview: some View {
        let devices = model.snapshot.inputDevices.devices
        return HStack(spacing: 18) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 27))
                .foregroundStyle(CalmTheme.cyan)
                .frame(width: 58, height: 58)
                .background(CalmTheme.cyan.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 5) {
                Text(AppCountLocalization.format(
                    count: devices.count,
                    oneKey: "hardware.inputDevice.count.one",
                    otherKey: "hardware.inputDevice.count.other",
                    oneDefaultValue: "已识别 %lld 台物理输入设备",
                    otherDefaultValue: "已识别 %lld 台物理输入设备",
                    locale: locale,
                    Int64(devices.count)
                ))
                    .font(.title3.weight(.semibold))
                Text(localized("复合设备的多个 HID collection 已合并；连接变化会自动恢复。"))
                    .font(.callout)
                    .foregroundStyle(CalmTheme.secondaryText)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 5) {
                Text(localized("能力数量 · 复合设备可重复计数"))
                    .font(.caption2)
                    .foregroundStyle(CalmTheme.secondaryText)
                HStack(spacing: 7) {
                    kindCountPill(.keyboard)
                    kindCountPill(.mouse)
                    kindCountPill(.trackpad)
                }
            }
        }
        .calmCard(padding: 18)
    }

    private func kindCountPill(_ kind: InputDeviceKind) -> some View {
        let count = model.snapshot.inputDevices.devices.filter { $0.kinds.contains(kind) }.count
        return VStack(spacing: 2) {
            Text(HardwareStorageLocalization.integer(count, locale: locale))
                .font(.headline.monospacedDigit())
                .foregroundStyle(kindColor(kind))
            Text(kindTitle(kind))
                .font(.caption2.weight(.medium))
                .foregroundStyle(CalmTheme.secondaryText)
        }
        .frame(minWidth: 54)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(kindColor(kind).opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .combine)
    }

    private func deviceCard(_ device: InputDeviceState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: kindSymbol(device.primaryKind))
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(kindColor(device.primaryKind))
                    .frame(width: 50, height: 50)
                    .background(
                        kindColor(device.primaryKind).opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 12)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(device.name)
                        .font(.headline)
                        .foregroundStyle(CalmTheme.primaryText)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        ForEach(device.kinds, id: \.self) { kind in
                            StatusPill(text: kindTitle(kind), color: kindColor(kind))
                        }
                        if let isBuiltIn = device.isBuiltIn {
                            StatusPill(
                                text: localized(isBuiltIn ? "内置" : "外接"),
                                color: isBuiltIn ? CalmTheme.mint : CalmTheme.cyan
                            )
                        }
                    }
                }
                Spacer(minLength: 4)
            }

            CalmDivider()
            DetailRow(label: localized("制造商"), value: device.manufacturer ?? localized("系统未提供"))
            DetailRow(label: localized("连接方式"), value: device.transport ?? localized("系统未提供"))
            DetailRow(label: "Vendor / Product", value: vendorProduct(device))
            DetailRow(
                label: localized("版本"),
                value: device.versionNumber.map { String(format: "0x%04llX", $0) } ?? localized("系统未提供")
            )
            DetailRow(
                label: "Location ID",
                value: device.locationID.map { String(format: "0x%08llX", $0) } ?? localized("系统未提供")
            )
            DetailRow(
                label: localized("序列号"),
                value: device.serialNumber.map(InputDevicePrivacyFormatter.maskedSerialNumber)
                    ?? localized("系统未提供")
            )
            Spacer(minLength: 0)
            if let level = InputDeviceBatteryPresentation.visibleLevel(for: device.battery) {
                CalmDivider()
                batteryRow(device.battery, level: level)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .calmCard()
        .accessibilityIdentifier("input-device-card-\(device.stableIdentifier)")
        .accessibilityElement(children: .contain)
    }

    private func batteryRow(
        _ battery: InputDeviceBatteryState,
        level: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(localized("设备电量"), systemImage: "battery.75percent")
                    .font(.callout)
                    .foregroundStyle(CalmTheme.secondaryText)
                Spacer()
                Text(MetricFormatter.percent(level, locale: locale))
                    .font(.callout.monospacedDigit().weight(.semibold))
            }
            ProgressView(value: level / 100)
                .tint(batteryColor(level))

            if InputDeviceBatteryPresentation.showsChargingState(battery.chargingState) {
                HStack(spacing: 9) {
                    Label(localized("充电状态"), systemImage: chargingSymbol(battery.chargingState))
                        .foregroundStyle(CalmTheme.secondaryText)
                    Spacer()
                    Text(chargingTitle(battery.chargingState))
                        .fontWeight(.semibold)
                        .foregroundStyle(chargingColor(battery.chargingState))
                }
                .font(.callout)
            }

            if battery.source == .appleDriverRegistry {
                Text(localized("Apple 驱动 IORegistry 报告（兼容读取）"))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(CalmTheme.secondaryText)
            }
        }
        .frame(minHeight: 92, alignment: .topLeading)
    }

    private var privacyNote: some View {
        Label {
            Text(localized("TraceHalo 只枚举 IORegistry 元数据，不打开 HID 设备、不读取输入值，也不需要“输入监控”权限。电量和充电状态仅显示 Apple 驱动明确报告的值。"))
        } icon: {
            Image(systemName: "lock.shield")
                .foregroundStyle(CalmTheme.mint)
        }
        .font(.caption)
        .foregroundStyle(CalmTheme.secondaryText)
        .padding(.horizontal, 4)
    }

    private func vendorProduct(_ device: InputDeviceState) -> String {
        let vendor = device.vendorID.map { String(format: "0x%04llX", $0) } ?? "—"
        let product = device.productID.map { String(format: "0x%04llX", $0) } ?? "—"
        return "\(vendor) / \(product)"
    }

    private func kindTitle(_ kind: InputDeviceKind) -> String {
        HardwareStorageLocalization.inputKindTitle(kind, locale: locale)
    }

    private func kindSymbol(_ kind: InputDeviceKind) -> String {
        switch kind {
        case .keyboard: "keyboard"
        case .mouse: "computermouse"
        case .trackpad: "hand.point.up.left"
        case .pointingDevice: "cursorarrow.rays"
        }
    }

    private func kindColor(_ kind: InputDeviceKind) -> Color {
        switch kind {
        case .keyboard: CalmTheme.cyan
        case .mouse: CalmTheme.violet
        case .trackpad: CalmTheme.mint
        case .pointingDevice: CalmTheme.amber
        }
    }

    private func batteryColor(_ level: Double) -> Color {
        if level <= 15 { return CalmTheme.rose }
        if level <= 35 { return CalmTheme.amber }
        return CalmTheme.mint
    }

    private func chargingTitle(_ state: InputDeviceChargingState) -> String {
        HardwareStorageLocalization.chargingTitle(state, locale: locale)
    }

    private func chargingSymbol(_ state: InputDeviceChargingState) -> String {
        switch state {
        case .charging: "bolt.fill"
        case .notCharging: "powerplug"
        case .unknown: "questionmark.circle"
        }
    }

    private func chargingColor(_ state: InputDeviceChargingState) -> Color {
        switch state {
        case .charging: CalmTheme.mint
        case .notCharging, .unknown: CalmTheme.secondaryText
        }
    }

    private func localized(_ key: String) -> String {
        HardwareStorageLocalization.text(key, locale: locale)
    }

    private func localizedAvailabilityTitle(_ availability: CapabilityAvailability) -> String {
        switch availability {
        case .available: localized("可用")
        case .unavailable: localized("不可用")
        case .permissionRequired: localized("需要权限")
        case .failed: localized("读取失败")
        }
    }
}

/// Adaptive input-device cards with deterministic row sizing. Wide containers
/// use two columns and propose the same height to both cards in each row.
/// Narrow containers use one column, preserving each card's natural height.
struct InputDeviceCardGridLayout: Layout {
    static let minimumCardWidth: CGFloat = 390
    static let spacing: CGFloat = 14

    static func columnCount(for width: CGFloat) -> Int {
        width >= minimumCardWidth * 2 + spacing ? 2 : 1
    }

    static func rowCount(itemCount: Int, width: CGFloat) -> Int {
        guard itemCount > 0 else { return 0 }
        let columns = columnCount(for: width)
        return (itemCount + columns - 1) / columns
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = max(proposal.width ?? Self.minimumCardWidth, 1)
        let metrics = rowMetrics(width: width, subviews: subviews)
        return CGSize(
            width: width,
            height: metrics.rowHeights.reduce(0, +)
                + Self.spacing * CGFloat(max(metrics.rowHeights.count - 1, 0))
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let metrics = rowMetrics(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in metrics.rowHeights.indices {
            let rowHeight = metrics.rowHeights[row]
            for column in 0..<metrics.columns {
                let index = row * metrics.columns + column
                guard index < subviews.count else { break }
                subviews[index].place(
                    at: CGPoint(
                        x: bounds.minX + CGFloat(column) * (metrics.cardWidth + Self.spacing),
                        y: y
                    ),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: metrics.cardWidth, height: rowHeight)
                )
            }
            y += rowHeight + Self.spacing
        }
    }

    private func rowMetrics(
        width: CGFloat,
        subviews: Subviews
    ) -> (columns: Int, cardWidth: CGFloat, rowHeights: [CGFloat]) {
        let columns = Self.columnCount(for: width)
        let totalSpacing = Self.spacing * CGFloat(columns - 1)
        let cardWidth = max((width - totalSpacing) / CGFloat(columns), 1)
        var rowHeights: [CGFloat] = []

        for rowStart in stride(from: 0, to: subviews.count, by: columns) {
            let rowEnd = min(rowStart + columns, subviews.count)
            var height: CGFloat = 0
            for index in rowStart..<rowEnd {
                height = max(
                    height,
                    subviews[index]
                        .sizeThatFits(ProposedViewSize(width: cardWidth, height: nil))
                        .height
                )
            }
            rowHeights.append(height)
        }
        return (columns, cardWidth, rowHeights)
    }
}

enum ThermalSensorDisplayGroup: Int, CaseIterable, Identifiable, Equatable {
    case cpu
    case gpu
    case memory
    case system
    case other

    var id: Self { self }

    func title(locale: Locale) -> String {
        switch self {
        case .cpu: HardwareStorageLocalization.text("CPU 温度", locale: locale)
        case .gpu: HardwareStorageLocalization.text("GPU 温度", locale: locale)
        case .memory: HardwareStorageLocalization.text("内存温度", locale: locale)
        case .system: HardwareStorageLocalization.text("系统与机身", locale: locale)
        case .other: HardwareStorageLocalization.text("其他传感器", locale: locale)
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "display"
        case .memory: "memorychip"
        case .system: "desktopcomputer"
        case .other: "thermometer.medium"
        }
    }

    static func classify(_ rawGroup: String) -> Self {
        let normalized = rawGroup
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()

        return switch normalized {
        case "cpu", "processor", "处理器", "中央处理器": .cpu
        case "gpu", "graphics", "graphics processor", "图形", "图形处理器": .gpu
        case "memory", "ram", "内存": .memory
        case "system", "chassis", "ambient", "系统", "机身", "环境": .system
        default: .other
        }
    }
}

struct ThermalSensorDisplaySection: Identifiable, Equatable {
    var id: ThermalSensorDisplayGroup { group }
    let group: ThermalSensorDisplayGroup
    let sensors: [ThermalSensor]

    var averageCelsius: Double {
        sensors.map(\.temperatureCelsius).reduce(0, +) / Double(sensors.count)
    }

    var maximumCelsius: Double {
        sensors.map(\.temperatureCelsius).max() ?? 0
    }
}

enum ThermalSensorDisplayGrouping {
    static func sections(from sensors: [ThermalSensor]) -> [ThermalSensorDisplaySection] {
        let validSensors = sensors.filter { $0.temperatureCelsius.isFinite }
        let grouped = Dictionary(grouping: validSensors) {
            ThermalSensorDisplayGroup.classify($0.group)
        }

        return ThermalSensorDisplayGroup.allCases.compactMap { group in
            guard let groupSensors = grouped[group], !groupSensors.isEmpty else { return nil }
            let sortedSensors = groupSensors.sorted { lhs, rhs in
                let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
                if nameOrder == .orderedSame { return lhs.key < rhs.key }
                return nameOrder == .orderedAscending
            }
            return ThermalSensorDisplaySection(group: group, sensors: sortedSensors)
        }
    }
}

struct CoolingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: localized("散热"),
                    subtitle: localized("读取温度传感器、风扇转速和系统热状态"),
                    symbol: "fan"
                )

                if model.snapshot.cooling.availability.isAvailable {
                    thermalOverview
                    fanSection
                    sensorSection
                } else {
                    EmptyCapabilityView(
                        title: localizedAvailabilityTitle(model.snapshot.cooling.availability),
                        message: model.snapshot.cooling.availability.message ?? localized("此设备没有提供散热数据。"),
                        symbol: "fan.slash"
                    )
                }
            }
            .padding(24)
            .frame(maxWidth: 1_180, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .calmPage()
        .navigationTitle(localized("散热"))
    }

    private var thermalOverview: some View {
        HStack(spacing: 18) {
            Image(systemName: conditionSymbol)
                .font(.system(size: 30))
                .foregroundStyle(conditionColor)
                .frame(width: 62, height: 62)
                .background(conditionColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 5) {
                Text(HardwareStorageLocalization.format(
                    "热状态 · %@",
                    locale: locale,
                    HardwareStorageLocalization.thermalConditionTitle(
                        model.snapshot.cooling.condition,
                        locale: locale
                    )
                ))
                    .font(.title3.weight(.semibold))
                Text(thermalDescription)
                    .font(.callout)
                    .foregroundStyle(CalmTheme.secondaryText)
            }
            Spacer()
            StatusPill(
                text: localizedAvailabilityTitle(model.snapshot.cooling.availability),
                color: model.snapshot.cooling.availability.calmColor
            )
        }
        .calmCard()
    }

    private var fanSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionTitle(
                title: localized("风扇"),
                subtitle: localized("当前页仅监测，不提供转速控制"),
                symbol: "fan"
            )
            if model.snapshot.cooling.fans.isEmpty {
                Text(sensorUnavailableMessage(fallback: localized("没有发现可读取的风扇转速。")))
                    .foregroundStyle(CalmTheme.secondaryText)
                if requiresSensorPermission {
                    SensorAccessActionView()
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                    ForEach(model.snapshot.cooling.fans) { fan in
                        fanCard(fan)
                    }
                }
            }
        }
        .calmCard()
    }

    private func fanCard(_ fan: FanState) -> some View {
        let maximum = max(fan.maximumRPM ?? 5_000, 1)
        return HStack(spacing: 15) {
            ZStack {
                Circle().fill(CalmTheme.cyan.opacity(0.09))
                Image(systemName: "fan.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(CalmTheme.cyan)
            }
            .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 5) {
                Text(fan.name).font(.callout.weight(.medium))
                Text("\(HardwareStorageLocalization.integer(fan.currentRPM, locale: locale)) RPM")
                    .font(.title3.monospacedDigit().weight(.semibold))
                ProgressView(value: Double(fan.currentRPM) / Double(maximum))
                    .tint(CalmTheme.cyan)
            }
            Spacer()
        }
        .padding(13)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
    }

    private var sensorSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionTitle(
                title: localized("温度传感器"),
                subtitle: localized("传感器数量与名称因机型而异"),
                symbol: "thermometer.medium"
            )
            if model.snapshot.cooling.sensors.isEmpty {
                Text(sensorUnavailableMessage(fallback: localized("没有发现可读取的温度传感器。")))
                    .foregroundStyle(CalmTheme.secondaryText)
            } else {
                VStack(spacing: 12) {
                    ForEach(
                        ThermalSensorDisplayGrouping.sections(
                            from: model.snapshot.cooling.sensors
                        )
                    ) { section in
                        sensorGroupCard(section)
                    }
                }
            }
        }
        .calmCard()
    }

    private func sensorGroupCard(_ section: ThermalSensorDisplaySection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label(section.group.title(locale: locale), systemImage: section.group.symbol)
                    .font(.headline)
                    .foregroundStyle(sensorGroupColor(section.group))
                Spacer(minLength: 12)
                Text(AppCountLocalization.format(
                    count: section.sensors.count,
                    oneKey: "hardware.sensor.count.one",
                    otherKey: "hardware.sensor.count.other",
                    oneDefaultValue: "%lld 个传感器",
                    otherDefaultValue: "%lld 个传感器",
                    locale: locale,
                    Int64(section.sensors.count)
                ))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CalmTheme.secondaryText)
            }

            HStack(spacing: 8) {
                sensorSummaryPill(
                    title: localized("平均"),
                    value: model.temperatureUnit.formatted(celsius: section.averageCelsius, locale: locale),
                    color: sensorColor(section.averageCelsius)
                )
                sensorSummaryPill(
                    title: localized("最高"),
                    value: model.temperatureUnit.formatted(celsius: section.maximumCelsius, locale: locale),
                    color: sensorColor(section.maximumCelsius)
                )
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 210), spacing: 12)],
                spacing: 12
            ) {
                ForEach(section.sensors) { sensor in
                    sensorRow(sensor)
                }
            }
        }
        .padding(14)
        .background(.primary.opacity(0.028), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(sensorGroupColor(section.group).opacity(0.16), lineWidth: 1)
        }
    }

    private func sensorSummaryPill(
        title: String,
        value: String,
        color: Color
    ) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .foregroundStyle(CalmTheme.secondaryText)
            Text(value)
                .monospacedDigit()
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
        .font(.caption)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.08), in: Capsule())
    }

    private func sensorRow(_ sensor: ThermalSensor) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "thermometer.medium")
                .foregroundStyle(sensorColor(sensor.temperatureCelsius))
                .frame(width: 34, height: 34)
                .background(
                    sensorColor(sensor.temperatureCelsius).opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 9)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(sensor.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                Text(sensor.group.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? localized("未分类")
                    : ThermalSensorDisplayGroup.classify(sensor.group).title(locale: locale))
                    .font(.caption)
                    .foregroundStyle(CalmTheme.secondaryText)
            }
            Spacer()
            Text(model.temperatureUnit.formatted(celsius: sensor.temperatureCelsius, locale: locale))
                .font(.callout.monospacedDigit().weight(.semibold))
        }
        .padding(12)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }

    private func sensorGroupColor(_ group: ThermalSensorDisplayGroup) -> Color {
        switch group {
        case .cpu: CalmTheme.cyan
        case .gpu: CalmTheme.violet
        case .memory: CalmTheme.mint
        case .system: CalmTheme.amber
        case .other: CalmTheme.secondaryText
        }
    }

    private var conditionColor: Color {
        switch model.snapshot.cooling.condition {
        case .nominal: CalmTheme.mint
        case .fair: CalmTheme.amber
        case .serious, .critical: CalmTheme.rose
        case .unavailable: .secondary
        }
    }

    private var conditionSymbol: String {
        switch model.snapshot.cooling.condition {
        case .nominal: "checkmark.circle.fill"
        case .fair: "thermometer.medium"
        case .serious, .critical: "exclamationmark.triangle.fill"
        case .unavailable: "questionmark.circle"
        }
    }

    private var thermalDescription: String {
        switch model.snapshot.cooling.condition {
        case .nominal: localized("系统热状态正常。")
        case .fair: localized("系统温度有所升高，建议观察负载和通风。")
        case .serious: localized("系统正在受到明显热压力，建议降低持续负载。")
        case .critical: localized("系统热状态严重，请尽快保存工作并检查散热环境。")
        case .unavailable: localized("系统没有提供可判断的热状态。")
        }
    }

    private func sensorColor(_ temperature: Double) -> Color {
        if temperature >= 80 { return CalmTheme.rose }
        if temperature >= 60 { return CalmTheme.amber }
        return CalmTheme.mint
    }

    private func sensorUnavailableMessage(fallback: String) -> String {
        model.snapshot.cooling.sensorAvailability.message ?? fallback
    }

    private var requiresSensorPermission: Bool {
        if case .permissionRequired = model.snapshot.cooling.sensorAvailability {
            return true
        }
        return false
    }

    private func localized(_ key: String) -> String {
        HardwareStorageLocalization.text(key, locale: locale)
    }

    private func localizedAvailabilityTitle(_ availability: CapabilityAvailability) -> String {
        switch availability {
        case .available: localized("可用")
        case .unavailable: localized("不可用")
        case .permissionRequired: localized("需要权限")
        case .failed: localized("读取失败")
        }
    }
}

struct BatteryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: localized("电池"),
                    subtitle: localized("查看电量、容量衰减、循环次数与实时供电状态"),
                    symbol: "battery.75percent"
                )

                if model.snapshot.battery.availability.isAvailable {
                    batteryOverview
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 14)], alignment: .leading, spacing: 14) {
                        capacityCard
                        powerCard
                        batteryDetails
                        cycleCard
                    }
                } else {
                    EmptyCapabilityView(
                        title: localized("没有电池数据"),
                        message: model.snapshot.battery.availability.message ?? localized("桌面设备通常没有内置电池。"),
                        symbol: "battery.0percent"
                    )
                }
            }
            .padding(24)
            .frame(maxWidth: 1_180, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .calmPage()
        .navigationTitle(localized("电池"))
    }

    private var batteryOverview: some View {
        let battery = model.snapshot.battery
        return HStack(spacing: 24) {
            RingGauge(
                value: battery.chargePercent.map { $0 / 100 },
                label: localized("电量"),
                tint: CalmTheme.mint,
                size: 126
            )
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) {
                    Text(localized(battery.isCharging ? "正在充电" : "使用电池供电"))
                        .font(.title3.weight(.semibold))
                    StatusPill(
                        text: HardwareStorageLocalization.batteryHealthTitle(
                            battery.health,
                            locale: locale
                        ),
                        color: healthColor
                    )
                }
                if let minutes = battery.timeRemainingMinutes {
                    Text(HardwareStorageLocalization.format(
                        "预计可用 %lld 小时 %lld 分钟",
                        locale: locale,
                        Int64(minutes / 60),
                        Int64(minutes % 60)
                    ))
                        .font(.callout)
                        .foregroundStyle(CalmTheme.secondaryText)
                }
                if let temperature = battery.temperatureCelsius {
                    Label(
                        model.temperatureUnit.formatted(celsius: temperature, locale: locale),
                        systemImage: "thermometer.medium"
                    )
                        .font(.caption)
                        .foregroundStyle(CalmTheme.secondaryText)
                }
            }
            Spacer()
            Image(systemName: battery.isCharging ? "bolt.fill" : "leaf.fill")
                .font(.system(size: 28))
                .foregroundStyle(battery.isCharging ? CalmTheme.amber : CalmTheme.mint)
                .frame(width: 56, height: 56)
                .background((battery.isCharging ? CalmTheme.amber : CalmTheme.mint).opacity(0.1), in: Circle())
        }
        .calmCard(padding: 20)
    }

    @ViewBuilder
    private var capacityCard: some View {
        let battery = model.snapshot.battery
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(
                title: localized("容量状态"),
                subtitle: battery.healthBasis == .systemReported
                    ? localized("优先采用 macOS 报告的电池健康状态")
                    : localized("系统未报告明确状态时使用原始容量估算"),
                symbol: "heart.circle"
            )
            HStack(alignment: .lastTextBaseline, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(localized(battery.healthBasis == .systemReported ? "系统健康" : "健康估算"))
                        .font(.caption)
                        .foregroundStyle(CalmTheme.secondaryText)
                    Text(HardwareStorageLocalization.batteryHealthTitle(
                        battery.health,
                        locale: locale
                    ))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                }
                Spacer()
                if let estimate = battery.rawCapacityEstimatePercent,
                   let maximum = battery.maximumCapacityMAh,
                   let design = battery.designCapacityMAh {
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(localized("原始容量参考"))
                            .font(.caption)
                            .foregroundStyle(CalmTheme.secondaryText)
                        Text(HardwareStorageLocalization.format(
                            "约 %@",
                            locale: locale,
                            MetricFormatter.percent(estimate, locale: locale)
                        ))
                            .font(.title3.weight(.semibold).monospacedDigit())
                        Text("\(HardwareStorageLocalization.integer(maximum, locale: locale)) / \(HardwareStorageLocalization.integer(design, locale: locale)) mAh")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(CalmTheme.secondaryText)
                    }
                }
            }
            if let estimate = battery.rawCapacityEstimatePercent {
                ProgressView(value: estimate / 100)
                    .tint(healthColor)
            }
            Text(localized(battery.healthBasis == .systemReported
                ? "原始容量参考与“系统设置”中的最大容量口径不同，不会覆盖 macOS 的健康结论。"
                : "当前没有明确的系统健康结论；原始容量比仅作为参考。"))
                .font(.caption)
                .foregroundStyle(CalmTheme.secondaryText)
        }
        .calmCard()
    }

    private var powerCard: some View {
        let battery = model.snapshot.battery
        return VStack(alignment: .leading, spacing: 13) {
            SectionTitle(
                title: localized("实时供电"),
                subtitle: localized("电压、电流与估算功率"),
                symbol: "bolt.circle"
            )
            DetailRow(
                label: localized("电压"),
                value: battery.voltageMV.map {
                    String(format: "%.2f V", locale: locale, Double($0) / 1_000)
                } ?? "—"
            )
            CalmDivider()
            DetailRow(
                label: localized("电流"),
                value: battery.amperageMA.map {
                    "\(HardwareStorageLocalization.integer($0, locale: locale)) mA"
                } ?? "—"
            )
            CalmDivider()
            DetailRow(
                label: localized("功率"),
                value: battery.powerWatts.map {
                    String(format: "%.1f W", locale: locale, abs($0))
                } ?? "—"
            )
        }
        .calmCard()
    }

    private var batteryDetails: some View {
        let battery = model.snapshot.battery
        return VStack(alignment: .leading, spacing: 13) {
            SectionTitle(title: localized("设备信息"), symbol: "info.circle")
            DetailRow(label: localized("制造商"), value: battery.manufacturer ?? localized("未知"))
            CalmDivider()
            DetailRow(label: localized("序列号"), value: battery.serialNumber ?? localized("未提供"))
            if let currentCapacityMAh = battery.currentCapacityMAh {
                CalmDivider()
                DetailRow(
                    label: localized("当前原始容量"),
                    value: "\(HardwareStorageLocalization.integer(currentCapacityMAh, locale: locale)) mAh"
                )
            }
        }
        .calmCard()
    }

    @ViewBuilder
    private var cycleCard: some View {
        let battery = model.snapshot.battery
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(
                title: localized("循环次数"),
                subtitle: localized("相对设计循环上限"),
                symbol: "arrow.triangle.2.circlepath"
            )
            if let cycles = battery.cycleCount,
               let limit = battery.designCycleCount,
               limit > 0 {
                HStack(alignment: .lastTextBaseline) {
                    Text(HardwareStorageLocalization.integer(cycles, locale: locale))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("/ \(HardwareStorageLocalization.integer(limit, locale: locale))")
                        .font(.callout)
                        .foregroundStyle(CalmTheme.secondaryText)
                    Spacer()
                    StatusPill(
                        text: MetricFormatter.percent(
                            Double(cycles) / Double(limit) * 100,
                            locale: locale
                        ),
                        color: CalmTheme.cyan
                    )
                }
                ProgressView(value: Double(cycles) / Double(limit))
                    .tint(CalmTheme.cyan)
            } else {
                Text(localized("循环数据不可用"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(CalmTheme.secondaryText)
            }
            Text(localized("循环次数只是健康判断的一部分，也应结合容量和系统状态。"))
                .font(.caption)
                .foregroundStyle(CalmTheme.secondaryText)
        }
        .calmCard()
    }

    private var healthColor: Color {
        switch model.snapshot.battery.health {
        case .excellent, .good: CalmTheme.mint
        case .aging: CalmTheme.amber
        case .serviceRecommended: CalmTheme.rose
        case .unknown: .secondary
        }
    }

    private func localized(_ key: String) -> String {
        HardwareStorageLocalization.text(key, locale: locale)
    }
}
