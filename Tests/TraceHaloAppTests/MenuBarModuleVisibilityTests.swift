import XCTest
@testable import TraceHaloApp
import TraceHaloCore

final class MenuBarModuleVisibilityTests: XCTestCase {
    func testDefaultModulesExposeAllEightCardsInReferenceOrder() {
        XCTAssertEqual(
            MenuBarDashboardSection.visibleSections(in: .standard),
            [.cpu, .memory, .gpu, .storage, .network, .fans, .sensors, .battery]
        )
    }

    func testDesktopMacHidesBatterySectionWhilePortableMacShowsIt() {
        var desktopSnapshot = SystemSnapshot.fixture
        desktopSnapshot.battery = BatteryState(
            availability: .unavailable(reason: "此 Mac 没有内置电池。")
        )
        XCTAssertFalse(
            MenuBarDashboardSection.visibleSections(
                in: .standard,
                snapshot: desktopSnapshot
            ).contains(.battery)
        )

        var portableSnapshot = desktopSnapshot
        portableSnapshot.battery = BatteryState(
            availability: .available,
            chargePercent: 48,
            health: .good,
            healthBasis: .systemReported
        )
        XCTAssertTrue(
            MenuBarDashboardSection.visibleSections(
                in: .standard,
                snapshot: portableSnapshot
            ).contains(.battery)
        )
    }

    func testEachModuleMapsToItsExpectedCards() {
        let expectedSections: [MonitorModule: [MenuBarDashboardSection]] = [
            .cpuAndGPU: [.cpu, .gpu],
            .memory: [.memory],
            .storage: [.storage],
            .sensors: [.fans, .sensors],
            .network: [.network],
            .power: [.battery]
        ]

        for module in MonitorModule.allCases {
            var configuration = MonitorConfiguration.standard
            for candidate in MonitorModule.allCases {
                configuration.setModule(candidate, isEnabled: candidate == module)
            }

            XCTAssertEqual(
                MenuBarDashboardSection.visibleSections(in: configuration),
                expectedSections[module],
                "\(module.rawValue) 的菜单栏卡片映射错误"
            )
        }
    }

    func testCPUAndGPUCardsAreEnabledAndHiddenAsOneModule() {
        var configuration = MonitorConfiguration.standard
        configuration.setModule(.cpuAndGPU, isEnabled: false)

        let sections = MenuBarDashboardSection.visibleSections(in: configuration)
        XCTAssertFalse(sections.contains(.cpu))
        XCTAssertFalse(sections.contains(.gpu))
        XCTAssertEqual(sections.count, 6)
    }

    func testFanAndSensorCardsAreEnabledAndHiddenAsOneModule() {
        var configuration = MonitorConfiguration.standard
        configuration.setModule(.sensors, isEnabled: false)

        let sections = MenuBarDashboardSection.visibleSections(in: configuration)
        XCTAssertFalse(sections.contains(.fans))
        XCTAssertFalse(sections.contains(.sensors))
        XCTAssertEqual(sections.count, 6)
    }

    func testNetworkProjectionPolicySkipsDisabledCollapsedNetworkModule() {
        var configuration = MonitorConfiguration.standard
        configuration.setModule(.network, isEnabled: false)
        let sections = MenuBarDashboardSection.visibleSections(in: configuration)

        XCTAssertFalse(
            MenuBarDashboardSection.requiresNetworkProjection(
                visibleSections: sections,
                selectedSection: nil
            )
        )
        XCTAssertTrue(
            MenuBarDashboardSection.requiresNetworkProjection(
                visibleSections: sections,
                selectedSection: .network
            ),
            "收起禁用详情前的过渡帧仍需保持数据完整"
        )
    }

    func testNetworkProjectionPolicyRunsForVisibleNetworkModule() {
        let sections = MenuBarDashboardSection.visibleSections(in: .standard)

        XCTAssertTrue(
            MenuBarDashboardSection.requiresNetworkProjection(
                visibleSections: sections,
                selectedSection: nil
            )
        )
    }
}
