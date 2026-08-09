import Foundation
import IOKit
import IOKit.hid

struct HIDUsagePair: Hashable, Sendable {
    let page: UInt32
    let usage: UInt32
}

struct HIDDeviceRecord: Equatable, Sendable {
    let registryID: UInt64
    let physicalDeviceUniqueID: String?
    let productName: String?
    let manufacturer: String?
    let transport: String?
    let vendorID: UInt64?
    let productID: UInt64?
    let versionNumber: UInt64?
    let locationID: UInt64?
    let serialNumber: String?
    let isBuiltIn: Bool?
    let usagePairs: [HIDUsagePair]
    var batteryReading: HIDDeviceBatteryReading?
}

struct HIDDeviceBatteryReading: Equatable, Sendable {
    let levelPercent: Double
    let source: InputDeviceBatterySource
    let chargingState: InputDeviceChargingState
}

/// Minimal Apple driver metadata used to associate a compatibility battery
/// report without relying on a product name, serial number, or input event.
struct AppleDriverBatteryRecord: Equatable, Sendable {
    let transport: String
    let vendorID: UInt64
    let productID: UInt64
    let locationID: UInt64
    let levelPercent: Double
    let chargingState: InputDeviceChargingState
}

enum InputDeviceCatalog {
    static var batteryUnavailableReason: String {
        TraceHaloLocalization.string(
            "input.battery.unavailable",
            defaultValue: "The device did not report a battery level through compatible Apple driver IORegistry metadata."
        )
    }

    static func record(
        registryID: UInt64,
        properties: [String: Any],
        additionalUsagePairs: [HIDUsagePair] = []
    ) -> HIDDeviceRecord? {
        var usagePairs = Set(usagePairs(from: properties[kIOHIDDeviceUsagePairsKey]))
        if let page = unsignedInteger(properties[kIOHIDPrimaryUsagePageKey]),
           let usage = unsignedInteger(properties[kIOHIDPrimaryUsageKey]),
           let page32 = UInt32(exactly: page),
           let usage32 = UInt32(exactly: usage) {
            usagePairs.insert(HIDUsagePair(page: page32, usage: usage32))
        }
        usagePairs.formUnion(additionalUsagePairs)

        let orderedUsagePairs = usagePairs.sorted {
            if $0.page == $1.page { return $0.usage < $1.usage }
            return $0.page < $1.page
        }
        guard !kinds(for: orderedUsagePairs).isEmpty else { return nil }

        let location = unsignedInteger(properties[kIOHIDLocationIDKey])
        return HIDDeviceRecord(
            registryID: registryID,
            physicalDeviceUniqueID: opaqueIdentifier(text(properties[kIOHIDPhysicalDeviceUniqueIDKey])),
            productName: text(properties[kIOHIDProductKey]),
            manufacturer: text(properties[kIOHIDManufacturerKey]),
            transport: text(properties[kIOHIDTransportKey]),
            vendorID: unsignedInteger(properties[kIOHIDVendorIDKey]),
            productID: unsignedInteger(properties[kIOHIDProductIDKey]),
            versionNumber: unsignedInteger(properties[kIOHIDVersionNumberKey]),
            locationID: location == 0 ? nil : location,
            serialNumber: opaqueIdentifier(text(properties[kIOHIDSerialNumberKey])),
            isBuiltIn: boolean(properties[kIOHIDBuiltInKey]),
            usagePairs: orderedUsagePairs,
            batteryReading: nil
        )
    }

    static func inventory(
        from records: [HIDDeviceRecord],
        appleDriverBatteries: [AppleDriverBatteryRecord] = []
    ) -> InputDeviceInventory {
        let records = applyingAppleDriverBatteryFallbacks(
            appleDriverBatteries,
            to: records
        )
        let physicalRecords = records.filter { record in
            guard let transport = record.transport else { return true }
            return transport.caseInsensitiveCompare(kIOHIDTransportVirtualValue) != .orderedSame
        }
        .sorted { deterministicRecordKey($0) < deterministicRecordKey($1) }

        let keyedRecords = physicalRecords.enumerated().map { index, record in
            (
                key: physicalIdentityKey(record, unidentifiedOrdinal: index),
                record: record
            )
        }
        let grouped = Dictionary(grouping: keyedRecords, by: \.key)
        let devices = grouped.compactMap { identityKey, records in
            makeDevice(identityKey: identityKey, records: records.map(\.record))
        }
        .sorted { lhs, rhs in
            let lhsRank = sortRank(lhs.primaryKind)
            let rhsRank = sortRank(rhs.primaryKind)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return lhs.stableIdentifier < rhs.stableIdentifier
        }

        return InputDeviceInventory(availability: .available, devices: devices)
    }

