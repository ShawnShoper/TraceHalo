import AppKit
import SwiftUI
import TraceHaloCore

enum ToolViewsLocalization {
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
        String(
            format: text(key, locale: locale),
            locale: locale,
            arguments: arguments
        )
    }

    static func format(
        _ key: String,
        locale: Locale,
        lookup: Lookup,
        _ arguments: CVarArg...
    ) -> String {
        format(
            key,
            locale: locale,
            lookup: lookup,
            arguments: arguments
        )
    }

    static func format(
        _ key: String,
        locale: Locale,
        lookup: Lookup,
        arguments: [CVarArg]
    ) -> String {
        String(
            format: text(key, locale: locale, lookup: lookup),
            locale: locale,
            arguments: arguments
        )
    }

    static func shortTime(_ date: Date, locale: Locale) -> String {
        date.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened)
                .locale(locale)
        )
    }

    static func startupKindTitle(_ kind: StartupItemKind, locale: Locale) -> String {
        switch kind {
        case .loginItem:
            text("登录项", locale: locale)
        case .launchAgent:
            text("Launch Agent", locale: locale)
        case .launchDaemon:
            text("Launch Daemon", locale: locale)
        }
    }

    static func associatedCategoryTitle(
        _ category: AssociatedFileCategory,
        locale: Locale
    ) -> String {
        category.localizedTitle(locale: locale)
    }
}

