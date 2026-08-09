import XCTest
@testable import TraceHaloCore

final class InputDeviceReaderTests: XCTestCase {
    func testParsesPublicPropertiesAndAllUsagePairsInMemory() throws {
        let record = try XCTUnwrap(InputDeviceCatalog.record(
            registryID: 42,
            properties: [
                "Product": "  Magic Trackpad  ",
                "Manufacturer": "Apple Inc.",
                "Transport": "Bluetooth",
                "VendorID": NSNumber(value: 0x05AC),
                "ProductID": NSNumber(value: 0x0265),
                "VersionNumber": NSNumber(value: 0x0110),
                "LocationID": NSNumber(value: 0x0100_0000),
                "SerialNumber": "SERIAL-TEST",
                "PhysicalDeviceUniqueID": "PHYSICAL-TEST",
                "Built-In": false,
                "DeviceUsagePairs": [
                    ["DeviceUsagePage": 0x01, "DeviceUsage": 0x02],
                    ["DeviceUsagePage": 0x01, "DeviceUsage": 0x01],
                    ["DeviceUsagePage": 0x0D, "DeviceUsage": 0x05]
                ]
            ]
        ))

        XCTAssertEqual(record.productName, "Magic Trackpad")
        XCTAssertEqual(record.manufacturer, "Apple Inc.")
        XCTAssertEqual(record.transport, "Bluetooth")
        XCTAssertEqual(record.vendorID, 0x05AC)
        XCTAssertEqual(record.productID, 0x0265)
        XCTAssertEqual(record.versionNumber, 0x0110)
        XCTAssertEqual(record.locationID, 0x0100_0000)
        XCTAssertEqual(record.serialNumber, "SERIAL-TEST")
        XCTAssertEqual(record.isBuiltIn, false)
        XCTAssertEqual(
            Set(InputDeviceCatalog.kinds(for: record.usagePairs)),
            Set([.mouse, .trackpad, .pointingDevice])
        )
    }

    func testPhysicalIdentifierMergesCompositeCollectionsEvenWhenOtherPropertiesDiffer() throws {
        let keyboard = try makeRecord(
            registryID: 1,
            name: "Receiver Keyboard",
            physicalID: "shared-physical-id",
            transport: "USB",
            vendorID: 1,
            productID: 10,
            page: 0x01,
            usage: 0x06
        )
        let mouse = try makeRecord(
            registryID: 2,
            name: "Receiver Keyboard and Mouse",
            physicalID: "shared-physical-id",
            transport: "Bluetooth",
            vendorID: 2,
            productID: 20,
            page: 0x01,
            usage: 0x02
        )

        let inventory = InputDeviceCatalog.inventory(from: [keyboard, mouse])

        XCTAssertEqual(inventory.devices.count, 1)
        XCTAssertEqual(inventory.devices[0].name, "Receiver Keyboard and Mouse")
        XCTAssertEqual(Set(inventory.devices[0].kinds), Set([.keyboard, .mouse]))
        XCTAssertFalse(inventory.devices[0].stableIdentifier.contains("shared-physical-id"))
    }

    func testSerialAndLocationFallbacksDeduplicateWithoutUsingNames() throws {
        let serialKeyboard = try makeRecord(
            registryID: 11,
            name: "Keyboard Collection",
            serial: "SERIAL-A",
            transport: "Bluetooth",
            vendorID: 1,
            productID: 2,
            page: 0x01,
            usage: 0x06
        )
        let serialKeypad = try makeRecord(
            registryID: 12,
            name: "Keypad Collection",
            serial: "SERIAL-A",
            transport: "Bluetooth",
            vendorID: 1,
            productID: 2,
            page: 0x01,
            usage: 0x07
        )
        let locationMouse = try makeRecord(
            registryID: 21,
            name: "Mouse Collection",
            transport: "USB",
            vendorID: 3,
            productID: 4,
            locationID: 99,
            page: 0x01,
            usage: 0x02
        )
        let locationPointer = try makeRecord(
            registryID: 22,
            name: "Pointer Collection",
            transport: "USB",
            vendorID: 3,
            productID: 4,
            locationID: 99,
            page: 0x01,
            usage: 0x01
        )

        let inventory = InputDeviceCatalog.inventory(from: [
            serialKeyboard,
            serialKeypad,
            locationMouse,
            locationPointer
        ])

        XCTAssertEqual(inventory.devices.count, 2)
        XCTAssertEqual(inventory.devices.filter { $0.kinds.contains(.keyboard) }.count, 1)
        XCTAssertEqual(inventory.devices.filter { $0.kinds.contains(.mouse) }.count, 1)
    }

