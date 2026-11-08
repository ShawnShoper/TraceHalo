import Darwin
import Foundation

private func scanningText(_ key: String, _ defaultValue: String) -> String {
    TraceHaloLocalization.string(key, defaultValue: defaultValue)
}

private func scanningFormat(
    _ key: String,
    _ defaultValue: String,
    _ arguments: CVarArg...
) -> String {
    TraceHaloLocalization.format(
        key,
        defaultValue: defaultValue,
        arguments: arguments
    )
}

public protocol StartupItemProviding: Sendable {
    func items() async throws -> [StartupItem]
}

public protocol ApplicationProviding: Sendable {
    func applications() async throws -> [ApplicationCandidate]
    func enrichedApplication(_ application: ApplicationCandidate) async -> ApplicationCandidate
    func sizeBytes(for application: ApplicationCandidate) async -> UInt64?
}

public extension ApplicationProviding {
    func enrichedApplication(_ application: ApplicationCandidate) async -> ApplicationCandidate {
        application
    }

    func sizeBytes(for application: ApplicationCandidate) async -> UInt64? {
        application.sizeBytes
    }
}

/// Read-only scanner for launchd property lists and legacy Login Items metadata.
public struct StartupItemScanner: StartupItemProviding, Sendable {
    private struct SearchDirectory: Sendable {
        var URL: URL
        var kind: StartupItemKind
        var scope: StartupItemScope
    }

    private let homeDirectory: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    public func items() async throws -> [StartupItem] {
        try await Task.detached(priority: .utility) {
            try scan()
        }.value
    }

    public func scan() throws -> [StartupItem] {
        var result: [StartupItem] = []
        let disabledOverrides = launchctlDisabledOverrides()
        for searchDirectory in searchDirectories {
            result.append(contentsOf: try scanLaunchItems(
                in: searchDirectory,
                disabledOverrides: disabledOverrides
            ))
        }
        result.append(contentsOf: scanLegacyLoginItems())

        var paths = Set<String>()
        return result
            .filter { paths.insert($0.path).inserted }
            .sorted { lhs, rhs in
                if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
    }

    private var searchDirectories: [SearchDirectory] {
        [
            SearchDirectory(
                URL: homeDirectory.appendingPathComponent("Library/LaunchAgents", isDirectory: true),
                kind: .launchAgent,
                scope: .currentUser
            ),
            SearchDirectory(
                URL: URL(fileURLWithPath: "/Library/LaunchAgents", isDirectory: true),
                kind: .launchAgent,
                scope: .allUsers
            ),
            SearchDirectory(
                URL: URL(fileURLWithPath: "/Library/LaunchDaemons", isDirectory: true),
                kind: .launchDaemon,
                scope: .system
            ),
            SearchDirectory(
                URL: URL(fileURLWithPath: "/System/Library/LaunchAgents", isDirectory: true),
                kind: .launchAgent,
                scope: .macOS
            ),
            SearchDirectory(
                URL: URL(fileURLWithPath: "/System/Library/LaunchDaemons", isDirectory: true),
                kind: .launchDaemon,
                scope: .macOS
            )
        ]
    }

    private func scanLaunchItems(
        in directory: SearchDirectory,
        disabledOverrides: [String: Bool]
    ) throws -> [StartupItem] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.URL.path) else { return [] }
        let contents = try fileManager.contentsOfDirectory(
            at: directory.URL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )

        return contents.compactMap { url -> StartupItem? in
            guard url.pathExtension.lowercased() == "plist" else { return nil }
            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
            guard
                let propertyList = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                let dictionary = propertyList as? [String: Any]
            else {
                return nil
            }

            let label = nonemptyString(dictionary["Label"]) ?? url.deletingPathExtension().lastPathComponent
            let program = nonemptyString(dictionary["Program"])
                ?? (dictionary["ProgramArguments"] as? [String])?.first
            let displayName = program.map { Foundation.URL(fileURLWithPath: $0).lastPathComponent }
                .flatMap { $0.isEmpty ? nil : $0 }
                ?? label
            let disabled = disabledOverrides[label] ?? bool(dictionary["Disabled"]) ?? false
            let developer = nonemptyString(dictionary["TeamIdentifier"])

            return StartupItem(
                label: label,
                displayName: displayName,
                developer: developer,
                kind: directory.kind,
                path: url.standardizedFileURL.path,
                isEnabled: !disabled,
                scopeKind: directory.scope
            )
        }
    }

    /// `launchctl print-disabled` is read-only and reflects the user's override
    /// database, which is more authoritative than a plist's optional Disabled key.
    private func launchctlDisabledOverrides() -> [String: Bool] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print-disabled", "gui/\(getuid())"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let data: Data
        do {
            try process.run()
            // Drain stdout while launchctl is running. Waiting first can deadlock
            // when the pipe buffer fills on machines with many overrides.
            data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [:] }
        } catch {
            return [:]
        }

        let text = String(decoding: data, as: UTF8.self)
        var result: [String: Bool] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let parts = rawLine.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let label = parts[0]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let value = parts[1]
                .replacingOccurrences(of: ">", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, value == "true" || value == "false" else { continue }
            result[label] = value == "true"
        }
        return result
    }

    /// Reads the legacy per-user list when it exists. Modern background items have
    /// no public enumeration API; launchd entries are still reported above without
    /// requesting Automation or administrator access.
    private func scanLegacyLoginItems() -> [StartupItem] {
        let preferencesURL = homeDirectory
            .appendingPathComponent("Library/Preferences/com.apple.loginitems.plist")
        guard let data = try? Data(contentsOf: preferencesURL, options: [.mappedIfSafe]) else { return [] }
        guard
            let propertyList = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let dictionary = propertyList as? [String: Any],
            let sessionItems = dictionary["SessionItems"] as? [String: Any],
            let customItems = sessionItems["CustomListItems"] as? [[String: Any]]
        else {
            return []
        }

        return customItems.compactMap { item -> StartupItem? in
            let name = nonemptyString(item["Name"])
                ?? scanningText("startup.loginItem.fallbackName", "Login Item")
            guard let path = nonemptyString(item["Path"]), path.hasPrefix("/") else { return nil }
            return StartupItem(
                label: name,
                displayName: name,
                kind: .loginItem,
                path: URL(fileURLWithPath: path).standardizedFileURL.path,
                isEnabled: true,
                scopeKind: .currentUser
            )
        }
    }

    private func nonemptyString(_ value: Any?) -> String? {
        guard let value = value as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    private func bool(_ value: Any?) -> Bool? {
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? Bool { return value }
        return nil
    }
}

/// Read-only application inventory and conservative associated-file discovery.
public struct ApplicationScanner: ApplicationProviding, Sendable {
    private struct FileIdentity: Hashable {
        let device: dev_t
        let inode: ino_t
    }

    private struct AssociationLocation: Sendable {
        var root: URL
        var relativePath: String
        var category: AssociatedFileCategory
        var reason: String
        var matchBasis: AssociatedFileMatchBasis
        var selected: Bool
    }

    private let searchRoots: [URL]
    private let homeDirectory: URL

    public init(
        searchRoots: [URL]? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        let normalizedHome = homeDirectory.standardizedFileURL
        self.homeDirectory = normalizedHome
        self.searchRoots = searchRoots ?? [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            normalizedHome.appendingPathComponent("Applications", isDirectory: true)
        ]
    }

    public func applications() async throws -> [ApplicationCandidate] {
        try await Task.detached(priority: .utility) {
            try scanApplications()
        }.value
    }