struct OptimizerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @State private var searchText = ""
    @State private var filter: StartupFilter = .recommended
    @State private var showsPaths = false
    @State private var showsApplyConfirmation = false
    @State private var operationMessage: String?
    @State private var isApplying = false

    var body: some View {
        let visibleItems = filteredItems
        let stagedCount = model.stagedStartupChangeCount

        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PageHeader(
                        title: localized("启动优化"),
                        subtitle: localized("审阅登录项与后台项目，减少不必要的启动负担"),
                        symbol: "power"
                    )

                    reviewBanner

                    startupInventoryStatus

                    startupSearchField

                    HStack {
                        Picker(localized("类型"), selection: $filter) {
                            ForEach(StartupFilter.allCases) { option in
                                Text(option.title(locale: locale)).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 520)
                        Spacer()
                        Text(AppCountLocalization.format(
                            count: model.startupItems.count,
                            oneKey: "tool.startup.ratio.one",
                            otherKey: "tool.startup.ratio.other",
                            oneDefaultValue: "%lld / %lld 项",
                            otherDefaultValue: "%lld / %lld 项",
                            locale: locale,
                            Int64(visibleItems.count),
                            Int64(model.startupItems.count)
                        ))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(CalmTheme.secondaryText)
                        Toggle(localized("显示路径"), isOn: $showsPaths)
                            .toggleStyle(.switch)
                    }

                    LazyVStack(spacing: 0) {
                        if model.isLoadingStartupItems && model.startupItems.isEmpty {
                            StartupInventorySkeleton()
                        } else if let error = model.startupItemsError, model.startupItems.isEmpty {
                            VStack(spacing: 14) {
                                ContentUnavailableView(
                                    localized("启动项目读取失败"),
                                    systemImage: "exclamationmark.triangle",
                                    description: Text(error)
                                )
                                Button(localized("重新读取")) {
                                    Task { await model.loadStartupItemsIfNeeded(force: true) }
                                }
                                .buttonStyle(CalmButtonStyle())
                            }
                            .frame(
                                maxWidth: .infinity,
                                minHeight: ToolLoadingLayout.startupInventoryHeight
                            )
                        } else if visibleItems.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                                .frame(minHeight: ToolLoadingLayout.startupInventoryHeight)
                        } else {
                            ForEach(visibleItems) { item in
                                startupRow(item)
                                if item.id != visibleItems.last?.id { CalmDivider() }
                            }
                        }
                    }
                    .frame(
                        minHeight: ToolLoadingLayout.startupInventoryHeight,
                        alignment: .top
                    )
                    .calmCard(padding: 0)

                    startupGuidance
                }
                .padding(24)
                .frame(maxWidth: 1_150, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .calmPage()

            if stagedCount > 0 {
                stagedBar(stagedCount: stagedCount)
            }
        }
        .navigationTitle(localized("启动优化"))
        .task {
            await model.loadStartupItemsIfNeeded()
        }
        .confirmationDialog(
            AppCountLocalization.format(
                count: model.stagedStartupChangeCount,
                oneKey: "tool.startup.confirm.one",
                otherKey: "tool.startup.confirm.other",
                oneDefaultValue: "应用 %lld 项启动设置？",
                otherDefaultValue: "应用 %lld 项启动设置？",
                locale: locale,
                Int64(model.stagedStartupChangeCount)
            ),
            isPresented: $showsApplyConfirmation,
            titleVisibility: .visible
        ) {
            Button(localized("应用更改")) { Task { await applyStartupChanges() } }
            Button(localized("取消"), role: .cancel) { }
        } message: {
            Text(localized("仅当前用户 LaunchAgents 可由公开系统工具修改；登录项和系统级后台项目会明确拒绝。安全测试模式会拒绝全部更改。"))
        }
        .alert(
            localized("启动设置结果"),
            isPresented: Binding(
                get: { operationMessage != nil },
                set: { if !$0 { operationMessage = nil } }
            )
        ) {
            Button(localized("知道了")) { operationMessage = nil }
        } message: {
            Text(operationMessage ?? "")
        }
    }

    private var startupSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(CalmTheme.secondaryText)
            TextField(localized("搜索名称、开发者或标识"), text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(CalmTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localized("清除启动项目搜索"))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: ToolLoadingLayout.searchFieldHeight)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(CalmTheme.hairline)
        }
        .accessibilityElement(children: .contain)
    }

    private var reviewBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "eye.circle.fill")
                .font(.title2)
                .foregroundStyle(CalmTheme.cyan)
            VStack(alignment: .leading, spacing: 3) {
                Text(localized(
                    RuntimeSafetyMode.current == .safeTest ? "安全测试模式" : "确认后应用"
                ))
                    .font(.headline)
                Text(localized("开关变化会先形成待确认方案；只有再次确认后才会尝试应用受支持的项目。"))
                    .font(.callout)
                    .foregroundStyle(CalmTheme.secondaryText)
            }
            Spacer()
            StatusPill(
                text: localized(
                    RuntimeSafetyMode.current == .safeTest ? "全部拒绝" : "受控修改"
                ),
                color: CalmTheme.cyan,
                symbol: RuntimeSafetyMode.current == .safeTest ? "lock.shield" : "checkmark.shield"
            )
        }
        .calmCard()
    }

    private var startupInventoryStatus: some View {
        HStack(spacing: 10) {
            if model.isLoadingStartupItems {
                ToolBackgroundActivity(
                    label: model.startupItems.isEmpty
                        ? localized("正在后台读取清单")
                        : localized("正在后台刷新，当前继续显示缓存")
                )
            } else if let error = model.startupItemsError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(CalmTheme.amber)
                Text(model.startupItems.isEmpty
                    ? localizedFormat("读取失败：%@", error)
                    : localizedFormat("刷新失败，继续显示缓存：%@", error))
                    .lineLimit(2)
            } else if let loadedAt = model.startupItemsLastLoadedAt {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(CalmTheme.mint)
                Text(AppCountLocalization.format(
                    count: model.startupItems.count,
                    oneKey: "tool.startup.cached.one",
                    otherKey: "tool.startup.cached.other",
                    oneDefaultValue: "已缓存 %lld 项 · %@",
                    otherDefaultValue: "已缓存 %lld 项 · %@",
                    locale: locale,
                    Int64(model.startupItems.count),
                    ToolViewsLocalization.shortTime(loadedAt, locale: locale)
                ))
            } else {
                Image(systemName: "clock")
                    .foregroundStyle(CalmTheme.secondaryText)
                Text(localized("等待后台读取"))
            }

            Spacer(minLength: 8)

            Button {
                Task { await model.loadStartupItemsIfNeeded(force: true) }
            } label: {
                Label(
                    localized(model.isLoadingStartupItems ? "正在刷新" : "刷新清单"),
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(CalmButtonStyle())
            .disabled(model.isLoadingStartupItems || model.stagedStartupChangeCount > 0)
            .help(localized(
                model.stagedStartupChangeCount > 0
                    ? "请先应用或撤销待确认的变化"
                    : "在后台重新读取启动项目"
            ))
        }
        .font(.caption)
        .foregroundStyle(CalmTheme.secondaryText)
        .padding(12)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }

    private func startupRow(_ item: StartupItem) -> some View {
        let isEditable = model.isStartupItemEditable(item)
        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color(for: item.kind).opacity(0.1))
                Image(systemName: symbol(for: item.kind))
                    .foregroundStyle(color(for: item.kind))
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.displayName)
                        .font(.callout.weight(.semibold))
                    StatusPill(
                        text: ToolViewsLocalization.startupKindTitle(
                            item.kind,
                            locale: locale
                        ),
                        color: color(for: item.kind)
                    )
                }
                Text(item.developer ?? item.label)
                    .font(.caption)
                    .foregroundStyle(CalmTheme.secondaryText)
                if showsPaths {
                    Text(item.path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(CalmTheme.tertiaryText)
                        .textSelection(.enabled)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 8) {
                    if !isEditable {
                        StatusPill(
                            text: localized("只读"),
                            color: .secondary,
                            symbol: "lock"
                        )
                    }
                    Toggle(
                        localizedFormat("启用 %@", item.displayName),
                        isOn: Binding(
                            get: { item.isEnabled },
                            set: { model.setStartupItem(item.id, enabled: $0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!isEditable)
                    .accessibilityLabel(localizedFormat("启用 %@", item.displayName))
                }
                Text(localizedScope(for: item))
                    .font(.caption2)
                    .foregroundStyle(CalmTheme.secondaryText)
            }
        }
        .padding(16)
    }

    private func stagedBar(stagedCount: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checklist")
                .foregroundStyle(CalmTheme.accent)
            Text(AppCountLocalization.format(
                count: stagedCount,
                oneKey: "tool.startup.staged.one",
                otherKey: "tool.startup.staged.other",
                oneDefaultValue: "已暂存 %lld 项变化",
                otherDefaultValue: "已暂存 %lld 项变化",
                locale: locale,
                Int64(stagedCount)
            ))
                .font(.callout.weight(.medium))
            Text(localized("尚未应用到系统"))
                .font(.caption)
                .foregroundStyle(CalmTheme.secondaryText)
            Spacer()
            Button(localized("撤销")) { model.resetStartupChanges() }
            Button(localized(isApplying ? "正在应用…" : "应用更改")) {
                showsApplyConfirmation = true
            }
                .buttonStyle(CalmButtonStyle(prominent: true))
                .disabled(isApplying)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { CalmDivider() }
    }

    private var startupGuidance: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: localized("判断建议"), symbol: "lightbulb")
            Label(
                localized("保留安全、输入法、云同步等你持续依赖的项目。"),
                systemImage: "checkmark.circle"
            )
            Label(
                localized("不认识的后台项目先查看开发者与路径，不根据名称直接停用。"),
                systemImage: "magnifyingglass"
            )
            Label(
                localized("系统范围项目可能影响所有用户，应单独核对。"),
                systemImage: "person.2"
            )
        }
        .font(.callout)
        .foregroundStyle(CalmTheme.secondaryText)
        .calmCard()
    }

    private var filteredItems: [StartupItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.startupItems.filter { item in
            let matchesFilter = filter.matches(item)
            let matchesQuery = query.isEmpty
                || item.displayName.localizedCaseInsensitiveContains(query)
                || item.label.localizedCaseInsensitiveContains(query)
                || (item.developer?.localizedCaseInsensitiveContains(query) ?? false)
            return matchesFilter && matchesQuery
        }
    }

    @MainActor
    private func applyStartupChanges() async {
        isApplying = true
        defer { isApplying = false }
        do {
            let count = try await model.applyStartupChanges()
            operationMessage = count == 0
                ? localized("没有需要应用的更改。")
                : AppCountLocalization.format(
                    count: count,
                    oneKey: "tool.startup.applied.one",
                    otherKey: "tool.startup.applied.other",
                    oneDefaultValue: "已应用 %lld 项更改。",
                    otherDefaultValue: "已应用 %lld 项更改。",
                    locale: locale,
                    Int64(count)
                )
        } catch {
            operationMessage = error.localizedDescription
        }
    }

    private func color(for kind: StartupItemKind) -> Color {
        switch kind {
        case .loginItem: CalmTheme.accent
        case .launchAgent: CalmTheme.violet
        case .launchDaemon: CalmTheme.amber
        }
    }

    private func symbol(for kind: StartupItemKind) -> String {
        switch kind {
        case .loginItem: "person.crop.circle.badge.clock"
        case .launchAgent: "gearshape.2"
        case .launchDaemon: "server.rack"
        }
    }

    private func localized(_ key: String) -> String {
        ToolViewsLocalization.text(key, locale: locale)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: localized(key),
            locale: locale,
            arguments: arguments
        )
    }

    private func localizedScope(for item: StartupItem) -> String {
        guard item.scopeKind != .unknown else { return item.scope }
        return item.scopeKind.localizedTitle(locale: locale)
    }
}