    func testFiltersOnlyDevicesThatDeclareVirtualTransport() throws {
        let physical = try makeRecord(
            registryID: 1,
            name: "Physical Keyboard",
            transport: "USB",
            page: 0x01,
            usage: 0x06
        )
        let virtual = try makeRecord(
            registryID: 2,
            name: "Virtual Keyboard",
            transport: "vIrTuAl",
            page: 0x01,
            usage: 0x06
        )
        let unknownTransport = try makeRecord(
            registryID: 3,
            name: "User Device Keyboard",
            transport: nil,
            page: 0x01,
            usage: 0x06
        )

        let inventory = InputDeviceCatalog.inventory(from: [physical, virtual, unknownTransport])

        XCTAssertEqual(inventory.devices.map(\.name), ["Physical Keyboard", "User Device Keyboard"])
    }

    func testUnidentifiedRecordsArePreservedRatherThanMergedByModelName() throws {
        let first = try makeRecord(
            registryID: 0,
            name: "Identical Keyboard",
            transport: "USB",
            vendorID: 1,
            productID: 2,
            page: 0x01,
            usage: 0x06
        )
        let second = try makeRecord(
            registryID: 0,
            name: "Identical Keyboard",
            transport: "USB",
            vendorID: 1,
            productID: 2,
            page: 0x01,
            usage: 0x06
        )

        let inventory = InputDeviceCatalog.inventory(from: [first, second])

        XCTAssertEqual(inventory.devices.count, 2)
        XCTAssertNotEqual(inventory.devices[0].stableIdentifier, inventory.devices[1].stableIdentifier)
    }

    func testUnidentifiedFallbackIDsRemainDeterministicAcrossInputOrder() throws {
        let alpha = try makeRecord(
            registryID: 0,
            name: "Alpha Keyboard",
            page: 0x01,
            usage: 0x06
        )
        let beta = try makeRecord(
            registryID: 0,
            name: "Beta Keyboard",
            page: 0x01,
            usage: 0x06
        )

        let forward = Dictionary(uniqueKeysWithValues: InputDeviceCatalog
            .inventory(from: [alpha, beta])
            .devices
            .map { ($0.name, $0.stableIdentifier) })
        let reversed = Dictionary(uniqueKeysWithValues: InputDeviceCatalog
            .inventory(from: [beta, alpha])
            .devices
            .map { ($0.name, $0.stableIdentifier) })

        XCTAssertEqual(forward, reversed)
    }

    func testStableIdentifierDoesNotDependOnCollectionOrder() throws {
        let mouse = try makeRecord(
            registryID: 20,
            name: "Composite Device",
            physicalID: "PRIVATE-PHYSICAL-ID",
            page: 0x01,
            usage: 0x02
        )
        let trackpad = try makeRecord(
            registryID: 10,
            name: "Composite Device",
            physicalID: "PRIVATE-PHYSICAL-ID",
            page: 0x0D,
            usage: 0x05
        )

        let forward = try XCTUnwrap(InputDeviceCatalog.inventory(from: [mouse, trackpad]).devices.first)
        let reversed = try XCTUnwrap(InputDeviceCatalog.inventory(from: [trackpad, mouse]).devices.first)

        XCTAssertEqual(forward, reversed)
        XCTAssertTrue(forward.stableIdentifier.hasPrefix("hid-"))
        XCTAssertFalse(forward.stableIdentifier.contains("PRIVATE-PHYSICAL-ID"))
        XCTAssertEqual(forward.primaryKind, .trackpad)
    }

    func testOpaqueIdentifiersPreserveCaseAndDiacritics() throws {
        let uppercase = try makeRecord(
            registryID: 1,
            name: "Keyboard",
            physicalID: "Device-Café",
            page: 0x01,
            usage: 0x06
        )
        let lowercase = try makeRecord(
            registryID: 2,
            name: "Keyboard",
            physicalID: "device-Cafe",
            page: 0x01,
            usage: 0x06
        )
        let serialUppercase = try makeRecord(
            registryID: 3,
            name: "Mouse",
            serial: "Serial-A",
            transport: "USB",
            vendorID: 1,
            productID: 2,
            page: 0x01,
            usage: 0x02
        )
        let serialLowercase = try makeRecord(
            registryID: 4,
            name: "Mouse",
            serial: "serial-a",
            transport: "USB",
            vendorID: 1,
            productID: 2,
            page: 0x01,
            usage: 0x02
        )

        let inventory = InputDeviceCatalog.inventory(from: [
            uppercase,
            lowercase,
            serialUppercase,
            serialLowercase
        ])

        XCTAssertEqual(inventory.devices.count, 4)
    }

