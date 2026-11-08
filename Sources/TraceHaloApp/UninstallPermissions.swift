import AppKit
import Observation
import ServiceManagement
import SwiftUI
import TraceHaloCore

// Readiness is an observed capability, not a persisted "user clicked Allow" flag.
enum UninstallHelperSetupState: Equatable {
    case notEnabled, awaitingApproval, updateRequired, enabled
}

enum UninstallTrashAccessState: Equatable {
    case notChecked, available, denied
}

@MainActor
protocol UninstallPermissionServicing {
    var helperState: UninstallHelperSetupState { get }
    func requestHelper() async throws
    func checkTrashAccess() async throws
    func openDiskSettings()
}

@MainActor
struct LiveUninstallPermissionService: UninstallPermissionServicing {
    var helperState: UninstallHelperSetupState {
        if PrivilegedUninstallClient.isEnabled {
            return PrivilegedUninstallClient.needsHelperUpdate ? .updateRequired : .enabled
        }
        if PrivilegedUninstallClient.isAwaitingApproval { return .awaitingApproval }
        return .notEnabled
    }

    func requestHelper() async throws {
        _ = try await PrivilegedUninstallClient.prepareHelper()
    }

    func checkTrashAccess() async throws {
        try await PrivilegedUninstallClient.checkTrashAccess()
    }

    func openDiskSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }
}

@MainActor @Observable
final class UninstallPermissionController {
    static let shared = UninstallPermissionController()
    static let introductionKey = "uninstallPermissionIntroductionSeenV1"

    private(set) var helperState: UninstallHelperSetupState = .notEnabled
    private(set) var trashAccess: UninstallTrashAccessState = .notChecked
    private(set) var isChecking = false
    private(set) var isConfiguring = false
    private(set) var errorMessage: String?
    @ObservationIgnored private let service: any UninstallPermissionServicing
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var revision = 0

    init(service: any UninstallPermissionServicing = LiveUninstallPermissionService(), defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
    }

    var isBusy: Bool { isChecking || isConfiguring }
    var isReady: Bool {
        helperState == .enabled && trashAccess == .available && !isBusy && errorMessage == nil
    }

    /// This only reads state. Registration and System Settings require an
    /// explicit click in the setup view, never a startup side effect.
    func prepareFirstRunIfNeeded() async -> Bool {
        guard !defaults.bool(forKey: Self.introductionKey) else { return false }
        await refresh()
        guard !Task.isCancelled, !defaults.bool(forKey: Self.introductionKey) else { return false }
        acknowledgeIntroduction()
        return !isReady
    }

    func acknowledgeIntroduction() {
        defaults.set(true, forKey: Self.introductionKey)
    }

    func refresh() async {
        guard !isConfiguring else { return }
        if let refreshTask {
            await refreshTask.value
            return
        }
        isChecking = true
        errorMessage = nil
        let expectedRevision = revision
        let task = Task { @MainActor in
            defer {
                isChecking = false
                refreshTask = nil
            }
            helperState = service.helperState
            guard helperState == .enabled else {
                trashAccess = .notChecked
                return
            }
            do {
                try await service.checkTrashAccess()
                guard revision == expectedRevision else { return }
                trashAccess = .available
            } catch PrivilegedUninstallClientError.trashAccessDenied {
                guard revision == expectedRevision else { return }
                trashAccess = .denied
            } catch {
                guard revision == expectedRevision else { return }
                // A missing reply or helper error is not proof of FDA denial.
                trashAccess = .notChecked
                errorMessage = error.localizedDescription
            }
        }
        refreshTask = task
        await task.value
    }

    func requestHelper() async {
        guard !isBusy else { return }
        isConfiguring = true
        errorMessage = nil
        do {
            try await service.requestHelper()
            isConfiguring = false
            await refresh()
        } catch {
            isConfiguring = false
            helperState = service.helperState
            trashAccess = .notChecked
            errorMessage = error.localizedDescription
        }
    }

    func openDiskSettings() {
        // Opening the pane does not change readiness. A subsequent probe must
        // succeed before the UI reports that access is available.
        service.openDiskSettings()
    }

    func recordTrashAccessDenied() {
        revision += 1
        trashAccess = .denied
        errorMessage = nil
    }

    func recordCheckFailure(_ error: any Error) {
        revision += 1
        helperState = service.helperState
        trashAccess = .notChecked
        errorMessage = error.localizedDescription
    }
}