private enum StartupFilter: String, CaseIterable, Identifiable {
    case recommended
    case all
    case login
    case agent
    case daemon

    var id: String { rawValue }
    func title(locale: Locale) -> String {
        switch self {
        case .recommended: ToolViewsLocalization.text("建议关注", locale: locale)
        case .all: ToolViewsLocalization.text("全部", locale: locale)
        case .login: ToolViewsLocalization.text("登录项", locale: locale)
        case .agent: ToolViewsLocalization.text("用户后台", locale: locale)
        case .daemon: ToolViewsLocalization.text("系统后台", locale: locale)
        }
    }

    func matches(_ item: StartupItem) -> Bool {
        switch self {
        case .recommended: item.scope != "macOS"
        case .all: true
        case .login: item.kind == .loginItem
        case .agent: item.kind == .launchAgent && item.scope != "macOS"
        case .daemon: item.kind == .launchDaemon && item.scope != "macOS"
        }
    }
}

struct UninstallerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @State private var searchText = ""
    @State private var showsPlan = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: localized("应用管理"),
                subtitle: localized("核对应用本体和明确关联的支持文件，先审阅再决定"),
                symbol: "app.badge.checkmark"
            )
            .padding(24)

            HStack(spacing: 0) {
                applicationList
                    .frame(width: 320)
                Divider()
                applicationDetail
                    .frame(minWidth: 430)
            }
        }
        .calmPage()
        .navigationTitle(localized("应用管理"))
        .task(id: model.selectedApplicationID) {
            await model.loadSelectedApplicationDetails()
        }
        .sheet(isPresented: $showsPlan) {
            RemovalPlanView(application: model.selectedApplication)
                .frame(width: 620, height: 520)
        }
    }

    private var applicationList: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(CalmTheme.secondaryText)
                TextField(localized("搜索应用"), text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(CalmTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(localized("清除应用搜索"))
                }
            }
            .padding(10)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
            .padding(12)

            CalmDivider()

            Group {
                if model.isLoadingApplications && model.applications.isEmpty {
                    ApplicationListSkeleton()
                } else if let error = model.applicationsError, model.applications.isEmpty {
                    ToolLoadFailurePane(
                        title: localized("应用清单读取失败"),
                        message: error,
                        retryLabel: localized("重新读取")
                    ) {
                        Task { await refreshApplications() }
                    }
                } else {
                    List(selection: selectedApplicationBinding) {
                        ForEach(filteredApplications) { application in
                            HStack(spacing: 11) {
                                applicationIcon(application)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(application.name)
                                        .font(.callout.weight(.medium))
                                    HStack(spacing: 6) {
                                        Text(application.version.map { "v\($0)" } ?? localized("版本未知"))
                                        Text("·")
                                        Text(
                                            application.sizeBytes.map(MetricFormatter.bytes)
                                                ?? localized("大小未知")
                                        )
                                    }
                                    .font(.caption)
                                    .foregroundStyle(CalmTheme.secondaryText)
                                }
                            }
                            .tag(application.id)
                            .padding(.vertical, 5)
                        }
                    }
                    .listStyle(.sidebar)
                }
            }

            HStack(spacing: 8) {
                if model.isLoadingApplications {
                    ToolBackgroundActivity(
                        label: localized(
                            model.applications.isEmpty ? "正在读取" : "正在刷新缓存"
                        )
                    )
                } else if let error = model.applicationsError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(CalmTheme.amber)
                    Text(localized("刷新失败"))
                        .help(error)
                } else if let loadedAt = model.applicationsLastLoadedAt {
                    Text(AppCountLocalization.format(
                        count: filteredApplications.count,
                        oneKey: "tool.application.loaded.one",
                        otherKey: "tool.application.loaded.other",
                        oneDefaultValue: "%lld 个 · %@",
                        otherDefaultValue: "%lld 个 · %@",
                        locale: locale,
                        Int64(filteredApplications.count),
                        ToolViewsLocalization.shortTime(loadedAt, locale: locale)
                    ))
                } else {
                    Text(AppCountLocalization.format(
                        count: filteredApplications.count,
                        oneKey: "tool.application.count.one",
                        otherKey: "tool.application.count.other",
                        oneDefaultValue: "%lld 个应用",
                        otherDefaultValue: "%lld 个应用",
                        locale: locale,
                        Int64(filteredApplications.count)
                    ))
                }
                Spacer()
                Button {
                    Task { await refreshApplications() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(model.isLoadingApplications)
                .help(localized("在后台重新读取应用清单"))
                StatusPill(
                    text: localized("审阅模式"),
                    color: CalmTheme.cyan,
                    symbol: "eye"
                )
            }
            .font(.caption)
            .foregroundStyle(CalmTheme.secondaryText)
            .padding(12)
            .background(.bar)
        }
        .background(.background.opacity(0.34))
    }

    @ViewBuilder
    private var applicationDetail: some View {
        if model.isLoadingApplications && model.applications.isEmpty {
            ApplicationDetailSkeleton()
        } else if let error = model.applicationsError, model.applications.isEmpty {
            ToolLoadFailurePane(
                title: localized("应用详情暂不可用"),
                message: error,
                retryLabel: localized("重新读取")
            ) {
                Task { await refreshApplications() }
            }
        } else if let application = model.selectedApplication {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    applicationHeader(application)

                    HStack(spacing: 12) {
                        Label(
                            localized("关联项默认不勾选"),
                            systemImage: "checkmark.shield"
                        )
                        Spacer()
                        Text(localized("请逐项核对路径与归属依据"))
                    }
                    .font(.caption)
                    .foregroundStyle(CalmTheme.cyan)
                    .padding(12)
                    .background(CalmTheme.cyan.opacity(0.075), in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 13) {
                        HStack(alignment: .center, spacing: 12) {
                            SectionTitle(
                                title: localized("关联项目"),
                                subtitle: detailsSubtitle(for: application),
                                symbol: "point.3.connected.trianglepath.dotted"
                            )
                            if model.dataSource == .live {
                                Button {
                                    Task { await model.loadSelectedApplicationDetails(force: true) }
                                } label: {
                                    Label(
                                        localized("重新扫描"),
                                        systemImage: "arrow.clockwise"
                                    )
                                }
                                .buttonStyle(CalmButtonStyle())
                                .disabled(model.isLoadingApplicationDetails)
                                .help(localized("在后台重新核对该应用的关联候选项"))
                            }
                        }

                        if model.isLoadingApplicationDetails && application.associatedFiles.isEmpty {
                            AssociatedFilesSkeleton()
                        } else if application.associatedFiles.isEmpty {
                            ContentUnavailableView(
                                localized("没有关联候选项"),
                                systemImage: "checkmark.circle",
                                description: Text(localized("当前只显示应用本体；系统不会猜测归属不明确的文件。"))
                            )
                            .frame(minHeight: 190)
                        } else {
                            if model.isLoadingApplicationDetails {
                                ToolBackgroundActivity(
                                    label: localized("正在后台重新核对，当前继续显示缓存")
                                )
                                    .font(.caption)
                                    .foregroundStyle(CalmTheme.secondaryText)
                            }
                            ForEach(application.associatedFiles) { file in
                                associatedFileRow(file, applicationID: application.id)
                                if file.id != application.associatedFiles.last?.id { CalmDivider() }
                            }
                        }
                    }
                    .calmCard()

                    reviewSummary(application)
                }
                .padding(20)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            ContentUnavailableView(
                localized("选择一个应用"),
                systemImage: "app.dashed",
                description: Text(localized("查看版本、占用空间和关联项目。"))
            )
        }
    }

    private func applicationHeader(_ application: ApplicationCandidate) -> some View {
        HStack(spacing: 16) {
            applicationIcon(application, size: 68)
            VStack(alignment: .leading, spacing: 5) {
                Text(application.name)
                    .font(.title2.weight(.semibold))
                Text(application.bundleIdentifier ?? localized("没有 Bundle Identifier"))
                    .font(.caption.monospaced())
                    .foregroundStyle(CalmTheme.secondaryText)
                    .textSelection(.enabled)
                Text(application.bundleURL.path)
                    .font(.caption)
                    .foregroundStyle(CalmTheme.tertiaryText)
                    .textSelection(.enabled)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(application.sizeBytes.map(MetricFormatter.bytes) ?? localized("未统计"))
                    .font(.title3.monospacedDigit().weight(.semibold))
                Text(localized("应用大小"))
                    .font(.caption)
                    .foregroundStyle(CalmTheme.secondaryText)
            }
        }
    }

    private func associatedFileRow(_ file: AssociatedFile, applicationID: String) -> some View {
        let evidence = evidencePresentation(for: file.matchBasis)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: file.category.symbol)
                .foregroundStyle(CalmTheme.violet)
                .frame(width: 26, height: 26)
                .background(CalmTheme.violet.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(ToolViewsLocalization.associatedCategoryTitle(
                        file.category,
                        locale: locale
                    ))
                        .font(.callout.weight(.medium))
                    StatusPill(text: evidence.title, color: evidence.color, symbol: evidence.symbol)
                }
                Text(file.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(CalmTheme.secondaryText)
                    .textSelection(.enabled)
                Label(file.ownershipReason, systemImage: "magnifyingglass")
                    .font(.caption2)
                    .foregroundStyle(CalmTheme.secondaryText)
                Text(evidence.guidance)
                    .font(.caption2)
                    .foregroundStyle(CalmTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Text(file.sizeBytes.map(MetricFormatter.bytes) ?? localized("未统计"))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(CalmTheme.secondaryText)
                Button(localized("在 Finder 中显示")) {
                    revealInFinder(path: file.path)
                }
                .buttonStyle(.link)
                .help(localized("只打开 Finder 定位该项目，不修改文件"))
                Toggle(
                    localized(file.isSelected ? "已确认并加入" : "确认归属并加入"),
                    isOn: Binding(
                        get: { file.isSelected },
                        set: { model.setAssociatedFile(file.id, selected: $0, applicationID: applicationID) }
                    )
                )
                .toggleStyle(.checkbox)
                .fixedSize()
                .accessibilityLabel(localizedFormat(
                    "确认归属并将 %@ 加入清单",
                    ToolViewsLocalization.associatedCategoryTitle(
                        file.category,
                        locale: locale
                    )
                ))
            }
        }
        .padding(.vertical, 2)
    }

    private func detailsSubtitle(for application: ApplicationCandidate) -> String {
        if model.isLoadingApplicationDetails {
            return localized(
                application.associatedFiles.isEmpty
                    ? "正在后台读取"
                    : "正在刷新，继续显示缓存"
            )
        }
        if let loadedAt = model.applicationDetailsLastLoadedAt[application.id] {
            return localizedFormat(
                "已缓存 · %@",
                ToolViewsLocalization.shortTime(loadedAt, locale: locale)
            )
        }
        return localized("根据标识符和目录归属生成的候选清单")
    }

    private func evidencePresentation(
        for basis: AssociatedFileMatchBasis
    ) -> (title: String, symbol: String, color: Color, guidance: String) {
        switch basis {
        case let .exactBundleIdentifier(value):
            (
                localized("Bundle ID 完全匹配"),
                "checkmark.seal.fill",
                CalmTheme.mint,
                localizedFormat(
                    "路径名称包含该应用的唯一标识 %@。这是较强证据；若同一开发者的其他应用共享此目录，仍应保留。",
                    value
                )
            )
        case let .bundleIdentifierPrefix(value):
            (
                localized("Bundle ID 前缀匹配"),
                "checkmark.seal",
                CalmTheme.cyan,
                localizedFormat(
                    "文件名前缀为 %@，通常属于该应用的按主机设置。请先在 Finder 核对名称与修改时间。",
                    value
                )
            )
        case let .applicationName(value):
            (
                localized("仅应用名匹配"),
                "exclamationmark.triangle.fill",
                CalmTheme.amber,
                localizedFormat(
                    "只匹配名称“%@”，不同应用可能同名。请查看目录内容，确认没有其他应用共用后再加入。",
                    value
                )
            )
        case .unspecified:
            (
                localized("依据待核对"),
                "questionmark.circle",
                CalmTheme.amber,
                localized("扫描器没有提供结构化匹配依据。建议保持未勾选，并在 Finder 中核对来源。")
            )
        }
    }

    private func revealInFinder(path: String) {
        let expandedPath = (path as NSString).expandingTildeInPath
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: expandedPath)])
    }

    private func reviewSummary(_ application: ApplicationCandidate) -> some View {
        let selectedFiles = application.associatedFiles.filter(\.isSelected)
        let plan = UninstallPlan(application: application, selectedFiles: selectedFiles)
        let sizeSummary = plan.knownTotalBytes.map {
            localizedFormat("约 %@", MetricFormatter.bytes($0))
        } ?? localized("大小未统计")
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(localized("审阅摘要"))
                    .font(.headline)
                Text(AppCountLocalization.format(
                    count: selectedFiles.count,
                    oneKey: "tool.associated.count.one",
                    otherKey: "tool.associated.count.other",
                    oneDefaultValue: "应用本体 + %lld 个关联项 · %@",
                    otherDefaultValue: "应用本体 + %lld 个关联项 · %@",
                    locale: locale,
                    Int64(selectedFiles.count),
                    sizeSummary
                ))
                    .font(.callout)
                    .foregroundStyle(CalmTheme.secondaryText)
            }
            Spacer()
            Button(localized("生成移除清单")) { showsPlan = true }
                .buttonStyle(CalmButtonStyle(prominent: true))
        }
        .calmCard()
    }

    private var filteredApplications: [ApplicationCandidate] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.applications }
        return model.applications.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.bundleIdentifier?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var selectedApplicationBinding: Binding<String?> {
        Binding(
            get: { model.selectedApplicationID },
            set: { model.selectedApplicationID = $0 }
        )
    }

    @MainActor
    private func refreshApplications() async {
        await model.loadApplicationsIfNeeded(force: true)
        guard model.applicationsError == nil else { return }
        await model.loadSelectedApplicationDetails(force: true)
    }

    private func applicationIcon(_ application: ApplicationCandidate, size: CGFloat = 42) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [CalmTheme.accent.opacity(0.88), CalmTheme.violet.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(application.name.prefix(1).uppercased())
                .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: CalmTheme.accent.opacity(0.14), radius: 5, y: 2)
    }

    private func localized(_ key: String) -> String {
        ToolViewsLocalization.text(key, locale: locale)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: localized(key),
            locale: locale,
            arguments: arguments
        )
    }
}

