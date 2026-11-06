import Darwin
import Foundation
import Security
import SystemConfiguration
import TraceHaloCore

private final class PrivilegedUninstallService: NSObject, PrivilegedUninstallXPCProtocol {
    private enum Operation {
        case preflight
        case move
    }

    private static let moveLock = NSLock()
    private static let directoryFlags = O_RDONLY | O_DIRECTORY | O_CLOEXEC
    private let user: uid_t

    init(user: uid_t) {
        self.user = user
    }

    func checkTrashAccess(withReply reply: @escaping (NSError?) -> Void) {
        do {
            try validateCaller()
            try withTrashDirectory { _, _, _ in }
            reply(nil)
        } catch {
            reply(error as NSError)
        }
    }

    func preflightApplicationMove(
        _ target: Data,
        authorization: Data,
        withReply reply: @escaping (NSError?) -> Void
    ) {
        handle(.preflight, target: target, authorization: authorization, reply: reply)
    }

    func moveApplicationToTrash(
        _ target: Data,
        authorization: Data,
        withReply reply: @escaping (NSError?) -> Void
    ) {
        handle(.move, target: target, authorization: authorization, reply: reply)
    }

    private func handle(
        _ operation: Operation,
        target: Data,
        authorization: Data,
        reply: (NSError?) -> Void
    ) {
        do {
            try Self.moveLock.withLock {
                try validateCaller()
                guard target.count <= 16_384,
                      let target = try? JSONDecoder().decode(PrivilegedUninstallTarget.self, from: target),
                      let name = target.applicationName else {
                    throw POSIXError(.EINVAL)
                }
                try Self.withAdministratorAuthorization(authorization, for: operation) {
                    try checkOrMoveToTrash(target, name: name, operation: operation)
                }
            }
            reply(nil)
        } catch {
            reply(error as NSError)
        }
    }

    private func validateCaller() throws {
        guard geteuid() == 0, Self.isConsoleUser(user),
              RuntimeSafetyMode.current == .live else {
            throw POSIXError(.EPERM)
        }
    }

    static func isConsoleUser(_ user: uid_t) -> Bool {
        var consoleUser: uid_t = 0
        return user != 0 && SCDynamicStoreCopyConsoleUser(nil, &consoleUser, nil) != nil
            && user == consoleUser
    }