struct UninstallPermissionSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let controller: UninstallPermissionController

    init(controller: UninstallPermissionController = .shared) {
        self.controller = controller
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: controller.isReady ? "checkmark.shield" : "lock.shield")
                    .font(.system(size: 26))
                    .foregroundStyle(controller.isReady ? CalmTheme.mint : CalmTheme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(text("卸载功能准备")).font(.title2.weight(.bold))
                    Text(text("完成一次配置，后续卸载无需反复打开系统设置。"))
                        .font(.callout).foregroundStyle(CalmTheme.secondaryText)
                }
                Spacer(minLength: 0)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    helperStep
                    diskStep
                    Text(text("普通监控不需要这些权限，可以稍后在「设置 → 卸载权限」中继续配置。"))
                        .font(.caption).foregroundStyle(CalmTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let message = controller.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(CalmTheme.rose)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if controller.isReady {
                        Label(text("卸载权限已就绪。移除受保护应用时，系统仍可能要求验证管理员身份。"), systemImage: "checkmark.circle.fill")
                            .font(.callout).foregroundStyle(CalmTheme.mint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                if controller.isBusy {
                    ProgressView().controlSize(.small)
                    Text(text("正在检查权限…")).font(.caption).foregroundStyle(CalmTheme.secondaryText)
                }
                Spacer()
                Button(text("重新检查")) { Task { await controller.refresh() } }
                    .buttonStyle(CalmButtonStyle())
                    .disabled(controller.isBusy)
                Button(text(controller.isReady ? "完成" : "稍后设置")) { dismiss() }
                    .buttonStyle(CalmButtonStyle(prominent: controller.isReady))
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(22)
        .frame(width: 660, height: 610)
        .calmPage()
        .task {
            controller.acknowledgeIntroduction()
            await controller.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await controller.refresh() }
        }
    }

    private var helperStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            stepHeader("1", title: "启用卸载助手", ready: controller.helperState == .enabled)
            Text(text("用于将需要管理员权限的应用移到废纸篓。只在你确认卸载后执行。"))
                .font(.callout).foregroundStyle(CalmTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if controller.helperState == .enabled {
                Label(text("卸载助手已启用"), systemImage: "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(CalmTheme.mint)
            } else {
                if controller.helperState == .awaitingApproval {
                    Text(text("请在「系统设置 → 通用 → 登录项与扩展」批准 TraceHalo 卸载助手。"))
                        .font(.caption).foregroundStyle(CalmTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(text(controller.helperState == .awaitingApproval ? "前往批准"
                    : controller.helperState == .updateRequired ? "更新卸载助手" : "启用卸载助手")) {
                    Task { await controller.requestHelper() }
                }
                .buttonStyle(CalmButtonStyle(prominent: true))
                .disabled(controller.isBusy)
            }
        }
        .calmCard(padding: 14)
    }

    private var diskStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            stepHeader("2", title: "配置文件访问权限", ready: controller.trashAccess == .available)
            Text(text("用于访问废纸篓及受保护的关联文件。完全磁盘访问权限范围较大，可访问其他应用的数据，需由你在系统设置中手动开启。"))
                .font(.callout).foregroundStyle(CalmTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if controller.trashAccess == .available {
                Label(text("已验证废纸篓访问"), systemImage: "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(CalmTheme.mint)
                Text(text("其他文件仍以实际访问检查结果为准。"))
                    .font(.caption).foregroundStyle(CalmTheme.secondaryText)
            } else if controller.helperState != .enabled {
                Text(text("先启用卸载助手，再检查文件访问权限。"))
                    .font(.callout).foregroundStyle(CalmTheme.secondaryText)
            } else {
                Text(text(controller.trashAccess == .denied ? "尚不能访问废纸篓" : "文件访问状态待检查"))
                    .font(.callout.weight(.medium))
                Button(text("打开系统设置")) { controller.openDiskSettings() }
                    .buttonStyle(CalmButtonStyle(prominent: true))
                    .disabled(controller.isBusy)
                Text(text("在「隐私与安全性 → 完全磁盘访问权限」中启用 TraceHalo 和 TraceHaloUninstallHelper（卸载助手）。返回后会自动检查；如系统要求，请退出并重新打开应用。"))
                    .font(.caption).foregroundStyle(CalmTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                DisclosureGroup(text("列表中找不到条目？")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(text("先启用卸载助手并重新检查。仍找不到时，可在系统设置中点「+」添加相应程序。"))
                            .fixedSize(horizontal: false, vertical: true)
                        Button(text("在 Finder 中显示 TraceHalo")) {
                            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                        }
                        .buttonStyle(.link)
                        Button(text("在 Finder 中显示卸载助手")) {
                            NSWorkspace.shared.activateFileViewerSelecting([
                                Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/TraceHaloUninstallHelper")
                            ])
                        }
                        .buttonStyle(.link)
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
            }
        }
        .calmCard(padding: 14)
    }

    private func stepHeader(_ number: String, title: String, ready: Bool) -> some View {
        HStack(spacing: 9) {
            Text(number).font(.caption.weight(.bold))
                .frame(width: 24, height: 24)
                .background(CalmTheme.selectionBackground, in: Circle())
                .foregroundStyle(CalmTheme.accent)
            Text(text(title)).font(.headline)
            Spacer()
            if ready { Image(systemName: "checkmark").foregroundStyle(CalmTheme.mint).accessibilityHidden(true) }
        }
    }

    private func text(_ key: String) -> String {
        AppLocalization.string(key, defaultValue: key, locale: locale)
    }
}