enum ToolLoadingLayout {
    static let searchFieldHeight: CGFloat = 42
    static let startupPlaceholderRowCount = 7
    static let startupRowHeight: CGFloat = 74
    static let startupInventoryHeight = startupRowHeight * CGFloat(startupPlaceholderRowCount)
        + CGFloat(startupPlaceholderRowCount - 1)
    static let applicationPlaceholderRowCount = 8
    static let applicationListRowHeight: CGFloat = 62
    static let associatedFilesHeight: CGFloat = 190
}

enum ToolSkeletonMotionPolicy {
    static func animates(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    static func opacity(reduceMotion: Bool, isBright: Bool) -> Double {
        if reduceMotion { return 0.72 }
        return isBright ? 0.92 : 0.56
    }
}

private struct ToolBackgroundActivity: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let label: String

    var body: some View {
        HStack(spacing: 7) {
            if reduceMotion {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(CalmTheme.accent)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            Text(label)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

private struct ToolLoadFailurePane: View {
    let title: String
    let message: String
    let retryLabel: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ContentUnavailableView(
                title,
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
            Button(retryLabel, action: action)
                .buttonStyle(CalmButtonStyle())
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

private struct StartupInventorySkeleton: View {
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0 ..< ToolLoadingLayout.startupPlaceholderRowCount, id: \.self) { index in
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(CalmTheme.accent.opacity(0.12))
                        .frame(width: 42, height: 42)

                    VStack(alignment: .leading, spacing: 8) {
                        ToolSkeletonBar(width: 154, height: 11)
                        ToolSkeletonBar(width: index.isMultiple(of: 2) ? 210 : 176, height: 8)
                    }

                    Spacer(minLength: 16)

                    ToolSkeletonBar(width: 40, height: 22, cornerRadius: 11)
                }
                .padding(.horizontal, 16)
                .frame(height: ToolLoadingLayout.startupRowHeight)

                if index < ToolLoadingLayout.startupPlaceholderRowCount - 1 {
                    CalmDivider()
                }
            }
        }
        .frame(minHeight: ToolLoadingLayout.startupInventoryHeight)
        .modifier(ToolSkeletonPulseModifier())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            ToolViewsLocalization.text("正在后台读取启动项目", locale: locale)
        )
    }
}

private struct ApplicationListSkeleton: View {
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0 ..< ToolLoadingLayout.applicationPlaceholderRowCount, id: \.self) { index in
                HStack(spacing: 11) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(CalmTheme.violet.opacity(0.12))
                        .frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 7) {
                        ToolSkeletonBar(width: index.isMultiple(of: 3) ? 142 : 116, height: 10)
                        ToolSkeletonBar(width: index.isMultiple(of: 2) ? 96 : 124, height: 8)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(height: ToolLoadingLayout.applicationListRowHeight)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .modifier(ToolSkeletonPulseModifier())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            ToolViewsLocalization.text("正在后台准备应用清单", locale: locale)
        )
    }
}