    public func scanApplications() throws -> [ApplicationCandidate] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isApplicationKey, .isPackageKey, .isSymbolicLinkKey]
        let fileManager = FileManager.default
        var applicationURLs: [URL] = []
        var seen = Set<String>()

        for root in searchRoots {
            guard fileManager.fileExists(atPath: root.path) else { continue }
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else {
                continue
            }

            while let URL = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                guard URL.pathExtension.lowercased() == "app" else { continue }
                let values = try? URL.resourceValues(forKeys: Set(keys))
                guard values?.isDirectory == true || values?.isApplication == true || values?.isPackage == true else {
                    continue
                }
                enumerator.skipDescendants()
                let path = URL.standardizedFileURL.path
                if seen.insert(path).inserted {
                    applicationURLs.append(URL.standardizedFileURL)
                }
            }
        }

        return applicationURLs.compactMap { URL in
            makeCandidate(for: URL, includeDetails: false)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func enrichedCandidate(for applicationURL: URL) -> ApplicationCandidate? {
        makeCandidate(for: applicationURL.standardizedFileURL, includeDetails: true)
    }

    public func enrichedApplication(_ application: ApplicationCandidate) async -> ApplicationCandidate {
        let task = Task.detached(priority: .utility) {
            enrichedCandidate(for: application.bundleURL) ?? application
        }
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    @concurrent
    public func sizeBytes(for application: ApplicationCandidate) async -> UInt64? {
        application.bundleURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return nil }
            var roots = [UnsafeMutablePointer(mutating: path), nil]
            // Keep the walk inside the bundle's filesystem, without following symlinks.
            guard let tree = fts_open(&roots, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else {
                return nil
            }
            defer { fts_close(tree) }

            var blocks: UInt64 = 0
            var hardLinks = Set<FileIdentity>()
            while !Task.isCancelled {
                errno = 0
                guard let entry = fts_read(tree)?.pointee else {
                    guard errno == 0 else { return nil }
                    // Darwin reports st_blocks in 512-byte units.
                    let bytes = blocks.multipliedReportingOverflow(by: 512)
                    return bytes.overflow ? nil : bytes.partialValue
                }

                let kind = Int32(entry.fts_info)
                if entry.fts_level == 0, kind != FTS_D, kind != FTS_DP { return nil }
                switch kind {
                case FTS_D: continue
                case FTS_DP, FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT: break
                default: return nil
                }
                guard let file = entry.fts_statp?.pointee, file.st_blocks >= 0 else { return nil }

                // Multiple names for the same file share its allocated blocks.
                if kind != FTS_DP, file.st_nlink > 1 {
                    let identity = FileIdentity(device: file.st_dev, inode: file.st_ino)
                    guard hardLinks.insert(identity).inserted else { continue }
                }

                let sum = blocks.addingReportingOverflow(UInt64(file.st_blocks))
                guard !sum.overflow else { return nil }
                blocks = sum.partialValue
            }
            return nil
        }
    }

    public func scanAssociatedFiles(for application: ApplicationCandidate) -> [AssociatedFile] {
        discoverData(for: application).files
    }

    private func discoverData(for application: ApplicationCandidate) -> ApplicationDataDiscovery.Result {
        let inventory = (try? scanApplications()) ?? []
        return ApplicationDataDiscovery(home: homeDirectory, applications: inventory)
            .discover(for: application, base: baseAssociatedFiles(for: application))
    }

    private func baseAssociatedFiles(for application: ApplicationCandidate) -> [AssociatedFile] {
        let fileManager = FileManager.default
        let library = homeDirectory.appendingPathComponent("Library", isDirectory: true)
        let bundleIdentifier = sanitizedBundleIdentifier(application.bundleIdentifier)
        let appName = application.bundleURL.deletingPathExtension().lastPathComponent
        var result: [AssociatedFile] = []
        var paths = Set<String>()

        func add(
            _ URL: URL,
            category: AssociatedFileCategory,
            reason: String,
            matchBasis: AssociatedFileMatchBasis,
            selected: Bool
        ) {
            let standardized = URL.standardizedFileURL
            let path = standardized.path
            guard fileManager.fileExists(atPath: path), paths.insert(path).inserted else { return }
            result.append(AssociatedFile(
                path: path,
                category: category,
                sizeBytes: Self.nonRecursiveRegularFileSize(of: standardized),
                ownershipReason: reason,
                matchBasis: matchBasis,
                isSelected: selected
            ))
        }

        if let bundleIdentifier {
            let exactLocations: [AssociationLocation] = [
                AssociationLocation(root: library, relativePath: "Application Support/\(bundleIdentifier)", category: .support, reason: scanningText("association.reason.supportExact", "The support directory name exactly matches the bundle identifier; confirm ownership manually."), matchBasis: .exactBundleIdentifier(bundleIdentifier), selected: false),
                AssociationLocation(root: library, relativePath: "Caches/\(bundleIdentifier)", category: .cache, reason: scanningText("association.reason.cacheExact", "The cache name exactly matches the bundle identifier; confirm ownership manually."), matchBasis: .exactBundleIdentifier(bundleIdentifier), selected: false),
                AssociationLocation(root: library, relativePath: "Containers/\(bundleIdentifier)", category: .container, reason: scanningText("association.reason.containerExact", "The container name exactly matches the bundle identifier; confirm ownership manually."), matchBasis: .exactBundleIdentifier(bundleIdentifier), selected: false),
                AssociationLocation(root: library, relativePath: "Preferences/\(bundleIdentifier).plist", category: .preference, reason: scanningText("association.reason.preferencesExact", "The preferences name exactly matches the bundle identifier; confirm ownership manually."), matchBasis: .exactBundleIdentifier(bundleIdentifier), selected: false),
                AssociationLocation(root: library, relativePath: "Logs/\(bundleIdentifier)", category: .log, reason: scanningText("association.reason.logExact", "The log directory name exactly matches the bundle identifier; confirm ownership manually."), matchBasis: .exactBundleIdentifier(bundleIdentifier), selected: false),
                AssociationLocation(root: library, relativePath: "Saved Application State/\(bundleIdentifier).savedState", category: .support, reason: scanningText("association.reason.savedStateExact", "The saved-state name exactly matches the bundle identifier; confirm ownership manually."), matchBasis: .exactBundleIdentifier(bundleIdentifier), selected: false),
                AssociationLocation(root: library, relativePath: "WebKit/\(bundleIdentifier)", category: .cache, reason: scanningText("association.reason.webKitExact", "The WebKit data name exactly matches the bundle identifier; confirm ownership manually."), matchBasis: .exactBundleIdentifier(bundleIdentifier), selected: false),
                AssociationLocation(root: library, relativePath: "HTTPStorages/\(bundleIdentifier)", category: .cache, reason: scanningText("association.reason.httpStorageExact", "The HTTP storage name exactly matches the bundle identifier; confirm ownership manually."), matchBasis: .exactBundleIdentifier(bundleIdentifier), selected: false),
                AssociationLocation(root: library, relativePath: "Application Scripts/\(bundleIdentifier)", category: .script, reason: scanningText("association.reason.scriptExact", "The script directory name exactly matches the bundle identifier; confirm ownership manually."), matchBasis: .exactBundleIdentifier(bundleIdentifier), selected: false),
                AssociationLocation(root: library, relativePath: "LaunchAgents/\(bundleIdentifier).plist", category: .loginItem, reason: scanningText("association.reason.launchAgentExact", "The LaunchAgent name exactly matches the bundle identifier; confirm ownership manually."), matchBasis: .exactBundleIdentifier(bundleIdentifier), selected: false)
            ]
            for location in exactLocations {
                add(
                    location.root.appendingPathComponent(location.relativePath),
                    category: location.category,
                    reason: location.reason,
                    matchBasis: location.matchBasis,
                    selected: location.selected
                )
            }

            addMatchingChildren(
                in: library.appendingPathComponent("Preferences/ByHost", isDirectory: true),
                where: { name in name.hasPrefix("\(bundleIdentifier).") && name.hasSuffix(".plist") },
                category: .preference,
                reason: scanningText(
                    "association.reason.hostPreferencePrefix",
                    "Matched the host preferences prefix to the bundle identifier."
                ),
                matchBasis: .bundleIdentifierPrefix(bundleIdentifier),
                selected: false,
                add: add
            )
        }

        // Name-only matches are intentionally not preselected: different vendors can
        // use the same product name, so the UI must require an explicit user choice.
        if !appName.isEmpty {
            let nameLocations: [(String, AssociatedFileCategory)] = [
                ("Application Support/\(appName)", .support),
                ("Caches/\(appName)", .cache),
                ("Logs/\(appName)", .log)
            ]
            for (relativePath, category) in nameLocations {
                add(
                    library.appendingPathComponent(relativePath),
                    category: category,
                    reason: scanningText(
                        "association.reason.applicationName",
                        "The directory name only matches the application name; confirm ownership manually."
                    ),
                    matchBasis: .applicationName(appName),
                    selected: false
                )
            }
        }

        return result.sorted { lhs, rhs in
            if lhs.category != rhs.category { return lhs.category.rawValue < rhs.category.rawValue }
            return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
    }

    private func makeCandidate(for URL: URL, includeDetails: Bool) -> ApplicationCandidate? {
        guard URL.pathExtension.lowercased() == "app" else { return nil }
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: URL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }

        let bundle = Bundle(url: URL)
        let info = bundle?.infoDictionary
        let name = (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? URL.deletingPathExtension().lastPathComponent
        let version = [info?["CFBundleShortVersionString"], info?["CFBundleVersion"]]
            .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        var candidate = ApplicationCandidate(
            name: name,
            bundleIdentifier: bundle?.bundleIdentifier,
            version: version,
            bundleURL: URL,
            sizeBytes: nil
        )
        if includeDetails {
            let discovery = discoverData(for: candidate)
            candidate.associatedFiles = discovery.files
            candidate.dataDiscovery = discovery.summary
            candidate.vendorUninstaller = VendorUninstallerScanner.find(for: candidate)
        }
        return candidate
    }

    private func sanitizedBundleIdentifier(_ value: String?) -> String? {
        ApplicationDataDiscovery.safeIdentifier(value)
    }

    private func addMatchingChildren(
        in directory: URL,
        where predicate: (String) -> Bool,
        category: AssociatedFileCategory,
        reason: String,
        matchBasis: AssociatedFileMatchBasis,
        selected: Bool,
        add: (URL, AssociatedFileCategory, String, AssociatedFileMatchBasis, Bool) -> Void
    ) {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        for child in children where predicate(child.lastPathComponent) {
            add(child, category, reason, matchBasis, selected)
        }
    }

    /// Associated folders can contain large or shared data, so discovering
    /// associated files only reads sizes for individual regular files.
    private static func nonRecursiveRegularFileSize(of URL: URL) -> UInt64? {
        let typeKeys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let type = try? URL.resourceValues(forKeys: typeKeys),
              type.isRegularFile == true,
              type.isSymbolicLink != true
        else {
            return nil
        }

        let sizeKeys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let values = try? URL.resourceValues(forKeys: sizeKeys),
              let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize,
              size >= 0
        else {
            return nil
        }
        return UInt64(size)
    }
}

public struct UninstallAppMoveUnconfirmed: LocalizedError, Sendable {
    public let applicationURL: URL

    public init(applicationURL: URL) {
        self.applicationURL = applicationURL
    }

    public var errorDescription: String? {
        localizedDescription()
    }

    public func localizedDescription(locale: Locale? = nil) -> String {
        TraceHaloLocalization.format(
            "uninstall.appMoveUnconfirmed",
            defaultValue: "Could not confirm whether “%@” moved to the Trash. Local data was kept. Check the Trash before retrying.",
            locale: locale,
            applicationURL.lastPathComponent
        )
    }
}

public enum UninstallExecutionError: LocalizedError, Sendable {
    case partialCompletion(moved: Int, total: Int, reason: String)
    case moveFailed(targetURL: URL, isApplication: Bool, permissionDenied: Bool, reason: String)
    case cleanupIncomplete(moved: Int, total: Int, targetURL: URL, permissionDenied: Bool, reason: String)

    public var didMoveApplication: Bool {
        if case .cleanupIncomplete = self { return true }
        return false
    }

    public var failedTargetURL: URL? {
        switch self {
        case let .moveFailed(url, _, _, _), let .cleanupIncomplete(_, _, url, _, _): url
        case .partialCompletion: nil
        }
    }

    public var isPermissionDenied: Bool {
        switch self {
        case let .moveFailed(_, _, denied, _), let .cleanupIncomplete(_, _, _, denied, _): denied
        case .partialCompletion: false
        }
    }

    public var errorDescription: String? {
        localizedDescription()
    }

    public func localizedDescription(locale: Locale? = nil) -> String {
        switch self {
        case let .partialCompletion(moved, total, reason):
            return TraceHaloLocalization.format(
                total == 1
                    ? "uninstall.partialCompletion.one"
                    : "uninstall.partialCompletion.other",
                defaultValue: total == 1
                    ? "Moved %ld of %ld item to the Trash, then stopped: %@. Items already moved can be restored from the Trash."
                    : "Moved %ld of %ld items to the Trash, then stopped: %@. Items already moved can be restored from the Trash.",
                locale: locale,
                moved, total, reason
            )
        case let .moveFailed(url, _, permissionDenied, reason):
            return TraceHaloLocalization.format(
                "uninstall.noItemsMoved",
                defaultValue: "%@. No items were moved to the Trash.",
                locale: locale,
                Self.moveFailureReason(url, permissionDenied: permissionDenied, reason: reason, locale: locale)
            )
        case let .cleanupIncomplete(moved, total, url, permissionDenied, reason):
            return TraceHaloLocalization.format(
                "uninstall.cleanupIncomplete",
                defaultValue: "The app is in the Trash. Moved %ld of %ld selected data items. %@. Cleanup stopped.",
                locale: locale,
                moved - 1, total - 1,
                Self.moveFailureReason(url, permissionDenied: permissionDenied, reason: reason, locale: locale)
            )
        }
    }

    private static func moveFailureReason(
        _ url: URL,
        permissionDenied: Bool,
        reason: String,
        locale: Locale?
    ) -> String {
        if permissionDenied {
            return TraceHaloLocalization.format(
                "uninstall.movePermissionDenied",
                defaultValue: "Moving “%@” to the Trash requires additional permission",
                locale: locale,
                url.lastPathComponent
            )
        }
        return TraceHaloLocalization.format(
            "uninstall.moveError",
            defaultValue: "Could not move “%@” to the Trash (%@)",
            locale: locale,
            url.lastPathComponent, reason
        )
    }
}

/// Validates every target before moving anything and moves the application first.
/// A failure to trash the bundle leaves its associated files in place.
public struct TrashUninstallExecutor: UninstallExecuting, Sendable {
    private struct ValidatedTarget: Sendable {
        var URL: URL
        var device: dev_t
        var inode: ino_t
    }

    private let validator: DestructiveTargetValidator
    private let pathPolicy: UninstallPathPolicy
    private let moveApplicationToTrash: @Sendable (URL) async throws -> Void

    public init(
        validator: DestructiveTargetValidator = DestructiveTargetValidator(),
        pathPolicy: UninstallPathPolicy = UninstallPathPolicy(),
        moveApplicationToTrash: @escaping @Sendable (URL) async throws -> Void = { url in
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    ) {
        self.validator = validator
        self.pathPolicy = pathPolicy
        self.moveApplicationToTrash = moveApplicationToTrash
    }

    public func execute(plan: UninstallPlan) async throws {
        guard RuntimeSafetyMode.current == .live else {
            throw SafetyViolation.deniedInSafeTestMode(.uninstall)
        }

        let fileManager = FileManager.default
        try await execute(
            plan: plan,
            homeDirectory: fileManager.homeDirectoryForCurrentUser,
            moveApplicationToTrash: moveApplicationToTrash,
            moveAssociatedFileToTrash: { url in
                try fileManager.trashItem(at: url, resultingItemURL: nil)
            }
        )
    }

    func execute(
        plan: UninstallPlan,
        homeDirectory: URL,
        moveApplicationToTrash: (URL) async throws -> Void,
        moveAssociatedFileToTrash: (URL) throws -> Void
    ) async throws {
        let targets = try validate(plan: plan, homeDirectory: homeDirectory)
        for (index, target) in targets.enumerated() {
            try Self.checkTrashPermission(target.URL, isApplication: index == 0)
        }

        for (index, target) in targets.enumerated() {
            do {
                try Self.validateUnchanged(target)
                if index == 0 {
                    try await moveApplicationToTrash(target.URL)
                } else {
                    try moveAssociatedFileToTrash(target.URL)
                }
            } catch let failure as UninstallAppMoveUnconfirmed {
                throw failure
            } catch {
                let permissionDenied = Self.isPermissionDenied(error)
                if index == 0 {
                    throw UninstallExecutionError.moveFailed(
                        targetURL: target.URL, isApplication: true,
                        permissionDenied: permissionDenied, reason: error.localizedDescription
                    )
                }
                throw UninstallExecutionError.cleanupIncomplete(
                    moved: index, total: targets.count, targetURL: target.URL,
                    permissionDenied: permissionDenied, reason: error.localizedDescription
                )
            }
        }
    }

    private static func checkTrashPermission(_ url: URL, isApplication: Bool) throws {
        // Moving a directory to the Trash needs permission on its directory entry,
        // not recursive write permission inside its contents. Trash can still
        // fail for reasons this filesystem preflight cannot see.
        guard faccessat(AT_FDCWD, url.path, _DELETE_OK, AT_EACCESS | AT_SYMLINK_NOFOLLOW) != 0 else { return }
        let code = errno
        // The system can authorize moving the app even when this process lacks
        // delete access. Selected data still requires upfront process access.
        guard code == EROFS || (!isApplication && (code == EACCES || code == EPERM)) else { return }
        throw UninstallExecutionError.moveFailed(
            targetURL: url, isApplication: isApplication,
            permissionDenied: code != EROFS, reason: String(cString: strerror(code))
        )
    }

    private static func validateUnchanged(_ target: ValidatedTarget) throws {
        var current = stat()
        if lstat(target.URL.path, &current) != 0,
           let code = POSIXErrorCode(rawValue: errno) {
            throw POSIXError(code)
        }
        guard current.st_dev == target.device,
              current.st_ino == target.inode,
              (current.st_mode & S_IFMT) != S_IFLNK,
              target.URL.resolvingSymlinksInPath().path == target.URL.path else {
            throw SafetyViolation.invalidTarget(scanningFormat(
                "uninstall.targetChanged",
                "The target changed after confirmation, so removal stopped: %@",
                target.URL.path
            ))
        }
    }

    private static func isPermissionDenied(_ error: any Error) -> Bool {
        let error = error as NSError
        switch error.domain {
        case NSCocoaErrorDomain where error.code == CocoaError.fileWriteNoPermission.rawValue
            || error.code == CocoaError.fileReadNoPermission.rawValue:
            return true
        case NSPOSIXErrorDomain where error.code == Int(EACCES) || error.code == Int(EPERM):
            return true
        default:
            if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                return isPermissionDenied(underlying)
            }
            return false
        }
    }

    private func validate(plan: UninstallPlan, homeDirectory: URL) throws -> [ValidatedTarget] {
        let home = homeDirectory.standardizedFileURL
        let applicationURL = plan.application.bundleURL.standardizedFileURL
        let scannedFiles = Dictionary(plan.application.associatedFiles.map {
            (URL(fileURLWithPath: $0.path).standardizedFileURL.path, $0)
        }, uniquingKeysWith: { first, _ in first })

        var URLs = [applicationURL]
        var seen = Set([applicationURL.path])
        for file in plan.selectedFiles {
            let URL = URL(fileURLWithPath: file.path).standardizedFileURL
            guard let scanned = scannedFiles[URL.path], scanned == file,
                  scanned.isEligibleForCleanup else {
                throw SafetyViolation.invalidTarget(scanningFormat(
                    "uninstall.unscannedAssociation",
                    "The uninstall plan contains an associated file that was not confirmed by the scan: %@",
                    file.path
                ))
            }
            guard !scannedFiles.values.contains(where: {
                $0.path.hasPrefix(URL.path + "/") && !$0.isEligibleForCleanup
            }) else {
                throw SafetyViolation.invalidTarget(scanningFormat(
                    "uninstall.protectedDescendant",
                    "The selected folder contains a protected finding. Choose its other children individually: %@",
                    file.path
                ))
            }
            guard seen.insert(URL.path).inserted else {
                throw SafetyViolation.invalidTarget(scanningFormat(
                    "safety.duplicateTarget",
                    "The uninstall plan contains a duplicate target: %@",
                    URL.path
                ))
            }
            URLs.append(URL)
        }

        for target in URLs.dropFirst() where URLs.dropFirst().contains(where: {
            $0.path != target.path && target.path.hasPrefix($0.path + "/")
        }) {
            throw SafetyViolation.invalidTarget(scanningFormat(
                "uninstall.overlappingAssociation",
                "The uninstall plan contains overlapping data folders. Review the selection: %@",
                target.path
            ))
        }

        try validator.validate(paths: URLs.map(\.path), homeDirectory: home.path)
        try pathPolicy.validate(
            applicationPath: applicationURL.path,
            associatedPaths: URLs.dropFirst().map(\.path),
            homeDirectory: home.path
        )

        var targets: [ValidatedTarget] = []
        for (index, URL) in URLs.enumerated() {
            var metadata = stat()
            guard lstat(URL.path, &metadata) == 0 else {
                let code = errno
                if code == EACCES || code == EPERM {
                    throw UninstallExecutionError.moveFailed(
                        targetURL: URL, isApplication: index == 0,
                        permissionDenied: true, reason: String(cString: strerror(code))
                    )
                }
                throw SafetyViolation.invalidTarget(scanningFormat(
                    "uninstall.targetMissing",
                    "The target does not exist: %@",
                    URL.path
                ))
            }
            guard (metadata.st_mode & S_IFMT) != S_IFLNK,
                  URL.resolvingSymlinksInPath().path == URL.path
            else {
                throw SafetyViolation.invalidTarget(scanningFormat(
                    "uninstall.symlinkRejected",
                    "Refusing to process a symbolic link or a target inside a symbolic-link path: %@",
                    URL.path
                ))
            }
            let fileType = metadata.st_mode & S_IFMT
            guard fileType == S_IFREG || fileType == S_IFDIR else {
                throw SafetyViolation.invalidTarget(scanningFormat(
                    "uninstall.regularTargetRequired",
                    "The target must be a regular file or directory: %@",
                    URL.path
                ))
            }
            if index == 0, fileType != S_IFDIR {
                throw SafetyViolation.invalidTarget(scanningText(
                    "uninstall.directoryAppRequired",
                    "The application target must be a directory-based .app bundle."
                ))
            }
            targets.append(ValidatedTarget(URL: URL, device: metadata.st_dev, inode: metadata.st_ino))
        }

        return targets
    }

}

public enum StartupItemMutationError: LocalizedError, Equatable, Sendable {
    case commandFailed(status: Int32, message: String)

    public var errorDescription: String? {
        localizedDescription()
    }

    public func localizedDescription(locale: Locale? = nil) -> String {
        switch self {
        case let .commandFailed(status, message):
            if message.isEmpty {
                return TraceHaloLocalization.format(
                    "startup.launchctlFailed",
                    defaultValue: "launchctl failed (exit code %d).",
                    locale: locale,
                    status
                )
            }
            return TraceHaloLocalization.format(
                "startup.launchctlFailedMessage",
                defaultValue: "launchctl failed (exit code %d): %@",
                locale: locale,
                status, message
            )
        }
    }
}

/// Minimal production mutator for the current user's own LaunchAgents.
///
/// macOS does not expose a public API for toggling arbitrary Login Items, and a
/// normal user process cannot safely promise system LaunchAgent/Daemon changes.
/// Those cases fail explicitly instead of attempting a guessed command.
public struct LaunchctlStartupItemMutator: StartupItemMutating, Sendable {
    private let validator: DestructiveTargetValidator
    private let homeDirectory: URL

    public init(
        validator: DestructiveTargetValidator = DestructiveTargetValidator(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.validator = validator
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    public func setEnabled(_ enabled: Bool, item: StartupItem) async throws {
        guard RuntimeSafetyMode.current == .live else {
            throw SafetyViolation.deniedInSafeTestMode(.startupItemChange)
        }
        switch item.kind {
        case .loginItem:
            throw SafetyViolation.unsupported(scanningText(
                "startup.loginItemUnsupported",
                "macOS does not provide a public API for modifying another application's login item."
            ))
        case .launchDaemon:
            throw SafetyViolation.unsupported(scanningText(
                "startup.daemonRequiresAdmin",
                "System LaunchDaemons require administrator authorization; this version will not attempt to modify them."
            ))
        case .launchAgent:
            break
        }

        let targetURL = URL(fileURLWithPath: item.path).standardizedFileURL
        let allowedRoot = homeDirectory.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        guard targetURL.deletingLastPathComponent().path == allowedRoot.path,
              targetURL.pathExtension.lowercased() == "plist"
        else {
            throw SafetyViolation.unsupported(scanningText(
                "startup.currentUserAgentsOnly",
                "Only direct items in the current user's ~/Library/LaunchAgents directory are supported."
            ))
        }
        try validator.validate(paths: [targetURL.path], homeDirectory: homeDirectory.path)
        guard targetURL.resolvingSymlinksInPath().path == targetURL.path else {
            throw SafetyViolation.invalidTarget(scanningText(
                "startup.symlinkRejected",
                "Refusing to modify a startup item that is a symbolic link or lies inside a symbolic-link path."
            ))
        }

        let resourceValues = try targetURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard resourceValues.isRegularFile == true, resourceValues.isSymbolicLink != true else {
            throw SafetyViolation.invalidTarget(scanningText(
                "startup.plistRequired",
                "The startup item must be a regular plist file."
            ))
        }
        guard
            let data = try? Data(contentsOf: targetURL, options: [.mappedIfSafe]),
            let propertyList = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let dictionary = propertyList as? [String: Any],
            let plistLabel = dictionary["Label"] as? String,
            plistLabel == item.label,
            Self.isSafeLaunchdLabel(plistLabel)
        else {
            throw SafetyViolation.invalidTarget(scanningText(
                "startup.invalidLabel",
                "The startup item label is invalid or does not match the plist contents."
            ))
        }

        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = [
            enabled ? "enable" : "disable",
            "gui/\(getuid())/\(plistLabel)"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw StartupItemMutationError.commandFailed(status: -1, message: error.localizedDescription)
        }

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(decoding: errorData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw StartupItemMutationError.commandFailed(
                status: process.terminationStatus,
                message: message
            )
        }
    }

    private static func isSafeLaunchdLabel(_ label: String) -> Bool {
        guard !label.isEmpty, label.count <= 255 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        return label.unicodeScalars.allSatisfy(allowed.contains)
    }
}

public typealias LiveStartupItemMutator = LaunchctlStartupItemMutator
