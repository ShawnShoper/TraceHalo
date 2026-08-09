import TraceHaloCore
import XCTest
@testable import TraceHaloApp

final class CoolingSensorGroupingTests: XCTestCase {
    func testSectionsUseStableOrderAndCalculateSummaries() throws {
        let sensors = [
            sensor("other", name: "Other", group: "存储", temperature: 38),
            sensor("cpu-b", name: "CPU B", group: "CPU", temperature: 50),
            sensor("system", name: "Ambient", group: "环境", temperature: 30),
            sensor("memory", name: "Memory", group: "内存", temperature: 42),
            sensor("gpu", name: "GPU", group: "GPU", temperature: 46),
            sensor("cpu-a", name: "CPU A", group: "CPU", temperature: 40)
        ]

        let sections = ThermalSensorDisplayGrouping.sections(from: sensors)

        XCTAssertEqual(sections.map(\.group), [.cpu, .gpu, .memory, .system, .other])
        let cpu = try XCTUnwrap(sections.first { $0.group == .cpu })
        XCTAssertEqual(cpu.sensors.map(\.key), ["cpu-a", "cpu-b"])
        XCTAssertEqual(cpu.averageCelsius, 45, accuracy: 0.001)
        XCTAssertEqual(cpu.maximumCelsius, 50, accuracy: 0.001)
    }

    func testChineseEnglishAliasesAndUnknownGroups() {
        let cases: [(String, ThermalSensorDisplayGroup)] = [
            (" CPU ", .cpu),
            ("处理器", .cpu),
            ("graphics processor", .gpu),
            ("图形处理器", .gpu),
            ("RAM", .memory),
            ("内存", .memory),
            ("System", .system),
            ("环境", .system),
            ("存储", .other),
            ("", .other),
            ("Future Sensor Group", .other)
        ]

        for (rawGroup, expected) in cases {
            XCTAssertEqual(ThermalSensorDisplayGroup.classify(rawGroup), expected)
        }
    }

    func testEmptyGroupsAndInvalidTemperaturesAreOmitted() {
        XCTAssertTrue(ThermalSensorDisplayGrouping.sections(from: []).isEmpty)

        let sections = ThermalSensorDisplayGrouping.sections(from: [
            sensor("valid", name: "Valid", group: "CPU", temperature: 44),
            sensor("nan", name: "NaN", group: "GPU", temperature: .nan),
            sensor("infinite", name: "Infinite", group: "Memory", temperature: .infinity)
        ])

        XCTAssertEqual(sections.map(\.group), [.cpu])
        XCTAssertEqual(sections.first?.sensors.map(\.key), ["valid"])
    }

    func testFixtureCoversEveryDisplayGroup() {
        let sections = ThermalSensorDisplayGrouping.sections(
            from: SystemSnapshot.fixture.cooling.sensors
        )

        XCTAssertEqual(sections.map(\.group), [.cpu, .gpu, .memory, .system, .other])
        XCTAssertEqual(sections.map(\.sensors.count), [1, 1, 1, 1, 1])
    }

    private func sensor(
        _ key: String,
        name: String,
        group: String,
        temperature: Double
    ) -> ThermalSensor {
        ThermalSensor(
            key: key,
            name: name,
            group: group,
            temperatureCelsius: temperature
        )
    }
}