private struct ApplicationDetailSkeleton: View {
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(CalmTheme.accent.opacity(0.12))
                        .frame(width: 68, height: 68)
                    VStack(alignment: .leading, spacing: 9) {
                        ToolSkeletonBar(width: 190, height: 16)
                        ToolSkeletonBar(width: 260, height: 9)
                        ToolSkeletonBar(width: 330, height: 9)
                    }
                    Spacer(minLength: 20)
                    VStack(alignment: .trailing, spacing: 8) {
                        ToolSkeletonBar(width: 82, height: 14)
                        ToolSkeletonBar(width: 58, height: 8)
                    }
                }

                ToolSkeletonBar(height: 44, cornerRadius: 10)

                VStack(alignment: .leading, spacing: 14) {
                    ToolSkeletonBar(width: 150, height: 13)
                    // The detail surface owns the pulse for the entire placeholder.
                    // Reusing the independently pulsing wrapper here would stack two
                    // repeat-forever animations with different phases.
                    AssociatedFilesSkeletonContent()
                }
                .calmCard()

                ToolSkeletonBar(height: 82, cornerRadius: 12)
            }
            .padding(20)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .modifier(ToolSkeletonPulseModifier())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            ToolViewsLocalization.text("正在后台准备应用详情", locale: locale)
        )
    }
}

