import Foundation
import XCTest
@testable import TraceHaloCore

final class FeatureModelTests: XCTestCase {
    func testAssociatedFilesRequireExplicitSelectionByDefault() {
        let candidate = AssociatedFile(
            path: "/Users/test/Library/Caches/com.example.app",
            category: .cache,
            ownershipReason: "Bundle ID 匹配但仍需人工确认"
        )

        XCTAssertFalse(candidate.isSelected)
    }

    func testAssociatedFileCarriesStructuredReviewEvidenceWithoutAutoSelection() {
        let exact = AssociatedFile(
            path: "/Users/test/Library/Caches/com.example.app",
            category: .cache,
            ownershipReason: "目录名称与 Bundle Identifier 完全一致",
            matchBasis: .exactBundleIdentifier("com.example.app")
        )
        let nameOnly = AssociatedFile(
            path: "/Users/test/Library/Application Support/Example",
            category: .support,
            ownershipReason: "目录名称仅与应用名称匹配",
            matchBasis: .applicationName("Example")
        )

        XCTAssertEqual(exact.matchBasis, .exactBundleIdentifier("com.example.app"))
        XCTAssertEqual(nameOnly.matchBasis, .applicationName("Example"))
        XCTAssertFalse(exact.isSelected)
        XCTAssertFalse(nameOnly.isSelected)
    }

    func testAssociatedFileEvidenceDefaultsToUnspecifiedForLegacyCallers() {
        let candidate = AssociatedFile(
            path: "/Users/test/Library/Logs/com.example.app",
            category: .log,
            ownershipReason: "旧调用方没有结构化依据"
        )

        XCTAssertEqual(candidate.matchBasis, .unspecified)
    }

    func testUninstallPlanOnlyContainsExplicitlySelectedAssociatedFiles() {
        let application = ApplicationCandidate(
            name: "Example",
            bundleIdentifier: "com.example.app",
            version: "1.0",
            bundleURL: URL(fileURLWithPath: "/Applications/Example.app")
        )
        let selected = AssociatedFile(
            path: "/Users/test/Library/Caches/com.example.app",
            category: .cache,
            ownershipReason: "Bundle ID 完整匹配"
        )
        let plan = UninstallPlan(application: application, selectedFiles: [selected])

        XCTAssertEqual(plan.totalItemCount, 2)
        XCTAssertEqual(
            plan.allPaths,
            ["/Applications/Example.app", "/Users/test/Library/Caches/com.example.app"]
        )
    }

    func testUninstallPlanWithNoAssociatedSelectionContainsOnlyApplication() {
        let application = ApplicationCandidate(
            name: "Example",
            bundleIdentifier: nil,
            version: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Example.app")
        )
        let plan = UninstallPlan(application: application, selectedFiles: [])

        XCTAssertEqual(plan.totalItemCount, 1)
        XCTAssertEqual(plan.allPaths, ["/Applications/Example.app"])
    }

    func testUninstallPlanTotalIsKnownOnlyWhenEverySizeIsKnown() {
        let application = ApplicationCandidate(
            name: "Example",
            bundleIdentifier: nil,
            version: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Example.app"),
            sizeBytes: 100
        )
        let selected = AssociatedFile(
            path: "/Users/test/Library/Preferences/com.example.app.plist",
            category: .preference,
            sizeBytes: 20,
            ownershipReason: "Bundle ID 完整匹配",
            isSelected: true
        )

        XCTAssertEqual(UninstallPlan(application: application, selectedFiles: [selected]).knownTotalBytes, 120)

        var unknownFile = selected
        unknownFile.sizeBytes = nil
        XCTAssertNil(UninstallPlan(application: application, selectedFiles: [unknownFile]).knownTotalBytes)

        var unknownApplication = application
        unknownApplication.sizeBytes = nil
        XCTAssertNil(UninstallPlan(application: unknownApplication, selectedFiles: []).knownTotalBytes)
    }

    func testUninstallPlanTotalRejectsOverflow() {
        let application = ApplicationCandidate(
            name: "Example",
            bundleIdentifier: nil,
            version: nil,
            bundleURL: URL(fileURLWithPath: "/Applications/Example.app"),
            sizeBytes: UInt64.max
        )
        let selected = AssociatedFile(
            path: "/Users/test/Library/Preferences/com.example.app.plist",
            category: .preference,
            sizeBytes: 1,
            ownershipReason: "Bundle ID 完整匹配",
            isSelected: true
        )

        XCTAssertNil(UninstallPlan(application: application, selectedFiles: [selected]).knownTotalBytes)
    }

    func testStartupAndAssociatedFileIdentifiersArePathBased() {
        let startup = StartupItem(
            label: "com.example.agent",
            displayName: "Example Agent",
            kind: .launchAgent,
            path: "/Users/test/Library/LaunchAgents/com.example.agent.plist",
            isEnabled: true,
            scope: "当前用户"
        )
        let associated = AssociatedFile(
            path: "/Users/test/Library/Preferences/com.example.app.plist",
            category: .preference,
            ownershipReason: "Bundle ID 完整匹配"
        )

        XCTAssertEqual(startup.id, startup.path)
        XCTAssertEqual(associated.id, associated.path)
    }
}
