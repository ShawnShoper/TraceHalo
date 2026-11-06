import Foundation
import XCTest
@testable import TraceHaloCore

final class VendorUninstallerTests: XCTestCase {
    func testSignedProductSpecificSiblingOpensItsApp() throws {
        let root = try temporaryDirectory()
        let host = try makeBundle("Photo Editor.app", in: root)
        let uninstaller = try makeBundle("Uninstall Photo Editor.app", in: root)
        _ = try makeBundle("Uninstall Calendar.app", in: root)

        let result = VendorUninstallerScanner.find(for: candidate(host)) { _ in "VENDOR" }

        XCTAssertEqual(result?.fileURL.resolvingSymlinksInPath().path, uninstaller.resolvingSymlinksInPath().path)
        XCTAssertEqual(result?.entryPoint, .application(uninstaller.resolvingSymlinksInPath()))
    }

    func testGenericSiblingAndMismatchedSignerAreIgnored() throws {
        let root = try temporaryDirectory()
        let host = try makeBundle("Photo Editor.app", in: root)
        let uninstaller = try makeBundle("Photo Editor Uninstaller.app", in: root)
        _ = try makeBundle("Uninstaller.app", in: root)

        let result = VendorUninstallerScanner.find(for: candidate(host)) { url in
            url.resolvingSymlinksInPath().path == uninstaller.resolvingSymlinksInPath().path ? "OTHER" : "VENDOR"
        }

        XCTAssertNil(result)
    }

    func testEmbeddedCommandOffersFinderLocationAndRejectsEscapingLink() throws {
        let root = try temporaryDirectory()
        let host = try makeBundle("Photo Editor.app", in: root)
        let resources = host.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let external = root.appendingPathComponent("other-tool")
        let command = resources.appendingPathComponent("uninstall.command")
        try writeExecutable(at: external)
        try FileManager.default.createSymbolicLink(at: command, withDestinationURL: external)

        XCTAssertNil(VendorUninstallerScanner.find(for: candidate(host)) { _ in "VENDOR" })

        try FileManager.default.removeItem(at: command)
        try writeExecutable(at: command)
        let result = VendorUninstallerScanner.find(for: candidate(host)) { _ in "VENDOR" }
        XCTAssertEqual(result?.fileURL.resolvingSymlinksInPath().path, command.resolvingSymlinksInPath().path)
        XCTAssertEqual(result?.entryPoint, .command)
    }

    func testDockerEntryOpensHostApplicationInsteadOfCommand() throws {
        let root = try temporaryDirectory()
        let host = try makeBundle("Docker.app", in: root)
        let executables = host.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: executables, withIntermediateDirectories: true)
        let command = executables.appendingPathComponent("uninstall")
        try writeExecutable(at: command)
        let docker = ApplicationCandidate(name: "Docker", bundleIdentifier: "com.docker.docker", version: nil, bundleURL: host)

        let result = VendorUninstallerScanner.find(for: docker) { _ in "9BNSXJN65R" }

        XCTAssertEqual(result?.fileURL.path, command.path)
        XCTAssertEqual(result?.entryPoint, .dockerDesktop(host))
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }

    private func makeBundle(_ name: String, in parent: URL) throws -> URL {
        let bundle = parent.appendingPathComponent(name, isDirectory: true)
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundlePackageType": "APPL"],
            format: .xml,
            options: 0
        )
        try info.write(to: contents.appendingPathComponent("Info.plist"))
        return bundle
    }

    private func candidate(_ bundle: URL) -> ApplicationCandidate {
        ApplicationCandidate(name: "Photo Editor", bundleIdentifier: nil, version: nil, bundleURL: bundle)
    }

    private func writeExecutable(at url: URL) throws {
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