    private static func withAdministratorAuthorization(
        _ authorization: Data,
        for operation: Operation,
        perform action: () throws -> Void
    ) throws {
        var externalForm = AuthorizationExternalForm()
        guard authorization.count == MemoryLayout.size(ofValue: externalForm) else {
            throw POSIXError(.EINVAL)
        }
        withUnsafeMutableBytes(of: &externalForm) { buffer in
            _ = authorization.copyBytes(to: buffer)
        }

        var reference: AuthorizationRef?
        let importStatus = AuthorizationCreateFromExternalForm(&externalForm, &reference)
        guard importStatus == errAuthorizationSuccess, let reference else {
            throw authorizationError(importStatus == errAuthorizationSuccess ? errAuthorizationInvalidRef : importStatus)
        }
        defer { AuthorizationFree(reference, operation == .move ? .destroyRights : []) }
        var grantedRights: UnsafeMutablePointer<AuthorizationRights>?
        defer { if let grantedRights { AuthorizationFreeItemSet(grantedRights) } }
        let status = PrivilegedUninstallConstants.authorizationRight.withCString { right in
            var item = AuthorizationItem(name: right, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { item in
                var rights = AuthorizationRights(count: 1, items: item)
                return AuthorizationCopyRights(reference, &rights, nil, [], &grantedRights)
            }
        }
        guard status == errAuthorizationSuccess else { throw authorizationError(status) }
        guard let grantedRights, grantedRights.pointee.count == 1,
              let granted = grantedRights.pointee.items?.pointee,
              String(cString: granted.name) == PrivilegedUninstallConstants.authorizationRight,
              granted.flags & UInt32(kAuthorizationFlagCanNotPreAuthorize) == 0 else {
            throw authorizationError(errAuthorizationDenied)
        }
        try action()
    }

    private static func authorizationError(_ status: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }

    private func checkOrMoveToTrash(
        _ target: PrivilegedUninstallTarget,
        name: String,
        operation: Operation
    ) throws {
        let applications = open("/Applications", Self.directoryFlags | O_NOFOLLOW_ANY)
        guard applications >= 0 else { throw Self.posixError() }
        defer { close(applications) }
        let applicationsInfo = try Self.metadata(for: applications)
        guard applicationsInfo.st_uid == 0,
              applicationsInfo.st_mode & S_IWOTH == 0,
              applicationsInfo.st_mode & S_IWGRP == 0
                || applicationsInfo.st_gid == getgrnam("admin")?.pointee.gr_gid else {
            throw POSIXError(.EPERM)
        }
        // Only root and administrators may replace directory entries between validation and rename.
        if let acl = acl_get_fd_np(applications, ACL_TYPE_EXTENDED) {
            defer { acl_free(UnsafeMutableRawPointer(acl)) }
            var entry: acl_entry_t?
            guard acl_get_entry(acl, Int32(ACL_FIRST_ENTRY.rawValue), &entry) == -1, errno == EINVAL else {
                throw POSIXError(.EPERM)
            }
        } else if errno != ENOENT && errno != ENOATTR {
            throw Self.posixError()
        }

        let bundle = openat(applications, name, Self.directoryFlags | O_NOFOLLOW)
        guard bundle >= 0 else { throw Self.posixError() }
        defer { close(bundle) }
        guard target.matchesEligibleBundle(try Self.metadata(for: bundle)) else {
            throw POSIXError(.ESTALE)
        }
        try Self.validateBundleInfo(in: bundle)

        try withTrashDirectory { home, trash, trashInfo in
            try checkOrMove(target, name: name, operation: operation, applications: applications,
                            home: home, trash: trash, trashInfo: trashInfo)
        }
    }

    private func withTrashDirectory(
        _ use: (_ home: Int32, _ trash: Int32, _ info: stat) throws -> Void
    ) throws {
        let home = open(try Self.homePath(for: user), Self.directoryFlags | O_NOFOLLOW_ANY)
        guard home >= 0 else { throw Self.posixError() }
        defer { close(home) }
        guard try Self.metadata(for: home).st_uid == user else { throw POSIXError(.EPERM) }

        let trash = openat(home, ".Trash", Self.directoryFlags | O_NOFOLLOW)
        if trash < 0 {
            let code = errno
            if code == EPERM || code == EACCES {
                throw NSError(domain: PrivilegedUninstallConstants.errorDomain,
                              code: PrivilegedUninstallConstants.trashAccessDeniedErrorCode)
            }
            throw Self.posixError(code)
        }
        defer { close(trash) }
        let trashInfo = try Self.metadata(for: trash)
        guard trashInfo.st_uid == user, trashInfo.st_mode & (S_IWGRP | S_IWOTH) == 0 else {
            throw POSIXError(.EPERM)
        }
        try use(home, trash, trashInfo)
    }

    private func checkOrMove(
        _ target: PrivilegedUninstallTarget,
        name: String,
        operation: Operation,
        applications: Int32,
        home: Int32,
        trash: Int32,
        trashInfo: stat
    ) throws {
        guard trashInfo.st_dev == target.device else { throw POSIXError(.EXDEV) }

        var currentBundle = stat()
        var currentTrash = stat()
        func validateCurrentPaths() throws {
            guard fstatat(applications, name, &currentBundle, AT_SYMLINK_NOFOLLOW) == 0,
                  target.matchesEligibleBundle(currentBundle),
                  fstatat(home, ".Trash", &currentTrash, AT_SYMLINK_NOFOLLOW) == 0,
                  Self.sameFile(currentTrash, trashInfo),
                  Self.isConsoleUser(user) else {
                throw POSIXError(.ESTALE)
            }
        }

        var existingDestination = stat()
        guard fstatat(trash, name, &existingDestination, AT_SYMLINK_NOFOLLOW) == 0 || errno == ENOENT else {
            throw Self.posixError()
        }
        try validateCurrentPaths()
        guard operation == .move else { return }

        var destination = name
        if renameatx_np(applications, name, trash, destination, UInt32(RENAME_EXCL)) != 0 {
            guard errno == EEXIST else { throw Self.posixError() }
            destination = "TraceHalo-\(UUID().uuidString).app"
            try validateCurrentPaths()
            guard renameatx_np(applications, name, trash, destination, UInt32(RENAME_EXCL)) == 0 else {
                throw Self.posixError()
            }
        }

        var moved = stat()
        guard fstatat(trash, destination, &moved, AT_SYMLINK_NOFOLLOW) == 0,
              target.matchesEligibleBundle(moved),
              fstatat(applications, name, &currentBundle, AT_SYMLINK_NOFOLLOW) == -1,
              errno == ENOENT,
              fstatat(home, ".Trash", &currentTrash, AT_SYMLINK_NOFOLLOW) == 0,
              Self.sameFile(currentTrash, trashInfo) else {
            throw NSError(
                domain: PrivilegedUninstallConstants.errorDomain,
                code: PrivilegedUninstallConstants.unconfirmedMoveErrorCode
            )
        }
    }

    private static func homePath(for user: uid_t) throws -> String {
        var account = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 16_384)
        return try buffer.withUnsafeMutableBufferPointer { buffer in
            let status = getpwuid_r(user, &account, buffer.baseAddress, buffer.count, &result)
            guard status == 0 else { throw posixError(status) }
            guard result != nil, let directory = account.pw_dir,
                  let path = String(validatingCString: directory),
                  path.hasPrefix("/"), path != "/" else {
                throw POSIXError(.ENOENT)
            }
            return path
        }
    }

