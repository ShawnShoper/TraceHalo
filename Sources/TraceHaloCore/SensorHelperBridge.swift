import Foundation

/// Stable product identifiers shared by the app and helper.
public enum TraceHaloBundleIdentifiers {
    public static let application = "com.tseai.tracehalo"
    public static let sensorHelper = "com.tseai.tracehalo.sensor-helper"
}

/// Stable identifiers shared by the UI process and the optional read-only
/// LaunchDaemon. The helper exposes one fixed operation and never accepts SMC
/// keys, write values, fan targets, or filesystem paths from a client.
public enum SensorHelperConstants {
    public static let machServiceName = TraceHaloBundleIdentifiers.sensorHelper
    public static let launchDaemonPlistName = "com.tseai.tracehalo.sensor-helper.plist"
}

@objc public protocol SensorHelperXPCProtocol {
    func fetchReadOnlySnapshot(withReply reply: @escaping (Data) -> Void)
}

public struct SensorHelperTemperature: Codable, Equatable, Sendable {
    public var key: String
    public var name: String
    public var group: String
    public var temperatureCelsius: Double

    public init(key: String, name: String, group: String, temperatureCelsius: Double) {
        self.key = key
        self.name = name
        self.group = group
        self.temperatureCelsius = temperatureCelsius
    }
}

public struct SensorHelperFan: Codable, Equatable, Sendable {
    public var name: String
    public var currentRPM: Int
    public var minimumRPM: Int?
    public var maximumRPM: Int?
    public var targetRPM: Int?

    public init(
        name: String,
        currentRPM: Int,
        minimumRPM: Int? = nil,
        maximumRPM: Int? = nil,
        targetRPM: Int? = nil
    ) {
        self.name = name
        self.currentRPM = currentRPM
        self.minimumRPM = minimumRPM
        self.maximumRPM = maximumRPM
        self.targetRPM = targetRPM
    }
}

/// Stable cross-process error semantics. The helper must not send localized UI
/// text because its defaults domain can differ from the foreground app's
/// manually selected language.
public enum SensorHelperErrorCode: String, Codable, Equatable, Sendable {
    case unavailable
    case permissionRequired
    case readFailed
    case encodingFailed
}

/// Codable XPC payload kept deliberately small. A failed read is represented
/// explicitly and never converted into fabricated zero measurements.
public struct SensorHelperPayload: Codable, Equatable, Sendable {
    public var capturedAt: Date
    public var temperatures: [SensorHelperTemperature]
    public var fans: [SensorHelperFan]
    public var cpuTemperatureCelsius: Double?
    public var gpuTemperatureCelsius: Double?
    public var errorCode: SensorHelperErrorCode?
    public var errorMessage: String?
    public var permissionRequired: Bool

    public init(
        capturedAt: Date = Date(),
        temperatures: [SensorHelperTemperature],
        fans: [SensorHelperFan],
        cpuTemperatureCelsius: Double?,
        gpuTemperatureCelsius: Double?,
        errorCode: SensorHelperErrorCode? = nil,
        errorMessage: String? = nil,
        permissionRequired: Bool = false
    ) {
        self.capturedAt = capturedAt
        self.temperatures = temperatures
        self.fans = fans
        self.cpuTemperatureCelsius = cpuTemperatureCelsius
        self.gpuTemperatureCelsius = gpuTemperatureCelsius
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.permissionRequired = permissionRequired
    }

    public var hasMeasurements: Bool {
        !temperatures.isEmpty || !fans.isEmpty
    }
}

/// The only hardware surface exported to the privileged helper target. It
/// delegates to the same cached, read-only reader used by the app process.
public actor ReadOnlyHardwareSensorSampler {
    private let reader = SMCSensorReader()

    public init() {}

    public func sample() async -> SensorHelperPayload {
        let snapshot = await reader.snapshot()
        let errorCode: SensorHelperErrorCode?
        switch snapshot.availability {
        case .available:
            errorCode = nil
        case .unavailable:
            errorCode = .unavailable
        case .permissionRequired:
            errorCode = .permissionRequired
        case .failed:
            errorCode = .readFailed
        }

        return SensorHelperPayload(
            temperatures: snapshot.sensors.map {
                SensorHelperTemperature(
                    key: $0.key,
                    name: $0.name,
                    group: $0.group,
                    temperatureCelsius: $0.temperatureCelsius
                )
            },
            fans: snapshot.fans.map {
                SensorHelperFan(
                    name: $0.name,
                    currentRPM: $0.currentRPM,
                    minimumRPM: $0.minimumRPM,
                    maximumRPM: $0.maximumRPM,
                    targetRPM: $0.targetRPM
                )
            },
            cpuTemperatureCelsius: snapshot.cpuTemperatureCelsius,
            gpuTemperatureCelsius: snapshot.gpuTemperatureCelsius,
            errorCode: errorCode,
            errorMessage: snapshot.availability.message,
            permissionRequired: errorCode == .permissionRequired
        )
    }
}
