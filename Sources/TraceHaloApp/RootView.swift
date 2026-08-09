import SwiftUI
import TraceHaloCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigationRouter.self) private var navigationRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("launchDestination") private var launchDestination = AppDestination.dashboard.rawValue
    @AppStorage("lastDestination") private var lastDestination = AppDestination.dashboard.rawValue
    @State private var isSidebarCollapsed = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                if !isSidebarCollapsed {
                    sidebar
                        .frame(width: SidebarLayout.width)
                        .transition(
                            SidebarMotionPolicy.sidebarTransition(reduceMotion: reduceMotion)
                        )
                }

                NavigationStack {
                    destinationView(navigationRouter.destination ?? .dashboard)
                        .redacted(reason: model.hasLoadedSnapshot ? [] : .placeholder)
                        .allowsHitTesting(model.hasLoadedSnapshot)
                        .overlay(alignment: .topTrailing) {
                            if !model.hasLoadedSnapshot {
                                InitialSamplingStatus()
                                    .padding(16)
                                    .transition(
                                        SidebarMotionPolicy.loadingTransition(reduceMotion: reduceMotion)
                                    )
                            }
                        }
                        .animation(
                            SidebarMotionPolicy.easeOutAnimation(
                                reduceMotion: reduceMotion,
                                duration: 0.2
                            ),
                            value: model.hasLoadedSnapshot
                        )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CalmTheme.pageGradient.ignoresSafeArea())
            }

            if isSidebarCollapsed {
                Button {
                    withAnimation(
                        SidebarMotionPolicy.animation(
                            reduceMotion: reduceMotion,
                            duration: 0.2
                        )
                    ) {
                        isSidebarCollapsed = false
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(CalmTheme.controlBackground, in: Circle())
                        .overlay(Circle().strokeBorder(CalmTheme.hairline))
                }
                .buttonStyle(.plain)
                .padding(10)
                .help("显示侧边栏")
                .accessibilityLabel("显示侧边栏")
            }
        }
        .tint(CalmTheme.accent)
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
        .onAppear {
            guard navigationRouter.destination == nil else { return }
            let preferred = launchDestination == "last" ? lastDestination : launchDestination
            let destination = AppDestination(rawValue: preferred) ?? .dashboard
            navigationRouter.navigate(to: supportedDestination(destination))
        }
        .onChange(of: navigationRouter.destination) { _, newValue in
            if let newValue { lastDestination = newValue.rawValue }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarCollapseHeader

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    SidebarNavigationRow(destination: .dashboard) {
                        navigationRouter.navigate(to: .dashboard)
                    }
                    SidebarNavigationRow(destination: .monitor) {
                        navigationRouter.navigate(to: .monitor)
                    }
                    SidebarDisclosureGroup(
                        title: "系统工具",
                        symbol: "wrench.and.screwdriver",
                        destinations: [.optimizer, .uninstaller]
                    )
                    HardwareSidebarDisclosureGroup()
                    SidebarNavigationRow(destination: .report) {
                        navigationRouter.navigate(to: .report)
                    }
                    SidebarNavigationRow(destination: .settings) {
                        navigationRouter.navigate(to: .settings)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }

            SidebarStatusView()
        }
        .background(CalmTheme.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(CalmTheme.hairline)
                .frame(width: 1)
        }
    }

    private func supportedDestination(_ destination: AppDestination) -> AppDestination {
        guard destination == .battery,
              model.hasLoadedSnapshot,
              !PowerPresentationPolicy.isAvailable(in: model.snapshot)
        else {
            return destination
        }
        return .dashboard
    }

    private var sidebarCollapseHeader: some View {
        HStack {
            Spacer()
            Button {
                withAnimation(
                    SidebarMotionPolicy.animation(
                        reduceMotion: reduceMotion,
                        duration: 0.2
                    )
                ) {
                    isSidebarCollapsed = true
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CalmTheme.secondaryText)
                    .frame(width: 28, height: 28)
                    .background(
                        CalmTheme.controlBackground,
                        in: Circle()
                    )
                    .overlay {
                        Circle()
                            .strokeBorder(CalmTheme.hairline)
                    }
            }
            .buttonStyle(.plain)
            .help("收起侧边栏")
            .accessibilityLabel("收起侧边栏")
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
    }

    @ViewBuilder
    private func destinationView(_ destination: AppDestination) -> some View {
        switch destination {
        case .dashboard: DashboardView()
        case .monitor: MonitorView()
        case .optimizer: OptimizerView()
        case .uninstaller: UninstallerView()
        case .storage: StorageView()
        case .graphics: GraphicsView()
        case .inputDevices: InputDevicesView()
        case .cooling: CoolingView()
        case .battery: BatteryView()
        case .report: ReportView()
        case .settings: SettingsView()
        }
    }
}