    /// Applies a compatibility reading only when the Apple driver and HID
    /// registry record share the complete, non-zero physical identity tuple.
    /// Duplicate driver rows must agree on the battery percentage; conflicting
    /// reports are treated as unavailable. Charging conflicts become unknown.
    static func applyingAppleDriverBatteryFallbacks(
        _ batteries: [AppleDriverBatteryRecord],
        to records: [HIDDeviceRecord]
    ) -> [HIDDeviceRecord] {
        let groupedBatteries = Dictionary(grouping: batteries, by: AppleDriverBatteryKey.init)
        let resolvedBatteries = groupedBatteries.compactMapValues { candidates
            -> HIDDeviceBatteryReading? in
            let percentages = Set(candidates.map(\.levelPercent))
            guard percentages.count == 1, let percentage = percentages.first else {
                return nil
            }
            return HIDDeviceBatteryReading(
                levelPercent: percentage,
                source: .appleDriverRegistry,
                chargingState: resolvedChargingState(in: candidates)
            )
        }

        return records.map { record in
            guard record.batteryReading == nil,
                  let key = AppleDriverBatteryKey(record),
                  let fallback = resolvedBatteries[key] else {
                return record
            }
            var updated = record
            updated.batteryReading = fallback
            return updated
        }
    }

    static func kinds(for usagePairs: [HIDUsagePair]) -> [InputDeviceKind] {
        let pairs = Set(usagePairs)
        var result: [InputDeviceKind] = []

        if pairs.contains(HIDUsagePair(
            page: UInt32(kHIDPage_GenericDesktop),
            usage: UInt32(kHIDUsage_GD_Keyboard)
        )) || pairs.contains(HIDUsagePair(
            page: UInt32(kHIDPage_GenericDesktop),
            usage: UInt32(kHIDUsage_GD_Keypad)
        )) {
            result.append(.keyboard)
        }
        if pairs.contains(HIDUsagePair(
            page: UInt32(kHIDPage_GenericDesktop),
            usage: UInt32(kHIDUsage_GD_Mouse)
        )) {
            result.append(.mouse)
        }
        if pairs.contains(HIDUsagePair(
            page: UInt32(kHIDPage_Digitizer),
            usage: UInt32(kHIDUsage_Dig_TouchPad)
        )) {
            result.append(.trackpad)
        }
        if pairs.contains(HIDUsagePair(
            page: UInt32(kHIDPage_GenericDesktop),
            usage: UInt32(kHIDUsage_GD_Pointer)
        )) {
            result.append(.pointingDevice)
        }

        return result
    }

