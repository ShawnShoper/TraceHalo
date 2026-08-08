import Testing
@testable import SystemScopeCore

@Suite("Display metadata")
struct DisplayMetadataReaderTests {
    @Test("decodes one localized IOKit product name")
    func decodesLocalizedProductName() {
        #expect(DisplayMetadataReader.preferredProductName([
            "en_US": "  Studio Display  "
        ]) == "Studio Display")
        #expect(DisplayMetadataReader.preferredProductName([String: String]()) == nil)
    }

    @Test("uses serial number to distinguish identical display models")
    func matchesExactSerialNumber() {
        let records = [
            IODisplayRecord(
                registryID: 1,
                vendorID: 0x0610,
                productID: 0xA064,
                serialNumber: 101,
                productName: "Studio Display A"
            ),
            IODisplayRecord(
                registryID: 2,
                vendorID: 0x0610,
                productID: 0xA064,
                serialNumber: 202,
                productName: "Studio Display B"
            )
        ]

        #expect(DisplayMetadataReader.matchingRecord(
            vendorID: 0x0610,
            productID: 0xA064,
            serialNumber: 202,
            records: records
        )?.registryID == 2)
        #expect(DisplayMetadataReader.matchingRecord(
            vendorID: 0x0610,
            productID: 0xA064,
            serialNumber: 0,
            records: records
        ) == nil)
    }

    @Test("falls back to public name then stable hardware identifiers")
    func resolvesBestAvailableName() {
        #expect(DisplayMetadataReader.resolvedName(
            appKitName: " Apple Studio Display ",
            ioKitName: "Studio Display",
            isBuiltIn: false,
            vendorID: 0x0610,
            productID: 0xA064
        ) == "Apple Studio Display")
        #expect(DisplayMetadataReader.resolvedName(
            appKitName: nil,
            ioKitName: nil,
            isBuiltIn: false,
            vendorID: 0x1234,
            productID: 0x5678
        ) == "外接显示器 1234:5678")
    }

    @Test("keeps effective resolution and physical pixels distinct")
    func separatesPointsFromPixelsAndKeepsIDsUnique() {
        let first = DisplayDevice(
            name: "Studio Display",
            resolution: "2560 × 1440",
            displayID: 1,
            pixelDimensions: "5120 × 2880 像素"
        )
        let second = DisplayDevice(
            name: "Studio Display",
            resolution: "2560 × 1440",
            displayID: 2,
            pixelDimensions: "5120 × 2880 像素"
        )

        #expect(first.resolution == "2560 × 1440")
        #expect(first.pixelDimensions == "5120 × 2880 像素")
        #expect(first.id != second.id)
    }
}
