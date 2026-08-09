import Darwin
import Foundation
import IOKit

/// One decoded AppleSMC sample. Detailed sensor availability is deliberately
/// separate from `ProcessInfo.thermalState`, which remains useful when AppleSMC
/// cannot be opened.
struct SMCSensorSnapshot: Equatable, Sendable {
    var availability: CapabilityAvailability
    var sensors: [ThermalSensor]
    var fans: [FanState]
    var cpuTemperatureCelsius: Double?
    var gpuTemperatureCelsius: Double?
}

enum SMCReadError: Error, Equatable, LocalizedError, Sendable {
    case serviceUnavailable
    case permissionDenied
    case permissionDeniedAt(operation: String, code: Int32)
    case incompatibleABI(actualSize: Int)
    case invalidKey(String)
    case ioKitAt(operation: String, code: Int32)
    case firmware(UInt8)
    case invalidPayload(key: String)

    var errorDescription: String? {
        localizedDescription()
    }

    func localizedDescription(locale: Locale? = nil) -> String {
        switch self {
        case .serviceUnavailable:
            TraceHaloLocalization.string("smc.serviceUnavailable", defaultValue: "AppleSMC service was not found.", locale: locale)
        case .permissionDenied:
            TraceHaloLocalization.string("smc.permissionDenied", defaultValue: "The system denied the read-only AppleSMC connection.", locale: locale)
        case let .permissionDeniedAt(operation, code):
            TraceHaloLocalization.format(
                "smc.permissionDeniedAt",
                defaultValue: "The system denied the read-only AppleSMC operation (%@, 0x%@).",
                locale: locale,
                operation, String(UInt32(bitPattern: code), radix: 16)
            )
        case let .incompatibleABI(actualSize):
            TraceHaloLocalization.format(
                "smc.incompatibleABI",
                defaultValue: "The AppleSMC call structure has an incompatible size (%ld bytes).",
                locale: locale,
                actualSize
            )
        case let .invalidKey(key):
            TraceHaloLocalization.format("smc.invalidKey", defaultValue: "Invalid SMC key: %@.", locale: locale, key)
        case let .ioKitAt(operation, code):
            TraceHaloLocalization.format(
                "smc.ioKitFailed",
                defaultValue: "The AppleSMC IOKit call failed (%@, 0x%@).",
                locale: locale,
                operation, String(UInt32(bitPattern: code), radix: 16)
            )
        case let .firmware(code):
            TraceHaloLocalization.format(
                "smc.firmwareError",
                defaultValue: "AppleSMC firmware returned an error (0x%@).",
                locale: locale,
                String(code, radix: 16)
            )
        case let .invalidPayload(key):
            TraceHaloLocalization.format(
                "smc.invalidPayload",
                defaultValue: "AppleSMC returned data that could not be parsed: %@.",
                locale: locale,
                key
            )
        }
    }

    var isMissingKey: Bool {
        // AppleSMC result 0x84 means that the requested key does not exist.
        if case .firmware(0x84) = self { return true }
        return false
    }

    /// Source-compatible factory retained for pure-memory transports that used
    /// the previous generic name before operation-level diagnostics existed.
    static func ioKit(operation: String, code: Int32) -> Self {
        .ioKitAt(operation: operation, code: code)
    }

    static func ioKit(_ code: Int32) -> Self {
        .ioKitAt(operation: "IOKit", code: code)
    }
}

struct SMCRawValue: Equatable, Sendable {
    var key: String
    var dataType: String
    var bytes: [UInt8]
}

