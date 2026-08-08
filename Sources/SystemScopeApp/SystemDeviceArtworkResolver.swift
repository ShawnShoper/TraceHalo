import AppKit
import Foundation

enum SystemDeviceFamily: String, Equatable, Sendable {
    case macBook
    case macMini
    case macStudio
    case iMac
    case macPro
    case mac

    var fallbackSymbolName: String {
        switch self {
        case .macBook:
            "macbook"
        case .macMini:
            "macmini"
        case .macStudio:
            "macstudio"
        case .iMac:
            "desktopcomputer"
        case .macPro:
            "macpro.gen3"
        case .mac:
            "desktopcomputer"
        }
    }

    static func infer(
        typeIdentifier: String?,
        typeDescription: String?,
        modelName: String
    ) -> SystemDeviceFamily {
        let evidence = [typeIdentifier, typeDescription, modelName]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        if evidence.contains("macbook") || evidence.contains("notebook") {
            return .macBook
        }
        if evidence.contains("macstudio") || evidence.contains("mac studio") {
            return .macStudio
        }
        if evidence.contains("macmini") || evidence.contains("mac mini") {
            return .macMini
        }
        if evidence.contains("imac") {
            return .iMac
        }
        if evidence.contains("macpro") || evidence.contains("mac pro") {
            return .macPro
        }
        return .mac
    }
}

struct SystemDeviceArtworkSelection: Equatable, Sendable {
    let iconURL: URL?
    let symbolName: String
    let family: SystemDeviceFamily
}

struct SystemDeviceTypeDeclaration: Equatable, Sendable {
    let identifier: String
    let description: String?
    let modelCodes: [String]
    let conformingTypeIdentifiers: [String]
    let iconFileName: String?
    let symbolName: String?
    let resourcesDirectory: URL
}

enum SystemDeviceTypeDeclarationParser {
    static func declarations(
        in infoDictionary: [String: Any],
        resourcesDirectory: URL
    ) -> [SystemDeviceTypeDeclaration] {
        let declarationKeys = ["UTExportedTypeDeclarations", "UTImportedTypeDeclarations"]

        return declarationKeys.flatMap { key -> [SystemDeviceTypeDeclaration] in
            guard let rawDeclarations = infoDictionary[key] as? [Any] else { return [] }
            return rawDeclarations.compactMap { value in
                guard let dictionary = value as? [String: Any],
                      let identifier = nonEmptyString(dictionary["UTTypeIdentifier"])
                else { return nil }

                let tagSpecification = dictionary["UTTypeTagSpecification"] as? [String: Any]
                let icons = dictionary["UTTypeIcons"] as? [String: Any]

                return SystemDeviceTypeDeclaration(
                    identifier: identifier,
                    description: nonEmptyString(dictionary["UTTypeDescription"]),
                    modelCodes: strings(tagSpecification?["com.apple.device-model-code"]),
                    conformingTypeIdentifiers: strings(dictionary["UTTypeConformsTo"]),
                    iconFileName: nonEmptyString(icons?["UTTypeIconFile"]),
                    symbolName: nonEmptyString(icons?["UTTypeSymbolName"]),
                    resourcesDirectory: resourcesDirectory
                )
            }
        }
    }