    static func stableIdentifier(for identityKey: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in identityKey.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "hid-%016llx", hash)
    }

    private static func makeDevice(
        identityKey: String,
        records: [HIDDeviceRecord]
    ) -> InputDeviceState? {
        let records = records.sorted { lhs, rhs in
            if lhs.registryID != rhs.registryID { return lhs.registryID < rhs.registryID }
            return deterministicRecordKey(lhs) < deterministicRecordKey(rhs)
        }
        let kindSet = Set(records.flatMap { Self.kinds(for: $0.usagePairs) })
        guard !kindSet.isEmpty else { return nil }
        let orderedKinds = InputDeviceKind.allCases.filter(kindSet.contains)
        let name = bestText(records.compactMap(\.productName))
            ?? fallbackName(for: orderedKinds)
        let batteryReading = records
            .compactMap(\.batteryReading)
            .first
        let battery = batteryReading.map {
            InputDeviceBatteryState(
                availability: .available,
                levelPercent: $0.levelPercent,
                source: $0.source,
                chargingState: $0.chargingState
            )
        } ?? InputDeviceBatteryState(
            availability: .unavailable(reason: batteryUnavailableReason)
        )

        return InputDeviceState(
            stableIdentifier: stableIdentifier(for: identityKey),
            name: name,
            kinds: orderedKinds,
            manufacturer: bestText(records.compactMap(\.manufacturer)),
            transport: bestText(records.compactMap(\.transport)),
            vendorID: records.compactMap(\.vendorID).min(),
            productID: records.compactMap(\.productID).min(),
            versionNumber: records.compactMap(\.versionNumber).min(),
            locationID: records.compactMap(\.locationID).min(),
            serialNumber: bestText(records.compactMap(\.serialNumber)),
            isBuiltIn: mergedBuiltIn(records.compactMap(\.isBuiltIn)),
            battery: battery
        )
    }

    private static func physicalIdentityKey(
        _ record: HIDDeviceRecord,
        unidentifiedOrdinal: Int
    ) -> String {
        let transport = normalizedIdentityText(record.transport) ?? "unknown"
        let vendor = record.vendorID.map(String.init) ?? "unknown"
        let product = record.productID.map(String.init) ?? "unknown"
        let base = "transport:\(transport)|vendor:\(vendor)|product:\(product)"

        if let physicalID = opaqueIdentifier(record.physicalDeviceUniqueID) {
            return "physical:\(physicalID)"
        }
        if let serial = opaqueIdentifier(record.serialNumber) {
            return "serial:\(serial)|\(base)"
        }
        if let locationID = record.locationID {
            return "location:\(locationID)|\(base)"
        }
        if record.registryID != 0 {
            return "registry:\(record.registryID)"
        }

        return "unidentified:\(unidentifiedOrdinal)"
    }

    private static func deterministicRecordKey(_ record: HIDDeviceRecord) -> String {
        let usages = record.usagePairs
            .map { "\($0.page):\($0.usage)" }
            .joined(separator: ",")
        var components: [String] = []
        components.append(opaqueIdentifier(record.physicalDeviceUniqueID) ?? "")
        components.append(opaqueIdentifier(record.serialNumber) ?? "")
        components.append(normalizedIdentityText(record.transport) ?? "")
        components.append(record.vendorID.map(String.init) ?? "")
        components.append(record.productID.map(String.init) ?? "")
        components.append(record.versionNumber.map(String.init) ?? "")
        components.append(record.locationID.map(String.init) ?? "")
        components.append(String(record.registryID))
        components.append(normalizedIdentityText(record.productName) ?? "")
        components.append(normalizedIdentityText(record.manufacturer) ?? "")
        components.append(usages)
        components.append(record.batteryReading.map { String($0.levelPercent) } ?? "")
        components.append(record.batteryReading?.source.rawValue ?? "")
        return components.joined(separator: "|")
    }

    private static func usagePairs(from value: Any?) -> [HIDUsagePair] {
        guard let values = value as? [Any] else { return [] }
        return values.compactMap { value in
            guard let dictionary = value as? [String: Any],
                  let page = unsignedInteger(dictionary[kIOHIDDeviceUsagePageKey]),
                  let usage = unsignedInteger(dictionary[kIOHIDDeviceUsageKey]),
                  let page32 = UInt32(exactly: page),
                  let usage32 = UInt32(exactly: usage) else {
                return nil
            }
            return HIDUsagePair(page: page32, usage: usage32)
        }
    }

    private static func text(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func unsignedInteger(_ value: Any?) -> UInt64? {
        if let value = value as? NSNumber, value.int64Value >= 0 {
            return value.uint64Value
        }
        if let value = value as? UInt64 { return value }
        if let value = value as? UInt32 { return UInt64(value) }
        if let value = value as? Int, value >= 0 { return UInt64(value) }
        if let value = value as? Int64, value >= 0 { return UInt64(value) }
        return nil
    }

    private static func boolean(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }

    private static func resolvedChargingState(
        in candidates: [AppleDriverBatteryRecord]
    ) -> InputDeviceChargingState {
        let states = Set(candidates.map(\.chargingState))
        guard states.count == 1 else { return .unknown }
        return states.first ?? .unknown
    }

    private static func normalizedIdentityText(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
        return normalized.isEmpty ? nil : normalized
    }

    /// Physical IDs and serials are opaque driver-provided values. Their case
    /// and diacritics are significant, so only surrounding whitespace and
    /// known placeholder values are removed.
    private static func opaqueIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let placeholder = trimmed.lowercased()
        let placeholders: Set<String> = [
            "0", "0x0", "unknown", "none", "n/a", "na", "null", "-",
            "unavailable", "not available", "未提供", "未知"
        ]
        guard !placeholders.contains(placeholder) else { return nil }
        let digits = trimmed.filter(\.isNumber)
        if !digits.isEmpty,
           digits.count == trimmed.count,
           digits.allSatisfy({ $0 == "0" }) {
            return nil
        }
        return trimmed
    }

    private static func bestText(_ values: [String]) -> String? {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
            .first
    }

    private static func mergedBuiltIn(_ values: [Bool]) -> Bool? {
        if values.contains(true) { return true }
        if values.contains(false) { return false }
        return nil
    }

    private static func fallbackName(for kinds: [InputDeviceKind]) -> String {
        if kinds.contains(.trackpad) {
            return TraceHaloLocalization.string("input.unnamed.trackpad", defaultValue: "Unnamed Trackpad")
        }
        if kinds.contains(.mouse) {
            return TraceHaloLocalization.string("input.unnamed.mouse", defaultValue: "Unnamed Mouse")
        }
        if kinds.contains(.keyboard) {
            return TraceHaloLocalization.string("input.unnamed.keyboard", defaultValue: "Unnamed Keyboard")
        }
        return TraceHaloLocalization.string("input.unnamed.pointer", defaultValue: "Unnamed Pointing Device")
    }

    private static func sortRank(_ kind: InputDeviceKind) -> Int {
        switch kind {
        case .keyboard: 0
        case .mouse: 1
        case .trackpad: 2
        case .pointingDevice: 3
        }
    }

    private struct AppleDriverBatteryKey: Hashable {
        let transport: String
        let vendorID: UInt64
        let productID: UInt64
        let locationID: UInt64

        init(_ battery: AppleDriverBatteryRecord) {
            transport = Self.normalizedTransport(battery.transport)
            vendorID = battery.vendorID
            productID = battery.productID
            locationID = battery.locationID
        }

        init?(_ record: HIDDeviceRecord) {
            guard let transport = record.transport,
                  let vendorID = record.vendorID,
                  let productID = record.productID,
                  let locationID = record.locationID,
                  vendorID != 0,
                  productID != 0,
                  locationID != 0 else {
                return nil
            }
            self.transport = Self.normalizedTransport(transport)
            self.vendorID = vendorID
            self.productID = productID
            self.locationID = locationID
        }

        private static func normalizedTransport(_ value: String) -> String {
            value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                )
        }
    }
}