private struct AssociatedFilesSkeleton: View {
    @Environment(\.locale) private var locale

    var body: some View {
        AssociatedFilesSkeletonContent()
            .modifier(ToolSkeletonPulseModifier())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                ToolViewsLocalization.text("正在后台读取关联项目", locale: locale)
            )
    }
}

private struct AssociatedFilesSkeletonContent: View {
    var body: some View {
        VStack(spacing: 12) {
            ForEach(0 ..< 3, id: \.self) { index in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(CalmTheme.violet.opacity(0.1))
                        .frame(width: 26, height: 26)
                    VStack(alignment: .leading, spacing: 7) {
                        ToolSkeletonBar(width: index == 1 ? 138 : 118, height: 9)
                        ToolSkeletonBar(height: 7)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: ToolLoadingLayout.associatedFilesHeight, alignment: .top)
    }
}

private struct ToolSkeletonBar: View {
    var width: CGFloat? = nil
    let height: CGFloat
    var cornerRadius: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.primary.opacity(0.11))
            .frame(maxWidth: width == nil ? .infinity : nil)
            .frame(width: width, height: height)
    }
}

private struct ToolSkeletonPulseModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBright = false

    func body(content: Content) -> some View {
        content
            .opacity(
                ToolSkeletonMotionPolicy.opacity(
                    reduceMotion: reduceMotion,
                    isBright: isBright
                )
            )
            .onAppear { updateAnimation() }
            .onChange(of: reduceMotion) { _, _ in updateAnimation() }
    }

    private func updateAnimation() {
        if !ToolSkeletonMotionPolicy.animates(reduceMotion: reduceMotion) {
            withAnimation(nil) { isBright = false }
        } else {
            isBright = false
            withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
                isBright = true
            }
        }
    }
}

