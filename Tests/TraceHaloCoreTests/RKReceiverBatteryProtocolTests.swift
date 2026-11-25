import XCTest
@testable import TraceHaloCore

final class RKReceiverBatteryProtocolTests: XCTestCase {
    // All response fixtures below are constructed from the reviewed format.
    // They are not captures from the user's keyboard or hardware acceptance.

    func testBuildsOnlyReviewedFixedReadCommands() throws {
        for (command, checksum): (UInt8, UInt8) in [(0x05, 0x19), (0x07, 0x1B), (0x4A, 0x5E)] {
            let frame = try XCTUnwrap(RKReceiverBatteryProtocol.request(command))
            XCTAssertEqual(frame.count, 20)
            XCTAssertEqual(Array(frame.prefix(5)), [0x13, command, 1, 0, 0])
            XCTAssertEqual(Array(frame[5..<19]), [UInt8](repeating: 0, count: 14))
            XCTAssertEqual(frame[19], checksum)
        }
        for command: UInt8 in [0x00, 0x01, 0x04, 0x06, 0x09, 0x12, 0x87, 0xFF] {
            XCTAssertNil(RKReceiverBatteryProtocol.request(command))
        }
    }

    func testIdentityUsesExactSixByteCodeAndAllowsDeclaredTrailingFields() throws {
        let data: [UInt8] = [0x03, 0, 0, 0, 0x01, 0x56, 0, 0, 0, 0]
        let payload = try XCTUnwrap(parse(frame(command: 0x05, payload: data), command: 0x05, minimum: 6))
        XCTAssertEqual(payload, data)
        XCTAssertTrue(RKReceiverBatteryProtocol.isR87Pro(payload))
        XCTAssertFalse(RKReceiverBatteryProtocol.isR87Pro([0x03, 0, 0, 0, 0x01, 0x15]))
        XCTAssertFalse(RKReceiverBatteryProtocol.isR87Pro([0, 0x03, 0, 0, 0, 0x01, 0x56]))
        XCTAssertFalse(RKReceiverBatteryProtocol.isR87Pro([0x03, 0, 0, 0, 0x01]))
    }

    func testOfflineReplyIsDifferentFromNoReply() throws {
        XCTAssertEqual(try XCTUnwrap(parse(frame(command: 0x07, payload: [0]), command: 0x07, minimum: 1)), [0])
        XCTAssertEqual(try XCTUnwrap(parse(frame(command: 0x07, payload: [1]), command: 0x07, minimum: 1)), [1])
        XCTAssertNil(parse([], command: 0x07, minimum: 1))
        XCTAssertNil(parse([UInt8](repeating: 0, count: 20), command: 0x07, minimum: 1))
    }

    func testRejectsWrongReportIDAndCommand() {
        var response = frame(command: 0x4A, payload: [53, 0])
        response[0] = 0x06
        XCTAssertNil(parse(response))
        response = frame(command: 0x07, payload: [1, 0])
        XCTAssertNil(parse(response))
        response = frame(command: 0xCA, payload: [53, 0])
        XCTAssertNil(parse(response))
        XCTAssertNil(parse(frame(command: 0x06, payload: [53, 0]), command: 0x06))
    }

    func testRejectsMultipartOutOfOrderAndErrorEnvelopes() {
        for (total, index): (UInt8, UInt8) in [(0, 0), (2, 0), (1, 1), (0x81, 0)] {
            var response = frame(command: 0x4A, payload: [53, 0])
            response[2] = total
            response[3] = index
            XCTAssertNil(parse(response))
        }
    }

    func testRejectsEchoesForEveryReadCommand() throws {
        for command: UInt8 in [0x05, 0x07, 0x4A] {
            let request = try XCTUnwrap(RKReceiverBatteryProtocol.request(command))
            XCTAssertNil(parse(request, command: command, minimum: 1))
            var unchecksummedEcho = request
            unchecksummedEcho[19] = 0
            XCTAssertNil(parse(unchecksummedEcho, command: command, minimum: 1))
        }
    }