    private static func validateBundleInfo(in bundle: Int32) throws {
        let contents = openat(bundle, "Contents", directoryFlags | O_NOFOLLOW)
        guard contents >= 0 else { throw posixError() }
        defer { close(contents) }
        let info = openat(contents, "Info.plist", O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard info >= 0 else { throw posixError() }
        let file = FileHandle(fileDescriptor: info, closeOnDealloc: true)
        defer { try? file.close() }
        let metadata = try self.metadata(for: info)
        let maxSize = 1_048_576
        guard metadata.st_mode & S_IFMT == S_IFREG, (1...Int64(maxSize)).contains(metadata.st_size),
              let data = try file.read(upToCount: maxSize + 1), data.count <= maxSize,
              let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              PrivilegedUninstallTarget.isThirdPartyApplication(plist) else {
            throw POSIXError(.EINVAL)
        }
    }

    private static func metadata(for descriptor: Int32) throws -> stat {
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else { throw posixError() }
        return metadata
    }

    private static func sameFile(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino
    }

    private static func posixError(_ code: Int32 = errno) -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
}

private final class PrivilegedUninstallListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        let user = connection.effectiveUserIdentifier
        guard PrivilegedUninstallService.isConsoleUser(user) else { return false }
        connection.exportedInterface = NSXPCInterface(with: PrivilegedUninstallXPCProtocol.self)
        connection.exportedObject = PrivilegedUninstallService(user: user)
        connection.activate()
        return true
    }
}

@main
private enum PrivilegedUninstallMain {
    static func main() {
        guard geteuid() == 0, RuntimeSafetyMode.current == .live else { return }
        let delegate = PrivilegedUninstallListenerDelegate()
        let listener = NSXPCListener(machServiceName: PrivilegedUninstallConstants.machServiceName)
        listener.setConnectionCodeSigningRequirement(PrivilegedUninstallConstants.clientSigningRequirement)
        listener.delegate = delegate
        listener.activate()
        withExtendedLifetime(delegate) { RunLoop.current.run() }
    }
}
