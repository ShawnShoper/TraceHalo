import Foundation
import Security
import Darwin

public enum ApplicationDataPurpose: String, CaseIterable, Sendable {
    case cache, logs, settings, savedState, websiteData, browserProfile, userData, automation, background, shared, unknown

    static func infer(category: AssociatedFileCategory, path: String) -> Self {
        if path.contains("/WebKit/") || path.contains("/HTTPStorages/") { return .websiteData }
        if path.contains("/Saved Application State/") { return .savedState }
        switch category {
        case .cache: return .cache
        case .log: return .logs
        case .preference: return .settings
        case .container, .support: return .userData
        case .script: return .automation
        case .groupContainer: return .shared
        case .helper, .loginItem, .plugin: return .background
        default: return .unknown
        }
    }

    public func title(locale: Locale? = nil) -> String {
        dataText("data.purpose.\(rawValue).title", locale: locale)
    }

    /// Describes possible contents, never claims that the user's files were read.
    public func impact(locale: Locale? = nil) -> String {
        dataText("data.purpose.\(rawValue).impact", locale: locale)
    }
}

public enum ApplicationDataRetentionReason: String, Sendable {
    case shared, uncertain, outsideScope, symbolicLink, protectedContents

    public var blocksCleanup: Bool {
        switch self {
        case .shared, .uncertain: false
        case .outsideScope, .symbolicLink, .protectedContents: true
        }
    }

    public func explanation(locale: Locale? = nil) -> String {
        dataText("data.retain.\(rawValue)", locale: locale)
    }
}

public enum ApplicationDataCleanupWarning: String, CaseIterable, Sendable {
    case uncertain, shared, savedContent

    public func title(locale: Locale? = nil) -> String {
        dataText("data.warning.\(rawValue).title", locale: locale)
    }

    public func impact(locale: Locale? = nil) -> String {
        dataText("data.warning.\(rawValue).impact", locale: locale)
    }
}

public struct ApplicationDataDiscoverySummary: Equatable, Sendable {
    public var signedComponentCount = 0
    public var scriptCount = 0
    public var receiptCount = 0
    public var signatureVerified = false
    public var wasLimited = false
    public var unreadableLocations = false
    public var incompleteSizeCount = 0
    public init() {}
}

private func dataText(_ key: String, locale: Locale? = nil) -> String {
    TraceHaloLocalization.string(key, defaultValue: key, locale: locale)
}

/// No application, script or installer is executed. Signature entitlements,
/// bundle metadata, bounded text references and system receipt records are read.
/// Discovery is evidence of association, not a history of filesystem writes.
struct ApplicationDataDiscovery {
    struct Signature: Sendable {
        var identifier: String
        var team: String
        var groups: [String] = []
    }

    struct Receipt: Sendable {
        var identifier: String
        var paths: [String]
    }

    struct Result {
        var files: [AssociatedFile]
        var summary: ApplicationDataDiscoverySummary
    }

    var home: URL
    var applications: [ApplicationCandidate]
    var signature: (URL) -> Signature? = Self.readSignature
    var receipts: (URL) -> (records: [Receipt], limited: Bool) = Self.readReceipts

