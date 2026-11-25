import AppKit
import TraceHaloCore
import SwiftUI
import XCTest
@testable import TraceHaloApp

final class InputDevicesRenderingTests: XCTestCase {
    func testReceiverQueryIsLimitedToExternalUSBKeyboardWithKnownLocation() {
        var receiver = InputDeviceState(
            stableIdentifier: "fixture",
            name: "2.4G Wireless Receiver",
            kinds: [.keyboard, .mouse],
            transport: "USB",
            vendorID: 0x3554,
            productID: 0xFA09,
            locationID: 17
        )
        XCTAssertEqual(InputDeviceBatteryPresentation.receiverLocation(for: receiver), 17)
        receiver.kinds = [.mouse]
        XCTAssertNil(InputDeviceBatteryPresentation.receiverLocation(for: receiver))
        receiver.kinds = [.keyboard]
        receiver.transport = "Bluetooth"
        XCTAssertNil(InputDeviceBatteryPresentation.receiverLocation(for: receiver))
        receiver.transport = "USB"
        receiver.productID = 0x019F
        XCTAssertNil(InputDeviceBatteryPresentation.receiverLocation(for: receiver))
        receiver.productID = 0xFA09
        receiver.locationID = nil
        XCTAssertNil(InputDeviceBatteryPresentation.receiverLocation(for: receiver))
        receiver.locationID = 17
        receiver.isBuiltIn = true
        XCTAssertNil(InputDeviceBatteryPresentation.receiverLocation(for: receiver))
    }

    func testReceiverWithoutBatteryReportShowsOnlyModelAndMissingReportMessage() {
        XCTAssertEqual(InputDeviceBatteryPresentation.receiverRows(for: .noBatteryReport), [
            .detail(label: "连接的键盘", value: "RK R87PRO"),
            .detail(label: "电量与充电状态", value: "接收器未上报")
        ])
    }

    func testReceiverWithUnknownChargingStateShowsItsLevelAndUnknownChargingLabel() {
        let rows = InputDeviceBatteryPresentation.receiverRows(for: .reading(level: 65, charging: .unknown))
        XCTAssertEqual(rows, [
            .detail(label: "连接的键盘", value: "RK R87PRO"),
            .battery(level: 65, charging: .unknown)
        ])
        XCTAssertEqual(
            HardwareStorageLocalization.chargingTitle(.unknown, locale: Locale(identifier: "zh-Hans")),
            "系统未明确报告"
        )
    }

    func testReceiverWithoutPermissionShowsOnlyAccessStatus() {
        XCTAssertEqual(InputDeviceBatteryPresentation.receiverRows(for: .permissionRequired), [
            .detail(label: "电量与充电状态", value: "系统未允许读取接收器")
        ])
    }

    func testBatteryAreaOnlyAppearsForValidReportedLevel() {
        let hiddenStates = [
            InputDeviceBatteryState(availability: .unavailable(reason: "不可用")),
            InputDeviceBatteryState(
                availability: .permissionRequired(reason: "需要权限"),
                levelPercent: 50
            ),
            InputDeviceBatteryState(
                availability: .failed(reason: "读取失败"),
                levelPercent: 50
            ),
            InputDeviceBatteryState(availability: .available),
            InputDeviceBatteryState(availability: .available, levelPercent: .nan),
            InputDeviceBatteryState(availability: .available, levelPercent: .infinity),
            InputDeviceBatteryState(availability: .available, levelPercent: -1),
            InputDeviceBatteryState(availability: .available, levelPercent: 101)
        ]

        for state in hiddenStates {
            XCTAssertNil(InputDeviceBatteryPresentation.visibleLevel(for: state))
        }

        for level in [0.0, 50.0, 100.0] {
            let state = InputDeviceBatteryState(
                availability: .available,
                levelPercent: level
            )
            XCTAssertEqual(InputDeviceBatteryPresentation.visibleLevel(for: state), level)
        }
    }

    func testChargingStateOnlyAppearsWhenSystemReportsItExplicitly() {
        XCTAssertEqual(InputDeviceBatteryPresentation.visibleChargingState(.charging), .charging)
        XCTAssertEqual(InputDeviceBatteryPresentation.visibleChargingState(.notCharging), .notCharging)
        XCTAssertNil(InputDeviceBatteryPresentation.visibleChargingState(.unknown))
    }

    func testFixtureIncludesHiddenAndVisibleBatteryExamples() throws {
        let devices = SystemSnapshot.fixture.inputDevices.devices
        let keyboard = try XCTUnwrap(devices.first { $0.name == "Magic Keyboard" })
        let mouse = try XCTUnwrap(devices.first { $0.name == "Magic Mouse" })
        let trackpad = try XCTUnwrap(devices.first { $0.name == "Magic Trackpad" })

        XCTAssertNil(InputDeviceBatteryPresentation.visibleLevel(for: keyboard.battery))
        XCTAssertEqual(InputDeviceBatteryPresentation.visibleLevel(for: mouse.battery), 76)
        XCTAssertEqual(InputDeviceBatteryPresentation.visibleLevel(for: trackpad.battery), 62)
    }

    func testAdaptiveGridUsesTwoColumnsOnlyWhenBothCardsFit() {
        let threshold = InputDeviceCardGridLayout.minimumCardWidth * 2
            + InputDeviceCardGridLayout.spacing

        XCTAssertEqual(InputDeviceCardGridLayout.columnCount(for: threshold - 1), 1)
        XCTAssertEqual(InputDeviceCardGridLayout.columnCount(for: threshold), 2)
        XCTAssertEqual(InputDeviceCardGridLayout.rowCount(itemCount: 3, width: threshold), 2)
        XCTAssertEqual(InputDeviceCardGridLayout.rowCount(itemCount: 3, width: 700), 3)
    }

    @MainActor
    func testInputDevicePageRendersWideAndNarrowLayoutsInMemory() async throws {
        let model = AppModel()
        let wide = try await render(model: model, size: CGSize(width: 1_180, height: 900))
        let narrow = try await render(model: model, size: CGSize(width: 720, height: 1_200))

        XCTAssertFalse(wide.isEmpty)
        XCTAssertFalse(narrow.isEmpty)
        XCTAssertNotEqual(wide, narrow)
        XCTAssertEqual(model.snapshot.inputDevices.devices.count, 3)
        XCTAssertEqual(
            Set(model.snapshot.inputDevices.devices.map(\.battery.chargingState)),
            Set([.charging, .notCharging, .unknown])
        )
    }

    @MainActor
    private func render(model: AppModel, size: CGSize) async throws -> Data {
        let hostingView = NSHostingView(
            rootView: NavigationStack {
                InputDevicesView()
                    .environment(model)
                    .preferredColorScheme(.dark)
            }
        )
        hostingView.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.orderOut(nil)
        defer {
            window.contentView = nil
            window.close()
        }

        await InMemoryHostingRenderer.settleUI(hostingView)
        return try InMemoryHostingRenderer.bitmapData(for: hostingView)
    }
}
