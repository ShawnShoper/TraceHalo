import Darwin
import Foundation
import OSLog
import Security
import ServiceManagement
import TraceHaloCore

enum PrivilegedUninstallClientError: LocalizedError {
    case cancelled
    case approvalRequired
    case helperNotPackaged
    case helperRegistrationFailed(domain: String, code: Int)
    case helperRegistrationNotConfirmed
    case helperConnectionFailed
    case trashAccessDenied
    case authorizationFailed(OSStatus)
    case authorizationExpired
    case targetChanged

    var errorDescription: String? {
        switch self {
        case .cancelled:
            AppLocalization.currentString("已取消管理员验证。")
        case .approvalRequired:
            AppLocalization.currentString("请先在系统设置中允许 TraceHalo 的卸载助手。")
        case .helperNotPackaged:
            AppLocalization.currentString("当前 TraceHalo 缺少卸载助手文件，请重新安装最新版。")
        case let .helperRegistrationFailed(domain, code):
            AppLocalization.currentFormat(
                "macOS 未能注册卸载助手（%@）。请重试，或在 Finder 中卸载这个应用。",
                defaultValue: "macOS 未能注册卸载助手（%@）。请重试，或在 Finder 中卸载这个应用。",
                "\(domain) \(code)"
            )
        case .helperRegistrationNotConfirmed:
            AppLocalization.currentString("macOS 尚未确认卸载助手已注册，请重新申请权限。")
        case .helperConnectionFailed:
            AppLocalization.currentString("无法连接已启用的卸载助手。未移动任何项目，请重新授权或在 Finder 中卸载。")
        case .trashAccessDenied:
            AppLocalization.currentString("macOS 未允许 TraceHalo 访问废纸篓。")
        case let .authorizationFailed(status):
            AppLocalization.currentFormat(
                "macOS 未授予卸载所需的管理员权限（%d）。",
                defaultValue: "macOS 未授予卸载所需的管理员权限（%d）。",
                status
            )
        case .authorizationExpired:
            AppLocalization.currentString("本次卸载的管理员授权已失效，请重新验证。")
        case .targetChanged:
            AppLocalization.currentString("待卸载应用已变更，请重新选择并验证。")
        }
    }

    fileprivate static func authorizationError(_ status: OSStatus) -> Self {
        status == errAuthorizationCanceled ? .cancelled : .authorizationFailed(status)
    }
}

private let uninstallHelperLogger = Logger(subsystem: "com.tseai.tracehalo", category: "UninstallHelper")

@MainActor
enum PrivilegedUninstallClient {
    // Update this when the daemon implementation or launch plist changes.
    private static let helperRevision = 2
    private static let helperRevisionKey = "uninstallHelperRegistrationRevision"

    static var isEnabled: Bool {
        RuntimeSafetyMode.current == .live && service.status == .enabled
    }

    static var isAwaitingApproval: Bool {
        RuntimeSafetyMode.current == .live && service.status == .requiresApproval
    }

    static var needsHelperUpdate: Bool {
        isEnabled && UserDefaults.standard.integer(forKey: helperRevisionKey) != helperRevision
    }

    static func prepareHelper() async throws -> Bool {
        guard RuntimeSafetyMode.current == .live else {
            throw SafetyViolation.deniedInSafeTestMode(.uninstall)
        }

        let helper = service
        let needsUpdate = helper.status == .enabled
            && UserDefaults.standard.integer(forKey: helperRevisionKey) != helperRevision
        if needsUpdate {
            // macOS keeps the old daemon process after a bundle replacement.
            // Re-enroll the changed executable on the next requested uninstall.
            do {
                try await helper.unregister()
            } catch {
                guard helper.status != .enabled else {
                    let failure = error as NSError
                    uninstallHelperLogger.error(
                        "Daemon update unregister failed: \(failure.domain, privacy: .public) \(failure.code, privacy: .public)"
                    )
                    throw PrivilegedUninstallClientError.helperRegistrationFailed(domain: failure.domain, code: failure.code)
                }
            }
            guard helper.status != .enabled else {
                throw PrivilegedUninstallClientError.helperRegistrationNotConfirmed
            }
        }
        try Task.checkCancellation()

        if needsUpdate {
            try await retryHelperRegistrationAfterUpdate(
                register: { try requestBundledApproval(for: helper) },
                wait: { try await Task.sleep(for: $0) }
            )
        } else {
            try requestBundledApproval(for: helper)
        }
        return helper.status == .enabled
    }