private struct RemovalPlanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    let application: ApplicationCandidate?
    @State private var showsConfirmation = false
    @State private var operationMessage: String?
    @State private var operationSucceeded = false
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(localized("移除清单"))
                        .font(.title2.weight(.semibold))
                    Text(localized("逐项核对后，可将确认内容移到废纸篓"))
                        .font(.callout)
                        .foregroundStyle(CalmTheme.secondaryText)
                }
                Spacer()
                StatusPill(
                    text: localized(
                        RuntimeSafetyMode.current == .safeTest ? "安全测试" : "可恢复"
                    ),
                    color: CalmTheme.cyan,
                    symbol: RuntimeSafetyMode.current == .safeTest ? "lock" : "trash"
                )
            }

            CalmDivider()

            if let application {
                ScrollView {
                    VStack(alignment: .leading, spacing: 13) {
                        planRow(
                            localized("应用程序"),
                            application.bundleURL.path,
                            application.sizeBytes
                        )
                        ForEach(application.associatedFiles.filter(\.isSelected)) { file in
                            planRow(
                                ToolViewsLocalization.associatedCategoryTitle(
                                    file.category,
                                    locale: locale
                                ),
                                file.path,
                                file.sizeBytes
                            )
                        }
                    }
                }

                HStack {
                    Image(systemName: "info.circle")
                    Text(localized("执行前会再次校验路径；安全测试模式始终拒绝文件操作。"))
                    Spacer()
                }
                .font(.callout)
                .foregroundStyle(CalmTheme.secondaryText)
                .padding(12)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
            } else {
                ContentUnavailableView(
                    localized("没有应用"),
                    systemImage: "app.dashed"
                )
            }

            HStack {
                Button(localized("返回")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if application != nil {
                    Button(
                        localized(isWorking ? "正在处理…" : "移到废纸篓"),
                        role: .destructive
                    ) {
                        showsConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CalmTheme.rose)
                    .disabled(isWorking)
                }
            }
        }
        .padding(22)
        .background(CalmTheme.pageGradient)
        .confirmationDialog(
            localized("确认移除所列项目？"),
            isPresented: $showsConfirmation,
            titleVisibility: .visible
        ) {
            Button(localized("移到废纸篓"), role: .destructive) {
                Task { await executeRemoval() }
            }
            Button(localized("取消"), role: .cancel) { }
        } message: {
            Text(localized("应用本体和你逐项勾选的关联候选项将移到废纸篓。请先关闭目标应用；此操作不会清空废纸篓。"))
        }
        .alert(
            localized(operationSucceeded ? "已完成" : "未执行"),
            isPresented: Binding(
                get: { operationMessage != nil },
                set: { if !$0 { operationMessage = nil } }
            )
        ) {
            Button(localized("完成")) {
                operationMessage = nil
                if operationSucceeded { dismiss() }
            }
        } message: {
            Text(operationMessage ?? "")
        }
    }

    private func planRow(_ title: String, _ path: String, _ bytes: UInt64?) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(CalmTheme.mint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.medium))
                Text(path)
                    .font(.caption.monospaced())
                    .foregroundStyle(CalmTheme.secondaryText)
                    .textSelection(.enabled)
            }
            Spacer()
            Text(bytes.map(MetricFormatter.bytes) ?? localized("未统计"))
                .font(.caption.monospacedDigit())
                .foregroundStyle(CalmTheme.secondaryText)
        }
        .padding(12)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
    }

    @MainActor
    private func executeRemoval() async {
        guard let application else { return }
        isWorking = true
        operationSucceeded = false
        defer { isWorking = false }
        do {
            let count = try await model.uninstall(application)
            operationSucceeded = true
            operationMessage = AppCountLocalization.format(
                count: count,
                oneKey: "tool.removal.count.one",
                otherKey: "tool.removal.count.other",
                oneDefaultValue: "已将 %lld 个确认项目移到废纸篓。",
                otherDefaultValue: "已将 %lld 个确认项目移到废纸篓。",
                locale: locale,
                Int64(count)
            )
        } catch {
            operationMessage = error.localizedDescription
        }
    }

    private func localized(_ key: String) -> String {
        ToolViewsLocalization.text(key, locale: locale)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: localized(key),
            locale: locale,
            arguments: arguments
        )
    }
}

private extension AssociatedFileCategory {
    var symbol: String {
        switch self {
        case .binary: "app"
        case .cache: "shippingbox"
        case .container, .groupContainer: "cube"
        case .helper: "gearshape.2"
        case .loginItem: "person.crop.circle.badge.clock"
        case .log: "doc.text"
        case .plugin: "puzzlepiece.extension"
        case .preference: "slider.horizontal.3"
        case .script: "terminal"
        case .support: "folder"
        case .other: "doc"
        }
    }
}