/// Numeric decoding for the data formats used by read-only temperature and fan
/// keys. SMC integers/fixed point are big-endian; `flt ` is native-endian and
/// therefore little-endian on every Mac supported by this package.
enum SMCValueDecoder {
    static func double(from value: SMCRawValue) -> Double? {
        switch value.dataType {
        case "flt ":
            guard value.bytes.count >= 4 else { return nil }
            let bits = UInt32(value.bytes[0])
                | (UInt32(value.bytes[1]) << 8)
                | (UInt32(value.bytes[2]) << 16)
                | (UInt32(value.bytes[3]) << 24)
            let decoded = Double(Float(bitPattern: bits))
            return decoded.isFinite ? decoded : nil
        case "fpe2":
            guard let raw = unsigned16(value.bytes) else { return nil }
            return Double(raw) / 4
        case "fp2e":
            guard let raw = unsigned16(value.bytes) else { return nil }
            return Double(raw) / 16_384
        case "sp1e": return signedFixed(value.bytes, fractionalBits: 14)
        case "sp3c": return signedFixed(value.bytes, fractionalBits: 12)
        case "sp4b": return signedFixed(value.bytes, fractionalBits: 11)
        case "sp5a": return signedFixed(value.bytes, fractionalBits: 10)
        case "sp69": return signedFixed(value.bytes, fractionalBits: 9)
        case "sp78": return signedFixed(value.bytes, fractionalBits: 8)
        case "sp87": return signedFixed(value.bytes, fractionalBits: 7)
        case "sp96": return signedFixed(value.bytes, fractionalBits: 6)
        case "spa5": return signedFixed(value.bytes, fractionalBits: 5)
        case "spb4": return signedFixed(value.bytes, fractionalBits: 4)
        case "spf0": return signedFixed(value.bytes, fractionalBits: 0)
        case "ui8 ":
            guard let first = value.bytes.first else { return nil }
            return Double(first)
        case "ui16":
            return unsigned16(value.bytes).map(Double.init)
        case "ui32":
            guard value.bytes.count >= 4 else { return nil }
            let raw = UInt32(value.bytes[0]) << 24
                | UInt32(value.bytes[1]) << 16
                | UInt32(value.bytes[2]) << 8
                | UInt32(value.bytes[3])
            return Double(raw)
        default:
            return nil
        }
    }

    private static func unsigned16(_ bytes: [UInt8]) -> UInt16? {
        guard bytes.count >= 2 else { return nil }
        return UInt16(bytes[0]) << 8 | UInt16(bytes[1])
    }

    private static func signedFixed(_ bytes: [UInt8], fractionalBits: Int) -> Double? {
        guard let unsigned = unsigned16(bytes) else { return nil }
        let signed = Int16(bitPattern: unsigned)
        return Double(signed) / Double(1 << fractionalBits)
    }
}

protocol SMCValueReading: Sendable {
    func readValue(for key: String) throws -> SMCRawValue
}

private enum SMCReadCommand: UInt8 {
    case kernelIndex = 2
    case readBytes = 5
    case readKeyInfo = 9
}

/// Swift layout matching the 80-byte AppleSMC user-client structure.
///
/// The otherwise surprising `padding` field is intentional. Swift reports
/// `KeyInfo.size == 9` while the C ABI advances by its 12-byte stride.
struct SMCKeyData {
    typealias Bytes32 = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct PLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var version = Version()
    var pLimitData = PLimitData()
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: Bytes32 = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}

/// A strictly read-only connection to AppleSMC. There is intentionally no
/// write command, write method, fan mode method, or privileged helper path.
private final class AppleSMCReadConnection: SMCValueReading, @unchecked Sendable {
    private let connection: io_connect_t
    private var keyInfoByCode: [UInt32: SMCKeyData.KeyInfo] = [:]