    static func retryHelperRegistrationAfterUpdate(
        register: () throws -> Void,
        wait: (Duration) async throws -> Void
    ) async throws {
        // Background Task Management can briefly reject registration after
        // its asynchronous unregister completion. Only retry this failure
        // during the update of an already approved helper.
        for delay in [Duration.seconds(1), .seconds(2), .seconds(3)] {
            do {
                try register()
                return
            } catch let PrivilegedUninstallClientError.helperRegistrationFailed(domain, code)
                where domain == "SMAppServiceErrorDomain" && code == Int(EPERM) {
                try await wait(delay)
                try Task.checkCancellation()
            }
        }
        try register()
    }

    private static func requestBundledApproval(for helper: SMAppService) throws {
        try requestApproval(
            status: { helper.status },
            register: {
                let bundle = Bundle.main.bundleURL
                let plist = bundle.appendingPathComponent("Contents/Library/LaunchDaemons")
                    .appendingPathComponent(PrivilegedUninstallConstants.launchDaemonPlistName)
                let executable = bundle.appendingPathComponent("Contents/Resources/TraceHaloUninstallHelper")
                guard FileManager.default.isReadableFile(atPath: plist.path),
                      FileManager.default.isExecutableFile(atPath: executable.path) else {
                    throw PrivilegedUninstallClientError.helperNotPackaged
                }
                defer {
                    let status = helper.status
                    if status == .enabled || status == .requiresApproval {
                        UserDefaults.standard.set(helperRevision, forKey: helperRevisionKey)
                    }
                }
                try helper.register()
            },
            openApprovalSettings: { SMAppService.openSystemSettingsLoginItems() }
        )
    }

    static func requestApproval(
        status: () -> SMAppService.Status,
        register: () throws -> Void,
        openApprovalSettings: () -> Void
    ) throws {
        let current = status()
        switch current {
        case .enabled:
            return
        case .requiresApproval:
            openApprovalSettings()
            return
        case .notRegistered, .notFound:
            // On some systems the first status lookup reports .notFound when
            // the packaged daemon is valid but has no registration record.
            do {
                try register()
            } catch let error as PrivilegedUninstallClientError {
                throw error
            } catch {
                switch status() {
                case .enabled:
                    return
                case .requiresApproval:
                    openApprovalSettings()
                    return
                default:
                    let failure = error as NSError
                    uninstallHelperLogger.error(
                        "Daemon registration failed: \(failure.domain, privacy: .public) \(failure.code, privacy: .public)"
                    )
                    throw PrivilegedUninstallClientError.helperRegistrationFailed(domain: failure.domain, code: failure.code)
                }
            }
        @unknown default:
            throw PrivilegedUninstallClientError.helperRegistrationNotConfirmed
        }

        switch status() {
        case .enabled:
            return
        case .requiresApproval:
            openApprovalSettings()
        case .notRegistered, .notFound:
            uninstallHelperLogger.error("Daemon registration returned successfully without a registration record")
            throw PrivilegedUninstallClientError.helperRegistrationNotConfirmed
        @unknown default:
            throw PrivilegedUninstallClientError.helperRegistrationNotConfirmed
        }
    }

    private static func requireEnabledHelper() throws {
        guard RuntimeSafetyMode.current == .live else {
            throw SafetyViolation.deniedInSafeTestMode(.uninstall)
        }
        guard isEnabled else {
            throw PrivilegedUninstallClientError.approvalRequired
        }
    }

    static func checkTrashAccess() async throws {
        try requireEnabledHelper()
        try await UninstallHelperOperation.checkTrashAccess.perform()
    }

