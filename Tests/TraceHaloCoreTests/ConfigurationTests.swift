import Foundation
import XCTest
@testable import TraceHaloCore

final class ConfigurationTests: XCTestCase {
    func testStandardConfigurationHasExpectedPanelOrder() {
        let configuration = MonitorConfiguration.standard

        XCTAssertTrue(configuration.isCombined)
        XCTAssertEqual(
            configuration.panels.map(\.name),
            ["CPU & GPU", "Memory", "Storage", "Sensors", "Network", "Power"]
        )
        XCTAssertEqual(configuration.panels.filter(\.isEnabled).count, 6)
        XCTAssertEqual(configuration.panels.last?.isEnabled, true)
    }

    func testStandardConfigurationCoversTheCoreMetrics() {
        let metrics = Set(MonitorConfiguration.standard.panels.flatMap(\.widgets).map(\.metric))

        XCTAssertTrue(metrics.contains(.cpuTotal))
        XCTAssertTrue(metrics.contains(.gpuUsage))
        XCTAssertTrue(metrics.contains(.memoryPressure))
        XCTAssertTrue(metrics.contains(.storageUsed))
        XCTAssertTrue(metrics.contains(.temperature))
        XCTAssertTrue(metrics.contains(.fanSpeed))
        XCTAssertTrue(metrics.contains(.networkReceived))
        XCTAssertTrue(metrics.contains(.networkSent))
        XCTAssertTrue(metrics.contains(.batteryCharge))
        XCTAssertTrue(metrics.contains(.uptime))
    }

    func testStandardConfigurationHasExpectedStatusBarComponents() {
        let components = MonitorConfiguration.standard.statusBarComponents

        XCTAssertEqual(components.map(\.title), ["CPU", "RAM", "SSD", "CPU"])
        XCTAssertEqual(
            components.map(\.metric),
            [.cpuTotal, .memoryPressure, .storageUsed, .temperature]
        )
        XCTAssertEqual(components.first?.style, .miniChart)
        XCTAssertEqual(
            components.dropFirst().map(\.style),
            [.verticalGaugeValue, .verticalGaugeValue, .value]
        )
        XCTAssertTrue(components.allSatisfy(\.isVisible))
        XCTAssertEqual(MonitorConfiguration.standard.statusBarLayoutMode, .full)
        XCTAssertFalse(MonitorConfiguration.standard.showsStatusBarIcon)
    }

    func testStandardConfigurationHasExpectedQuickItems() {
        let items = MonitorConfiguration.standard.quickItems

        XCTAssertEqual(
            items.map(\.action),
            [.traceHalo, .activityMonitor, .console, .terminal, .systemInformation, .systemSettings]
        )
        XCTAssertEqual(
            items.map(\.systemImage),
            [
                "scope",
                "waveform.path.ecg.rectangle",
                "list.bullet.rectangle",
                "terminal",
                "info.circle",
                "gearshape"
            ]
        )
        XCTAssertTrue(items.allSatisfy(\.isVisible))
    }