/// Enumerates selected IORegistry metadata from IOHIDDevice services. It does
/// not create an IOHIDManager, open a device, inspect HID elements, or register
/// input callbacks, so this path does not require Input Monitoring permission.
enum InputDeviceInventoryReader {
    static func read() -> InputDeviceInventory {
        guard let matching = IOServiceMatching(serviceClass) else {
            return InputDeviceInventory(availability: .available)
        }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            matching,
            &iterator
        ) == KERN_SUCCESS else {
            return InputDeviceInventory(availability: .available)
        }
        defer { IOObjectRelease(iterator) }

        var records: [HIDDeviceRecord] = []
        var service = IOIteratorNext(iterator)
        while service != IO_OBJECT_NULL {
            if let record = record(for: service) {
                records.append(record)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return InputDeviceCatalog.inventory(
            from: records,
            appleDriverBatteries: AppleDriverBatteryRegistryReader.read()
        )
    }

    private static let serviceClass = "IOHIDDevice"

    private static let propertyKeys = [
        kIOHIDTransportKey,
        kIOHIDVendorIDKey,
        kIOHIDProductIDKey,
        kIOHIDVersionNumberKey,
        kIOHIDManufacturerKey,
        kIOHIDProductKey,
        kIOHIDSerialNumberKey,
        kIOHIDLocationIDKey,
        kIOHIDDeviceUsagePairsKey,
        kIOHIDPrimaryUsageKey,
        kIOHIDPrimaryUsagePageKey,
        kIOHIDBuiltInKey,
        kIOHIDPhysicalDeviceUniqueIDKey
    ]

    private static func record(for service: io_service_t) -> HIDDeviceRecord? {
        let properties = Dictionary(
            uniqueKeysWithValues: propertyKeys.compactMap { key in
                registryProperty(service: service, key: key).map { (key, $0) }
            }
        )
        return InputDeviceCatalog.record(
            registryID: registryIdentifier(for: service),
            properties: properties
        )
    }

    private static func registryProperty(service: io_service_t, key: String) -> Any? {
        IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue()
    }

    private static func registryIdentifier(for service: io_service_t) -> UInt64 {
        var identifier: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(service, &identifier) == kIOReturnSuccess else {
            return 0
        }
        return identifier
    }
}

/// Compatibility reader for rechargeable Apple input devices whose public HID
/// battery element is unavailable. It performs a read-only IORegistry query;
/// it never opens a HID device, registers callbacks, or reads input reports.
enum AppleDriverBatteryRegistryReader {
    private static let serviceClass = "AppleDeviceManagementHIDEventService"
    private static let batteryPercentKey = "BatteryPercent"
    private static let batteryStatusFlagsKey = "BatteryStatusFlags"
    private static let isChargingKey = "IsCharging"
    private static let spacedIsChargingKey = "Is Charging"