    static func authorize(
        _ target: PrivilegedUninstallTarget,
        prompt: String
    ) async throws -> PrivilegedUninstallAuthorization {
        try requireEnabledHelper()

        // SecurityAgent owns the prompt. Its synchronous API must not block
        // SwiftUI while the user is authenticating.
        let authorization = try await Task.detached(priority: .userInitiated) {
            try UninstallAuthorizationReference(prompt: prompt)
        }.value
        try await UninstallHelperOperation.preflight(target, authorization).perform()
        try Task.checkCancellation()
        return PrivilegedUninstallAuthorization(target: target, authorization: authorization)
    }

    private static var service: SMAppService {
        .daemon(plistName: PrivilegedUninstallConstants.launchDaemonPlistName)
    }
}

/// Owns a single authorization until it is discarded or used to submit the
/// already selected bundle to the privileged helper.
final class PrivilegedUninstallAuthorization: @unchecked Sendable {
    let target: PrivilegedUninstallTarget
    private let lock = NSLock()
    private var authorization: UninstallAuthorizationReference?
    private let expiresAt = ContinuousClock.now + .seconds(240)

    fileprivate init(target: PrivilegedUninstallTarget, authorization: UninstallAuthorizationReference) {
        self.target = target
        self.authorization = authorization
    }

    func invalidate() {
        lock.withLock { authorization = nil }
    }

    func moveApplicationToTrash(_ url: URL) async throws {
        let authorization = lock.withLock {
            defer { self.authorization = nil }
            return self.authorization
        }
        guard RuntimeSafetyMode.current == .live else {
            throw SafetyViolation.deniedInSafeTestMode(.uninstall)
        }
        guard url.standardizedFileURL.path == target.path else {
            throw PrivilegedUninstallClientError.targetChanged
        }
        guard let authorization, ContinuousClock.now < expiresAt else {
            throw PrivilegedUninstallClientError.authorizationExpired
        }

        try await UninstallHelperOperation.move(url, target, authorization).perform()
    }
}

private enum UninstallHelperOperation: Sendable {
    case checkTrashAccess
    case preflight(PrivilegedUninstallTarget, UninstallAuthorizationReference)
    case move(URL, PrivilegedUninstallTarget, UninstallAuthorizationReference)

    func perform() async throws {
        try Task.checkCancellation()
        defer { withExtendedLifetime(self) {} }

        let connectionFailure: any Error = switch self {
        case .checkTrashAccess, .preflight:
            PrivilegedUninstallClientError.helperConnectionFailed
        case let .move(url, _, _):
            UninstallAppMoveUnconfirmed(applicationURL: url)
        }
        let connection = NSXPCConnection(
            machServiceName: PrivilegedUninstallConstants.machServiceName,
            options: .privileged
        )
        connection.setCodeSigningRequirement(PrivilegedUninstallConstants.helperSigningRequirement)
        connection.remoteObjectInterface = NSXPCInterface(with: PrivilegedUninstallXPCProtocol.self)

        try await withCheckedThrowingContinuation { continuation in
            let gate = UninstallReplyGate(continuation: continuation, connection: connection)
            connection.invalidationHandler = { [weak gate] in gate?.finish(throwing: connectionFailure) }
            connection.interruptionHandler = { [weak gate] in gate?.finish(throwing: connectionFailure) }
            connection.resume()

            guard let helper = connection.remoteObjectProxyWithErrorHandler({ error in
                let failure = error as NSError
                uninstallHelperLogger.error(
                    "Daemon XPC failed: \(failure.domain, privacy: .public) \(failure.code, privacy: .public)"
                )
                gate.finish(throwing: connectionFailure)
            }) as? PrivilegedUninstallXPCProtocol else {
                gate.finish(throwing: connectionFailure)
                return
            }

            let reply: (NSError?) -> Void = { error in
                guard let error, error.domain == PrivilegedUninstallConstants.errorDomain else {
                    gate.finish(throwing: error)
                    return
                }
                switch error.code {
                case PrivilegedUninstallConstants.unconfirmedMoveErrorCode:
                    gate.finish(throwing: connectionFailure)
                case PrivilegedUninstallConstants.trashAccessDeniedErrorCode:
                    gate.finish(throwing: PrivilegedUninstallClientError.trashAccessDenied)
                default:
                    gate.finish(throwing: error)
                }
            }
            do {
                try send(to: helper, reply: reply)
            } catch {
                gate.finish(throwing: error)
                return
            }

            // A lost reply to a move is indeterminate because the helper may
            // already have moved the bundle. Preflight never mutates it.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 15) {
                gate.finish(throwing: connectionFailure)
            }
        }
    }

    private func send(to helper: PrivilegedUninstallXPCProtocol, reply: @escaping (NSError?) -> Void) throws {
        switch self {
        case .checkTrashAccess:
            helper.checkTrashAccess(withReply: reply)
        case let .preflight(target, authorization):
            let request = try JSONEncoder().encode(target)
            let credentials = try authorization.externalForm()
            helper.preflightApplicationMove(request, authorization: credentials, withReply: reply)
        case let .move(_, target, authorization):
            let request = try JSONEncoder().encode(target)
            let credentials = try authorization.externalForm()
            helper.moveApplicationToTrash(request, authorization: credentials, withReply: reply)
        }
    }
}

