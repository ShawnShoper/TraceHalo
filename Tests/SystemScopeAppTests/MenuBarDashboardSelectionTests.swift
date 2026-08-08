import XCTest
@testable import SystemScopeApp

final class MenuBarDashboardSelectionTests: XCTestCase {
    func testReferenceOrderContainsEverySectionExactlyOnce() {
        XCTAssertEqual(
            MenuBarDashboardSection.referenceOrder,
            [.cpu, .memory, .gpu, .storage, .network, .fans, .sensors, .battery]
        )
        XCTAssertEqual(
            Set(MenuBarDashboardSection.referenceOrder.map(\.id)).count,
            MenuBarDashboardSection.allCases.count
        )
    }

    func testSectionTitlesMatchTheirDetailRoutes() {
        XCTAssertEqual(
            MenuBarDashboardSection.referenceOrder.map(\.title),
            ["CPU", "内存", "GPU", "存储", "网络服务", "风扇", "温度传感器", "电池"]
        )
    }

    func testDefaultSelectionStartsCollapsed() {
        let selection = MenuBarDashboardSelection()

        XCTAssertNil(selection.selectedSection)
        XCTAssertFalse(selection.isExpanded)
    }

    func testEverySectionCanOpenFromCollapsedState() {
        for section in MenuBarDashboardSection.referenceOrder {
            var selection = MenuBarDashboardSelection()

            selection.toggle(section)

            XCTAssertEqual(selection.selectedSection, section)
            XCTAssertTrue(selection.isExpanded)
        }
    }

    func testTogglingSelectedSectionCollapsesDetailColumn() {
        for section in MenuBarDashboardSection.referenceOrder {
            var selection = MenuBarDashboardSelection(selectedSection: section)

            selection.toggle(section)

            XCTAssertNil(selection.selectedSection)
            XCTAssertFalse(selection.isExpanded)
        }
    }

    func testTogglingDifferentSectionSwitchesDetailWithoutIntermediateCollapse() {
        for source in MenuBarDashboardSection.referenceOrder {
            for destination in MenuBarDashboardSection.referenceOrder where destination != source {
                var selection = MenuBarDashboardSelection(selectedSection: source)

                selection.toggle(destination)

                XCTAssertEqual(selection.selectedSection, destination)
                XCTAssertTrue(selection.isExpanded)
            }
        }
    }

    func testEmbeddedPreviewSelectingCurrentSectionKeepsDetailExpanded() {
        var selection = MenuBarDashboardSelection(selectedSection: .cpu)

        selection.select(.cpu)

        XCTAssertEqual(selection.selectedSection, .cpu)
        XCTAssertTrue(selection.isExpanded)
    }

    func testEmbeddedPreviewSelectingAnotherSectionSwitchesDetailDirectly() {
        var selection = MenuBarDashboardSelection(selectedSection: .cpu)

        selection.select(.memory)

        XCTAssertEqual(selection.selectedSection, .memory)
        XCTAssertTrue(selection.isExpanded)
    }

    func testCollapseIsIdempotentAndSelectionCanOpenAgain() {
        var selection = MenuBarDashboardSelection(selectedSection: .network)

        selection.collapse()
        selection.collapse()

        XCTAssertNil(selection.selectedSection)
        XCTAssertFalse(selection.isExpanded)

        selection.toggle(.battery)

        XCTAssertEqual(selection.selectedSection, .battery)
        XCTAssertTrue(selection.isExpanded)
    }

    func testSelectionTransitionsLoadTheNewSupportingDetailsWithoutAnIntermediateBlankState() {
        var selection = MenuBarDashboardSelection(selectedSection: .cpu)
        var loadedDetailSection: MenuBarDashboardSection? = .cpu

        selection.toggle(
            .memory,
            loadedDetailSection: &loadedDetailSection
        )

        XCTAssertEqual(selection.selectedSection, .memory)
        XCTAssertEqual(loadedDetailSection, .memory)

        loadedDetailSection = .memory
        selection.toggle(
            .memory,
            loadedDetailSection: &loadedDetailSection
        )

        XCTAssertNil(selection.selectedSection)
        XCTAssertNil(loadedDetailSection)
    }

    func testEveryModuleSwitchKeepsSummaryAndSupportingDetailsOnTheSameSection() {
        for source in MenuBarDashboardSection.referenceOrder {
            for destination in MenuBarDashboardSection.referenceOrder where destination != source {
                var selection = MenuBarDashboardSelection(selectedSection: source)
                var loadedDetailSection: MenuBarDashboardSection? = source

                selection.toggle(
                    destination,
                    loadedDetailSection: &loadedDetailSection
                )

                XCTAssertEqual(selection.selectedSection, destination)
                XCTAssertEqual(loadedDetailSection, destination)
            }
        }
    }

    func testCollapseInvalidatesLoadedSupportingDetails() {
        var selection = MenuBarDashboardSelection(selectedSection: .sensors)
        var loadedDetailSection: MenuBarDashboardSection? = .sensors

        selection.collapse(loadedDetailSection: &loadedDetailSection)

        XCTAssertNil(selection.selectedSection)
        XCTAssertNil(loadedDetailSection)
    }
}