/// Keeps battery capability observation out of `RootView` so the two-second
/// telemetry publication does not invalidate and rebuild the active page's
/// entire navigation container.
private struct HardwareSidebarDisclosureGroup: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigationRouter.self) private var navigationRouter

    var body: some View {
        SidebarDisclosureGroup(
            title: "硬件",
            symbol: "memorychip",
            destinations: destinations
        )
        .onAppear(perform: redirectUnavailableBatteryPage)
        .onChange(of: isBatteryDestinationAvailable) { _, _ in
            redirectUnavailableBatteryPage()
        }
    }

    private var destinations: [AppDestination] {
        var destinations: [AppDestination] = [.storage, .graphics, .inputDevices, .cooling]
        if isBatteryDestinationAvailable {
            destinations.append(.battery)
        }
        return destinations
    }

    private var isBatteryDestinationAvailable: Bool {
        !model.hasLoadedSnapshot || PowerPresentationPolicy.isAvailable(in: model.snapshot)
    }

    private func redirectUnavailableBatteryPage() {
        guard !isBatteryDestinationAvailable,
              navigationRouter.destination == .battery
        else { return }
        navigationRouter.navigate(to: .dashboard)
    }
}

private struct SidebarDisclosureGroup: View {
    @Environment(AppNavigationRouter.self) private var navigationRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

    let title: String
    let symbol: String
    let destinations: [AppDestination]

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button {
                withAnimation(
                    SidebarMotionPolicy.animation(
                        reduceMotion: reduceMotion,
                        duration: 0.18
                    )
                ) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: SidebarLayout.itemSpacing) {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isActive ? CalmTheme.accent : CalmTheme.secondaryText)
                        .frame(width: SidebarLayout.iconSize, height: SidebarLayout.iconSize)

                    Text(AppLocalization.string(title, defaultValue: title, locale: locale))
                        .font(.system(size: SidebarLayout.primaryFontSize, weight: isActive ? .semibold : .medium))
                        .foregroundStyle(CalmTheme.primaryText)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(CalmTheme.tertiaryText)
                        .frame(width: 12, height: 20)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, SidebarLayout.rowHorizontalPadding)
                .frame(height: SidebarLayout.primaryRowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                AppLocalization.format(
                    "sidebar.disclosure.accessibility",
                    defaultValue: "%@，%@",
                    locale: locale,
                    AppLocalization.string(title, defaultValue: title, locale: locale),
                    AppLocalization.string(
                        isExpanded ? "已展开" : "已折叠",
                        defaultValue: isExpanded ? "已展开" : "已折叠",
                        locale: locale
                    )
                )
            )

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(destinations) { destination in
                        SidebarNavigationRow(destination: destination, isChild: true) {
                            navigationRouter.navigate(to: destination)
                        }
                    }
                }
                .padding(.leading, SidebarLayout.childIndent)
                .transition(
                    SidebarMotionPolicy.disclosureTransition(reduceMotion: reduceMotion)
                )
            }
        }
        .onAppear {
            if SidebarLayout.shouldExpand(
                current: navigationRouter.destination,
                destinations: destinations
            ) {
                isExpanded = true
            }
        }
        .onChange(of: navigationRouter.destination) { _, destination in
            if SidebarLayout.shouldExpand(current: destination, destinations: destinations),
               !isExpanded {
                withAnimation(
                    SidebarMotionPolicy.animation(
                        reduceMotion: reduceMotion,
                        duration: 0.18
                    )
                ) {
                    isExpanded = true
                }
            }
        }
    }

    private var isActive: Bool {
        guard let destination = navigationRouter.destination else { return false }
        return destinations.contains(destination)
    }
}

private struct SidebarNavigationRow: View {
    @Environment(AppNavigationRouter.self) private var navigationRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

