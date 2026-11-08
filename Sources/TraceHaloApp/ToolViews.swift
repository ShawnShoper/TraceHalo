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
    @State private var isShowingApplicationReview = false
    @State private var applicationIcons: [String: NSImage] = [:]
    @State private var removalApplicationID: String?
    @State private var pendingPrivilegedRemoval: PrivilegedUninstallTarget?
    @State private var privilegedRemovalAuthorization: PrivilegedUninstallAuthorization?
    @State private var isShowingPermissionSetup = false
    @State private var permissions = UninstallPermissionController.shared
    @State private var isRequestingRemovalAuthorization = false
    @State private var completedRemoval: UninstallPlan?
    @State private var removalFailure: UninstallExecutionError?
    @State private var removalError: String?
    @State private var isOpeningVendorUninstaller = false
    @State private var vendorUninstallerError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            applicationToolbar
            applicationList
                .disabled(model.isUninstallingApplication || isRequestingRemovalAuthorization)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CalmTheme.surface)
        .foregroundStyle(CalmTheme.primaryText)
        .navigationTitle(localized("应用管理"))
        .task { await model.loadApplicationsIfNeeded() }
        .task(id: model.applicationsLastLoadedAt, priority: .utility) {
            await model.loadApplicationSizes()
        }
        .task(id: model.applicationsLastLoadedAt, priority: .utility) {
            await loadApplicationIcons()
        }
        .onChange(of: searchText) { _, _ in
            clearRemovalPreparation()
            completedRemoval = nil
            removalFailure = nil
            if visibleSelectedApplication == nil {
                model.selectedApplicationID = nil
            }
        }
        .onDisappear { clearRemovalPreparation() }
        .sheet(isPresented: $isShowingApplicationReview, onDismiss: resetApplicationReview) {
            applicationReviewSheet
                .environment(\.locale, locale)
        }
    }

    private var applicationToolbar: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(localized("应用管理"))
                    .font(.system(size: 28, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text(localized("卸载应用，可选择保留本机数据。"))
                    .font(.system(size: 15))
                    .foregroundStyle(CalmTheme.secondaryText)
            }
            Spacer(minLength: 12)
            applicationSearch
                .frame(minWidth: 200, idealWidth: 280, maxWidth: 320)
            Button {
                Task { await refreshApplications() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(CalmTheme.secondaryText)
            .disabled(model.isLoadingApplications)
            .help(localized("在后台重新读取应用清单"))
            .accessibilityLabel(localized("刷新"))
        }
    }

    private var applicationSearch: some View {
        HStack(spacing: 8) {
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
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(CalmTheme.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(CalmTheme.hairline)
        }
    }

    private var applicationReviewSheet: some View {
        VStack(spacing: 12) {
            HStack {
                Text(localized("卸载选项"))
                    .font(.headline)
                Spacer()
                Button(action: closeApplicationReview) {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(localized("关闭卸载选项"))
                .keyboardShortcut(.cancelAction)
                .disabled(model.isUninstallingApplication || isRequestingRemovalAuthorization)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            applicationDetail
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(width: 720, height: 640)
        .calmPage()
        .interactiveDismissDisabled(model.isUninstallingApplication || isRequestingRemovalAuthorization)
        .task(id: model.selectedApplicationID) {
            await model.loadSelectedApplicationDetails()
            guard !Task.isCancelled, isShowingApplicationReview,
                  let application = visibleSelectedApplication,
                  application.vendorUninstaller == nil else { return }
            beginRemoval(application)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard pendingPrivilegedRemoval != nil else { return }
            Task { await permissions.refresh() }
        }
        .sheet(isPresented: $isShowingPermissionSetup, onDismiss: {
            Task { await permissions.refresh() }
        }) {
            UninstallPermissionSetupView(controller: permissions)
                .environment(\.locale, locale)
        }
        .alert(localized("卸载未完成"), isPresented: Binding(
            get: { removalError != nil },
            set: { if !$0 { removalError = nil } }
        )) {
            Button(localized("知道了"), role: .cancel) { }
        } message: {
            Text(removalError ?? "")
        }
        .alert(localized("无法打开厂商卸载器"), isPresented: Binding(
            get: { vendorUninstallerError != nil },
            set: { if !$0 { vendorUninstallerError = nil } }
        )) {
            Button(localized("知道了"), role: .cancel) { }
        } message: {
            Text(vendorUninstallerError ?? "")
        }
    }

    private func openApplicationReview(_ application: ApplicationCandidate) {
        guard !model.isUninstallingApplication, !isRequestingRemovalAuthorization,
              filteredApplications.contains(where: { $0.id == application.id }) else { return }
        resetApplicationReview()
        model.selectedApplicationID = application.id
        isShowingApplicationReview = true
    }

    private func closeApplicationReview() {
        guard !model.isUninstallingApplication, !isRequestingRemovalAuthorization else { return }
        isShowingApplicationReview = false
    }

    private func resetApplicationReview() {
        clearRemovalPreparation()
        completedRemoval = nil
        removalFailure = nil
        removalError = nil
        vendorUninstallerError = nil
    }

    private var applicationList: some View {
        GeometryReader { geometry in
            applicationTable(layout: ApplicationTableLayout(width: geometry.size.width))
        }
    }

    private func applicationTable(layout: ApplicationTableLayout) -> some View {
        let duplicateNames = duplicateApplicationNames
        return VStack(spacing: 0) {
            HStack(spacing: ApplicationTableLayout.columnSpacing) {
                Text(localized("应用"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(localized("版本"))
                    .frame(width: layout.versionWidth, alignment: .leading)
                Text(localized("大小"))
                    .frame(width: layout.sizeWidth, alignment: .trailing)
                Text(localized("操作"))
                    .frame(width: layout.actionWidth)
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(CalmTheme.secondaryText)
            .padding(.horizontal, ApplicationTableLayout.horizontalPadding)
            .frame(height: 40)
            .accessibilityHidden(true)

            Group {
                if model.isLoadingApplications && model.applications.isEmpty {
                    ApplicationListSkeleton(layout: layout)
                } else if let error = model.applicationsError, model.applications.isEmpty {
                    ToolLoadFailurePane(
                        title: localized("应用清单读取失败"),
                        message: error,
                        retryLabel: localized("重新读取")
                    ) {
                        Task { await refreshApplications() }
                    }
                } else if filteredApplications.isEmpty {
                    Group {
                        if searchQuery.isEmpty {
                            ContentUnavailableView(
                                localized("未找到可卸载的应用"), systemImage: "app.dashed",
                                description: Text(localized("可以刷新应用清单。"))
                            )
                        } else {
                            ContentUnavailableView.search(text: searchQuery)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filteredApplications) { application in
                            ApplicationListRow(
                                layout: layout,
                                name: application.name,
                                version: applicationVersionLabel(for: application),
                                size: applicationSizeLabel(for: application),
                                path: duplicateNames.contains(application.name) ? application.bundleURL.path : nil,
                                isSelected: model.selectedApplicationID == application.id,
                                icon: applicationIcon(application, size: 44),
                                onRemove: { openApplicationReview(application) }
                            )
                            .simultaneousGesture(TapGesture().onEnded {
                                selectedApplicationBinding.wrappedValue = application.id
                            })
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }

            CalmDivider()
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
            }
            .font(.caption)
            .foregroundStyle(CalmTheme.secondaryText)
            .padding(12)
        }
    }

    @ViewBuilder
    private var applicationDetail: some View {
        if let completedRemoval {
            removalReceipt(completedRemoval)
        } else if let removalFailure, removalFailure.didMoveApplication {
            removalFailureCard(removalFailure)
                .calmCard()
        } else if model.isLoadingApplications && model.applications.isEmpty {
            ApplicationDetailSkeleton()
        } else if let error = model.applicationsError, model.applications.isEmpty {
            ToolLoadFailurePane(
                title: localized("应用详情暂不可用"),
                message: error,
                retryLabel: localized("重新读取")
            ) {
                Task { await refreshApplications() }
            }
        } else if !searchQuery.isEmpty, filteredApplications.isEmpty {
            ContentUnavailableView.search(text: searchQuery)
                .frame(maxWidth: .infinity, minHeight: 200)
                .calmCard(padding: 0)
        } else if let application = visibleSelectedApplication {
            let isConfirming = removalApplicationID == application.id
            let isCheckingUninstaller = model.dataSource == .live
                && model.applicationDetailsLastLoadedAt[application.id] == nil
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        applicationIcon(application, size: 46)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isConfirming ? localizedFormat("卸载%@", application.name) : application.name)
                                .font(.title2.weight(.semibold))
                                .accessibilityAddTraits(.isHeader)
                            Text("\(applicationVersionLabel(for: application)) · \(applicationSizeLabel(for: application))")
                                .font(.callout)
                                .foregroundStyle(CalmTheme.secondaryText)
                            if duplicateApplicationNames.contains(application.name) {
                                Text(application.bundleURL.path)
                                    .font(.caption)
                                    .foregroundStyle(CalmTheme.secondaryText)
                                    .textSelection(.enabled)
                            }
                        }
                        Spacer(minLength: 0)
                    }

                    if let removalFailure {
                        CalmDivider()
                        removalFailureCard(removalFailure, application: application)
                    } else if pendingPrivilegedRemoval?.path == application.bundleURL.standardizedFileURL.path {
                        CalmDivider()
                        removalApprovalCard(for: application)
                    } else if isConfirming {
                        CalmDivider()
                        if privilegedRemovalAuthorization != nil {
                            Label(localized("管理员身份已验证"), systemImage: "checkmark.shield")
                                .foregroundStyle(CalmTheme.mint)
                        }
                        RemovalConfirmationView(
                            application: application,
                            onCancel: closeApplicationReview,
                            onConfirm: { plan in Task { await executeRemoval(plan) } }
                        )
                        .id(application.id)
                    } else {
                        if let uninstaller = application.vendorUninstaller {
                            vendorUninstallerNotice(uninstaller, for: application.id)
                        } else if isCheckingUninstaller {
                            ToolBackgroundActivity(label: localized("正在查找本机数据与卸载方式…"))
                        }

                        if !isCheckingUninstaller {
                            CalmDivider()
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 14) {
                                    removalDescription
                                    Spacer(minLength: 4)
                                    removalButton(for: application)
                                }
                                VStack(alignment: .leading, spacing: 10) {
                                    removalDescription
                                    removalButton(for: application)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .calmCard()
            }
            .disabled(model.isUninstallingApplication)
        } else {
            ContentUnavailableView(
                localized("选择一个应用"),
                systemImage: "app.dashed",
                description: Text(localized("选择应用，查看大小和卸载选项。"))
            )
            .frame(maxWidth: .infinity, minHeight: 200)
            .calmCard(padding: 0)
        }
    }

    private var removalDescription: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localized("移到废纸篓"))
                .font(.callout.weight(.semibold))
            Text(localized("可选择保留或清理本机数据。"))
                .font(.callout)
                .foregroundStyle(CalmTheme.secondaryText)
        }
    }

    private func removalButton(for application: ApplicationCandidate) -> some View {
        Button(application.vendorUninstaller == nil
            ? localized("卸载…")
            : localized("使用 TraceHalo 卸载…")) {
            beginRemoval(application)
        }
        .buttonStyle(CalmButtonStyle(prominent: application.vendorUninstaller == nil))
        .disabled(isOpeningVendorUninstaller || isRequestingRemovalAuthorization)
    }

    private func removalApprovalCard(for application: ApplicationCandidate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if isRequestingRemovalAuthorization || permissions.isChecking {
                ToolBackgroundActivity(label: localized("正在检查卸载权限…"))
            } else {
                Label(localized(permissions.isReady ? "需要管理员授权" : "卸载权限尚未就绪"), systemImage: "lock.shield")
                    .font(.headline)
                Text(localized(permissions.isReady
                    ? "验证管理员身份后，即可确认移到废纸篓。"
                    : "请先在权限设置中完成配置。配置完成后，后续卸载无需重复打开系统设置。"))
                    .foregroundStyle(CalmTheme.secondaryText)
                if let message = permissions.errorMessage {
                    Text(message).font(.caption).foregroundStyle(CalmTheme.secondaryText)
                }
                HStack(spacing: 10) {
                    Button(localized(permissions.isReady ? "继续授权" : "权限设置")) {
                        if permissions.isReady { continuePrivilegedRemoval() }
                        else { isShowingPermissionSetup = true }
                    }
                        .buttonStyle(CalmButtonStyle(prominent: true))
                    Button(localized("在 Finder 中显示")) {
                        NSWorkspace.shared.activateFileViewerSelecting([application.bundleURL])
                    }
                    .buttonStyle(CalmButtonStyle())
                    Button(localized("取消"), action: clearRemovalPreparation)
                        .buttonStyle(CalmButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func beginRemoval(_ application: ApplicationCandidate) {
        clearRemovalPreparation()
        removalFailure = nil
        do {
            guard let target = try model.privilegedUninstallTarget(for: application) else {
                removalApplicationID = application.id
                return
            }
            pendingPrivilegedRemoval = target
            Task {
                await permissions.refresh()
                guard pendingPrivilegedRemoval == target,
                      visibleSelectedApplication?.id == application.id else { return }
                if permissions.isReady { continuePrivilegedRemoval() }
            }
        } catch {
            removalError = error.localizedDescription
        }
    }

    private func continuePrivilegedRemoval() {
        guard let target = pendingPrivilegedRemoval,
              let application = visibleSelectedApplication,
              target.path == application.bundleURL.standardizedFileURL.path,
              !isRequestingRemovalAuthorization else { return }

        do {
            guard try model.privilegedUninstallTarget(for: application) == target else {
                throw AppOperationError.uninstallTargetChanged
            }
        } catch {
            clearRemovalPreparation()
            removalError = error.localizedDescription
            return
        }

        isRequestingRemovalAuthorization = true
        Task {
            defer { isRequestingRemovalAuthorization = false }
            do {
                await permissions.refresh()
                guard permissions.isReady,
                      pendingPrivilegedRemoval == target,
                      visibleSelectedApplication?.id == application.id else { return }
                try await PrivilegedUninstallClient.checkTrashAccess()
                guard pendingPrivilegedRemoval == target,
                      visibleSelectedApplication?.id == application.id else { return }
                guard try model.privilegedUninstallTarget(for: application) == target else {
                    throw AppOperationError.uninstallTargetChanged
                }
                let authorization = try await PrivilegedUninstallClient.authorize(
                    target,
                    prompt: localizedFormat("请验证管理员身份，以继续卸载 %@。", application.name)
                )
                guard pendingPrivilegedRemoval == target,
                      visibleSelectedApplication?.id == application.id else { return }
                guard try model.privilegedUninstallTarget(for: application) == target else {
                    throw AppOperationError.uninstallTargetChanged
                }
                pendingPrivilegedRemoval = nil
                privilegedRemovalAuthorization = authorization
                removalApplicationID = application.id
            } catch PrivilegedUninstallClientError.cancelled {
                if pendingPrivilegedRemoval == target { clearRemovalPreparation() }
            } catch PrivilegedUninstallClientError.approvalRequired {
                await permissions.refresh()
            } catch PrivilegedUninstallClientError.helperConnectionFailed {
                permissions.recordCheckFailure(PrivilegedUninstallClientError.helperConnectionFailed)
            } catch PrivilegedUninstallClientError.trashAccessDenied {
                guard pendingPrivilegedRemoval == target,
                      visibleSelectedApplication?.id == application.id else { return }
                permissions.recordTrashAccessDenied()
            } catch {
                guard pendingPrivilegedRemoval == target else { return }
                removalError = error.localizedDescription
            }
        }
    }

    private func clearRemovalPreparation() {
        removalApplicationID = nil
        pendingPrivilegedRemoval = nil
        privilegedRemovalAuthorization?.invalidate()
        privilegedRemovalAuthorization = nil
        isShowingPermissionSetup = false
    }

    private func removalFailureCard(
        _ failure: UninstallExecutionError,
        application: ApplicationCandidate? = nil
    ) -> some View {
        let target = failure.failedTargetURL
        let appPermissionDenied = failure.isPermissionDenied && target != nil
            && target?.standardizedFileURL == application?.bundleURL.standardizedFileURL
        let retryApplication = application.flatMap { candidate in
            target?.standardizedFileURL == candidate.bundleURL.standardizedFileURL
                && (try? model.privilegedUninstallTarget(for: candidate)) != nil ? candidate : nil
        }

        return VStack(alignment: .leading, spacing: 12) {
            Label(
                localized(failure.didMoveApplication ? "应用已移除，部分文件仍在原处" : "卸载未完成"),
                systemImage: "exclamationmark.triangle"
            )
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
            if appPermissionDenied {
                Text(localized("macOS 拒绝移动这个应用。本次移入废纸篓 0 项。可在 Finder 中将应用移到废纸篓，按系统提示验证。"))
                    .foregroundStyle(CalmTheme.secondaryText)
                DisclosureGroup(localized("错误详情")) {
                    Text(failure.localizedDescription(locale: locale))
                        .font(.callout)
                        .foregroundStyle(CalmTheme.secondaryText)
                        .textSelection(.enabled)
                }
                .font(.callout)
            } else {
                Text(failure.localizedDescription(locale: locale))
                    .foregroundStyle(CalmTheme.secondaryText)
                    .textSelection(.enabled)
            }
            HStack(spacing: 10) {
                if let retryApplication {
                    Button(localized("重新授权…")) { beginRemoval(retryApplication) }
                        .buttonStyle(CalmButtonStyle(prominent: true))
                }
                if let target {
                    Button(localized("在 Finder 中显示")) {
                        NSWorkspace.shared.activateFileViewerSelecting([target])
                    }
                    .buttonStyle(CalmButtonStyle(prominent: appPermissionDenied && retryApplication == nil))
                }
                Button(localized("完成"), action: closeApplicationReview)
                    .buttonStyle(CalmButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func vendorUninstallerNotice(_ uninstaller: VendorUninstaller, for applicationID: String) -> some View {
        let message: String
        let openButton: (title: String, url: URL)?
        switch uninstaller.entryPoint {
        case .application(let url):
            message = localizedFormat("建议使用厂商卸载器卸载 %@。", uninstaller.productName)
            openButton = (localized("打开厂商卸载器"), url)
        case .dockerDesktop(let url):
            message = localized("建议在 Docker Desktop 中选择「疑难解答 → 卸载」。")
            openButton = (localized("打开 Docker Desktop"), url)
        case .command:
            message = localizedFormat("建议使用厂商卸载器卸载 %@。", uninstaller.productName)
            openButton = nil
        }

        return VStack(alignment: .leading, spacing: 10) {
            Label(localized("推荐使用厂商卸载器"), systemImage: "checkmark.seal")
                .font(.callout.weight(.semibold))
                .foregroundStyle(CalmTheme.selectionText)
            Text(message)
                .font(.callout)
                .foregroundStyle(CalmTheme.secondaryText)
            if let openButton {
                Button(openButton.title) {
                    Task { await openVendorUninstaller(openButton.url, matching: uninstaller, for: applicationID) }
                }
                .buttonStyle(CalmButtonStyle(prominent: true))
                .disabled(isOpeningVendorUninstaller)
            }
            DisclosureGroup(localized("卸载器位置")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: uninstaller.fileURL.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(CalmTheme.secondaryText)
                        .textSelection(.enabled)
                    Button(localized("在 Finder 中显示")) {
                        NSWorkspace.shared.activateFileViewerSelecting([uninstaller.fileURL])
                    }
                    .buttonStyle(CalmButtonStyle())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            }
            .font(.callout)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CalmTheme.selectionBackground.opacity(0.60), in: RoundedRectangle(cornerRadius: 10))
    }

    private func openVendorUninstaller(_ url: URL, matching uninstaller: VendorUninstaller, for applicationID: String) async {
        guard !isOpeningVendorUninstaller else { return }
        isOpeningVendorUninstaller = true
        defer { isOpeningVendorUninstaller = false }

        guard await model.canOpenVendorUninstaller(uninstaller, for: applicationID) else {
            if model.selectedApplicationID == applicationID {
                vendorUninstallerError = localized("卸载器已移动或变更，请重新查看应用详情。")
                await model.loadSelectedApplicationDetails(force: true)
            }
            return
        }
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: .init())
        } catch {
            vendorUninstallerError = error.localizedDescription
        }
    }

    private func removalReceipt(_ plan: UninstallPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.title2)
                .foregroundStyle(CalmTheme.mint)
                .accessibilityHidden(true)
            Text(localizedFormat("%@已移到废纸篓", plan.application.name))
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            if plan.selectedFiles.isEmpty {
                Text(localized("本机数据已保留。"))
            } else {
                Text(AppCountLocalization.format(
                    count: plan.selectedFiles.count,
                    oneKey: "tool.uninstall.filesMoved.one",
                    otherKey: "tool.uninstall.filesMoved.other",
                    oneDefaultValue: "选中的 %lld 项文件也已移到废纸篓。",
                    otherDefaultValue: "选中的 %lld 项文件也已移到废纸篓。",
                    locale: locale,
                    Int64(plan.selectedFiles.count)
                ))
            }
            Text(localized("需要找回应用时，可以到废纸篓中恢复。"))
                .foregroundStyle(CalmTheme.secondaryText)
            Button(localized("完成"), action: closeApplicationReview)
                .buttonStyle(CalmButtonStyle())
                .padding(.top, 6)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredApplications: [ApplicationCandidate] {
        let query = searchQuery
        return model.applications.filter { matchesSearch($0, query: query) }
    }

    private var visibleSelectedApplication: ApplicationCandidate? {
        guard let application = model.selectedApplication,
              matchesSearch(application, query: searchQuery) else { return nil }
        return application
    }

    private func matchesSearch(_ application: ApplicationCandidate, query: String) -> Bool {
        query.isEmpty
            || application.name.localizedCaseInsensitiveContains(query)
            || (application.bundleIdentifier?.localizedCaseInsensitiveContains(query) ?? false)
    }

    private func applicationVersionLabel(for application: ApplicationCandidate) -> String {
        guard let version = application.version?.trimmingCharacters(in: .whitespacesAndNewlines),
              !version.isEmpty else { return localized("版本未知") }
        return version.first?.isNumber == true ? "v\(version)" : version
    }

    private var duplicateApplicationNames: Set<String> {
        let groups = Dictionary(grouping: model.applications, by: \.name)
        return Set(groups.compactMap { name, applications in
            applications.count > 1 ? name : nil
        })
    }

    private func applicationSizeLabel(for application: ApplicationCandidate) -> String {
        if let size = application.sizeBytes {
            return size.formatted(.byteCount(style: .file).locale(locale))
        }
        return localized(
            model.dataSource == .live && !model.unavailableApplicationSizeIDs.contains(application.id)
                ? "正在统计大小…"
                : "无法统计大小"
        )
    }

    private var selectedApplicationBinding: Binding<String?> {
        Binding(
            get: { visibleSelectedApplication?.id },
            set: { id in
                guard id != model.selectedApplicationID else { return }
                clearRemovalPreparation()
                completedRemoval = nil
                removalFailure = nil
                model.selectedApplicationID = id
            }
        )
    }

    @MainActor
    private func refreshApplications() async {
        clearRemovalPreparation()
        completedRemoval = nil
        removalFailure = nil
        await model.loadApplicationsIfNeeded(force: true)
        guard model.applicationsError == nil else { return }
        guard visibleSelectedApplication != nil else {
            model.selectedApplicationID = nil
            return
        }
    }

    @MainActor
    private func executeRemoval(_ plan: UninstallPlan) async {
        guard !model.isUninstallingApplication,
              removalApplicationID == plan.application.id,
              visibleSelectedApplication?.id == plan.application.id else { return }
        let authorization = privilegedRemovalAuthorization
        privilegedRemovalAuthorization = nil
        clearRemovalPreparation()
        do {
            try await model.uninstall(plan, authorization: authorization)
            completedRemoval = plan
        } catch let failure as UninstallExecutionError {
            removalFailure = failure
            if !failure.didMoveApplication {
                await model.loadSelectedApplicationDetails(force: true)
            }
        } catch let failure as UninstallAppMoveUnconfirmed {
            await refreshApplications()
            removalError = failure.localizedDescription(locale: locale)
        } catch {
            removalError = error.localizedDescription
        }
    }

    private func loadApplicationIcons() async {
        guard model.dataSource == .live, let loadedAt = model.applicationsLastLoadedAt else { return }
        var icons: [String: NSImage] = [:]
        for application in model.applications {
            guard !Task.isCancelled else { return }
            icons[application.id] = await Self.readApplicationIcon(at: application.bundleURL)
        }
        guard !Task.isCancelled, model.applicationsLastLoadedAt == loadedAt else { return }
        applicationIcons = icons
    }

    @concurrent
    nonisolated private static func readApplicationIcon(at bundleURL: URL) async -> NSImage? {
        guard let resources = try? bundleURL.resourceValues(forKeys: [.effectiveIconKey]),
              let icon = resources.effectiveIcon as? NSImage,
              icon.isValid else {
            return nil
        }
        return icon
    }

    private func applicationIcon(_ application: ApplicationCandidate, size: CGFloat = 42) -> some View {
        Group {
            if let icon = applicationIcons[application.id] {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
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
                .shadow(color: CalmTheme.accent.opacity(0.14), radius: 5, y: 2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
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

private struct ApplicationTableLayout {
    let width: CGFloat
    static let columnSpacing: CGFloat = 20
    static let horizontalPadding: CGFloat = 12
    var versionWidth: CGFloat { max(100, min(240, width * 0.20)) }
    var sizeWidth: CGFloat { max(116, min(220, width * 0.18)) }
    var actionWidth: CGFloat { 120 }
}

private struct ApplicationListRow<Icon: View>: View {
    @Environment(\.locale) private var locale
    let layout: ApplicationTableLayout
    let name: String
    let version: String
    let size: String
    let path: String?
    let isSelected: Bool
    let icon: Icon
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: ApplicationTableLayout.columnSpacing) {
            HStack(spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.system(size: 18, weight: .semibold))
                        .lineLimit(1)
                        .help(name)
                    if let path {
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(CalmTheme.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(path)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(version)
                .font(.system(size: 16))
                .foregroundStyle(CalmTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(version)
                .frame(width: layout.versionWidth, alignment: .leading)
            Text(size)
                .font(.system(size: 16).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .frame(width: layout.sizeWidth, alignment: .trailing)
            Button(ToolViewsLocalization.text("卸载", locale: locale), action: onRemove)
                .font(.system(size: 16, weight: .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .buttonStyle(CalmButtonStyle())
                .frame(width: layout.actionWidth)
                .accessibilityLabel(ToolViewsLocalization.format(
                    "卸载%@", locale: locale, name
                ))
        }
        .foregroundStyle(CalmTheme.primaryText)
        .padding(.horizontal, ApplicationTableLayout.horizontalPadding)
        .frame(minHeight: 80)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 7)
                    .fill(CalmTheme.selectionBackground)
            }
        }
        .overlay(alignment: .bottom) {
            if !isSelected { CalmDivider() }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }
}

enum ToolLoadingLayout {
    static let searchFieldHeight: CGFloat = 42
    static let startupPlaceholderRowCount = 7
    static let startupRowHeight: CGFloat = 74
    static let startupInventoryHeight = startupRowHeight * CGFloat(startupPlaceholderRowCount)
        + CGFloat(startupPlaceholderRowCount - 1)
    static let applicationPlaceholderRowCount = 8
    static let applicationListRowHeight: CGFloat = 80
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
    let layout: ApplicationTableLayout
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0 ..< ToolLoadingLayout.applicationPlaceholderRowCount, id: \.self) { index in
                HStack(spacing: ApplicationTableLayout.columnSpacing) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(CalmTheme.violet.opacity(0.12))
                            .frame(width: 44, height: 44)
                        ToolSkeletonBar(width: index.isMultiple(of: 3) ? 142 : 116, height: 10)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ToolSkeletonBar(width: 64, height: 9)
                        .frame(width: layout.versionWidth, alignment: .leading)
                    ToolSkeletonBar(width: 58, height: 9)
                        .frame(width: layout.sizeWidth, alignment: .trailing)
                    ToolSkeletonBar(width: 48, height: 9)
                        .frame(width: layout.actionWidth)
                }
                .padding(.horizontal, ApplicationTableLayout.horizontalPadding)
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
                        .frame(width: 54, height: 54)
                    ToolSkeletonBar(width: 190, height: 16)
                }
                ToolSkeletonBar(width: 300, height: 12)
                ToolSkeletonBar(width: 120, height: 32, cornerRadius: 8)
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

struct ApplicationRemovalSelection {
    enum DataMode: Equatable {
        case keep
        case clean
    }

    var dataMode: DataMode = .keep {
        didSet {
            if dataMode == .keep { selectedFileIDs.removeAll() }
        }
    }
    var selectedFileIDs = Set<AssociatedFile.ID>()

    mutating func toggleBulkSelection(for application: ApplicationCandidate) {
        let eligible = Set(application.associatedFiles.filter(\.isEligibleForBulkSelection).map(\.id))
        if eligible.isSubset(of: selectedFileIDs) { selectedFileIDs.subtract(eligible) }
        else { selectedFileIDs.formUnion(eligible) }
    }

    mutating func setSelected(_ isSelected: Bool, file: AssociatedFile, in application: ApplicationCandidate) {
        guard dataMode == .clean, file.isEligibleForCleanup,
              application.associatedFiles.contains(file) else { return }
        let descendants = application.associatedFiles.filter {
            $0.path == file.path || $0.path.hasPrefix(file.path + "/")
        }
        if isSelected {
            selectedFileIDs.formUnion(descendants.filter(\.isEligibleForCleanup).map(\.id))
        } else {
            selectedFileIDs.subtract(descendants.map(\.id))
            // An unchecked child must never move through a selected ancestor.
            selectedFileIDs.subtract(application.associatedFiles.filter {
                file.path.hasPrefix($0.path + "/")
            }.map(\.id))
        }
    }

    func makePlan(for application: ApplicationCandidate) -> UninstallPlan {
        let checked = dataMode == .clean
            ? application.associatedFiles.filter { $0.isEligibleForCleanup && selectedFileIDs.contains($0.id) }
            : []
        let complete = checked.filter { parent in
            !application.associatedFiles.contains { child in
                child.path.hasPrefix(parent.path + "/") && !selectedFileIDs.contains(child.id)
            }
        }
        let selectedFiles = complete.filter { child in
            !complete.contains { child.path.hasPrefix($0.path + "/") }
        }
        return UninstallPlan(application: application, selectedFiles: selectedFiles)
    }
}

struct RemovalFinalConfirmationView: View {
    @Environment(\.locale) private var locale
    let plan: UninstallPlan
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(text("确认移除"), systemImage: "trash")
                .font(.title2.weight(.bold))
                .foregroundStyle(CalmTheme.primaryText)
            Text(format("确认将「%@」移到废纸篓？", plan.application.name))
                .font(.callout)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if plan.coveredAssociatedFiles.contains(where: { !$0.cleanupWarnings.isEmpty }) {
                        VStack(alignment: .leading, spacing: 10) {
                            Label {
                                Text(text("请特别注意所选数据"))
                            } icon: {
                                Image(systemName: "exclamationmark.triangle").foregroundStyle(CalmTheme.amber)
                            }
                            .font(.callout.weight(.semibold)).foregroundStyle(CalmTheme.primaryText)
                            ForEach(ApplicationDataCleanupWarning.allCases, id: \.self) { warning in
                                let count = plan.coveredAssociatedFiles.filter { $0.cleanupWarnings.contains(warning) }.count
                                if count > 0 {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(format("%@（%lld 项）", warning.title(locale: locale), Int64(count)))
                                            .font(.callout.weight(.medium)).foregroundStyle(CalmTheme.primaryText)
                                        Text(warning.impact(locale: locale)).font(.caption)
                                    }
                                }
                            }
                        }
                        .foregroundStyle(CalmTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .calmCard(padding: 14)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(text("将移到废纸篓：")).font(.callout.weight(.semibold))
                        Text(plan.application.name).font(.callout.weight(.medium))
                        pathText(plan.application.bundleURL.path)
                        ForEach(plan.selectedFiles) { file in
                            CalmDivider()
                            Text(file.dataPurpose.title(locale: locale)).font(.callout.weight(.medium))
                            pathText(file.path)
                            ForEach(warnings(coveredBy: file), id: \.self) { warning in
                                Label {
                                    Text(warning.title(locale: locale)).foregroundStyle(CalmTheme.primaryText)
                                } icon: {
                                    Image(systemName: "exclamationmark.triangle").foregroundStyle(CalmTheme.amber)
                                }
                                .font(.caption.weight(.medium))
                            }
                        }
                        if plan.selectedFiles.isEmpty {
                            Text(text("本机数据将保留。"))
                                .font(.callout).foregroundStyle(CalmTheme.secondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .calmCard(padding: 14)

                    if !plan.retainedAssociatedFiles.isEmpty {
                        DisclosureGroup(format("将保留（%lld 项候选文件）", Int64(plan.retainedAssociatedFiles.count))) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(plan.retainedAssociatedFiles) { file in pathText(file.path) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                        }
                        .font(.caption)
                        .calmCard(padding: 14)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(text("仅将应用和已选文件移到废纸篓，不会清空废纸篓。"))
                .font(.caption).foregroundStyle(CalmTheme.secondaryText)
            HStack(spacing: 12) {
                Spacer()
                Button(text("取消"), action: onCancel)
                    .buttonStyle(CalmButtonStyle()).keyboardShortcut(.cancelAction)
                Button(text("确认移除"), role: .destructive, action: onConfirm)
                    .buttonStyle(.borderedProminent).tint(CalmTheme.rose)
            }
        }
        .padding(22)
        .frame(width: 660, height: 610)
        .calmPage()
    }

    private func warnings(coveredBy file: AssociatedFile) -> [ApplicationDataCleanupWarning] {
        let covered = plan.coveredAssociatedFiles.filter {
            $0.path == file.path || $0.path.hasPrefix(file.path + "/")
        }
        return ApplicationDataCleanupWarning.allCases.filter { warning in
            covered.contains { $0.cleanupWarnings.contains(warning) }
        }
    }

    private func pathText(_ path: String) -> some View {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let display = path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
        return Text(display)
            .font(.caption.monospaced()).foregroundStyle(CalmTheme.secondaryText)
            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func text(_ key: String) -> String { ToolViewsLocalization.text(key, locale: locale) }
    private func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }
}

struct RemovalConfirmationView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    @State private var selection = ApplicationRemovalSelection()
    @State private var pendingConfirmation: UninstallPlan?
    let application: ApplicationCandidate
    let onCancel: () -> Void
    let onConfirm: (UninstallPlan) -> Void

    init(application: ApplicationCandidate, initialSelection: ApplicationRemovalSelection = ApplicationRemovalSelection(),
         onCancel: @escaping () -> Void, onConfirm: @escaping (UninstallPlan) -> Void) {
        self.application = application
        self._selection = State(initialValue: initialSelection)
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    private var isLookingForFiles: Bool {
        model.isLoadingApplicationDetails
            || (model.dataSource == .live && model.applicationDetailsLastLoadedAt[application.id] == nil)
    }

    var body: some View {
        let plan = selection.makePlan(for: application)
        VStack(alignment: .leading, spacing: 16) {
            if isLookingForFiles || !application.associatedFiles.isEmpty || selection.dataMode == .clean {
                VStack(alignment: .leading, spacing: 7) {
                    Text(localized("本机数据怎么处理？"))
                        .font(.headline)
                    modeOption(
                        .keep,
                        title: localized("保留本机数据"),
                        subtitle: localized("重装时可能还能用原来的设置。")
                    )
                    modeOption(
                        .clean,
                        title: localized("同时清理本机数据"),
                        subtitle: localized("把选中的本机文件也移到废纸篓。")
                    )
                }
            } else {
                HStack {
                    Text(localized("没有找到可一起清理的本机文件。"))
                        .foregroundStyle(CalmTheme.secondaryText)
                    Spacer()
                    rescanButton
                }
            }

            if selection.dataMode == .clean {
                cleanupFiles
            }

            Text(localized("未列出的位置、个人文稿和云端数据不会清理。查找结果不代表全部历史数据。"))
                .font(.caption)
                .foregroundStyle(CalmTheme.secondaryText)

            HStack(spacing: 12) {
                Spacer()
                Button(localized("取消"), action: onCancel)
                    .buttonStyle(CalmButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(confirmationButtonTitle(for: plan), role: .destructive) {
                    pendingConfirmation = plan
                }
                .buttonStyle(.borderedProminent)
                .tint(CalmTheme.rose)
                .disabled(!canConfirm(plan))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(
            isPresented: Binding(
                get: { pendingConfirmation != nil },
                set: { if !$0 { pendingConfirmation = nil } }
            )
        ) {
            if let confirmedPlan = pendingConfirmation {
                RemovalFinalConfirmationView(plan: confirmedPlan, onCancel: {
                    pendingConfirmation = nil
                }, onConfirm: {
                    let currentPlan = selection.makePlan(for: application)
                    guard canConfirm(currentPlan),
                          currentPlan.application.id == confirmedPlan.application.id,
                          currentPlan.selectedFiles == confirmedPlan.selectedFiles else { return }
                    pendingConfirmation = nil
                    onConfirm(confirmedPlan)
                })
                .traceHaloLanguageEnvironment()
            }
        }
        .onChange(of: application.associatedFiles) { _, _ in
            selection.selectedFileIDs.removeAll()
            pendingConfirmation = nil
        }
    }

    private func canConfirm(_ plan: UninstallPlan) -> Bool {
        !model.isLoadingApplications && !model.isUninstallingApplication
            && (selection.dataMode == .keep || (!isLookingForFiles && !plan.selectedFiles.isEmpty))
    }

    private func modeOption(
        _ mode: ApplicationRemovalSelection.DataMode,
        title: String,
        subtitle: String
    ) -> some View {
        let isSelected = selection.dataMode == mode
        return Button {
            selection.dataMode = mode
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? CalmTheme.accent : CalmTheme.secondaryText)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.callout.weight(.semibold))
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(CalmTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(
                isSelected ? CalmTheme.accent.opacity(0.15) : Color.clear,
                in: RoundedRectangle(cornerRadius: CalmTheme.controlRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CalmTheme.controlRadius)
                    .strokeBorder(CalmTheme.hairline)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var cleanupFiles: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(localized("选择要一起清理的文件"))
                    .font(.headline)
                Spacer()
                if !isLookingForFiles && application.associatedFiles.contains(where: \.isEligibleForBulkSelection) {
                    selectAllFilesButton
                }
                rescanButton
            }
            if isLookingForFiles {
                ToolBackgroundActivity(label: localized("正在查找可一起清理的文件"))
            } else if application.associatedFiles.isEmpty {
                Text(localized("没有找到可一起清理的本机文件。"))
                    .foregroundStyle(CalmTheme.secondaryText)
            } else {
                Text(localizedFormat("这些文件可能与%@有关。未勾选的文件会保留。", application.name))
                    .foregroundStyle(CalmTheme.secondaryText)
                if let summary = application.dataDiscovery {
                    DisclosureGroup(localized("查找范围与限制")) {
                        discoveryCoverage(summary)
                            .padding(.top, 4)
                    }
                    .font(.caption)
                    if summary.wasLimited || summary.unreadableLocations {
                        Text(localized("部分位置受权限或查找范围限制，可能仍有未发现的文件。"))
                            .font(.caption)
                            .foregroundStyle(CalmTheme.secondaryText)
                    }
                }
                Text(localized("全选包含归属未确认、共享数据和保存的内容。请核对下方标记；未勾选的项目会保留。"))
                    .font(.caption)
                    .foregroundStyle(CalmTheme.secondaryText)
                ForEach(application.associatedFiles.filter(\.isEligibleForCleanup)) { file in
                    CalmDivider()
                    associatedFileRow(file)
                }
                if application.associatedFiles.contains(where: { !$0.isEligibleForCleanup }) {
                    CalmDivider()
                    Label(localized("无法在此清理 · 路径或来源受限"), systemImage: "lock.shield")
                        .font(.callout.weight(.semibold))
                    ForEach(application.associatedFiles.filter { !$0.isEligibleForCleanup }) { file in
                        associatedFileRow(file)
                    }
                }
            }
        }
        .calmCard(padding: 12)
    }

    private var selectAllFilesButton: some View {
        let fileIDs = Set(application.associatedFiles.filter(\.isEligibleForBulkSelection).map(\.id))
        let allSelected = fileIDs.isSubset(of: selection.selectedFileIDs)
        return Button(localized(allSelected ? "取消全选" : "全选")) {
            selection.toggleBulkSelection(for: application)
        }
        .buttonStyle(CalmButtonStyle())
        .disabled(model.isLoadingApplications || model.isUninstallingApplication)
    }

    @ViewBuilder
    private var rescanButton: some View {
        if model.dataSource == .live {
            Button(localized("重新查找")) {
                selection.selectedFileIDs.removeAll()
                Task { await model.loadSelectedApplicationDetails(force: true) }
            }
            .buttonStyle(CalmButtonStyle())
            .disabled(isLookingForFiles || model.isLoadingApplications)
        }
    }

    private func associatedFileRow(_ file: AssociatedFile) -> some View {
        let title = file.dataPurpose.title(locale: locale)
        return VStack(alignment: .leading, spacing: 5) {
            if file.isEligibleForCleanup {
            Toggle(isOn: Binding(
                get: { selection.selectedFileIDs.contains(file.id) },
                set: { isChecked in
                    selection.setSelected(isChecked, file: file, in: application)
                }
            )) {
                HStack {
                    Text(title).font(.callout.weight(.medium))
                    Spacer(minLength: 10)
                    Text(file.sizeBytes.map { MetricFormatter.bytes($0, locale: locale) } ?? localized("大小未统计"))
                        .font(.caption).foregroundStyle(CalmTheme.secondaryText)
                }
            }
            .toggleStyle(.checkbox)
            } else {
                Label(title, systemImage: "lock")
                    .font(.callout.weight(.medium))
            }
            Text(file.dataPurpose.impact(locale: locale))
                .font(.caption)
                .foregroundStyle(CalmTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if file.isEligibleForCleanup {
                ForEach(file.cleanupWarnings, id: \.self) { warning in
                    Label {
                        Text(warning.title(locale: locale) + "：" + warning.impact(locale: locale))
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(CalmTheme.secondaryText)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(CalmTheme.amber)
                    }
                    .font(.caption)
                }
            }
            Text(displayPath(file))
                .font(.caption.monospaced())
                .foregroundStyle(CalmTheme.secondaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if !file.isEligibleForCleanup {
                Text((file.retentionReason ?? .uncertain).explanation(locale: locale))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CalmTheme.secondaryText)
            }

            DisclosureGroup(localized("文件详情")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.path)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Text(file.ownershipReason)
                        .font(.caption)
                        .foregroundStyle(CalmTheme.secondaryText)
                    ForEach(file.additionalEvidence, id: \.self) { evidence in
                        Text(evidence).font(.caption).foregroundStyle(CalmTheme.secondaryText)
                    }
                    Button(localized("在 Finder 中显示")) {
                        let path = (file.path as NSString).expandingTildeInPath
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                    .buttonStyle(.link)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            .font(.caption)
            .accessibilityLabel(localizedFormat("查看%@的文件详情", title))
        }
    }

    private func displayPath(_ file: AssociatedFile) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return file.path.hasPrefix(home + "/") ? "~" + file.path.dropFirst(home.count) : file.path
    }

    private func discoveryCoverage(_ summary: ApplicationDataDiscoverySummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localizedFormat("已检查：应用标识、%lld 个同厂商签名组件、%lld 个脚本文本、%lld 份相关安装收据。", Int64(summary.signedComponentCount), Int64(summary.scriptCount), Int64(summary.receiptCount)))
            if !summary.signatureVerified {
                Text(localized("未能验证应用签名；未启用厂商专用路径和应用群组查找。"))
            }
            if summary.wasLimited || summary.unreadableLocations {
                Text(localized("部分位置受权限或查找范围限制，可能仍有未发现的文件。"))
            }
            if summary.incompleteSizeCount > 0 {
                Text(localized("部分文件夹较大或无法读取，大小暂未统计。"))
            }
        }
        .font(.caption)
        .foregroundStyle(CalmTheme.secondaryText)
    }

    private func confirmationButtonTitle(for plan: UninstallPlan) -> String {
        if model.isUninstallingApplication { return localized("正在处理…") }
        if plan.selectedFiles.isEmpty { return localized("移到废纸篓") }
        return localizedFormat("移到废纸篓（%lld 项）", Int64(plan.totalItemCount))
    }

    private func localized(_ key: String) -> String {
        ToolViewsLocalization.text(key, locale: locale)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: localized(key), locale: locale, arguments: arguments)
    }
}