    func testRejectsTruncatedAndOversizedReports() {
        let response = frame(command: 0x4A, payload: [53, 0])
        for length in 0..<20 { XCTAssertNil(parse(Array(response.prefix(length)))) }
        XCTAssertNil(parse(response + [0]))
    }

    func testRejectsMissingShortAndImpossibleDeclaredPayloadLengths() {
        let response = frame(command: 0x4A, payload: [53, 0])
        for declared: UInt8 in [0, 1, 15] {
            var changed = response
            changed[4] = declared
            XCTAssertNil(parse(changed))
        }
        XCTAssertNil(parse(response, minimum: 0))
        XCTAssertNil(parse(response, minimum: 15))
    }

    func testUsesDeclaredLengthAndOfficialLowNibbleWithoutInventingReplyChecksum() {
        var response = frame(command: 0x4A, payload: [53, 0, 99])
        response[4] = 0xA2
        response[19] = 0xD7
        XCTAssertEqual(parse(response), [53, 0])
    }

    func testZeroFilledRequestShapeCannotBecomeZeroBattery() {
        var placeholder = [UInt8](repeating: 0, count: 20)
        placeholder[0] = 0x13
        placeholder[1] = 0x4A
        placeholder[2] = 1
        XCTAssertNil(parse(placeholder))
    }

    func testConstructedDischargingAndChargingResponses() throws {
        for (status, charging): (UInt8, InputDeviceChargingState) in [(0x00, .notCharging), (0x01, .notCharging), (0x10, .charging)] {
            let payload = try XCTUnwrap(parse(frame(command: 0x4A, payload: [53, status])))
            XCTAssertEqual(RKReceiverBatteryProtocol.reading(payload), .reading(level: 53, charging: charging))
        }
    }

    func testChargingAtHundredFollowsRKIconRuleRatherThanMHubRule() {
        XCTAssertEqual(RKReceiverBatteryProtocol.reading([100, 0x10]), .reading(level: 100, charging: .charging))
        XCTAssertEqual(RKReceiverBatteryProtocol.reading([100, 0x11]), .reading(level: 100, charging: .charging))
        XCTAssertEqual(RKReceiverBatteryProtocol.reading([100, 0x01]), .reading(level: 100, charging: .notCharging))
    }

    func testConflictingFullOverlayDoesNotOverwriteReportedLevel() {
        XCTAssertEqual(RKReceiverBatteryProtocol.reading([53, 0x11]), .reading(level: 53, charging: .unknown))
    }

    func testUnknownStatusKeepsValidLevelAndUnknownCharging() {
        for status: UInt8 in [0x02, 0x12, 0x20, 0x80, 0xFF] {
            XCTAssertEqual(RKReceiverBatteryProtocol.reading([53, status]), .reading(level: 53, charging: .unknown))
        }
    }

    func testLegitimateOnlineZeroIsAcceptedWithoutConvertingSilenceToZero() throws {
        let payload = try XCTUnwrap(parse(frame(command: 0x4A, payload: [0, 0])))
        XCTAssertEqual(RKReceiverBatteryProtocol.reading(payload), .reading(level: 0, charging: .notCharging))
        XCTAssertNil(RKReceiverBatteryProtocol.reading([]))
        XCTAssertNil(RKReceiverBatteryProtocol.reading([0]))
    }

    func testOutOfRangeLevelIsRejectedIndependentlyOfStatus() {
        for level: UInt8 in [101, 200, 255] {
            for status: UInt8 in [0x00, 0x10, 0xFF] {
                XCTAssertNil(RKReceiverBatteryProtocol.reading([level, status]))
            }
        }
    }

    private func frame(command: UInt8, payload: [UInt8]) -> [UInt8] {
        precondition((1...14).contains(payload.count))
        var frame = [UInt8](repeating: 0, count: 20)
        frame[0] = 0x13
        frame[1] = command
        frame[2] = 1
        frame[4] = UInt8(payload.count)
        frame.replaceSubrange(5..<(5 + payload.count), with: payload)
        return frame
    }

    private func parse(_ frame: [UInt8], command: UInt8 = 0x4A, minimum: Int = 2) -> [UInt8]? {
        RKReceiverBatteryProtocol.payload(frame, command: command, minimumLength: minimum)
    }
}