    private static func strings(_ value: Any?) -> [String] {
        if let string = nonEmptyString(value) {
            return [string]
        }
        guard let values = value as? [Any] else { return [] }
        return values.compactMap(nonEmptyString)
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct SystemDeviceArtworkCatalog: Sendable {
    private let declarationsByIdentifier: [String: [SystemDeviceTypeDeclaration]]
    private let declarationsByModelCode: [String: [SystemDeviceTypeDeclaration]]
    private let declarationsByBaseModelCode: [String: [SystemDeviceTypeDeclaration]]

    init(declarations: [SystemDeviceTypeDeclaration]) {
        declarationsByIdentifier = Dictionary(grouping: declarations) {
            Self.normalized($0.identifier)
        }
        declarationsByModelCode = Dictionary(
            grouping: declarations.flatMap { declaration in
                declaration.modelCodes.map { (Self.normalized($0), declaration) }
            },
            by: \.0
        )
        .mapValues { $0.map(\.1) }
        declarationsByBaseModelCode = Dictionary(
            grouping: declarations.flatMap { declaration in
                declaration.modelCodes.map { (Self.baseModelCode($0), declaration) }
            },
            by: \.0
        )
        .mapValues { $0.map(\.1) }
    }

    func selection(modelIdentifier: String, modelName: String) -> SystemDeviceArtworkSelection {
        let normalizedModelIdentifier = Self.normalized(modelIdentifier)
        let exactMatches = declarationsByModelCode[normalizedModelIdentifier] ?? []
        let candidates = exactMatches.isEmpty
            ? declarationsByBaseModelCode[Self.baseModelCode(modelIdentifier)] ?? []
            : exactMatches

        for candidate in candidates {
            let family = SystemDeviceFamily.infer(
                typeIdentifier: candidate.identifier,
                typeDescription: candidate.description,
                modelName: modelName
            )
            if let visual = inheritedVisual(startingAt: candidate.identifier) {
                return SystemDeviceArtworkSelection(
                    iconURL: visual.iconFileName.map {
                        Self.iconURL(fileName: $0, resourcesDirectory: visual.resourcesDirectory)
                    },
                    symbolName: visual.symbolName ?? family.fallbackSymbolName,
                    family: family
                )
            }
        }

        let firstCandidate = candidates.first
        let family = SystemDeviceFamily.infer(
            typeIdentifier: firstCandidate?.identifier,
            typeDescription: firstCandidate?.description,
            modelName: modelName
        )
        return SystemDeviceArtworkSelection(
            iconURL: nil,
            symbolName: family.fallbackSymbolName,
            family: family
        )
    }

    private func inheritedVisual(startingAt identifier: String) -> SystemDeviceTypeDeclaration? {
        var pendingIdentifiers = [identifier]
        var visitedIdentifiers = Set<String>()
        var symbolDeclaration: SystemDeviceTypeDeclaration?

        while let nextIdentifier = pendingIdentifiers.first {
            pendingIdentifiers.removeFirst()
            let normalizedIdentifier = Self.normalized(nextIdentifier)
            guard visitedIdentifiers.insert(normalizedIdentifier).inserted else { continue }

            let matchingDeclarations = declarationsByIdentifier[normalizedIdentifier] ?? []
            if let iconDeclaration = matchingDeclarations.first(where: { $0.iconFileName != nil }) {
                return iconDeclaration
            }
            if symbolDeclaration == nil {
                symbolDeclaration = matchingDeclarations.first(where: { $0.symbolName != nil })
            }
            pendingIdentifiers.append(
                contentsOf: matchingDeclarations.flatMap(\.conformingTypeIdentifiers)
            )
        }
        return symbolDeclaration
    }

    private static func iconURL(fileName: String, resourcesDirectory: URL) -> URL {
        let fileURL = resourcesDirectory.appendingPathComponent(fileName, isDirectory: false)
        return fileURL.pathExtension.isEmpty
            ? fileURL.appendingPathExtension("icns")
            : fileURL
    }

    private static func baseModelCode(_ value: String) -> String {
        let normalizedValue = normalized(value)
        return normalizedValue.split(separator: "@", maxSplits: 1).first.map(String.init)
            ?? normalizedValue
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum SystemCoreTypesArtworkCatalogLoader {
    static let defaultBundleURL = URL(
        fileURLWithPath: "/System/Library/CoreServices/CoreTypes.bundle",
        isDirectory: true
    )

    static func load(bundleURL: URL = defaultBundleURL) -> SystemDeviceArtworkCatalog {
        let fileManager = FileManager.default
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        var infoURLs = [contentsURL.appendingPathComponent("Info.plist", isDirectory: false)]
        let libraryURL = contentsURL.appendingPathComponent("Library", isDirectory: true)

        if let childURLs = try? fileManager.contentsOfDirectory(
            at: libraryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for childURL in childURLs where childURL.pathExtension == "bundle" {
                let standardInfoURL = childURL
                    .appendingPathComponent("Contents", isDirectory: true)
                    .appendingPathComponent("Info.plist", isDirectory: false)
                let flatInfoURL = childURL.appendingPathComponent("Info.plist", isDirectory: false)
                if fileManager.fileExists(atPath: standardInfoURL.path) {
                    infoURLs.append(standardInfoURL)
                } else if fileManager.fileExists(atPath: flatInfoURL.path) {
                    infoURLs.append(flatInfoURL)
                }
            }
        }

        let declarations = infoURLs
            .sorted { $0.path < $1.path }
            .flatMap { infoURL -> [SystemDeviceTypeDeclaration] in
                guard let data = try? Data(contentsOf: infoURL),
                      let propertyList = try? PropertyListSerialization.propertyList(
                          from: data,
                          options: [],
                          format: nil
                      ),
                      let infoDictionary = propertyList as? [String: Any]
                else { return [] }

                let resourcesDirectory = infoURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("Resources", isDirectory: true)
                return SystemDeviceTypeDeclarationParser.declarations(
                    in: infoDictionary,
                    resourcesDirectory: resourcesDirectory
                )
            }

        return SystemDeviceArtworkCatalog(declarations: declarations)
    }
}

struct ResolvedSystemDeviceArtwork {
    let image: NSImage?
    let symbolName: String
}

@MainActor
final class SystemDeviceArtworkResolver {
    static let shared = SystemDeviceArtworkResolver(
        catalog: SystemCoreTypesArtworkCatalogLoader.load()
    )

    private let catalog: SystemDeviceArtworkCatalog
    private var imagesByURL: [URL: NSImage] = [:]
    private var unavailableImageURLs = Set<URL>()

    init(catalog: SystemDeviceArtworkCatalog) {
        self.catalog = catalog
    }

    func artwork(modelIdentifier: String, modelName: String) -> ResolvedSystemDeviceArtwork {
        let selection = catalog.selection(
            modelIdentifier: modelIdentifier,
            modelName: modelName
        )
        guard let iconURL = selection.iconURL else {
            return ResolvedSystemDeviceArtwork(image: nil, symbolName: selection.symbolName)
        }
        if let cachedImage = imagesByURL[iconURL] {
            return ResolvedSystemDeviceArtwork(
                image: cachedImage,
                symbolName: selection.symbolName
            )
        }
        guard !unavailableImageURLs.contains(iconURL),
              let image = NSImage(contentsOf: iconURL)
        else {
            unavailableImageURLs.insert(iconURL)
            return ResolvedSystemDeviceArtwork(image: nil, symbolName: selection.symbolName)
        }

        image.isTemplate = false
        imagesByURL[iconURL] = image
        return ResolvedSystemDeviceArtwork(image: image, symbolName: selection.symbolName)
    }
}
