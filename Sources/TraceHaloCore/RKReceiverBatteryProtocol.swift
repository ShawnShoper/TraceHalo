/// The result of an explicitly requested RK receiver battery read.
/// Missing reports and permission failures never become a zero-percent reading.
public enum RKReceiverBatteryResult: Equatable, Sendable {
    case permissionRequired
    case unavailable
    case otherKeyboard
    case offline
    case noBatteryReport
    case reading(level: Int, charging: InputDeviceChargingState)
}

/// The old BY receiver protocol used by RK R87PRO (3554:FA09).
///
/// Protocol facts were checked against RK's Windows driver V4.6: GetPower at
/// 0x40E600 uses command 4A, the framing/parser at 0x40E200 uses report 13 and
/// the low nibble of byte 4 as payload length. No reply checksum was established.
/// These are format definitions, not a claim that every receiver returns power.
enum RKReceiverBatteryProtocol {
    private static let reportID: UInt8 = 0x13
    private static let r87ProIdentity: [UInt8] = [0x03, 0x00, 0x00, 0x00, 0x01, 0x56]

    /// Only these three read commands may leave the application through this API.
    static func request(_ command: UInt8) -> [UInt8]? {
        guard command == 0x05 || command == 0x07 || command == 0x4A else { return nil }
        var frame = [UInt8](repeating: 0, count: 20)
        frame[0] = reportID
        frame[1] = command
        frame[2] = 1
        frame[19] = frame.prefix(19).reduce(UInt8(0), &+)
        return frame
    }

    /// Extracts one complete, non-echo response without interpreting its data.
    /// A missing/zero declared length is not a reported zero battery level.
    static func payload(_ frame: [UInt8], command: UInt8, minimumLength: Int) -> [UInt8]? {
        guard let request = request(command),
              (1...14).contains(minimumLength),
              frame.count == 20,
              frame[0] == reportID,
              frame[1] == command,
              frame[2] == 1,
              frame[3] == 0,
              frame != request else { return nil }

        let length = Int(frame[4] & 0x0F)
        guard (minimumLength...14).contains(length) else { return nil }
        return Array(frame[5..<(5 + length)])
    }

    /// The identity response can contain trailing fields after the six-byte code.
    static func isR87Pro(_ payload: [UInt8]) -> Bool {
        payload.count >= r87ProIdentity.count && payload.prefix(r87ProIdentity.count).elementsEqual(r87ProIdentity)
    }

    /// The caller must first confirm the exact identity and an online 07 reply.
    /// A valid online report can contain 0%; silence or malformed data cannot.
    static func reading(_ payload: [UInt8]) -> RKReceiverBatteryResult? {
        guard payload.count >= 2, payload[0] <= 100 else { return nil }
        let level = Int(payload[0])
        let charging: InputDeviceChargingState
        // RK's drawing code (0x45B2C0) selects power_charging.png when the
        // high nibble is 10; unlike M HUB, it has no level<100 condition.
        // Its low-nibble 1 overlay says "100%". Preserve the reported level,
        // and leave contradictory/undefined status combinations unknown.
        switch payload[1] {
        case 0x00, 0x01:
            charging = .notCharging
        case 0x10:
            charging = .charging
        case 0x11 where level == 100:
            charging = .charging
        default:
            charging = .unknown
        }
        return .reading(level: level, charging: charging)
    }
}
