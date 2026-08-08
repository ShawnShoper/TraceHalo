import XCTest
@testable import SystemScopeApp

final class InputDevicePrivacyTests: XCTestCase {
    func testShortSerialNumbersAreCompletelyHidden() {
        XCTAssertEqual(InputDevicePrivacyFormatter.maskedSerialNumber("A"), "••••")
        XCTAssertEqual(InputDevicePrivacyFormatter.maskedSerialNumber("ABCD"), "••••")
        XCTAssertEqual(InputDevicePrivacyFormatter.maskedSerialNumber("  ABC  "), "••••")
    }

    func testLongSerialNumbersRevealOnlyTheLastFourCharacters() {
        XCTAssertEqual(
            InputDevicePrivacyFormatter.maskedSerialNumber("SERIAL-1234"),
            "•••• 1234"
        )
    }
}