    func testQuickActionReadsAndWritesTraceHaloValue() throws {
        XCTAssertEqual(
            MonitorQuickAction.allCases.map(\.rawValue),
            [
                "traceHalo",
                "activityMonitor",
                "console",
                "terminal",
                "systemInformation",
                "systemSettings"
            ]
        )

        let decodedValue = try JSONDecoder().decode(
            MonitorQuickAction.self,
            from: Data(#""traceHalo""#.utf8)
        )
        XCTAssertEqual(decodedValue, .traceHalo)
        XCTAssertEqual(
            String(decoding: try JSONEncoder().encode(MonitorQuickAction.traceHalo), as: UTF8.self),
            #""traceHalo""#
        )
    }

    func testConfigurationCodableRoundTripStaysInMemory() throws {
        var source = MonitorConfiguration.standard
        source.statusBarLayoutMode = .compact
        source.showsStatusBarIcon = true
        let encoded = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(MonitorConfiguration.self, from: encoded)

        XCTAssertEqual(decoded, source)
    }

    func testLegacyConfigurationDecodingAddsStatusBarAndQuickItemDefaults() throws {
        struct LegacyConfiguration: Encodable {
            let isCombined: Bool
            let panels: [MonitorPanel]
        }

        let legacy = LegacyConfiguration(
            isCombined: false,
            panels: Array(MonitorConfiguration.standard.panels.prefix(2))
        )
        let encoded = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(MonitorConfiguration.self, from: encoded)

        XCTAssertFalse(decoded.isCombined)
        XCTAssertEqual(decoded.panels, legacy.panels)
        XCTAssertEqual(decoded.statusBarComponents, MonitorConfiguration.defaultStatusBarComponents)
        XCTAssertEqual(decoded.quickItems, MonitorConfiguration.defaultQuickItems)
        XCTAssertEqual(decoded.statusBarLayoutMode, .full)
        XCTAssertFalse(decoded.showsStatusBarIcon)
    }

    func testLegacyFourChartStatusBarMigratesToSenseiStyles() throws {
        struct LegacyConfiguration: Encodable {
            let isCombined: Bool
            let panels: [MonitorPanel]
            let statusBarComponents: [MonitorStatusBarComponent]
            let quickItems: [MonitorQuickItem]
        }

        let legacy = LegacyConfiguration(
            isCombined: true,
            panels: MonitorConfiguration.standard.panels,
            statusBarComponents: [
                MonitorStatusBarComponent(style: .miniChart, metric: .cpuTotal, title: "CPU"),
                MonitorStatusBarComponent(style: .miniChart, metric: .memoryPressure, title: "RAM"),
                MonitorStatusBarComponent(style: .miniChart, metric: .storageUsed, title: "SSD"),
                MonitorStatusBarComponent(style: .miniChart, metric: .temperature, title: "CPU")
            ],
            quickItems: MonitorConfiguration.defaultQuickItems
        )

        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(MonitorConfiguration.self, from: data)

        XCTAssertEqual(
            decoded.statusBarComponents.map(\.style),
            [.miniChart, .verticalGaugeValue, .verticalGaugeValue, .value]
        )
        XCTAssertEqual(decoded.statusBarLayoutMode, .full)
        XCTAssertFalse(decoded.showsStatusBarIcon)
    }

    func testTraceHaloQuickItemTitleRoundTrips() throws {
        let configuration = MonitorConfiguration(
            panels: MonitorConfiguration.standard.panels,
            quickItems: [
                MonitorQuickItem(
                    action: .traceHalo,
                    title: "TraceHalo",
                    systemImage: "scope"
                )
            ]
        )
        let data = try JSONEncoder().encode(configuration)

        let decoded = try JSONDecoder().decode(MonitorConfiguration.self, from: data)

        XCTAssertEqual(decoded.quickItems.first?.title, "TraceHalo")
    }

    func testStatusBarComponentsCanBeReorderedAndHidden() {
        var configuration = MonitorConfiguration.standard
        let originalIDs = configuration.statusBarComponents.map(\.id)

        configuration.statusBarComponents.swapAt(0, 3)
        configuration.statusBarComponents[1].isVisible = false

        XCTAssertEqual(
            configuration.statusBarComponents.map(\.id),
            [originalIDs[3], originalIDs[1], originalIDs[2], originalIDs[0]]
        )
        XCTAssertFalse(configuration.statusBarComponents[1].isVisible)
    }

    func testQuickItemsCanBeReorderedAndHidden() throws {
        var configuration = MonitorConfiguration.standard

        configuration.quickItems = Array(configuration.quickItems.reversed())
        configuration.quickItems[0].isVisible = false

        let encoded = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(MonitorConfiguration.self, from: encoded)

        XCTAssertEqual(decoded, configuration)
        XCTAssertEqual(decoded.quickItems.first?.action, .systemSettings)
        XCTAssertFalse(decoded.quickItems[0].isVisible)
    }

    func testPanelReorderingDoesNotChangeWidgetContent() {
        let source = MonitorConfiguration.standard
        let reversed = Array(source.panels.reversed())

        XCTAssertEqual(reversed.first?.name, "Power")
        XCTAssertEqual(reversed.last?.name, "CPU & GPU")
        XCTAssertEqual(Set(reversed.map(\.id)), Set(source.panels.map(\.id)))
        XCTAssertEqual(reversed.flatMap(\.widgets).count, source.panels.flatMap(\.widgets).count)
    }

    func testPersistedDefaultsAreLocaleIndependentCanonicalValues() {
        let configuration = MonitorConfiguration.standard

        XCTAssertEqual(
            configuration.panels.flatMap(\.widgets).map(\.title),
            [
                "CPU", "GPU", "Top Processes",
                "Memory Usage", "Memory Used",
                "Storage", "Thermal Status", "Fans",
                "Download", "Upload", "Battery", "Uptime"
            ]
        )
        XCTAssertEqual(
            configuration.quickItems.map(\.title),
            [
                "TraceHalo", "Activity Monitor", "Console", "Terminal",
                "System Information", "System Settings"
            ]
        )
    }

    func testLegacyChineseDefaultsResolveForEnglishWithoutMutatingConfiguration() throws {
        let panelID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let widgetID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let componentID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
        let source = MonitorConfiguration(
            isCombined: false,
            panels: [
                MonitorPanel(
                    id: panelID,
                    name: "内存",
                    symbol: "memorychip",
                    isEnabled: false,
                    widgets: [
                        MonitorWidget(
                            id: widgetID,
                            kind: .ring,
                            metric: .memoryPressure,
                            title: "内存压力",
                            accentHex: "D45CAC",
                            hideWhenUnavailable: false
                        )
                    ]
                )
            ],
            statusBarLayoutMode: .compact,
            showsStatusBarIcon: true,
            statusBarComponents: [
                MonitorStatusBarComponent(
                    id: componentID,
                    style: .verticalGaugeValue,
                    metric: .memoryPressure,
                    title: "内存",
                    accentHex: "55B7F3",
                    isVisible: false
                )
            ],
            quickItems: [
                MonitorQuickItem(
                    action: .terminal,
                    title: "终端",
                    systemImage: "terminal",
                    isVisible: false
                )
            ]
        )
        let decoded = try JSONDecoder().decode(
            MonitorConfiguration.self,
            from: JSONEncoder().encode(source)
        )
        let english = Locale(identifier: AppLanguageResolver.englishIdentifier)

        XCTAssertEqual(decoded.panels[0].localizedDisplayName(locale: english), "Memory")
        XCTAssertEqual(decoded.panels[0].widgets[0].localizedDisplayTitle(locale: english), "Memory Usage")
        XCTAssertEqual(decoded.statusBarComponents[0].localizedDisplayTitle(locale: english), "RAM")
        XCTAssertEqual(
            decoded.quickItems[0].action.localizedTitle(
                persistedTitle: decoded.quickItems[0].title,
                locale: english
            ),
            "Terminal"
        )

        XCTAssertEqual(decoded, source)
        XCTAssertEqual(decoded.panels.map(\.id), [panelID])
        XCTAssertEqual(decoded.panels.flatMap(\.widgets).map(\.id), [widgetID])
        XCTAssertEqual(decoded.statusBarComponents.map(\.id), [componentID])
        XCTAssertEqual(decoded.statusBarComponents.map(\.style), [.verticalGaugeValue])
        XCTAssertEqual(decoded.statusBarComponents.map(\.metric), [.memoryPressure])
        XCTAssertEqual(decoded.statusBarComponents.map(\.isVisible), [false])
        XCTAssertEqual(decoded.quickItems.map(\.action), [.terminal])
        XCTAssertEqual(decoded.quickItems.map(\.isVisible), [false])
    }

    func testUnknownCustomPersistedTitlesRemainUntouchedAcrossLanguages() {
        let english = Locale(identifier: AppLanguageResolver.englishIdentifier)
        let simplifiedChinese = Locale(identifier: AppLanguageResolver.simplifiedChineseIdentifier)
        let panel = MonitorPanel(name: "工作台", symbol: "square", widgets: [])
        let widget = MonitorWidget(kind: .value, metric: .memoryPressure, title: "我的内存")
        let component = MonitorStatusBarComponent(
            style: .value,
            metric: .memoryPressure,
            title: "MEM-X"
        )

        for locale in [english, simplifiedChinese] {
            XCTAssertEqual(panel.localizedDisplayName(locale: locale), "工作台")
            XCTAssertEqual(widget.localizedDisplayTitle(locale: locale), "我的内存")
            XCTAssertEqual(component.localizedDisplayTitle(locale: locale), "MEM-X")
            XCTAssertEqual(
                MonitorQuickAction.terminal.localizedTitle(
                    persistedTitle: "My Shell",
                    locale: locale
                ),
                "My Shell"
            )
        }
    }

    func testWidgetDefaultsAreExplicitAndStable() {
        let widget = MonitorWidget(kind: .value, metric: .temperature, title: "温度")

        XCTAssertEqual(widget.accentHex, "7C5CFC")
        XCTAssertTrue(widget.hideWhenUnavailable)
    }

    func testWidgetHidesUnavailableMetricOnlyWhenPreferenceIsEnabled() {
        var snapshot = SystemSnapshot.fixture
        snapshot.gpus[0].utilizationPercent = nil
        var widget = MonitorWidget(
            kind: .value,
            metric: .gpuUsage,
            title: "GPU",
            hideWhenUnavailable: true
        )

        XCTAssertFalse(MonitorMetric.gpuUsage.isAvailable(in: snapshot))
        XCTAssertTrue(widget.shouldHide(in: snapshot))

        widget.hideWhenUnavailable = false
        XCTAssertFalse(widget.shouldHide(in: snapshot))

        snapshot.gpus[0].utilizationPercent = 42
        widget.hideWhenUnavailable = true
        XCTAssertFalse(widget.shouldHide(in: snapshot))
    }

    func testStructuralWidgetsStayVisibleAndEmptyProcessListCanHide() {
        var snapshot = SystemSnapshot.fixture
        snapshot.cpu.topProcesses = []

        let title = MonitorWidget(kind: .title, metric: .gpuUsage, title: "标题")
        let separator = MonitorWidget(kind: .separator, metric: .gpuUsage, title: "分隔线")
        var processList = MonitorWidget(kind: .processList, metric: .gpuUsage, title: "进程")

        XCTAssertFalse(title.shouldHide(in: snapshot))
        XCTAssertFalse(separator.shouldHide(in: snapshot))
        XCTAssertTrue(processList.shouldHide(in: snapshot))

        processList.hideWhenUnavailable = false
        XCTAssertFalse(processList.shouldHide(in: snapshot))
    }
}