    func testPlaceholderOpaqueIdentifiersAreRejectedBeforeDeduplication() throws {
        let unknown = try makeRecord(
            registryID: 31,
            name: "Keyboard",
            physicalID: " unknown ",
            serial: "0",
            transport: "USB",
            page: 0x01,
            usage: 0x06
        )
        let none = try makeRecord(
            registryID: 32,
            name: "Keyboard",
            physicalID: "NONE",
            serial: "0000",
            transport: "USB",
            page: 0x01,
            usage: 0x06
        )

        XCTAssertNil(unknown.physicalDeviceUniqueID)
        XCTAssertNil(unknown.serialNumber)
        XCTAssertNil(none.physicalDeviceUniqueID)
        XCTAssertNil(none.serialNumber)
        XCTAssertEqual(InputDeviceCatalog.inventory(from: [unknown, none]).devices.count, 2)
    }

    func testGenericHIDRegistryBatteryPropertiesAreIgnored() throws {
        let genericRegistryRecord = try XCTUnwrap(InputDeviceCatalog.record(
            registryID: 1,
            properties: [
                "Product": "Mouse",
                "PrimaryUsagePage": 0x01,
                "PrimaryUsage": 0x02,
                "BatteryPercent": 88,
                "IsCharging": true,
                "BatteryStatusFlags": 3
            ]
        ))
        let unavailable = try XCTUnwrap(
            InputDeviceCatalog.inventory(from: [genericRegistryRecord]).devices.first
        )
        XCTAssertFalse(unavailable.battery.availability.isAvailable)
        XCTAssertNil(unavailable.battery.levelPercent)
        XCTAssertEqual(unavailable.battery.chargingState, .unknown)
    }

    func testAppleDriverBatteryFallbackRequiresCompleteExactIdentity() throws {
        let trackpad = try makeRecord(
            registryID: 1,
            name: "Magic Trackpad",
            transport: "Bluetooth",
            vendorID: 76,
            productID: 613,
            locationID: 1_810_643_337,
            page: 0x0D,
            usage: 0x05
        )

        let device = try XCTUnwrap(InputDeviceCatalog.inventory(
            from: [trackpad],
            appleDriverBatteries: [
                AppleDriverBatteryRecord(
                    transport: " bluetooth ",
                    vendorID: 76,
                    productID: 613,
                    locationID: 1_810_643_337,
                    levelPercent: 7,
                    chargingState: .charging
                )
            ]
        ).devices.first)

        XCTAssertEqual(device.battery.levelPercent, 7)
        XCTAssertEqual(device.battery.source, .appleDriverRegistry)
        XCTAssertEqual(device.battery.chargingState, .charging)
    }

    func testChargingStateUsesOnlyExplicitDriverProperties() {
        XCTAssertEqual(
            AppleDriverBatteryRegistryReader.chargingState(from: ["IsCharging": true]),
            .charging
        )
        XCTAssertEqual(
            AppleDriverBatteryRegistryReader.chargingState(from: ["Is Charging": false]),
            .notCharging
        )
        XCTAssertEqual(
            AppleDriverBatteryRegistryReader.chargingState(from: [
                "Transport": " usb ",
                "BatteryStatusFlags": 3
            ]),
            .charging
        )
        XCTAssertEqual(
            AppleDriverBatteryRegistryReader.chargingState(from: [
                "Transport": "Bluetooth",
                "BatteryStatusFlags": 3
            ]),
            .unknown
        )
        XCTAssertEqual(
            AppleDriverBatteryRegistryReader.chargingState(from: ["BatteryStatusFlags": 0]),
            .notCharging
        )
        for unverifiedFlags in [1, 2, 4, 255] {
            XCTAssertEqual(
                AppleDriverBatteryRegistryReader.chargingState(
                    from: ["BatteryStatusFlags": unverifiedFlags]
                ),
                .unknown
            )
        }
        XCTAssertEqual(
            AppleDriverBatteryRegistryReader.chargingState(from: ["BatteryPercent": 100]),
            .unknown,
            "电量百分比不能用来推断充电状态"
        )
    }

