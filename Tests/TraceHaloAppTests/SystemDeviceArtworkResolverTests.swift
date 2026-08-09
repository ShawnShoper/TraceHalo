import Foundation
import XCTest
@testable import TraceHaloApp

final class SystemDeviceArtworkResolverTests: XCTestCase {
    func testDirectModelMappingResolvesDeclaredSystemIcon() throws {
        let resourcesURL = URL(fileURLWithPath: "/fixture/CoreTypes.bundle/Contents/Resources")
        let declarations = SystemDeviceTypeDeclarationParser.declarations(
            in: [
                "UTExportedTypeDeclarations": [
                    [
                        "UTTypeIdentifier": "com.apple.macstudio",
                        "UTTypeDescription": "Mac Studio",
                        "UTTypeIcons": [
                            "UTTypeIconFile": "com.apple.macstudio.icns",
                            "UTTypeSymbolName": "macstudio"
                        ],
                        "UTTypeTagSpecification": [
                            "com.apple.device-model-code": ["Mac13,1", "Mac13,2"]
                        ]
                    ]
                ]
            ],
            resourcesDirectory: resourcesURL
        )

        let selection = SystemDeviceArtworkCatalog(declarations: declarations).selection(
            modelIdentifier: "Mac13,2",
            modelName: "Mac13,2"
        )

        XCTAssertEqual(selection.family, .macStudio)
        XCTAssertEqual(selection.symbolName, "macstudio")
        XCTAssertEqual(
            selection.iconURL,
            resourcesURL.appendingPathComponent("com.apple.macstudio.icns")
        )
    }

    func testM4MacBookFollowsTypeInheritanceToSystemMacBookIcon() throws {
        let modernResourcesURL = URL(fileURLWithPath: "/fixture/CoreTypes-0020.bundle/Contents/Resources")
        let baseResourcesURL = URL(fileURLWithPath: "/fixture/CoreTypes.bundle/Contents/Resources")

        let modernDeclarations = SystemDeviceTypeDeclarationParser.declarations(
            in: [
                "UTExportedTypeDeclarations": [
                    [
                        "UTTypeIdentifier": "com.apple.macbookpro-14-2024",
                        "UTTypeConformsTo": "com.apple.macbookpro-14-2021",
                        "UTTypeTagSpecification": [
                            "com.apple.device-model-code": ["Mac16,1"]
                        ]
                    ]
                ]
            ],
            resourcesDirectory: modernResourcesURL
        )
        let baseDeclarations = SystemDeviceTypeDeclarationParser.declarations(
            in: [
                "UTImportedTypeDeclarations": [
                    [
                        "UTTypeIdentifier": "com.apple.macbookpro-14-2021",
                        "UTTypeDescription": "MacBook Pro",
                        "UTTypeIcons": [
                            "UTTypeIconFile": "com.apple.macbookpro-14-2021-silver.icns"
                        ]
                    ]
                ]
            ],
            resourcesDirectory: baseResourcesURL
        )

        let selection = SystemDeviceArtworkCatalog(
            declarations: modernDeclarations + baseDeclarations
        )
        .selection(modelIdentifier: "Mac16,1", modelName: "MacBook")

        XCTAssertEqual(selection.family, .macBook)
        XCTAssertEqual(selection.symbolName, "macbook")
        XCTAssertEqual(
            selection.iconURL,
            baseResourcesURL.appendingPathComponent("com.apple.macbookpro-14-2021-silver.icns")
        )
        XCTAssertFalse(selection.iconURL?.lastPathComponent.contains("macstudio") == true)
    }

    func testExactColorModelCodeWinsOverGenericModelCode() throws {
        let genericResourcesURL = URL(fileURLWithPath: "/fixture/generic/Resources")
        let colorResourcesURL = URL(fileURLWithPath: "/fixture/color/Resources")
        let generic = declaration(
            identifier: "com.apple.macbookair-2025",
            modelCode: "Mac16,12",
            iconFile: "generic.icns",
            resourcesDirectory: genericResourcesURL
        )
        let color = declaration(
            identifier: "com.apple.macbookair-2025-sky-blue",
            modelCode: "Mac16,12@ECOLOR=11",
            iconFile: "sky-blue.icns",
            resourcesDirectory: colorResourcesURL
        )

        let catalog = SystemDeviceArtworkCatalog(declarations: [generic, color])

        XCTAssertEqual(
            catalog.selection(
                modelIdentifier: "Mac16,12@ECOLOR=11",
                modelName: "MacBook Air"
            ).iconURL,
            colorResourcesURL.appendingPathComponent("sky-blue.icns")
        )
        XCTAssertEqual(
            catalog.selection(modelIdentifier: "Mac16,12", modelName: "MacBook Air").iconURL,
            genericResourcesURL.appendingPathComponent("generic.icns")
        )
    }

    func testUnknownModelFallsBackByDeviceFamilyWithoutInventingStudioArtwork() {
        let selection = SystemDeviceArtworkCatalog(declarations: []).selection(
            modelIdentifier: "FutureMac99,1",
            modelName: "MacBook Pro"
        )

        XCTAssertEqual(selection.family, .macBook)
        XCTAssertEqual(selection.symbolName, "macbook")
        XCTAssertNil(selection.iconURL)
    }

    func testConformanceCycleTerminatesWithFamilyFallback() {
        let resourcesURL = URL(fileURLWithPath: "/fixture/Resources")
        let first = SystemDeviceTypeDeclaration(
            identifier: "com.apple.macbook.future",
            description: "MacBook",
            modelCodes: ["Mac99,1"],
            conformingTypeIdentifiers: ["com.apple.macbook.future-parent"],
            iconFileName: nil,
            symbolName: nil,
            resourcesDirectory: resourcesURL
        )
        let second = SystemDeviceTypeDeclaration(
            identifier: "com.apple.macbook.future-parent",
            description: nil,
            modelCodes: [],
            conformingTypeIdentifiers: ["com.apple.macbook.future"],
            iconFileName: nil,
            symbolName: nil,
            resourcesDirectory: resourcesURL
        )

        let selection = SystemDeviceArtworkCatalog(declarations: [first, second]).selection(
            modelIdentifier: "Mac99,1",
            modelName: "MacBook"
        )

        XCTAssertEqual(selection.symbolName, "macbook")
        XCTAssertNil(selection.iconURL)
    }

    private func declaration(
        identifier: String,
        modelCode: String,
        iconFile: String,
        resourcesDirectory: URL
    ) -> SystemDeviceTypeDeclaration {
        SystemDeviceTypeDeclaration(
            identifier: identifier,
            description: nil,
            modelCodes: [modelCode],
            conformingTypeIdentifiers: [],
            iconFileName: iconFile,
            symbolName: nil,
            resourcesDirectory: resourcesDirectory
        )
    }
}