    let destination: AppDestination
    var isChild = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: SidebarLayout.itemSpacing) {
                Image(systemName: destination.symbol)
                    .font(.system(
                        size: isChild ? SidebarLayout.childIconFontSize : SidebarLayout.primaryFontSize,
                        weight: isSelected ? .semibold : .medium
                    ))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(isSelected ? Color.white : CalmTheme.secondaryText)
                    .frame(width: SidebarLayout.iconSize, height: SidebarLayout.iconSize)

                Text(sidebarTitle)
                    .font(.system(
                        size: isChild ? SidebarLayout.childFontSize : SidebarLayout.primaryFontSize,
                        weight: isSelected ? .semibold : .medium
                    ))
                    .foregroundStyle(isSelected ? Color.white : CalmTheme.primaryText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, SidebarLayout.rowHorizontalPadding)
            .frame(height: isChild ? SidebarLayout.childRowHeight : SidebarLayout.primaryRowHeight)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: CalmTheme.sidebarRowRadius, style: .continuous)
                    .fill(rowBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: CalmTheme.sidebarRowRadius, style: .continuous)
                    .strokeBorder(isSelected ? CalmTheme.accent.opacity(0.32) : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(
            SidebarMotionPolicy.easeOutAnimation(
                reduceMotion: reduceMotion,
                duration: 0.14
            ),
            value: isHovering
        )
        .animation(
            SidebarMotionPolicy.easeOutAnimation(
                reduceMotion: reduceMotion,
                duration: 0.14
            ),
            value: isSelected
        )
    }

    private var rowBackground: Color {
        if isSelected { return CalmTheme.primaryAction }
        if isHovering { return CalmTheme.sidebarHover }
        return .clear
    }

    private var isSelected: Bool {
        navigationRouter.destination == destination
    }

    private var sidebarTitle: String {
        SidebarLayout.title(for: destination, locale: locale)
    }
}

enum SidebarLayout {
    static let width: CGFloat = 184
    static let iconSize: CGFloat = 20
    static let itemSpacing: CGFloat = 10
    static let rowHorizontalPadding: CGFloat = 10
    static let childIndent: CGFloat = 9
    static let primaryRowHeight: CGFloat = 40
    static let childRowHeight: CGFloat = 35
    static let primaryFontSize: CGFloat = 13
    static let childFontSize: CGFloat = 12.5
    static let childIconFontSize: CGFloat = 12

    static func title(for destination: AppDestination) -> String {
        let title = titleDescriptor(for: destination)
        return AppLocalization.currentString(
            title.key,
            defaultValue: title.defaultValue
        )
    }

    static func title(for destination: AppDestination, locale: Locale) -> String {
        let title = titleDescriptor(for: destination)
        return AppLocalization.string(
            title.key,
            defaultValue: title.defaultValue,
            locale: locale
        )
    }

    private static func titleDescriptor(
        for destination: AppDestination
    ) -> (key: String, defaultValue: String) {
        switch destination {
        case .monitor: ("sidebar.title.monitor", "实时监控")
        case .optimizer: ("sidebar.title.optimizer", "启动优化")
        case .uninstaller: ("sidebar.title.uninstaller", "应用管理")
        case .inputDevices: ("sidebar.title.inputDevices", "键盘鼠标")
        case .report: ("sidebar.title.report", "报告")
        default: (destination.title, destination.title)
        }
    }

    static func shouldExpand(
        current destination: AppDestination?,
        destinations: [AppDestination]
    ) -> Bool {
        guard let destination else { return false }
        return destinations.contains(destination)
    }
}

enum SidebarMotionPolicy {
    static func animation(reduceMotion: Bool, duration: Double) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: duration)
    }

    static func easeOutAnimation(reduceMotion: Bool, duration: Double) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: duration)
    }

    static func sidebarTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : .move(edge: .leading).combined(with: .opacity)
    }

    static func loadingTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top))
    }

    static func disclosureTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top))
    }
}

private struct InitialSamplingStatus: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("正在读取本机状态")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CalmTheme.secondaryText)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            CalmTheme.surfaceRaised,
            in: RoundedRectangle(cornerRadius: CalmTheme.controlRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CalmTheme.controlRadius, style: .continuous)
                .strokeBorder(CalmTheme.strongHairline)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SidebarStatusView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(CalmTheme.hairline)
                .frame(height: 1)

            HStack(spacing: 8) {
                Circle()
                    .fill(model.lastError == nil ? CalmTheme.mint : CalmTheme.rose)
                    .frame(width: 6, height: 6)
                    .shadow(
                        color: (model.lastError == nil ? CalmTheme.mint : CalmTheme.rose).opacity(0.25),
                        radius: 3
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text("数据更新")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CalmTheme.secondaryText)
                    Text(
                        AppLocalization.string(
                            model.isRefreshing ? "更新中" : "刚刚",
                            defaultValue: model.isRefreshing ? "更新中" : "刚刚",
                            locale: locale
                        )
                    )
                        .font(.caption2)
                        .foregroundStyle(CalmTheme.tertiaryText)
                }
                Spacer()
                if model.isRefreshing {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(CalmTheme.secondaryText)
                        .accessibilityLabel("正在刷新状态")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
        }
        .background(CalmTheme.sidebar)
    }
}
