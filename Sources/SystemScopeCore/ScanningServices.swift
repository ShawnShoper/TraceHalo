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
}

public extension ApplicationProviding {
    func enrichedApplication(_ application: ApplicationCandidate) async -> ApplicationCandidate {
        application
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
        await Task.detached(priority: .utility) {
            enrichedCandidate(for: application.bundleURL) ?? application
        }.value
    }

    public func scanAssociatedFiles(for application: ApplicationCandidate) -> [AssociatedFile] {
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
        var candidate = ApplicationCandidate(
            name: name,
            bundleIdentifier: bundle?.bundleIdentifier,
            version: (info?["CFBundleShortVersionString"] as? String)
                ?? (info?["CFBundleVersion"] as? String),
            bundleURL: URL,
            sizeBytes: nil
        )
        if includeDetails {
            candidate.associatedFiles = scanAssociatedFiles(for: candidate)
        }
        return candidate
    }

    private func sanitizedBundleIdentifier(_ value: String?) -> String? {
        guard let value, !value.isEmpty, !value.contains("/") else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        guard value.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return value
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

    /// Directory packages and support folders are deliberately not traversed.
    /// A recursive size walk can consume substantial CPU and memory for large
    /// applications, and a partial walk would present a misleading exact value.
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

/// Production uninstall executor. Every target is validated before the first item
/// is moved, and removal uses Finder's Trash rather than permanent deletion.
/// SafeTestMode always denies execution.
public enum UninstallExecutionError: LocalizedError, Sendable {
    case partialCompletion(moved: Int, total: Int, reason: String)

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
        }
    }
}

public struct TrashUninstallExecutor: UninstallExecuting, Sendable {
    private struct ValidatedTarget: Sendable {
        var URL: URL
        var device: dev_t
        var inode: ino_t
    }

    private let validator: DestructiveTargetValidator
    private let pathPolicy: UninstallPathPolicy

    public init(
        validator: DestructiveTargetValidator = DestructiveTargetValidator(),
        pathPolicy: UninstallPathPolicy = UninstallPathPolicy()
    ) {
        self.validator = validator
        self.pathPolicy = pathPolicy
    }

    public func execute(plan: UninstallPlan) async throws {
        guard RuntimeSafetyMode.current == .live else {
            throw SafetyViolation.deniedInSafeTestMode(.uninstall)
        }

        let validatedTargets = try validate(plan: plan)
        let fileManager = FileManager.default
        // Move optional support files first and the application bundle last. If a
        // support-file operation fails, the main application remains available.
        let orderedTargets = Array(validatedTargets.dropFirst()) + Array(validatedTargets.prefix(1))
        var moved = 0
        for target in orderedTargets {
            var current = stat()
            guard
                lstat(target.URL.path, &current) == 0,
                current.st_dev == target.device,
                current.st_ino == target.inode,
                (current.st_mode & S_IFMT) != S_IFLNK
            else {
                throw SafetyViolation.invalidTarget(scanningFormat(
                    "uninstall.targetChanged",
                    "The target changed after confirmation, so removal stopped: %@",
                    target.URL.path
                ))
            }
            var resultingURL: NSURL?
            do {
                try fileManager.trashItem(at: target.URL, resultingItemURL: &resultingURL)
                moved += 1
            } catch {
                if moved > 0 {
                    throw UninstallExecutionError.partialCompletion(
                        moved: moved,
                        total: orderedTargets.count,
                        reason: error.localizedDescription
                    )
                }
                throw error
            }
        }
    }

    private func validate(plan: UninstallPlan) throws -> [ValidatedTarget] {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let applicationURL = plan.application.bundleURL.standardizedFileURL
        let associatedPaths = Set(plan.application.associatedFiles.map {
            URL(fileURLWithPath: $0.path).standardizedFileURL.path
        })

        var URLs = [applicationURL]
        var seen = Set([applicationURL.path])
        for file in plan.selectedFiles {
            let URL = URL(fileURLWithPath: file.path).standardizedFileURL
            guard associatedPaths.contains(URL.path) else {
                throw SafetyViolation.invalidTarget(scanningFormat(
                    "uninstall.unscannedAssociation",
                    "The uninstall plan contains an associated file that was not confirmed by the scan: %@",
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
