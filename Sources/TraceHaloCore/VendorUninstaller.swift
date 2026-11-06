import Foundation
import Security

public struct VendorUninstaller: Equatable, Sendable {
    public enum EntryPoint: Equatable, Sendable {
        case application(URL)
        case dockerDesktop(URL)
        case command
    }

    public let productName: String
    public let fileURL: URL
    public let entryPoint: EntryPoint
}

enum VendorUninstallerScanner {
    private static let names = ["uninstall", "uninstaller", "卸载", "卸载器"]
    private static let embeddedDirectories = [
        "Contents/Resources",
        "Contents/Resources/Uninstaller",
        "Contents/Helpers",
        "Contents/Library/Helpers",
        "Contents/MacOS"
    ]

    static func find(
        for application: ApplicationCandidate,
        signingTeam: (URL) -> String? = trustedSigningTeam
    ) -> VendorUninstaller? {
        let host = application.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        if let known = knownUninstaller(for: application, at: host, signingTeam: signingTeam) {
            return known
        }

        let productNames = [application.name, host.deletingPathExtension().lastPathComponent]
            .map(normalizedName)
            .filter { !$0.isEmpty }
        let productUninstallerNames = Set(productNames.flatMap { product in
            names.flatMap { [$0 + product, product + $0] }
        })
        let embeddedNames = productUninstallerNames.union(names)
        let embedded = embeddedDirectories.flatMap { directory in
            children(of: host.appendingPathComponent(directory, isDirectory: true))
        }.filter { file in
            file.resolvingSymlinksInPath().path.hasPrefix(host.path + "/")
                && embeddedNames.contains(normalizedName(file.deletingPathExtension().lastPathComponent))
        }
        let parent = host.deletingLastPathComponent()
        let siblings = children(of: parent).filter { file in
            file.pathExtension.lowercased() == "app"
                && productUninstallerNames.contains(normalizedName(file.deletingPathExtension().lastPathComponent))
                && file.resolvingSymlinksInPath().deletingLastPathComponent().path == parent.path
        }
        guard !embedded.isEmpty || !siblings.isEmpty, let team = signingTeam(host) else { return nil }

        for file in embedded + siblings where file.pathExtension.lowercased() == "app" {
            let target = file.resolvingSymlinksInPath()
            guard target.path != host.path,
                  Bundle(url: target)?.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL",
                  signingTeam(target) == team else { continue }
            return VendorUninstaller(productName: application.name, fileURL: file, entryPoint: .application(target))
        }

        if let file = embedded.first(where: isUninstallCommand) {
            return VendorUninstaller(productName: application.name, fileURL: file, entryPoint: .command)
        }
        return nil
    }

    private static func knownUninstaller(
        for application: ApplicationCandidate,
        at host: URL,
        signingTeam: (URL) -> String?
    ) -> VendorUninstaller? {
        if application.bundleIdentifier == "com.docker.docker" {
            let command = host.appendingPathComponent("Contents/MacOS/uninstall")
            if isUninstallCommand(command),
               command.resolvingSymlinksInPath().path.hasPrefix(host.path + "/"),
               signingTeam(host) == "9BNSXJN65R",
               signingTeam(command) == "9BNSXJN65R" {
                return VendorUninstaller(
                    productName: "Docker Desktop",
                    fileURL: command,
                    entryPoint: .dockerDesktop(host)
                )
            }
        }

        // The Applications folder can expose only the network installer and
        // the uninstaller link. The link removes the Endpoint Security product.
        let bitdefenderProductID = "com.bitdefender.EndpointSecurityforMac"
        let bitdefenderFolder = URL(fileURLWithPath: "/Applications/Bitdefender", isDirectory: true)
        let isNetworkInstaller = application.bundleIdentifier == "com.bitdefender.networkinstaller"
            && host.path == bitdefenderFolder.appendingPathComponent("SecurityNetworkInstallerApp.app").path
        guard application.bundleIdentifier == bitdefenderProductID || isNetworkInstaller else { return nil }

        let product = isNetworkInstaller
            ? URL(fileURLWithPath: "/Library/Bitdefender/AVP/product/bin/EndpointSecurityforMac.app", isDirectory: true)
            : host
        let link = bitdefenderFolder.appendingPathComponent("EndpointSecurityforMacUninstaller.app", isDirectory: true)
        let target = link.resolvingSymlinksInPath()
        let team = "GUNFMW623Y"
        guard Bundle(url: product)?.bundleIdentifier == bitdefenderProductID,
              Bundle(url: target)?.bundleIdentifier == "com.epsecurity.uninstaller",
              signingTeam(host) == team,
              (!isNetworkInstaller || signingTeam(product) == team),
              signingTeam(target) == team else { return nil }
        return VendorUninstaller(
            productName: "Bitdefender Endpoint Security Tools",
            fileURL: link,
            entryPoint: .application(target)
        )
    }

    private static func children(of directory: URL) -> [URL] {
        let children = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return (children ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func normalizedName(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func isUninstallCommand(_ url: URL) -> Bool {
        let target = url.resolvingSymlinksInPath()
        let ext = target.pathExtension.lowercased()
        return ["", "command", "sh"].contains(ext)
            && (try? target.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            && FileManager.default.isExecutableFile(atPath: target.path)
    }

    private static func trustedSigningTeam(at url: URL) -> String? {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        var information: CFDictionary?
        let signingInformation = SecCSFlags(rawValue: UInt32(kSecCSSigningInformation))
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
              let code,
              SecRequirementCreateWithString("anchor apple generic" as CFString, [], &requirement) == errSecSuccess,
              let requirement,
              SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess,
              SecCodeCopySigningInformation(code, signingInformation, &information) == errSecSuccess,
              let values = information as? [String: Any],
              let team = values[kSecCodeInfoTeamIdentifier as String] as? String,
              !team.isEmpty else { return nil }
        return team
    }
}
