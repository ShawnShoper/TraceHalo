import Foundation
import XCTest
@testable import TraceHaloCore

final class ApplicationDataDiscoveryTests: XCTestCase {
    private var home: URL!
    private var app: ApplicationCandidate!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("TraceHalo-discovery-\(UUID().uuidString)")
        app = try bundle("Applications/Example.app", id: "com.example.app")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: home) }

    @discardableResult
    private func file(_ relative: String, text: String = "data") throws -> URL {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func bundle(_ relative: String, id: String) throws -> ApplicationCandidate {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": id, "CFBundleName": "Example", "CFBundleVersion": "1", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: url.appendingPathComponent("Contents/Info.plist"))
        return ApplicationCandidate(name: "Example", bundleIdentifier: id, version: "1", bundleURL: url)
    }

    private func discovery(signatures: [String: ApplicationDataDiscovery.Signature] = [:], others: [ApplicationCandidate] = [],
                           receipts: [ApplicationDataDiscovery.Receipt] = []) -> ApplicationDataDiscovery {
        ApplicationDataDiscovery(home: home, applications: [app] + others,
            signature: { signatures[$0.path] }, receipts: { _ in (receipts, false) })
    }

    private func association(_ url: URL, category: AssociatedFileCategory = .cache,
                             basis: AssociatedFileMatchBasis = .exactBundleIdentifier("com.example.app")) -> AssociatedFile {
        AssociatedFile(path: url.path, category: category, ownershipReason: "fixture", matchBasis: basis)
    }

    func testWeakSourcesAreSelectableWithOwnershipWarnings() throws {
        let path = try file("Library/Caches/Example")
        let result = discovery().discover(for: app, base: [association(path, basis: .applicationName("Example"))])
        XCTAssertTrue(try XCTUnwrap(result.files.first).isEligibleForCleanup)
        XCTAssertTrue(result.files[0].isEligibleForBulkSelection)
        XCTAssertEqual(result.files[0].retentionReason, .uncertain)
        XCTAssertTrue(result.files[0].cleanupWarnings.contains(.uncertain))
        XCTAssertFalse(result.files[0].isSelected)
        XCTAssertTrue(association(path, basis: .unspecified).isEligibleForCleanup)
        XCTAssertTrue(association(path, basis: .unspecified).cleanupWarnings.contains(.uncertain))
    }

    func testDuplicateInstalledIdentifierMarksSelectableCacheAsShared() throws {
        let path = try file("Library/Caches/com.example.app")
        let other = try bundle("Applications/OtherCopy.app", id: "com.example.app")
        let result = discovery(others: [other]).discover(for: app, base: [association(path)])
        XCTAssertEqual(result.files[0].retentionReason, .shared)
        XCTAssertTrue(result.files[0].isEligibleForCleanup)
        XCTAssertEqual(result.files[0].cleanupWarnings, [.shared])
    }

    func testSignedComponentAndAppGroupsAreDiscoveredWithDifferentPermissions() throws {
        let plugin = try bundle("Applications/Example.app/Contents/PlugIns/Widget.appex", id: "com.example.widget")
        let cache = try file("Library/Caches/com.example.widget/cache") .deletingLastPathComponent()
        let group = try file("Library/Group Containers/team.shared/data").deletingLastPathComponent()
        let signed: [String: ApplicationDataDiscovery.Signature] = [
            app.id: .init(identifier: "com.example.app", team: "TEAM", groups: ["team.shared", "../bad"]),
            plugin.id: .init(identifier: "com.example.widget", team: "TEAM")]
        let metadata = ApplicationDataDiscovery.components(in: app.bundleURL)
        XCTAssertEqual(metadata.urls.map(\.path), [plugin.id])
        XCTAssertNotNil(ApplicationDataDiscovery.plist(plugin.bundleURL.appendingPathComponent("Contents/Info.plist"), maximumBytes: 262_144))
        let result = discovery(signatures: signed).discover(for: app, base: [])
        XCTAssertEqual(result.summary.signedComponentCount, 1)
        XCTAssertTrue(result.summary.signatureVerified)
        XCTAssertTrue(try XCTUnwrap(result.files.first { $0.path == cache.path }).isEligibleForBulkSelection)
        let shared = try XCTUnwrap(result.files.first { $0.path == group.path })
        XCTAssertEqual(shared.dataPurpose, .shared)
        XCTAssertEqual(shared.retentionReason, .shared)
        XCTAssertTrue(shared.isEligibleForCleanup)
        XCTAssertTrue(shared.isEligibleForBulkSelection)
        XCTAssertEqual(shared.cleanupWarnings, [.shared])
        XCTAssertFalse(shared.isSelected)
        XCTAssertNotNil(shared.sizeBytes, "Selectable shared data uses the same bounded size measurement")
    }

    func testForeignOrUnverifiedComponentsCannotGrantCleanup() throws {
        let plugin = try bundle("Applications/Example.app/Contents/PlugIns/Foreign.appex", id: "com.other.plugin")
        try file("Library/Caches/com.other.plugin/cache")
        let signed: [String: ApplicationDataDiscovery.Signature] = [
            app.id: .init(identifier: "com.example.app", team: "TEAM"),
            plugin.id: .init(identifier: "com.other.plugin", team: "OTHER")]
        let result = discovery(signatures: signed).discover(for: app, base: [])
        XCTAssertTrue(result.files.isEmpty)
        XCTAssertEqual(result.summary.signedComponentCount, 0)
    }

    func testOtherAppComponentClaimProtectsComponentData() throws {
        let plugin = try bundle("Applications/Example.app/Contents/XPCServices/Service.xpc", id: "com.example.service")
        let other = try bundle("Applications/Other.app", id: "com.other.app")
        _ = try bundle("Applications/Other.app/Contents/XPCServices/Service.xpc", id: "com.example.service")
        try file("Library/Caches/com.example.service/cache")
        let signed: [String: ApplicationDataDiscovery.Signature] = [
            app.id: .init(identifier: "com.example.app", team: "TEAM"),
            plugin.id: .init(identifier: "com.example.service", team: "TEAM")]
        let result = discovery(signatures: signed, others: [other]).discover(for: app, base: [])
        XCTAssertEqual(result.files.first?.retentionReason, .shared)
    }

    func testLiteralPathExtractionRejectsDynamicPersonalAndTraversalPaths() {
        let text = #"""
        "$HOME/Library/Application Support/Example"
        '~/Library/Caches/Example'
        "${HOME}/Library/Logs/Example"
        "$HOME/Documents/important.txt"
        "$HOME/Library/"
        "$HOME/Library/Caches/../Preferences/a"
        "$HOME/Library/Caches/$APP"
        "$HOME/Library/Caches/$(whoami)"
        "$HOME/Library/Caches/*"
        "$HOME/Library/Caches/`whoami`"
        "~/Library/Caches"
        """#
        let paths = ApplicationDataDiscovery.literalLibraryPaths(in: text, home: home)
        XCTAssertEqual(paths.count, 3)
        XCTAssertTrue(paths.allSatisfy { $0.path.hasPrefix(home.path + "/Library/") })
    }

    func testScriptIsNeverExecutedAndItsNewCandidateCarriesOwnershipWarning() throws {
        let data = try file("Library/Application Support/Uncertain/file").deletingLastPathComponent()
        let marker = home.appendingPathComponent("SCRIPT_EXECUTED")
        try file("Applications/Example.app/Contents/Resources/discover.sh",
                 text: "#!/bin/sh\ntouch '\(marker.path)'\necho '$HOME/Library/Application Support/Uncertain'\n")
        let result = discovery().discover(for: app, base: [])
        XCTAssertEqual(result.summary.scriptCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        let found = try XCTUnwrap(result.files.first { $0.path == data.path })
        XCTAssertTrue(found.isEligibleForCleanup)
        XCTAssertEqual(found.retentionReason, .uncertain)
        XCTAssertTrue(found.cleanupWarnings.contains(.uncertain))
        XCTAssertFalse(found.isSelected)
    }

    func testScriptReferenceAddsEvidenceWithoutDowngradingAnExactMatch() throws {
        let path = try file("Library/Caches/com.example.app/cache").deletingLastPathComponent()
        try file("Applications/Example.app/Contents/Resources/setup.py", text: "path = '~/Library/Caches/com.example.app'")
        let result = discovery().discover(for: app, base: [association(path)])
        XCTAssertTrue(result.files[0].isEligibleForBulkSelection)
        XCTAssertEqual(result.files[0].additionalEvidence.count, 1)
    }

    func testScriptSymlinkAndOversizedTextAreNotRead() throws {
        let external = try file("outside.sh", text: "'~/Library/Caches/Example'")
        let link = app.bundleURL.appendingPathComponent("Contents/Resources/link.sh")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
        try file("Applications/Example.app/Contents/Resources/large.sh", text: String(repeating: "x", count: 300_000))
        let result = discovery().discover(for: app, base: [])
        XCTAssertEqual(result.summary.scriptCount, 0)
        XCTAssertTrue(result.files.isEmpty)
    }

    func testSymlinkDataCannotBeSelectedAndIsNotMeasured() throws {
        let original = try file("unrelated/file").deletingLastPathComponent()
        let link = home.appendingPathComponent("Library/Caches/com.example.app")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        let result = discovery().discover(for: app, base: [association(link)])
        XCTAssertEqual(result.files[0].retentionReason, .symbolicLink)
        XCTAssertFalse(result.files[0].isEligibleForCleanup)
        XCTAssertNil(result.files[0].sizeBytes)
    }

    func testReceiptNeedsExactAppEntryAndScopedCandidatesCarryOwnershipWarnings() throws {
        let component = try file("Library/LaunchAgents/vendor.other.plist")
        let unrelated = ApplicationDataDiscovery.Receipt(identifier: "unrelated", paths: [app.id + "2", component.path])
        XCTAssertTrue(discovery(receipts: [unrelated]).discover(for: app, base: []).files.isEmpty)
        let receipt = ApplicationDataDiscovery.Receipt(identifier: "vendor.pkg", paths: [app.id, component.path])
        let result = discovery(receipts: [receipt]).discover(for: app, base: [])
        XCTAssertEqual(result.summary.receiptCount, 1)
        XCTAssertEqual(result.files.count, 1)
        XCTAssertTrue(result.files[0].isEligibleForBulkSelection)
        XCTAssertEqual(result.files[0].retentionReason, .uncertain)
        XCTAssertTrue(result.files[0].cleanupWarnings.contains(.uncertain))
    }

    func testReceiptDoesNotListPersonalDocumentsOrSharedDirectories() throws {
        let document = try file("Documents/important.txt")
        let directory = try file("Library/Application Support/Vendor/important.txt").deletingLastPathComponent()
        let receipt = ApplicationDataDiscovery.Receipt(identifier: "vendor.pkg", paths: [app.id, document.path, directory.path])
        XCTAssertTrue(discovery(receipts: [receipt]).discover(for: app, base: []).files.isEmpty)
    }

    func testDocumentedRulesRequireVerifiedIdentityAndTeam() throws {
        app.bundleIdentifier = "com.google.Chrome"
        let profile = try file("Library/Application Support/Google/Chrome/Default/content").deletingLastPathComponent().deletingLastPathComponent()
        let signed = ApplicationDataDiscovery.Signature(identifier: "com.google.Chrome", team: "EQHXZ8M8AV")
        let result = discovery(signatures: [app.id: signed]).discover(for: app, base: [])
        let found = try XCTUnwrap(result.files.first { $0.path == profile.path })
        XCTAssertTrue(found.isEligibleForCleanup)
        XCTAssertTrue(found.isEligibleForBulkSelection)
        XCTAssertEqual(found.cleanupWarnings, [.savedContent])
        XCTAssertEqual(found.dataPurpose, .browserProfile)
        XCTAssertTrue(discovery(signatures: [app.id: .init(identifier: "com.google.Chrome", team: "FAKE")])
            .discover(for: app, base: []).files.isEmpty)
        XCTAssertTrue(discovery().discover(for: app, base: []).files.isEmpty)
    }

    func testBlenderRuleUsesOnlyCurrentMajorMinorAndProtectsOtherCopies() throws {
        app.bundleIdentifier = "org.blenderfoundation.blender"
        app.version = "5.2.1"
        let current = try file("Library/Application Support/Blender/5.2/config/settings").deletingLastPathComponent().deletingLastPathComponent()
        try file("Library/Application Support/Blender/4.5/config/settings")
        let signed = ApplicationDataDiscovery.Signature(identifier: app.bundleIdentifier!, team: "68UA947AUU")
        let result = discovery(signatures: [app.id: signed]).discover(for: app, base: [])
        XCTAssertEqual(result.files.map(\.path), [current.path])
        var other = try bundle("Applications/OtherBlender.app", id: app.bundleIdentifier!)
        other.version = "5.2.0"
        let shared = discovery(signatures: [app.id: signed], others: [other]).discover(for: app, base: [])
        XCTAssertEqual(shared.files.first?.retentionReason, .shared)
    }

    func testWebsiteDataAndScriptsCanBeBulkSelectedWithSavedContentWarning() throws {
        for (folder, category) in [("WebKit", AssociatedFileCategory.cache), ("HTTPStorages", .cache), ("Application Scripts", .script)] {
            let item = association(try file("Library/\(folder)/com.example.app/data").deletingLastPathComponent(), category: category)
            XCTAssertTrue(item.isEligibleForCleanup)
            XCTAssertTrue(item.isEligibleForBulkSelection)
            XCTAssertTrue(item.cleanupWarnings.contains(.savedContent))
        }
    }

    func testByHostPrefixMarksLongerDomainsAsUnconfirmedInsteadOfLockingThem() throws {
        let hostID = "A7DD0F9F-DA50-4A1E-BCEE-509344180F8D"
        let valid = association(try file("Library/Preferences/ByHost/com.example.app.\(hostID).plist"),
            category: .preference, basis: .bundleIdentifierPrefix("com.example.app"))
        let extensionFile = association(try file("Library/Preferences/ByHost/com.example.app.extension.\(hostID).plist"),
            category: .preference, basis: .bundleIdentifierPrefix("com.example.app"))
        let result = discovery().discover(for: app, base: [valid, extensionFile])
        XCTAssertTrue(try XCTUnwrap(result.files.first { $0.id == valid.id }).isEligibleForBulkSelection)
        let retained = try XCTUnwrap(result.files.first { $0.id == extensionFile.id })
        XCTAssertTrue(retained.isEligibleForBulkSelection)
        XCTAssertEqual(retained.retentionReason, .uncertain)
        XCTAssertEqual(retained.cleanupWarnings, [.uncertain])
    }

    func testBackgroundRecordMustReferenceExecutableInsideExactApp() throws {
        let good = try file("Library/LaunchAgents/good.plist")
        let bad = try file("Library/LaunchAgents/bad.plist")
        for (url, executable) in [(good, app.id + "/Contents/MacOS/Example"), (bad, app.id + "2/Contents/MacOS/Example")] {
            try PropertyListSerialization.data(fromPropertyList: ["ProgramArguments": [executable]], format: .xml, options: 0).write(to: url)
        }
        let result = discovery().discover(for: app, base: [])
        XCTAssertEqual(result.files.map(\.path), [good.path])
        XCTAssertTrue(result.files[0].isEligibleForCleanup)
        XCTAssertTrue(result.files[0].isEligibleForBulkSelection)
    }

    func testSizesCountAllocatedBlocksWithoutFollowingInternalLinks() throws {
        let root = try file("Library/Caches/com.example.app/data", text: String(repeating: "x", count: 10_000)).deletingLastPathComponent()
        let external = try file("external-big", text: String(repeating: "y", count: 100_000))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("outside"), withDestinationURL: external)
        let result = discovery().discover(for: app, base: [association(root)])
        let size = try XCTUnwrap(result.files[0].sizeBytes)
        XCTAssertGreaterThan(size, 0)
        XCTAssertLessThan(size, 100_000)
        XCTAssertNil(ApplicationDataDiscovery.allocatedSize(root, deadline: .distantPast))
    }

    func testPurposeAndRetentionExplanationsResolveInBothLanguages() {
        for locale in [Locale(identifier: "en"), Locale(identifier: "zh-Hans")] {
            for purpose in ApplicationDataPurpose.allCases {
                XCTAssertFalse(purpose.title(locale: locale).contains("data.purpose."))
                XCTAssertFalse(purpose.impact(locale: locale).contains("data.purpose."))
            }
            XCTAssertFalse(ApplicationDataRetentionReason.shared.explanation(locale: locale).contains("data.retain."))
            for warning in ApplicationDataCleanupWarning.allCases {
                XCTAssertFalse(warning.title(locale: locale).contains("data.warning."))
                XCTAssertFalse(warning.impact(locale: locale).contains("data.warning."))
            }
        }
    }

    func testScannerIntegrationKeepsInventoryReadOnlyAndEnrichesOnDemand() throws {
        let cache = try file("Library/Caches/com.example.app/data").deletingLastPathComponent()
        let named = try file("Library/Application Support/Example/data").deletingLastPathComponent()
        let scanner = ApplicationScanner(searchRoots: [home.appendingPathComponent("Applications")], homeDirectory: home)
        let inventory = try scanner.scanApplications()
        XCTAssertEqual(inventory.count, 1)
        XCTAssertTrue(inventory[0].associatedFiles.isEmpty)
        let enriched = try XCTUnwrap(scanner.enrichedCandidate(for: app.bundleURL))
        XCTAssertNotNil(enriched.dataDiscovery)
        XCTAssertTrue(try XCTUnwrap(enriched.associatedFiles.first { $0.path == cache.path }).isEligibleForBulkSelection)
        let nameOnly = try XCTUnwrap(enriched.associatedFiles.first { $0.path == named.path })
        XCTAssertTrue(nameOnly.isEligibleForBulkSelection)
        XCTAssertEqual(nameOnly.cleanupWarnings, [.uncertain, .savedContent])
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: named.path))
    }

    func testFindingsAreBoundedAndTheIncompleteCoverageIsReported() throws {
        let candidates = try (0..<270).map { index in
            association(try file("Library/Caches/com.example.app-\(index)"))
        }
        let result = discovery().discover(for: app, base: candidates)
        XCTAssertEqual(result.files.count, 256)
        XCTAssertTrue(result.summary.wasLimited)
        XCTAssertTrue(result.files.allSatisfy { !$0.isSelected })
    }

    func testInstalledWebAppProtectsTheBrowserProfileCacheAndSettings() throws {
        app.bundleIdentifier = "com.google.Chrome"
        let profile = try file("Library/Application Support/Google/Chrome/Default/content").deletingLastPathComponent().deletingLastPathComponent()
        let cache = try file("Library/Caches/Google/Chrome/Default/content").deletingLastPathComponent().deletingLastPathComponent()
        let preference = try file("Library/Preferences/com.google.Chrome.plist")
        let webApp = try bundle("Applications/Web App.app", id: "com.google.Chrome.app.fixture")
        let infoURL = webApp.bundleURL.appendingPathComponent("Contents/Info.plist")
        var info = try XCTUnwrap(ApplicationDataDiscovery.plist(infoURL, maximumBytes: 262_144))
        info["CrAppModeUserDataDir"] = profile.appendingPathComponent("Default/Web Applications/fixture").path
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: infoURL)
        let signed = ApplicationDataDiscovery.Signature(identifier: "com.google.Chrome", team: "EQHXZ8M8AV")
        let result = discovery(signatures: [app.id: signed], others: [webApp]).discover(for: app,
            base: [association(preference, category: .preference, basis: .exactBundleIdentifier("com.google.Chrome"))])
        XCTAssertEqual(Set(result.files.map(\.path)), Set([profile.path, cache.path, preference.path]))
        XCTAssertTrue(result.files.allSatisfy { $0.retentionReason == .shared && $0.isEligibleForBulkSelection })
        XCTAssertTrue(result.files.allSatisfy { $0.cleanupWarnings.contains(.shared) })
        XCTAssertTrue(try XCTUnwrap(result.files.first { $0.path == profile.path }).additionalEvidence.contains { $0.contains(webApp.name) })
    }

    func testScriptParentWarnsAboutAnotherAppsKnownDataBelowIt() throws {
        let parent = try file("Library/Application Support/Google/Chrome/data").deletingLastPathComponent().deletingLastPathComponent()
        let other = try bundle("Applications/Chrome.app", id: "com.google.Chrome")
        try file("Applications/Example.app/Contents/Resources/path.sh", text: "'~/Library/Application Support/Google'")
        let result = discovery(others: [other]).discover(for: app, base: [])
        let found = try XCTUnwrap(result.files.first { $0.path == parent.path })
        XCTAssertTrue(found.isEligibleForBulkSelection)
        XCTAssertTrue(found.cleanupWarnings.contains(.shared))
        XCTAssertTrue(found.cleanupWarnings.contains(.uncertain))
    }

    func testParentContainingAProtectedFindingStaysNonSelectable() throws {
        let childURL = try file("Library/Application Support/Example/protected")
        let parent = association(childURL.deletingLastPathComponent(), category: .support, basis: .applicationName("Example"))
        var child = association(childURL, basis: .installationReceipt("example"))
        child.retentionReason = .outsideScope
        let result = discovery().discover(for: app, base: [parent, child])
        let found = try XCTUnwrap(result.files.first { $0.path == parent.path })
        XCTAssertEqual(found.retentionReason, .protectedContents)
        XCTAssertFalse(found.isEligibleForBulkSelection)
    }

    func testSharedOwnershipWarningCannotWeakenAHardPathRestriction() throws {
        let url = try file("Library/Caches/com.example.app")
        let other = try bundle("Applications/OtherCopy.app", id: "com.example.app")
        var blocked = association(url)
        blocked.retentionReason = .outsideScope
        let result = discovery(others: [other]).discover(for: app, base: [blocked])
        XCTAssertEqual(result.files.first?.retentionReason, .outsideScope)
        XCTAssertFalse(try XCTUnwrap(result.files.first).isEligibleForCleanup)
    }

    func testUnstructuredFindingOutsideAllowedUserLibraryStaysBlocked() throws {
        let url = try file("Documents/important.txt")
        let result = discovery().discover(for: app, base: [association(url, basis: .unspecified)])
        XCTAssertEqual(result.files.first?.retentionReason, .outsideScope)
        XCTAssertFalse(try XCTUnwrap(result.files.first).isEligibleForBulkSelection)
    }
}
