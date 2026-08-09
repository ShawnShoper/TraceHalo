import Foundation
import ServiceManagement
import SwiftUI
import TraceHaloCore

enum SensorHelperErrorPresentation {
    static func reason(
        code: SensorHelperErrorCode?,
        legacyMessage: String?,
        locale: Locale
    ) -> String? {
        guard let code else {
            return legacyMessage.map {
                AppLocalization.string($0, defaultValue: $0, locale: locale)
            }
        }
        let key: String
        let fallback: String
        switch code {
        case .unavailable:
            key = "sensor.helper.error.unavailable"
            fallback = "No readable temperature or fan sensors were found."
        case .permissionRequired:
            key = "sensor.helper.error.permissionRequired"
            fallback = "macOS blocked read-only access to temperature and fan sensors."
        case .readFailed:
            key = "sensor.helper.error.readFailed"
            fallback = "The read-only sensor service could not collect sensor data."
        case .encodingFailed:
            key = "sensor.helper.error.encodingFailed"
            fallback = "The read-only sensor service could not encode its result."
        }
        return AppLocalization.string(key, defaultValue: fallback, locale: locale)
    }
}

protocol SupplementalSensorProviding: Sendable {
    func snapshot() async -> SensorHelperPayload?
}

struct NoSupplementalSensorProvider: SupplementalSensorProviding {
    func snapshot() async -> SensorHelperPayload? { nil }
}

enum SensorHelperRegistrationState: Equatable {
    case notRegistered
    case awaitingApproval
    case enabled
    case unavailable

    var buttonTitle: String {
        AppLocalization.currentString(rawButtonTitle)
    }

    func buttonTitle(locale: Locale) -> String {
        AppLocalization.string(
            rawButtonTitle,
            defaultValue: rawButtonTitle,
            locale: locale
        )
    }

    private var rawButtonTitle: String {
        switch self {
        case .notRegistered: "启用只读传感器"
        case .awaitingApproval: "前往系统设置批准"
        case .enabled: "重新读取"
        case .unavailable: "查看传感器权限"
        }
    }
}

@MainActor
enum SensorHelperRegistration {
    static var state: SensorHelperRegistrationState {
        switch service.status {
        case .notRegistered: .notRegistered
        case .requiresApproval: .awaitingApproval
        case .enabled: .enabled
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    static var isEnabled: Bool { state == .enabled }

    @discardableResult
    static func requestAccess() throws -> SensorHelperRegistrationState {
        let helper = service
        if helper.status == .notRegistered {
            try helper.register()
        }

        let current = state
        if current == .awaitingApproval || current == .unavailable {
            SMAppService.openSystemSettingsLoginItems()
        }
        return current
    }

    static func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static var service: SMAppService {
        .daemon(plistName: SensorHelperConstants.launchDaemonPlistName)
    }
}

private final class SensorReplyGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<SensorHelperPayload?, Never>?
    private let connection: NSXPCConnection

    init(
        continuation: CheckedContinuation<SensorHelperPayload?, Never>,
        connection: NSXPCConnection
    ) {
        self.continuation = continuation
        self.connection = connection
    }

    func finish(_ value: SensorHelperPayload?) {
        let pending: CheckedContinuation<SensorHelperPayload?, Never>? = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        guard let pending else { return }
        connection.invalidate()
        pending.resume(returning: value)
    }
}

/// Short-lived XPC client. Successful payloads are reused briefly so the app's
/// fast telemetry loop does not recreate an XPC connection for unchanged
/// temperature and fan data. A strict timeout still prevents a disabled or
/// restarting daemon from delaying refreshes.
actor SensorHelperClient: SupplementalSensorProviding {
    private let clock = ContinuousClock()
    private let successCacheDuration: Duration = .seconds(5)
    private var retryAfterFailure: ContinuousClock.Instant?
    private var cachedPayload: SensorHelperPayload?
    private var cachedAt: ContinuousClock.Instant?

    func snapshot() async -> SensorHelperPayload? {
        let now = clock.now
        if let cachedPayload,
           let cachedAt,
           now < cachedAt.advanced(by: successCacheDuration) {
            return cachedPayload
        }

        if let retryAfterFailure, clock.now < retryAfterFailure {
            return nil
        }

        let enabled = await MainActor.run { SensorHelperRegistration.isEnabled }
        guard enabled else {
            retryAfterFailure = nil
            cachedPayload = nil
            cachedAt = nil
            return nil
        }

        let connection = NSXPCConnection(machServiceName: SensorHelperConstants.machServiceName)
        connection.remoteObjectInterface = NSXPCInterface(with: SensorHelperXPCProtocol.self)
        connection.resume()

        let payload = await withCheckedContinuation { continuation in
            let gate = SensorReplyGate(continuation: continuation, connection: connection)
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                gate.finish(nil)
            } as? SensorHelperXPCProtocol

            guard let proxy else {
                gate.finish(nil)
                return
            }

            proxy.fetchReadOnlySnapshot { data in
                let payload = try? JSONDecoder().decode(SensorHelperPayload.self, from: data)
                gate.finish(payload)
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.8) {
                gate.finish(nil)
            }
        }

        if let payload {
            cachedPayload = payload
            cachedAt = clock.now
            retryAfterFailure = nil
        } else {
            cachedPayload = nil
            cachedAt = nil
            retryAfterFailure = clock.now.advanced(by: .seconds(5))
        }
        return payload
    }
}

struct SensorAccessActionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.locale) private var locale
    var compact = false

    @State private var registrationState = SensorHelperRegistration.state
    @State private var errorDetail: String?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 8) {
            Button {
                requestAccess()
            } label: {
                HStack(spacing: 6) {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "lock.open")
                    }
                    Text(registrationState.buttonTitle(locale: locale))
                }
                .font(.system(size: compact ? 9 : 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(compact ? .mini : .regular)
            .disabled(isWorking)

            if !compact {
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(CalmTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            registrationState = SensorHelperRegistration.state
        }
    }

    private var guidance: String {
        localized(rawGuidance)
    }

    private var detailText: String {
        guard let errorDetail else { return guidance }
        return AppLocalization.format(
            "sensor.helper.enable.error",
            defaultValue: "无法启用只读传感器服务：%@",
            locale: locale,
            errorDetail
        )
    }

    private var rawGuidance: String {
        switch registrationState {
        case .notRegistered:
            "macOS 已阻止普通应用进程读取 AppleSMC。启用后只读取温度和风扇转速，不提供风扇控制。"
        case .awaitingApproval:
            "请在“系统设置 → 通用 → 登录项与扩展”中批准 TraceHalo 后台项目。"
        case .enabled:
            "只读传感器服务已获批准；若数据尚未出现，可重新读取。"
        case .unavailable:
            "当前构建未被系统识别，请确认应用位于固定位置后再批准后台项目。"
        }
    }

    private func requestAccess() {
        isWorking = true
        errorDetail = nil
        Task { @MainActor in
            do {
                if registrationState == .awaitingApproval || registrationState == .unavailable {
                    SensorHelperRegistration.openApprovalSettings()
                } else {
                    registrationState = try SensorHelperRegistration.requestAccess()
                }
                registrationState = SensorHelperRegistration.state
                if registrationState == .enabled {
                    await model.refreshAll()
                }
            } catch {
                registrationState = SensorHelperRegistration.state
                errorDetail = error.localizedDescription
                if registrationState == .awaitingApproval {
                    SensorHelperRegistration.openApprovalSettings()
                }
            }
            isWorking = false
        }
    }

    private func localized(_ value: String) -> String {
        AppLocalization.string(value, defaultValue: value, locale: locale)
    }
}
