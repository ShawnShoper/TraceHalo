import Foundation

public enum RuntimeSafetyMode: String, Sendable {
    case live
    case safeTest

    public static var current: RuntimeSafetyMode {
        resolve(
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment
        )
    }

    public static func resolve(
        arguments: [String],
        environment: [String: String]
    ) -> RuntimeSafetyMode {
        if arguments.contains("--safe-test-mode")
            || environment["TRACEHALO_SAFE_TEST_MODE"] == "1"
            || environment[TraceHaloLegacyIdentifiers.safeTestEnvironmentKey] == "1" {
            return .safeTest
        }
        return .live
    }
}

public enum MutationKind: String, Sendable {
    case uninstall
    case startupItemChange
    case launchAtLogin
    case feedbackSubmission
    case updateInstallation

    func localizedTitle(locale: Locale? = nil) -> String {
        switch self {
        case .uninstall: TraceHaloLocalization.string("mutation.uninstall", defaultValue: "uninstall", locale: locale)
        case .startupItemChange: TraceHaloLocalization.string("mutation.startupItem", defaultValue: "startup item change", locale: locale)
        case .launchAtLogin: TraceHaloLocalization.string("mutation.launchAtLogin", defaultValue: "launch at login", locale: locale)
        case .feedbackSubmission: TraceHaloLocalization.string("mutation.feedback", defaultValue: "feedback submission", locale: locale)
        case .updateInstallation: TraceHaloLocalization.string("mutation.update", defaultValue: "update installation", locale: locale)
        }
    }
}

public enum SafetyViolation: LocalizedError, Equatable, Sendable {
    case deniedInSafeTestMode(MutationKind)
    case invalidTarget(String)
    case unsupported(String)

    public var errorDescription: String? {
        localizedDescription()
    }

    public func localizedDescription(locale: Locale? = nil) -> String {
        switch self {
        case let .deniedInSafeTestMode(kind):
            TraceHaloLocalization.format(
                "safety.denied",
                defaultValue: "Safe Test Mode blocked the %@ operation.",
                locale: locale,
                kind.localizedTitle(locale: locale)
            )
        case let .invalidTarget(reason), let .unsupported(reason):
            reason
        }
    }
}

public struct DestructiveTargetValidator: Sendable {
    private let forbiddenExactPaths: Set<String> = [
        "/",
        "/Applications",
        "/Library",
        "/System",
        "/Users"
    ]

    public init() {}

    public func validate(paths: [String], homeDirectory: String = NSHomeDirectory()) throws {
        guard !paths.isEmpty else {
            throw SafetyViolation.invalidTarget(
                TraceHaloLocalization.string(
                    "safety.noTargets",
                    defaultValue: "There are no targets to process."
                )
            )
        }

        let normalizedHome = URL(fileURLWithPath: homeDirectory).standardizedFileURL.path
        for path in paths {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw SafetyViolation.invalidTarget(
                    TraceHaloLocalization.string(
                        "safety.emptyPath",
                        defaultValue: "A target path cannot be empty."
                    )
                )
            }
            let expanded = (trimmed as NSString).expandingTildeInPath
            guard expanded.hasPrefix("/") else {
                throw SafetyViolation.invalidTarget(
                    TraceHaloLocalization.format(
                        "safety.absolutePathRequired",
                        defaultValue: "The target must be an absolute path: %@",
                        path
                    )
                )
            }
            let normalized = URL(fileURLWithPath: expanded).standardizedFileURL.path
            if forbiddenExactPaths.contains(normalized) || normalized == normalizedHome {
                throw SafetyViolation.invalidTarget(
                    TraceHaloLocalization.format(
                        "safety.highRiskRoot",
                        defaultValue: "Refusing to process a high-risk root directory: %@",
                        normalized
                    )
                )
            }
        }
    }
}

/// Pure path policy used before any filesystem metadata is read. It intentionally
/// allows only application bundles in Applications and associated items in the
/// current user's non-shared Library subdirectories.
public struct UninstallPathPolicy: Sendable {
    public init() {}

    public func validate(
        applicationPath: String,
        associatedPaths: [String],
        homeDirectory: String = NSHomeDirectory()
    ) throws {
        let home = URL(fileURLWithPath: homeDirectory).standardizedFileURL
        let application = URL(fileURLWithPath: applicationPath).standardizedFileURL
        guard application.pathExtension.lowercased() == "app" else {
            throw SafetyViolation.invalidTarget(
                TraceHaloLocalization.string(
                    "safety.appBundleRequired",
                    defaultValue: "The application target must be an .app bundle."
                )
            )
        }
        let applicationRoots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true)
        ]
        guard isStrictDescendant(application, ofAny: applicationRoots) else {
            throw SafetyViolation.invalidTarget(
                TraceHaloLocalization.string(
                    "safety.applicationsOnly",
                    defaultValue: "Only applications inside an Applications directory can be moved to the Trash."
                )
            )
        }

        let associatedRoots = [
            "Application Support",
            "Caches",
            "Containers",
            "Preferences",
            "Logs",
            "LaunchAgents",
            "Application Scripts",
            "Saved Application State",
            "WebKit",
            "HTTPStorages"
        ].map { home.appendingPathComponent("Library/\($0)", isDirectory: true) }

        var seen = Set([application.path])
        for path in associatedPaths {
            let URL = URL(fileURLWithPath: path).standardizedFileURL
            guard seen.insert(URL.path).inserted else {
                throw SafetyViolation.invalidTarget(
                    TraceHaloLocalization.format(
                        "safety.duplicateTarget",
                        defaultValue: "The uninstall plan contains a duplicate target: %@",
                        URL.path
                    )
                )
            }
            guard isStrictDescendant(URL, ofAny: associatedRoots) else {
                throw SafetyViolation.invalidTarget(
                    TraceHaloLocalization.format(
                        "safety.associatedOutsideLibrary",
                        defaultValue: "The associated file is outside the allowed user Library directories: %@",
                        URL.path
                    )
                )
            }
        }
    }

    private func isStrictDescendant(_ URL: URL, ofAny roots: [URL]) -> Bool {
        let path = URL.standardizedFileURL.path
        return roots.contains { root in
            let rootPath = root.standardizedFileURL.path
            return path != rootPath && path.hasPrefix(rootPath + "/")
        }
    }
}

public protocol UninstallExecuting: Sendable {
    func execute(plan: UninstallPlan) async throws
}

public struct DenyAllUninstallExecutor: UninstallExecuting {
    public init() {}

    public func execute(plan: UninstallPlan) async throws {
        throw SafetyViolation.deniedInSafeTestMode(.uninstall)
    }
}

public protocol StartupItemMutating: Sendable {
    func setEnabled(_ enabled: Bool, item: StartupItem) async throws
}

public struct DenyAllStartupItemMutator: StartupItemMutating {
    public init() {}

    public func setEnabled(_ enabled: Bool, item: StartupItem) async throws {
        throw SafetyViolation.deniedInSafeTestMode(.startupItemChange)
    }
}
