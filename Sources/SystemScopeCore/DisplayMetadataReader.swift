import AppKit
import CoreGraphics
import Foundation
import IOKit
import IOKit.graphics

struct IODisplayRecord: Equatable, Sendable {
    var registryID: UInt64
    var vendorID: UInt32
    var productID: UInt32
    var serialNumber: UInt32?
    var productName: String?
}

/// Best-effort display identity using public AppKit, CoreGraphics, and IOKit APIs.
/// AppKit supplies the user-visible device name while IOKit is retained as a
/// fallback for older display stacks that publish `IODisplayConnect` records.
enum DisplayMetadataReader {
    @MainActor
    static func appKitNamesByDisplayID() -> [CGDirectDisplayID: String] {
        var result: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            guard
                let number = screen.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")
                ] as? NSNumber
            else {
                continue
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            guard displayID != kCGNullDirectDisplay else { continue }
            if let name = normalizedName(screen.localizedName) {
                result[displayID] = name
            }
        }
        return result
    }

    static func readIOKitRecords() -> [IODisplayRecord] {
        var iterator: io_iterator_t = 0
        guard
            IOServiceGetMatchingServices(
                kIOMainPortDefault,
                IOServiceMatching("IODisplayConnect"),
                &iterator
            ) == KERN_SUCCESS
        else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var records: [IODisplayRecord] = []
        var service = IOIteratorNext(iterator)
        while service != IO_OBJECT_NULL {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            guard
                let unmanagedInfo = IODisplayCreateInfoDictionary(
                    service,
                    IOOptionBits(kIODisplayOnlyPreferredName)
                )
            else {
                continue
            }
            let info = unmanagedInfo.takeRetainedValue() as NSDictionary
            guard
                let vendor = info[kDisplayVendorID] as? NSNumber,
                let product = info[kDisplayProductID] as? NSNumber
            else {
                continue
            }

            var registryID: UInt64 = 0
            if IORegistryEntryGetRegistryEntryID(service, &registryID) != KERN_SUCCESS {
                registryID = 0
            }
            let rawSerial = (info[kDisplaySerialNumber] as? NSNumber)?.uint32Value
            records.append(IODisplayRecord(
                registryID: registryID,
                vendorID: vendor.uint32Value,
                productID: product.uint32Value,
                serialNumber: rawSerial.flatMap { $0 == 0 ? nil : $0 },
                productName: preferredProductName(info[kDisplayProductName])
            ))
        }
        return records
    }

    static func matchingRecord(
        vendorID: UInt32,
        productID: UInt32,
        serialNumber: UInt32,
        records: [IODisplayRecord]
    ) -> IODisplayRecord? {
        let candidates = records.filter {
            $0.vendorID == vendorID && $0.productID == productID
        }
        if serialNumber != 0,
           let exact = candidates.first(where: { $0.serialNumber == serialNumber })
        {
            return exact
        }
        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1 { return candidates[0] }

        let distinctNames = Set(candidates.compactMap(\.productName))
        guard distinctNames.count == 1 else { return nil }
        return candidates.first(where: { $0.productName != nil })
    }

    static func resolvedName(
        appKitName: String?,
        ioKitName: String?,
        isBuiltIn: Bool,
        vendorID: UInt32,
        productID: UInt32
    ) -> String {
        if let appKitName = normalizedName(appKitName) { return appKitName }
        if let ioKitName = normalizedName(ioKitName) { return ioKitName }
        if isBuiltIn {
            return TraceHaloLocalization.string(
                "display.builtin",
                defaultValue: "Built-in Display"
            )
        }
        if vendorID != 0 || productID != 0 {
            return TraceHaloLocalization.format(
                "display.external.identifier",
                defaultValue: "External Display %04X:%04X",
                Int(vendorID), Int(productID)
            )
        }
        return TraceHaloLocalization.string(
            "display.external",
            defaultValue: "External Display"
        )
    }

    static func preferredProductName(_ value: Any?) -> String? {
        guard let localizedNames = value as? [String: String], !localizedNames.isEmpty else {
            return nil
        }
        let localizations = localizedNames.keys.sorted()
        if let preferred = Bundle.preferredLocalizations(from: localizations).first,
           let name = normalizedName(localizedNames[preferred])
        {
            return name
        }
        return localizedNames.values.compactMap(normalizedName).sorted().first
    }

    private static func normalizedName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
