import Darwin
import Foundation

public enum PrivilegedUninstallConstants {
    public static let machServiceName = "com.tseai.tracehalo.uninstall-helper"
    public static let launchDaemonPlistName = "com.tseai.tracehalo.uninstall-helper.plist"
    public static let authorizationRight = "system.privilege.admin"
    public static let errorDomain = machServiceName
    public static let unconfirmedMoveErrorCode = 1
    public static let trashAccessDeniedErrorCode = 2

    // An ad-hoc signature or a development build with get-task-allow must
    // never be able to impersonate either end of the privileged connection.
    private static let developerIDRequirement =
        """
        anchor apple generic and certificate leaf[subject.OU] = "4DXU5FSLLY" \
        and certificate leaf[field.1.2.840.113635.100.6.1.13] exists \
        and !entitlement["com.apple.security.get-task-allow"] exists
        """

    public static let clientSigningRequirement =
        "identifier \"com.tseai.tracehalo\" and \(developerIDRequirement)"
    public static let helperSigningRequirement =
        "identifier \"\(machServiceName)\" and \(developerIDRequirement)"
}

public struct PrivilegedUninstallTarget: Codable, Equatable, Sendable {
    public let path: String
    public let device: Int32
    public let inode: UInt64

    public var applicationName: String? {
        Self.directApplicationName(for: path)
    }

    public static func captureIfNeeded(applicationURL: URL) throws -> Self? {
        guard applicationURL.isFileURL else { return nil }
        let path = applicationURL.standardizedFileURL.path
        guard directApplicationName(for: path) != nil else { return nil }

        var metadata = stat()
        guard lstat(path, &metadata) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard isEligibleBundle(metadata),
              let info = Bundle(url: URL(fileURLWithPath: path))?.infoDictionary,
              isThirdPartyApplication(info) else {
            return nil
        }
        return Self(path: path, device: metadata.st_dev, inode: metadata.st_ino)
    }

    public func matchesEligibleBundle(_ metadata: stat) -> Bool {
        metadata.st_dev == device && metadata.st_ino == inode && Self.isEligibleBundle(metadata)
    }

    public static func isThirdPartyApplication(_ info: [String: Any]) -> Bool {
        guard info["CFBundlePackageType"] == nil || info["CFBundlePackageType"] as? String == "APPL",
              let identifier = (info["CFBundleIdentifier"] as? String)?.lowercased() else {
            return false
        }
        return !identifier.isEmpty && identifier != "com.tseai.tracehalo"
            && identifier != "com.apple" && !identifier.hasPrefix("com.apple.")
    }

    private static func directApplicationName(for path: String) -> String? {
        let parent = "/Applications/"
        guard path.hasPrefix(parent) else { return nil }
        let name = String(path.dropFirst(parent.count))
        guard !name.contains("/"), !name.utf8.contains(0),
              name.utf8.count <= Int(NAME_MAX),
              name.count > 4, name.lowercased().hasSuffix(".app"),
              name.lowercased() != "tracehalo.app" else {
            return nil
        }
        return name
    }

    private static func isEligibleBundle(_ metadata: stat) -> Bool {
        let protectedFlags = UInt32(UF_IMMUTABLE | UF_APPEND | UF_DATAVAULT
            | SF_IMMUTABLE | SF_APPEND | SF_RESTRICTED | SF_NOUNLINK)
        return (metadata.st_mode & S_IFMT) == S_IFDIR
            && metadata.st_uid == 0
            && metadata.st_flags & protectedFlags == 0
    }
}

@objc public protocol PrivilegedUninstallXPCProtocol {
    func checkTrashAccess(withReply reply: @escaping (NSError?) -> Void)

    func preflightApplicationMove(
        _ target: Data,
        authorization: Data,
        withReply reply: @escaping (NSError?) -> Void
    )

    func moveApplicationToTrash(
        _ target: Data,
        authorization: Data,
        withReply reply: @escaping (NSError?) -> Void
    )
}