    func discover(for application: ApplicationCandidate, base: [AssociatedFile]) -> Result {
        let library = home.appendingPathComponent("Library")
        let host = application.bundleURL.standardizedFileURL
        let pathPolicy = UninstallPathPolicy()
        func isWithinCleanupScope(_ path: String) -> Bool {
            do {
                try pathPolicy.validate(applicationPath: host.path, associatedPaths: [path], homeDirectory: home.path)
                return true
            } catch { return false }
        }
        var summary = ApplicationDataDiscoverySummary()
        let maximumFindings = 256
        var files = Dictionary(base.prefix(maximumFindings).map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        summary.wasLimited = base.count > maximumFindings
        let deadline = Date().addingTimeInterval(8)
        func stopped() -> Bool { Task.isCancelled || Date() > deadline }
        func exists(_ url: URL) -> Bool {
            var info = stat()
            if lstat(url.path, &info) == 0 { return true }
            if errno == EACCES || errno == EPERM { summary.unreadableLocations = true }
            return false
        }
        func add(_ url: URL, category: AssociatedFileCategory, basis: AssociatedFileMatchBasis,
                 evidence: String, retention: ApplicationDataRetentionReason? = nil,
                 purpose: ApplicationDataPurpose? = nil) {
            let target = url.standardizedFileURL
            guard !stopped(), files[target.path] != nil || files.count < maximumFindings else {
                summary.wasLimited = true
                return
            }
            guard exists(target), target.path != home.path, target.path != library.path else { return }
            if var file = files[target.path] {
                if !file.additionalEvidence.contains(evidence) { file.additionalEvidence.append(evidence) }
                // Advisory evidence must not weaken a previously protected finding.
                if retention == .shared, file.retentionReason?.blocksCleanup != true { file.retentionReason = retention }
                files[target.path] = file
            } else {
                files[target.path] = AssociatedFile(
                    path: target.path, category: category, ownershipReason: evidence,
                    matchBasis: basis, dataPurpose: purpose, retentionReason: retention
                )
            }
        }

        let mainSignature = signature(host)
        summary.signatureVerified = mainSignature?.identifier == application.bundleIdentifier
        let components = Self.components(in: host)
        summary.wasLimited = summary.wasLimited || components.limited
        var groups = Set<String>()
        if summary.signatureVerified, let mainSignature {
            groups.formUnion(mainSignature.groups.compactMap(Self.safeIdentifier))
            for component in components.urls {
                if stopped() { summary.wasLimited = true; break }
                guard let signed = signature(component), signed.team == mainSignature.team,
                      signed.identifier == Self.componentIdentifier(component),
                      let identifier = Self.safeIdentifier(signed.identifier) else { continue }
                summary.signedComponentCount += 1
                groups.formUnion(signed.groups.compactMap(Self.safeIdentifier))
                if identifier != application.bundleIdentifier {
                    for (folder, suffix, category) in Self.identifierLocations {
                        add(library.appendingPathComponent("\(folder)/\(identifier)\(suffix)"),
                            category: category, basis: .signedComponent(identifier),
                            evidence: dataText("data.evidence.component") + " " + identifier)
                    }
                }
            }
        }
        for group in groups.sorted() {
            if stopped() { summary.wasLimited = true; break }
            add(library.appendingPathComponent("Group Containers/\(group)"),
                category: .groupContainer, basis: .appGroup(group),
                evidence: dataText("data.evidence.group") + " " + group, retention: .shared)
        }

        // Explicit vendor paths are gated by validated identity AND signing team.
        // Never include the parent vendor directory (Google, Blender, etc.).
        if summary.signatureVerified, let mainSignature {
            for location in Self.verifiedLocations(application, signature: mainSignature, library: library) {
                add(location.url, category: location.category,
                    basis: .verifiedLocation(location.source),
                    evidence: dataText("data.evidence.vendor") + " " + location.source, purpose: location.purpose)
            }
        }

        // launchd records are read only; a direct executable reference into this
        // app is stronger than a similar label or a matching vendor name.
        let agents = Self.children(library.appendingPathComponent("LaunchAgents"), limit: 256)
        summary.wasLimited = summary.wasLimited || agents.limited
        for url in agents.urls where url.pathExtension == "plist" {
            guard !stopped(), let plist = Self.plist(url, maximumBytes: 262_144) else { continue }
            let executable = (plist["Program"] as? String)
                ?? (plist["ProgramArguments"] as? [String])?.first
            guard let executable, executable.hasPrefix(host.path + "/"),
                  URL(fileURLWithPath: executable).standardizedFileURL.path == executable,
                  URL(fileURLWithPath: executable).resolvingSymlinksInPath().path.hasPrefix(host.path + "/") else { continue }
            add(url, category: .loginItem, basis: .backgroundExecutable(executable),
                evidence: dataText("data.evidence.background") + " " + executable)
        }

        // Read literal paths in bounded UTF-8 scripts; do not evaluate variables,
        // expressions, imports, shell substitutions or downloaded code.
        let scripts = Self.scripts(in: host)
        summary.wasLimited = summary.wasLimited || scripts.limited
        for url in scripts.urls {
            if stopped() { summary.wasLimited = true; break }
            guard let bytes = Self.regularFile(url, maximumBytes: 262_144),
                  let text = String(data: bytes, encoding: .utf8) else {
                summary.wasLimited = true
                continue
            }
            summary.scriptCount += 1
            for target in Self.literalLibraryPaths(in: text, home: home) {
                add(target, category: .other, basis: .scriptReference(url.path),
                    evidence: dataText("data.evidence.script") + " " + url.lastPathComponent,
                    retention: .uncertain)
            }
        }

        if !stopped() {
            let receiptResult = receipts(host)
            summary.wasLimited = summary.wasLimited || receiptResult.limited
            for receipt in receiptResult.records {
                // A receipt must contain the exact application bundle entry.
                guard receipt.paths.contains(host.path) else { continue }
                summary.receiptCount += 1
                for path in receipt.paths.prefix(20_000) {
                    let url = URL(fileURLWithPath: path).standardizedFileURL
                    guard !url.path.hasPrefix(host.path + "/"), url.path != host.path,
                          Self.isReceiptComponent(url, home: home),
                          (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                    add(url, category: .helper, basis: .installationReceipt(receipt.identifier),
                        evidence: dataText("data.evidence.receipt") + " " + receipt.identifier,
                        retention: isWithinCleanupScope(url.path) ? .uncertain : .outsideScope)
                    if files.count >= 256 { summary.wasLimited = true; break }
                }
            }
        } else { summary.wasLimited = true }

        // Another installed copy or product can claim the same identifier or
        // version-specific directory. Such claims add a shared-data warning;
        // they do not establish exclusive ownership.
        var otherIDs = Set<String>()
        var otherLocations = Set<String>()
        var declaredUsers: [String: Set<String>] = [:]
        for other in applications where other.id != application.id {
            if stopped() { summary.wasLimited = true; break }
            if let identifier = Self.safeIdentifier(other.bundleIdentifier) { otherIDs.insert(identifier) }
            let otherComponents = Self.components(in: other.bundleURL)
            summary.wasLimited = summary.wasLimited || otherComponents.limited
            for component in otherComponents.urls {
                if let id = Self.safeIdentifier(Self.componentIdentifier(component)) { otherIDs.insert(id) }
            }
            // An unverified claim may warn about shared use, never prove ownership.
            let team = other.bundleIdentifier == "com.google.Chrome" ? "EQHXZ8M8AV" : "68UA947AUU"
            for location in Self.verifiedLocations(other, signature: Signature(identifier: other.bundleIdentifier ?? "", team: team), library: library) {
                otherLocations.insert(location.url.path)
            }
            // Chrome-created web apps are separate installed applications but
            // declare a directory inside the browser profile. Removing that
            // whole profile would also remove their stored content. Metadata
            // adds a warning; it is never proof of exclusive ownership.
            if let declared = Self.plist(other.bundleURL.appendingPathComponent("Contents/Info.plist"), maximumBytes: 262_144)?["CrAppModeUserDataDir"] as? String,
               declared.hasPrefix("/"), !declared.split(separator: "/").contains("..") {
                let path = URL(fileURLWithPath: declared).standardizedFileURL.path
                declaredUsers[path, default: []].insert(other.name)
                let chromeProfile = library.appendingPathComponent("Application Support/Google/Chrome").path
                if other.bundleIdentifier?.hasPrefix("com.google.Chrome.app.") == true,
                   path == chromeProfile || path.hasPrefix(chromeProfile + "/") {
                    otherIDs.insert("com.google.Chrome")
                    for folder in ["Application Support/Google/Chrome", "Caches/Google/Chrome"] {
                        let sharedPath = library.appendingPathComponent(folder).path
                        otherLocations.insert(sharedPath)
                        declaredUsers[sharedPath, default: []].insert(other.name)
                    }
                }
            }
        }
        // Replace a broad name-only parent with a documented, more specific
        // location. Otherwise the review would claim to retain a whole folder
        // while offering to remove a child of that same folder.
        let specificPaths = files.values.filter { $0.isEligibleForCleanup && !$0.hasUncertainOwnership }.map(\.path)
        for path in Array(files.keys) {
            if case .applicationName = files[path]?.matchBasis,
               specificPaths.contains(where: { $0.hasPrefix(path + "/") }) {
                files.removeValue(forKey: path)
            }
        }
        for path in files.keys.sorted() {
            guard var file = files[path] else { continue }
            let url = URL(fileURLWithPath: path)
            if !isWithinCleanupScope(path) { file.retentionReason = .outsideScope }
            let claimedID: String?
            switch file.matchBasis {
            case .exactBundleIdentifier(let id), .bundleIdentifierPrefix(let id), .signedComponent(let id): claimedID = id
            default: claimedID = nil
            }
            if file.retentionReason?.blocksCleanup != true,
               claimedID.map(otherIDs.contains) == true || otherLocations.contains(where: { $0 == path || $0.hasPrefix(path + "/") }) {
                file.retentionReason = .shared
            }
            let users = Set(declaredUsers.filter { $0.key == path || $0.key.hasPrefix(path + "/") }.values.flatMap { $0 })
            if !users.isEmpty {
                if file.retentionReason?.blocksCleanup != true { file.retentionReason = .shared }
                file.additionalEvidence.append(TraceHaloLocalization.format(
                    "data.evidence.otherApp", defaultValue: "Other installed apps declare use of this data location: %@",
                    users.sorted().joined(separator: ", ")))
            }
            if url.resolvingSymlinksInPath().path != path { file.retentionReason = .symbolicLink }
            if file.hasUncertainOwnership, file.retentionReason == nil { file.retentionReason = .uncertain }
            files[path] = file
        }
        // Parent/child findings are not separate deletion targets. Retain a
        // selectable parent if it would also remove a non-selectable descendant.
        let protected = files.values.filter { !$0.isEligibleForCleanup }.map(\.path)
        for path in Array(files.keys) where protected.contains(where: { $0.hasPrefix(path + "/") }) {
            files[path]?.retentionReason = .protectedContents
        }
        let sizeDeadline = Date().addingTimeInterval(2)
        for path in files.keys.sorted() {
            guard var file = files[path], file.isEligibleForCleanup else { continue }
            if stopped() || Date() > sizeDeadline {
                summary.incompleteSizeCount += 1
            } else {
                file.sizeBytes = Self.allocatedSize(URL(fileURLWithPath: path), deadline: min(sizeDeadline, Date().addingTimeInterval(0.2)))
                if file.sizeBytes == nil { summary.incompleteSizeCount += 1 }
            }
            files[path] = file
        }
        return Result(files: files.values.sorted {
            if $0.isEligibleForCleanup != $1.isEligibleForCleanup { return $0.isEligibleForCleanup }
            return $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }, summary: summary)
    }

    static let identifierLocations: [(String, String, AssociatedFileCategory)] = [
        ("Application Support", "", .support), ("Caches", "", .cache), ("Containers", "", .container),
        ("Preferences", ".plist", .preference), ("Logs", "", .log),
        ("Saved Application State", ".savedState", .support), ("WebKit", "", .cache),
        ("HTTPStorages", "", .cache), ("Application Scripts", "", .script), ("LaunchAgents", ".plist", .loginItem)
    ]

    static func safeIdentifier(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.count <= 255, value != ".", value != "..",
              value.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_")).contains)
        else { return nil }
        return value
    }

    struct Location {
        var url: URL
        var category: AssociatedFileCategory
        var source: String
        var purpose: ApplicationDataPurpose? = nil
    }
    static func verifiedLocations(_ app: ApplicationCandidate, signature: Signature, library: URL) -> [Location] {
        switch (app.bundleIdentifier, signature.team) {
        case ("com.google.Chrome", "EQHXZ8M8AV"):
            let source = "https://chromium.googlesource.com/chromium/src/+/main/docs/user_data_dir.md"
            return [Location(url: library.appendingPathComponent("Application Support/Google/Chrome"), category: .support, source: source, purpose: .browserProfile),
                    Location(url: library.appendingPathComponent("Caches/Google/Chrome"), category: .cache, source: source)]
        case ("org.blenderfoundation.blender", "68UA947AUU"):
            let parts = (app.version ?? "").split(separator: ".")
            guard parts.count >= 2, parts.prefix(2).allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return [] }
            return [Location(url: library.appendingPathComponent("Application Support/Blender/\(parts[0]).\(parts[1])"), category: .support,
                             source: "https://docs.blender.org/manual/en/latest/advanced/blender_directory_layout.html")]
        default: return []
        }
    }

    static func readSignature(_ url: URL) -> Signature? {
        guard url.resolvingSymlinksInPath().path == url.standardizedFileURL.path else { return nil }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        var info: CFDictionary?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString("anchor apple generic" as CFString, [], &requirement) == errSecSuccess,
              let requirement, SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: UInt32(kSecCSSigningInformation)), &info) == errSecSuccess,
              let values = info as? [String: Any], let team = values[kSecCodeInfoTeamIdentifier as String] as? String,
              let identifier = values[kSecCodeInfoIdentifier as String] as? String, !team.isEmpty else { return nil }
        let entitlements = values[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        let groups = entitlements?["com.apple.security.application-groups"] as? [String] ?? []
        return Signature(identifier: identifier, team: team, groups: groups)
    }

