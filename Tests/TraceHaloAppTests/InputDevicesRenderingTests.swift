import AppKit
import TraceHaloCore
import SwiftUI
import XCTest
@testable import TraceHaloApp

final class InputDevicesRenderingTests: XCTestCase {
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
        XCTAssertTrue(InputDeviceBatteryPresentation.showsChargingState(.charging))
        XCTAssertTrue(InputDeviceBatteryPresentation.showsChargingState(.notCharging))
        XCTAssertFalse(InputDeviceBatteryPresentation.showsChargingState(.unknown))
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