    static func read() -> [AppleDriverBatteryRecord] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching(serviceClass),
            &iterator
        ) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var records: [AppleDriverBatteryRecord] = []
        var service = IOIteratorNext(iterator)
        while service != IO_OBJECT_NULL {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            let properties = Dictionary(
                uniqueKeysWithValues: registryPropertyKeys.compactMap { key in
                    registryProperty(service: service, key: key).map { (key, $0) }
                }
            )
            guard let record = record(from: properties) else {
                continue
            }
            records.append(record)
        }
        return records
    }

    /// Fetches only identity, battery, and explicit charging-state values used
    /// by the compatibility path.
    /// `IORegistryEntryCreateCFProperty` returns a retained value, transferred
    /// here with `takeRetainedValue`; no unrelated registry properties (such as
    /// serial numbers or device addresses) are copied into this process.
    private static func registryProperty(service: io_service_t, key: String) -> Any? {
        IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue()
    }

    private static let registryPropertyKeys = [
        kIOHIDTransportKey,
        kIOHIDVendorIDKey,
        kIOHIDProductIDKey,
        kIOHIDLocationIDKey,
        batteryPercentKey,
        batteryStatusFlagsKey,
        isChargingKey,
        spacedIsChargingKey
    ]

    static func record(from properties: [String: Any]) -> AppleDriverBatteryRecord? {
        guard let transport = text(properties[kIOHIDTransportKey]),
              let vendorID = unsignedInteger(properties[kIOHIDVendorIDKey]),
              let productID = unsignedInteger(properties[kIOHIDProductIDKey]),
              let locationID = unsignedInteger(properties[kIOHIDLocationIDKey]),
              let batteryPercent = number(properties[batteryPercentKey]),
              vendorID != 0,
              productID != 0,
              locationID != 0,
              batteryPercent.isFinite,
              (0...100).contains(batteryPercent) else {
            return nil
        }
        return AppleDriverBatteryRecord(
            transport: transport,
            vendorID: vendorID,
            productID: productID,
            locationID: locationID,
            levelPercent: batteryPercent,
            chargingState: chargingState(from: properties)
        )
    }

    /// Apple input drivers can publish either one of the system charging
    /// booleans or a private `BatteryStatusFlags` value. Boolean keys are used
    /// directly. For the flags field, only combinations verified on the Apple
    /// driver path are decoded: 0 means no charging flags, while 3 together
    /// with USB transport is emitted by a wired, charging Magic Trackpad.
    /// Other bit patterns or transport combinations remain unknown.
    static func chargingState(from properties: [String: Any]) -> InputDeviceChargingState {
        for key in [isChargingKey, spacedIsChargingKey] {
            if let value = boolean(properties[key]) {
                return value ? .charging : .notCharging
            }
        }
        guard let flags = unsignedInteger(properties[batteryStatusFlagsKey]) else {
            return .unknown
        }
        return switch flags {
        case 0: .notCharging
        case 3 where text(properties[kIOHIDTransportKey])?
            .caseInsensitiveCompare("USB") == .orderedSame:
            .charging
        default: .unknown
        }
    }

    private static func text(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func unsignedInteger(_ value: Any?) -> UInt64? {
        if let value = value as? NSNumber, value.int64Value >= 0 {
            return value.uint64Value
        }
        if let value = value as? UInt64 { return value }
        if let value = value as? UInt32 { return UInt64(value) }
        if let value = value as? Int, value >= 0 { return UInt64(value) }
        if let value = value as? Int64, value >= 0 { return UInt64(value) }
        return nil
    }

    private static func boolean(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        guard let value = value as? NSNumber else { return nil }
        return switch value.intValue {
        case 0: false
        case 1: true
        default: nil
        }
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? UInt { return Double(value) }
        return nil
    }
}