private final class UninstallAuthorizationReference: @unchecked Sendable {
    private let reference: AuthorizationRef

    init(prompt: String) throws {
        var reference: AuthorizationRef?
        let creation = AuthorizationCreate(nil, nil, [], &reference)
        guard creation == errAuthorizationSuccess, let reference else {
            throw PrivilegedUninstallClientError.authorizationError(creation)
        }

        var grantedRights: UnsafeMutablePointer<AuthorizationRights>?
        defer {
            if let grantedRights { AuthorizationFreeItemSet(grantedRights) }
        }
        let status = PrivilegedUninstallConstants.authorizationRight.withCString { rightName in
            kAuthorizationEnvironmentPrompt.withCString { promptTag in
                prompt.withCString { promptBytes in
                    var right = AuthorizationItem(name: rightName, valueLength: 0, value: nil, flags: 0)
                    var promptItem = AuthorizationItem(
                        name: promptTag,
                        valueLength: prompt.utf8.count,
                        value: UnsafeMutableRawPointer(mutating: promptBytes),
                        flags: 0
                    )
                    return withUnsafeMutablePointer(to: &right) { rightPointer in
                        withUnsafeMutablePointer(to: &promptItem) { promptPointer in
                            var rights = AuthorizationRights(count: 1, items: rightPointer)
                            var environment = AuthorizationEnvironment(count: 1, items: promptPointer)
                            return AuthorizationCopyRights(
                                reference,
                                &rights,
                                &environment,
                                [.interactionAllowed, .extendRights, .preAuthorize],
                                &grantedRights
                            )
                        }
                    }
                }
            }
        }
        guard status == errAuthorizationSuccess else {
            AuthorizationFree(reference, .destroyRights)
            throw PrivilegedUninstallClientError.authorizationError(status)
        }

        // PreAuthorize may return success for a right marked as unavailable
        // until another prompt. Require a usable right before confirmation.
        guard let grantedRights,
              grantedRights.pointee.count == 1,
              let granted = grantedRights.pointee.items?.pointee,
              granted.flags & UInt32(kAuthorizationFlagCanNotPreAuthorize) == 0 else {
            AuthorizationFree(reference, .destroyRights)
            throw PrivilegedUninstallClientError.authorizationFailed(errAuthorizationDenied)
        }
        self.reference = reference
    }

    deinit {
        AuthorizationFree(reference, .destroyRights)
    }

    func externalForm() throws -> Data {
        var form = AuthorizationExternalForm()
        let status = AuthorizationMakeExternalForm(reference, &form)
        guard status == errAuthorizationSuccess else {
            throw PrivilegedUninstallClientError.authorizationError(status)
        }
        return withUnsafeBytes(of: &form) { Data($0) }
    }
}

private final class UninstallReplyGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, any Error>?
    private let connection: NSXPCConnection

    init(continuation: CheckedContinuation<Void, any Error>, connection: NSXPCConnection) {
        self.continuation = continuation
        self.connection = connection
    }

    func finish(throwing error: (any Error)?) {
        let pending = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        guard let pending else { return }
        connection.invalidate()
        if let error {
            pending.resume(throwing: error)
        } else {
            pending.resume()
        }
    }
}