    func testAppleDriverFallbackRejectsMismatchedIncompleteAndConflictingIdentity() throws {
        let exactHIDRecord = try makeRecord(
            registryID: 1,
            name: "Magic Trackpad",
            transport: "Bluetooth",
            vendorID: 76,
            productID: 613,
            locationID: 1_810_643_337,
            page: 0x0D,
            usage: 0x05
        )
        let missingLocation = try makeRecord(
            registryID: 2,
            name: "Magic Trackpad",
            transport: "Bluetooth",
            vendorID: 76,
            productID: 613,
            page: 0x0D,
            usage: 0x05
        )
        let mismatched = AppleDriverBatteryRecord(
            transport: "Bluetooth",
            vendorID: 76,
            productID: 613,
            locationID: 99,
            levelPercent: 7,
            chargingState: .notCharging
        )

        let mismatchedDevices = InputDeviceCatalog.inventory(
            from: [exactHIDRecord, missingLocation],
            appleDriverBatteries: [mismatched]
        ).devices
        XCTAssertTrue(mismatchedDevices.allSatisfy { !$0.battery.availability.isAvailable })

        let conflicting = InputDeviceCatalog.inventory(
            from: [exactHIDRecord],
            appleDriverBatteries: [
                AppleDriverBatteryRecord(
                    transport: "Bluetooth",
                    vendorID: 76,
                    productID: 613,
                    locationID: 1_810_643_337,
                    levelPercent: 7,
                    chargingState: .charging
                ),
                AppleDriverBatteryRecord(
                    transport: "Bluetooth",
                    vendorID: 76,
                    productID: 613,
                    locationID: 1_810_643_337,
                    levelPercent: 8,
                    chargingState: .charging
                )
            ]
        ).devices
        XCTAssertEqual(conflicting.count, 1)
        XCTAssertFalse(conflicting[0].battery.availability.isAvailable)

        let chargingConflict = try XCTUnwrap(InputDeviceCatalog.inventory(
            from: [exactHIDRecord],
            appleDriverBatteries: [
                AppleDriverBatteryRecord(
                    transport: "Bluetooth",
                    vendorID: 76,
                    productID: 613,
                    locationID: 1_810_643_337,
                    levelPercent: 7,
                    chargingState: .charging
                ),
                AppleDriverBatteryRecord(
                    transport: "Bluetooth",
                    vendorID: 76,
                    productID: 613,
                    locationID: 1_810_643_337,
                    levelPercent: 7,
                    chargingState: .notCharging
                )
            ]
        ).devices.first)
        XCTAssertEqual(chargingConflict.battery.levelPercent, 7)
        XCTAssertEqual(chargingConflict.battery.chargingState, .unknown)
    }

    func testAppleDriverRegistryRecordAcceptsOnlyCompleteValidValues() throws {
        let valid = try XCTUnwrap(AppleDriverBatteryRegistryReader.record(from: [
            "Transport": "USB",
            "VendorID": 76,
            "ProductID": 613,
            "LocationID": 1_810_643_337,
            "BatteryPercent": 7,
            "BatteryStatusFlags": 3
        ]))
        XCTAssertEqual(valid.levelPercent, 7)
        XCTAssertEqual(valid.chargingState, .charging)

        for invalidBattery in [-1, 101] {
            XCTAssertNil(AppleDriverBatteryRegistryReader.record(from: [
                "Transport": "Bluetooth",
                "VendorID": 76,
                "ProductID": 613,
                "LocationID": 1_810_643_337,
                "BatteryPercent": invalidBattery
            ]))
        }
        XCTAssertNil(AppleDriverBatteryRegistryReader.record(from: [
            "Transport": "Bluetooth",
            "VendorID": 76,
            "ProductID": 613,
            "LocationID": 0,
            "BatteryPercent": 7
        ]))
        XCTAssertNil(AppleDriverBatteryRegistryReader.record(from: [
            "Product": "Magic Trackpad",
            "BatteryPercent": 7
        ]))
    }

    private func makeRecord(
        registryID: UInt64,
        name: String,
        physicalID: String? = nil,
        serial: String? = nil,
        transport: String? = nil,
        vendorID: UInt64? = nil,
        productID: UInt64? = nil,
        locationID: UInt64? = nil,
        page: Int,
        usage: Int
    ) throws -> HIDDeviceRecord {
        var properties: [String: Any] = [
            "Product": name,
            "PrimaryUsagePage": page,
            "PrimaryUsage": usage
        ]
        properties["PhysicalDeviceUniqueID"] = physicalID
        properties["SerialNumber"] = serial
        properties["Transport"] = transport
        properties["VendorID"] = vendorID
        properties["ProductID"] = productID
        properties["LocationID"] = locationID
        return try XCTUnwrap(InputDeviceCatalog.record(
            registryID: registryID,
            properties: properties
        ))
    }
}