    init() throws {
        let ABIBytes = MemoryLayout<SMCKeyData>.stride
        guard ABIBytes == 80 else {
            throw SMCReadError.incompatibleABI(actualSize: ABIBytes)
        }

        var selectedConnection: io_connect_t?
        var lastError: SMCReadError?
        var deniedError: SMCReadError?
        var visitedServices = Set<UInt64>()

        // Class matching `AppleSMC` also returns AppleSMCKeysEndpoint on Apple
        // Silicon. Keep the explicit endpoint fallback, but de-duplicate the
        // registry object. `SMCEndpoint1` itself is only the RTBuddy provider;
        // opening it does not create an AppleSMC user client.
        let matches: [(label: String, matching: CFMutableDictionary)] = [
            ("class AppleSMC", IOServiceMatching("AppleSMC")),
            ("class AppleSMCKeysEndpoint", IOServiceMatching("AppleSMCKeysEndpoint"))
        ].compactMap { label, matching in
            matching.map { (label, $0) }
        }

        matchLoop: for match in matches {
            var iterator: io_iterator_t = 0
            let matchingResult = IOServiceGetMatchingServices(
                kIOMainPortDefault,
                match.matching,
                &iterator
            )
            guard matchingResult == kIOReturnSuccess else {
                let operation = "IOServiceGetMatchingServices \(match.label)"
                if Self.isPermissionError(matchingResult) {
                    deniedError = .permissionDeniedAt(operation: operation, code: matchingResult)
                } else {
                    lastError = .ioKitAt(operation: operation, code: matchingResult)
                }
                continue
            }

            var service = IOIteratorNext(iterator)
            while service != IO_OBJECT_NULL {
                var registryID: UInt64 = 0
                let registryResult = IORegistryEntryGetRegistryEntryID(service, &registryID)
                if registryResult == kIOReturnSuccess,
                   !visitedServices.insert(registryID).inserted {
                    IOObjectRelease(service)
                    service = IOIteratorNext(iterator)
                    continue
                }

                let serviceName = Self.registryName(service) ?? match.label
                var candidate: io_connect_t = 0
                let openResult = IOServiceOpen(service, mach_task_self_, 0, &candidate)
                IOObjectRelease(service)

                if openResult == kIOReturnSuccess {
                    selectedConnection = candidate
                    IOObjectRelease(iterator)
                    break matchLoop
                }
                let operation = "IOServiceOpen \(serviceName)"
                if Self.isPermissionError(openResult) {
                    deniedError = .permissionDeniedAt(operation: operation, code: openResult)
                } else {
                    lastError = .ioKitAt(operation: operation, code: openResult)
                }
                service = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }

        guard let selectedConnection else {
            // Do not let a later fallback failure hide a real permission result.
            if let deniedError { throw deniedError }
            if let lastError { throw lastError }
            throw SMCReadError.serviceUnavailable
        }
        connection = selectedConnection
    }

    deinit {
        IOServiceClose(connection)
    }

    func readValue(for key: String) throws -> SMCRawValue {
        let keyCode = try Self.fourCharacterCode(key)
        let keyInfo: SMCKeyData.KeyInfo
        if let cached = keyInfoByCode[keyCode] {
            keyInfo = cached
        } else {
            var keyInfoInput = SMCKeyData()
            keyInfoInput.key = keyCode
            keyInfoInput.data8 = SMCReadCommand.readKeyInfo.rawValue

            let keyInfoOutput = try call(&keyInfoInput)
            try Self.validateFirmwareResult(keyInfoOutput.result)
            keyInfo = keyInfoOutput.keyInfo
            keyInfoByCode[keyCode] = keyInfo
        }

        let dataSize = Int(keyInfo.dataSize)
        guard (1...32).contains(dataSize) else {
            throw SMCReadError.invalidPayload(key: key)
        }

        var valueInput = SMCKeyData()
        valueInput.key = keyCode
        valueInput.keyInfo.dataSize = keyInfo.dataSize
        valueInput.data8 = SMCReadCommand.readBytes.rawValue

        let valueOutput = try call(&valueInput)
        try Self.validateFirmwareResult(valueOutput.result)
        let bytes = withUnsafeBytes(of: valueOutput.bytes) { buffer in
            Array(buffer.prefix(dataSize))
        }

        return SMCRawValue(
            key: key,
            dataType: Self.fourCharacterString(keyInfo.dataType),
            bytes: bytes
        )
    }

    private func call(_ input: inout SMCKeyData) throws -> SMCKeyData {
        var output = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.stride
        let result = IOConnectCallStructMethod(
            connection,
            UInt32(SMCReadCommand.kernelIndex.rawValue),
            &input,
            MemoryLayout<SMCKeyData>.stride,
            &output,
            &outputSize
        )
        guard result == kIOReturnSuccess else {
            let operation = "IOConnectCallStructMethod selector \(SMCReadCommand.kernelIndex.rawValue)"
            if Self.isPermissionError(result) {
                throw SMCReadError.permissionDeniedAt(operation: operation, code: result)
            }
            throw SMCReadError.ioKitAt(operation: operation, code: result)
        }
        return output
    }

    private static func isPermissionError(_ result: kern_return_t) -> Bool {
        result == kIOReturnNotPrivileged || result == kIOReturnNotPermitted
    }

    private static func registryName(_ service: io_service_t) -> String? {
        var name = [CChar](repeating: 0, count: 128)
        guard IORegistryEntryGetName(service, &name) == kIOReturnSuccess else { return nil }
        return String(
            decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
            as: UTF8.self
        )
    }

    private static func validateFirmwareResult(_ result: UInt8) throws {
        guard result == 0 else { throw SMCReadError.firmware(result) }
    }

    private static func fourCharacterCode(_ string: String) throws -> UInt32 {
        let bytes = Array(string.utf8)
        guard bytes.count == 4 else { throw SMCReadError.invalidKey(string) }
        return bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func fourCharacterString(_ value: UInt32) -> String {
        String(bytes: [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ], encoding: .ascii) ?? "????"
    }
}

struct SMCTemperatureDefinition: Equatable, Sendable {
    var key: String
    var name: String
    var group: String
}

enum SMCTemperatureCatalog {
    static func definitions(forChipName chipName: String) -> [SMCTemperatureDefinition] {
        let lowercaseChip = chipName.lowercased()
        var definitions = commonDefinitions

        if lowercaseChip.contains("m5") {
            definitions.append(contentsOf: m5Definitions)
        } else if lowercaseChip.contains("m4") {
            definitions.append(contentsOf: m4Definitions)
        } else if lowercaseChip.contains("m3") {
            definitions.append(contentsOf: m3Definitions)
        } else if lowercaseChip.contains("m2") {
            definitions.append(contentsOf: m2Definitions)
            if isLargeAppleSiliconVariant(lowercaseChip) {
                definitions.append(contentsOf: proMaxDefinitions)
            }
        } else if lowercaseChip.contains("m1") {
            definitions.append(contentsOf: m1Definitions)
            if isLargeAppleSiliconVariant(lowercaseChip) {
                definitions.append(contentsOf: proMaxDefinitions)
            }
        } else {
            definitions.append(contentsOf: m1Definitions)
            definitions.append(contentsOf: m2Definitions)
            definitions.append(contentsOf: m3Definitions)
            definitions.append(contentsOf: m4Definitions)
            definitions.append(contentsOf: m5Definitions)
            definitions.append(contentsOf: proMaxDefinitions)
        }

        var seen = Set<String>()
        return definitions.filter { seen.insert($0.key).inserted }
    }

    private static func isLargeAppleSiliconVariant(_ chip: String) -> Bool {
        chip.contains(" pro") || chip.contains(" max") || chip.contains(" ultra")
    }

    private static func make(_ keys: [String], name: String, group: String) -> [SMCTemperatureDefinition] {
        keys.map { SMCTemperatureDefinition(key: $0, name: "\(name) · \($0)", group: group) }
    }

    private static let commonDefinitions: [SMCTemperatureDefinition] =
        make(["TCMz"], name: "CPU Die Hotspot", group: "CPU")
        + make(["TC0D", "TC0E", "TC0F", "TC0H", "TC0P", "TCAD"], name: "CPU Sensor", group: "CPU")
        + make(["TG0D", "TGDD", "TG0H", "TG0P"], name: "GPU Sensor", group: "GPU")
        + make(["Tm0P", "TW0P", "TL0P", "TTLD", "TTRD", "TH0x"], name: "System Sensor", group: "System")
        + make(["TB1T", "TB2T"], name: "Battery Sensor", group: "System")

    private static let m1Definitions: [SMCTemperatureDefinition] =
        make(["Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"], name: "CPU Zone", group: "CPU")
        + make(["Tg05", "Tg0D", "Tg0L", "Tg0T"], name: "GPU Zone", group: "GPU")
        + make(["Tm02", "Tm06", "Tm08", "Tm09"], name: "Memory Sensor", group: "Memory")

    private static let m2Definitions: [SMCTemperatureDefinition] =
        make(["Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"], name: "CPU Zone", group: "CPU")
        + make(["Tg0f", "Tg0j"], name: "GPU Zone", group: "GPU")

    private static let m3Definitions: [SMCTemperatureDefinition] =
        make(["Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"], name: "CPU Zone", group: "CPU")
        + make(["Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"], name: "GPU Zone", group: "GPU")

    private static let m4Definitions: [SMCTemperatureDefinition] =
        make(["Te05", "Te0S", "Te09", "Te0H", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"], name: "CPU Zone", group: "CPU")
        + make(["Tg0G", "Tg0H", "Tg1U", "Tg1k", "Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k"], name: "GPU Zone", group: "GPU")
        + make(["Tm0p", "Tm1p", "Tm2p"], name: "Memory Sensor", group: "Memory")

    private static let m5Definitions: [SMCTemperatureDefinition] =
        make(["Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K", "Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0d", "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y"], name: "CPU Zone", group: "CPU")
        + make(["Tg0U", "Tg0X", "Tg0d", "Tg0g", "Tg0j", "Tg1Y", "Tg1c", "Tg1g"], name: "GPU Zone", group: "GPU")

    private static let proMaxDefinitions: [SMCTemperatureDefinition] =
        make([
            "TC10", "TC11", "TC12", "TC13", "TC20", "TC21", "TC22", "TC23",
            "TC30", "TC31", "TC32", "TC33", "TC40", "TC41", "TC42", "TC43",
            "TC50", "TC51", "TC52", "TC53"
        ], name: "CPU Zone", group: "CPU")
        + make(["Tg04", "Tg05", "Tg0C", "Tg0D", "Tg0K", "Tg0L", "Tg0S", "Tg0T"], name: "GPU Zone", group: "GPU")
}

/// Background, cached AppleSMC sampler. The actor owns the connection and is the
/// only executor that calls into the private AppleSMC user client.
actor SMCSensorReader {
    typealias TransportFactory = @Sendable () throws -> any SMCValueReading

    private struct FanStaticMetadata: Sendable {
        var minimumRPM: Int?
        var maximumRPM: Int?
    }

    private let cacheInterval: TimeInterval
    private let failureCacheInterval: TimeInterval
    private let temperatureProbeRetryInterval: TimeInterval
    private let chipName: String
    private let transportFactory: TransportFactory

    private var transport: (any SMCValueReading)?
    private var cachedTemperatureDefinitions: [SMCTemperatureDefinition]?
    private var lastTemperatureProbeAt: Date?
    private var cachedFanCount: Int?
    private var cachedFanStaticMetadata: [Int: FanStaticMetadata] = [:]
    private var cachedSnapshot: SMCSensorSnapshot?
    private var cachedAt: Date?

    init(
        cacheInterval: TimeInterval = 5,
        failureCacheInterval: TimeInterval = 30,
        temperatureProbeRetryInterval: TimeInterval = 60,
        chipName: String = SMCSensorReader.readChipName(),
        transportFactory: @escaping TransportFactory = { try AppleSMCReadConnection() }
    ) {
        self.cacheInterval = max(cacheInterval, 0)
        self.failureCacheInterval = max(failureCacheInterval, 0)
        self.temperatureProbeRetryInterval = max(temperatureProbeRetryInterval, 0)
        self.chipName = chipName
        self.transportFactory = transportFactory
    }

    func snapshot() -> SMCSensorSnapshot {
        let now = Date()
        if let cachedSnapshot, let cachedAt {
            let interval = cachedSnapshot.availability.isAvailable ? cacheInterval : failureCacheInterval
            if now.timeIntervalSince(cachedAt) < interval {
                return cachedSnapshot
            }
        }

        do {
            let activeTransport: any SMCValueReading
            if let transport {
                activeTransport = transport
            } else {
                activeTransport = try transportFactory()
                transport = activeTransport
            }

            let result = readSnapshot(using: activeTransport, at: now)
            let sampled = result.snapshot
            cachedSnapshot = sampled
            cachedAt = now
            if result.shouldResetTransport || !sampled.availability.isAvailable {
                transport = nil
                cachedFanCount = nil
                cachedFanStaticMetadata.removeAll(keepingCapacity: true)
            }
            return sampled
        } catch {
            transport = nil
            cachedFanCount = nil
            cachedFanStaticMetadata.removeAll(keepingCapacity: true)
            let sampled = Self.failureSnapshot(for: error)
            cachedSnapshot = sampled
            cachedAt = now
            return sampled
        }
    }

    private func readSnapshot(
        using transport: any SMCValueReading,
        at now: Date
    ) -> (snapshot: SMCSensorSnapshot, shouldResetTransport: Bool) {
        var firstUnexpectedError: Error?
        let definitions: [SMCTemperatureDefinition]
        let isProbe: Bool

        if let cachedTemperatureDefinitions, !cachedTemperatureDefinitions.isEmpty {
            definitions = cachedTemperatureDefinitions
            isProbe = false
        } else if let lastTemperatureProbeAt,
                  now.timeIntervalSince(lastTemperatureProbeAt) < temperatureProbeRetryInterval {
            definitions = []
            isProbe = false
        } else {
            definitions = SMCTemperatureCatalog.definitions(forChipName: chipName)
            isProbe = true
        }

        var sensors: [ThermalSensor] = []
        var validDefinitions: [SMCTemperatureDefinition] = []
        for definition in definitions {
            do {
                let rawValue = try transport.readValue(for: definition.key)
                guard rawValue.bytes.contains(where: { $0 != 0 }),
                      let temperature = SMCValueDecoder.double(from: rawValue),
                      temperature.isFinite,
                      (-20...130).contains(temperature) else {
                    continue
                }
                sensors.append(ThermalSensor(
                    key: definition.key,
                    name: definition.name,
                    group: definition.group,
                    temperatureCelsius: temperature
                ))
                validDefinitions.append(definition)
            } catch let error as SMCReadError where error.isMissingKey {
                continue
            } catch {
                firstUnexpectedError = firstUnexpectedError ?? error
            }
        }

        if isProbe {
            cachedTemperatureDefinitions = validDefinitions
            lastTemperatureProbeAt = now
        } else if !definitions.isEmpty, sensors.isEmpty {
            // A stale connection after sleep/wake should trigger a fresh probe
            // after the failure cache expires, rather than emitting zeroes.
            cachedTemperatureDefinitions = nil
        }

        let fanResult = readFans(using: transport)
        firstUnexpectedError = firstUnexpectedError ?? fanResult.error

        let availability: CapabilityAvailability
        if !sensors.isEmpty || !fanResult.fans.isEmpty {
            availability = .available
        } else if let firstUnexpectedError {
            availability = .failed(reason: firstUnexpectedError.localizedDescription)
        } else {
            availability = .unavailable(
                reason: TraceHaloLocalization.string(
                    "smc.noRecognizedSensors",
                    defaultValue: "AppleSMC is accessible, but this Mac did not return recognizable temperature or fan data."
                )
            )
        }

        return (
            snapshot: SMCSensorSnapshot(
                availability: availability,
                sensors: sensors,
                fans: fanResult.fans,
                cpuTemperatureCelsius: Self.averageTemperature(in: sensors, group: "CPU"),
                gpuTemperatureCelsius: Self.averageTemperature(in: sensors, group: "GPU")
            ),
            shouldResetTransport: firstUnexpectedError != nil
                && sensors.isEmpty
                && fanResult.fans.isEmpty
        )
    }

    private func readFans(using transport: any SMCValueReading) -> (fans: [FanState], error: Error?) {
        let fanCount: Int
        do {
            if let cachedFanCount {
                fanCount = cachedFanCount
            } else {
                let rawCount = try transport.readValue(for: "FNum")
                guard let decoded = SMCValueDecoder.double(from: rawCount),
                      decoded.isFinite,
                      (0...8).contains(decoded) else {
                    throw SMCReadError.invalidPayload(key: "FNum")
                }
                fanCount = Int(decoded.rounded(.towardZero))
                cachedFanCount = fanCount
            }
        } catch let error as SMCReadError where error.isMissingKey {
            cachedFanCount = 0
            return ([], nil)
        } catch {
            return ([], error)
        }

        var fans: [FanState] = []
        var firstError: Error?
        for index in 0..<fanCount {
            do {
                let actual = try readFanValue("F\(index)Ac", using: transport)
                let staticMetadata: FanStaticMetadata
                if let cached = cachedFanStaticMetadata[index] {
                    staticMetadata = cached
                } else {
                    let sampled = FanStaticMetadata(
                        minimumRPM: try? optionalFanValue("F\(index)Mn", using: transport),
                        maximumRPM: try? optionalFanValue("F\(index)Mx", using: transport)
                    )
                    cachedFanStaticMetadata[index] = sampled
                    staticMetadata = sampled
                }
                fans.append(FanState(
                    name: "Fan \(index + 1)",
                    currentRPM: Int(actual.rounded()),
                    minimumRPM: staticMetadata.minimumRPM,
                    maximumRPM: staticMetadata.maximumRPM,
                    targetRPM: try? optionalFanValue("F\(index)Tg", using: transport)
                ))
            } catch {
                // A failed actual-speed read does not become a fabricated 0 RPM.
                firstError = firstError ?? error
            }
        }
        return (fans, firstError)
    }

    private func readFanValue(_ key: String, using transport: any SMCValueReading) throws -> Double {
        let rawValue = try transport.readValue(for: key)
        guard let value = SMCValueDecoder.double(from: rawValue),
              value.isFinite,
              (0...30_000).contains(value) else {
            throw SMCReadError.invalidPayload(key: key)
        }
        return value
    }

    private func optionalFanValue(_ key: String, using transport: any SMCValueReading) throws -> Int {
        Int(try readFanValue(key, using: transport).rounded())
    }

    private static func averageTemperature(in sensors: [ThermalSensor], group: String) -> Double? {
        let values = sensors.lazy.filter { $0.group == group }.map(\.temperatureCelsius)
        let result = values.reduce(into: (sum: 0.0, count: 0)) { partial, value in
            partial.sum += value
            partial.count += 1
        }
        guard result.count > 0 else { return nil }
        return result.sum / Double(result.count)
    }

    private static func failureSnapshot(for error: Error) -> SMCSensorSnapshot {
        let availability: CapabilityAvailability
        switch error {
        case SMCReadError.serviceUnavailable:
            availability = .unavailable(reason: error.localizedDescription)
        case SMCReadError.permissionDenied,
             SMCReadError.permissionDeniedAt:
            availability = .permissionRequired(reason: error.localizedDescription)
        default:
            availability = .failed(reason: error.localizedDescription)
        }
        return SMCSensorSnapshot(
            availability: availability,
            sensors: [],
            fans: [],
            cpuTemperatureCelsius: nil,
            gpuTemperatureCelsius: nil
        )
    }

    private static func readChipName() -> String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 1 else {
            return "Unknown Apple Silicon"
        }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0) == 0 else {
            return "Unknown Apple Silicon"
        }
        return bytes.withUnsafeBytes { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