    static func children(_ url: URL, limit: Int) -> (urls: [URL], limited: Bool) {
        guard url.resolvingSymlinksInPath().path == url.standardizedFileURL.path,
              let urls = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return ([], false) }
        return (Array(urls.map(\.standardizedFileURL).sorted { $0.path < $1.path }.prefix(limit)), urls.count > limit)
    }

    static func components(in host: URL) -> (urls: [URL], limited: Bool) {
        var urls: [URL] = []
        var limited = false
        for folder in ["Contents/PlugIns", "Contents/XPCServices", "Contents/Library/LoginItems", "Contents/Library/Helpers", "Contents/Helpers"] {
            let entries = children(host.appendingPathComponent(folder), limit: 64)
            limited = limited || entries.limited
            urls += entries.urls.filter {
                ["app", "appex", "xpc"].contains($0.pathExtension.lowercased())
                    && $0.resolvingSymlinksInPath().path == $0.path
            }
        }
        return (urls, limited)
    }

    private static func componentIdentifier(_ url: URL) -> String? {
        plist(url.appendingPathComponent("Contents/Info.plist"), maximumBytes: 262_144)?["CFBundleIdentifier"] as? String
    }

    static func scripts(in host: URL) -> (urls: [URL], limited: Bool) {
        guard host.resolvingSymlinksInPath().path == host.standardizedFileURL.path,
              let walk = FileManager.default.enumerator(at: host.appendingPathComponent("Contents"),
                includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey], options: [.skipsHiddenFiles]) else { return ([], false) }
        var urls: [URL] = []
        var visited = 0
        let deadline = Date().addingTimeInterval(0.5)
        while let url = walk.nextObject() as? URL {
            visited += 1
            if Task.isCancelled || visited > 4_000 || urls.count >= 64 || Date() > deadline { return (urls, true) }
            let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            if values?.isSymbolicLink == true || ["framework", "lproj"].contains(url.pathExtension) {
                walk.skipDescendants(); continue
            }
            if values?.isDirectory != true && ["sh", "bash", "zsh", "py", "rb", "pl", "js", "command", "applescript"].contains(url.pathExtension.lowercased()) {
                urls.append(url)
            }
        }
        return (urls, false)
    }

    static func literalLibraryPaths(in text: String, home: URL) -> [URL] {
        guard let pattern = try? NSRegularExpression(pattern: #"[\"']([^\"'\r\n]{1,512})[\"']"#) else { return [] }
        let input = text as NSString
        var found = Set<String>()
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: input.length)).prefix(256) {
            var value = input.substring(with: match.range(at: 1))
            for prefix in ["~/", "$HOME/", "${HOME}/"] where value.hasPrefix(prefix) {
                value = home.path + "/" + value.dropFirst(prefix.count)
                break
            }
            guard value.hasPrefix(home.path + "/Library/"),
                  !value.contains("$"), !value.contains("`"), !value.contains("\\"),
                  !value.contains("*"), !value.contains("?"), !value.contains("\0"),
                  !value.split(separator: "/").contains(".."),
                  value == URL(fileURLWithPath: value).standardizedFileURL.path else { continue }
            // Never treat personal documents, vendor roots or Library itself as
            // script-derived removal candidates.
            let url = URL(fileURLWithPath: value)
            let allowed = ["Application Support", "Caches", "Logs", "Preferences", "Containers", "Group Containers", "Application Scripts", "LaunchAgents"]
            guard allowed.contains(where: { value.hasPrefix(home.path + "/Library/\($0)/") }) else { continue }
            found.insert(url.path)
        }
        return found.sorted().map { URL(fileURLWithPath: $0) }
    }

    static func regularFile(_ url: URL, maximumBytes: Int) -> Data? {
        guard url.resolvingSymlinksInPath().path == url.standardizedFileURL.path else { return nil }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size >= 0, info.st_size <= maximumBytes else { return nil }
        var bytes = [UInt8](repeating: 0, count: maximumBytes + 1)
        let count = read(fd, &bytes, bytes.count)
        guard count >= 0, count <= maximumBytes else { return nil }
        return Data(bytes.prefix(count))
    }

    static func plist(_ url: URL, maximumBytes: Int) -> [String: Any]? {
        guard let bytes = regularFile(url, maximumBytes: maximumBytes) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: bytes, options: [], format: nil)) as? [String: Any]
    }

    static func isReceiptComponent(_ url: URL, home: URL) -> Bool {
        let roots = ["/Library/LaunchAgents", "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools", "/Library/Application Support",
                     home.path + "/Library/LaunchAgents", home.path + "/Library/Application Support"]
        return roots.contains { url.path.hasPrefix($0 + "/") }
    }

    static func readReceipts(_ host: URL) -> (records: [Receipt], limited: Bool) {
        let root = URL(fileURLWithPath: "/var/db/receipts").resolvingSymlinksInPath()
        guard FileManager.default.isReadableFile(atPath: root.path) else { return ([], true) }
        let entries = children(root, limit: 1_024)
        var records: [Receipt] = []
        var limited = entries.limited
        let deadline = Date().addingTimeInterval(2)
        for url in entries.urls where url.pathExtension == "plist" {
            if Task.isCancelled || Date() > deadline { limited = true; break }
            guard let info = plist(url, maximumBytes: 262_144),
                  let id = info["PackageIdentifier"] as? String,
                  let prefix = info["InstallPrefixPath"] as? String,
                  !prefix.split(separator: "/").contains("..") else { continue }
            let installRoot = URL(fileURLWithPath: prefix.hasPrefix("/") ? prefix : "/" + prefix).standardizedFileURL
            guard host.path.hasPrefix(installRoot.path == "/" ? "/" : installRoot.path + "/") else { continue }
            let bom = url.deletingPathExtension().appendingPathExtension("bom")
            let directories = receiptPaths(bom, directoriesOnly: true, deadline: deadline)
            limited = limited || directories.limited
            let appEntry = host.path.dropFirst(installRoot.path == "/" ? 1 : installRoot.path.count + 1)
            guard directories.text.split(separator: "\n").contains(where: {
                String($0).replacingOccurrences(of: "^\\./", with: "", options: .regularExpression) == appEntry
            }) else { continue }
            let output = receiptPaths(bom, directoriesOnly: false, deadline: deadline)
            limited = limited || output.limited
            let paths = output.text.split(separator: "\n").compactMap { line -> String? in
                var path = String(line)
                if path.hasPrefix("./") { path.removeFirst(2) }
                guard path != ".", !path.hasPrefix("/"), !path.contains("\0"),
                      !path.split(separator: "/").contains("..") else { return nil }
                return installRoot.appendingPathComponent(path).standardizedFileURL.path
            }
            if paths.contains(host.path) { records.append(Receipt(identifier: id, paths: paths)) }
        }
        return (records, limited)
    }

    private static func receiptPaths(_ bom: URL, directoriesOnly: Bool, deadline: Date) -> (text: String, limited: Bool) {
        guard bom.resolvingSymlinksInPath().path == bom.path,
              FileManager.default.fileExists(atPath: bom.path) else { return ("", false) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/lsbom")
        process.arguments = (directoriesOnly ? ["-s", "-d"] : ["-s"]) + [bom.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let fd = pipe.fileHandleForReading.fileDescriptor
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        do { try process.run() } catch { return ("", true) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8_192)
        var limited = false
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count > 0 { data.append(contentsOf: buffer.prefix(count)) }
            if data.count > 2_000_000 || Date() > deadline || Task.isCancelled {
                limited = true
                if process.isRunning { process.terminate() }
                break
            }
            if count == 0 { break }
            if count < 0 && errno != EAGAIN && errno != EINTR { limited = true; break }
            if count < 0 { Thread.sleep(forTimeInterval: 0.005) }
        }
        while process.isRunning && Date() < deadline && !Task.isCancelled {
            Thread.sleep(forTimeInterval: 0.005)
        }
        if process.isRunning {
            process.terminate()
            limited = true
        } else if process.terminationStatus != 0 {
            limited = true
        }
        try? pipe.fileHandleForReading.close()
        return (String(data: data, encoding: .utf8) ?? "", limited)
    }

    static func allocatedSize(_ url: URL, deadline: Date) -> UInt64? {
        guard url.resolvingSymlinksInPath().path == url.path else { return nil }
        return url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return nil }
            var roots = [UnsafeMutablePointer(mutating: path), nil]
            guard let tree = fts_open(&roots, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return nil }
            defer { fts_close(tree) }
            var blocks: UInt64 = 0
            var visited = 0
            var links = Set<String>()
            while !Task.isCancelled && Date() < deadline {
                errno = 0
                guard let entry = fts_read(tree)?.pointee else {
                    guard errno == 0 else { return nil }
                    let bytes = blocks.multipliedReportingOverflow(by: 512)
                    return bytes.overflow ? nil : bytes.partialValue
                }
                visited += 1
                if visited > 10_000 { return nil }
                let kind = Int32(entry.fts_info)
                if kind == FTS_D { continue }
                guard [FTS_DP, FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT].contains(kind),
                      let file = entry.fts_statp?.pointee, file.st_blocks >= 0 else { return nil }
                if kind != FTS_DP && file.st_nlink > 1 {
                    guard links.insert("\(file.st_dev):\(file.st_ino)").inserted else { continue }
                }
                let sum = blocks.addingReportingOverflow(UInt64(file.st_blocks))
                guard !sum.overflow else { return nil }
                blocks = sum.partialValue
            }
            return nil
        }
    }
}
