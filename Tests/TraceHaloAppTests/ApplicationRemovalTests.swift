import TraceHaloCore
import XCTest
@testable import TraceHaloApp

final class ApplicationRemovalTests: XCTestCase {
    @MainActor
    func testDefaultUninstallKeepsDataEvenWithAnOldSelection() async throws {
        var application = FixtureCatalog.applications[0]
        application.associatedFiles[0].isSelected = true
        let executor = RecordingUninstallExecutor()
        let model = AppModel(uninstallExecutor: executor)
        model.applications = [application]
        model.selectedApplicationID = application.id

        let selection = ApplicationRemovalSelection()
        XCTAssertEqual(selection.dataMode, .keep)
        try await model.uninstall(selection.makePlan(for: application))

        let plans = await executor.plans
        XCTAssertEqual(plans.map(\.allPaths), [[application.bundleURL.path]])
        XCTAssertTrue(model.applications.isEmpty)
        XCTAssertNil(model.selectedApplicationID)
    }

    @MainActor
    func testCleanupExecutesOnlyFilesCheckedInThisConfirmation() async throws {
        var application = FixtureCatalog.applications[0]
        application.associatedFiles[0].isSelected = true
        let checkedFile = application.associatedFiles[1]
        let executor = RecordingUninstallExecutor()
        let model = AppModel(uninstallExecutor: executor)

        var selection = ApplicationRemovalSelection()
        selection.dataMode = .clean
        selection.selectedFileIDs = [checkedFile.id, "/stale/scan/path"]
        try await model.uninstall(selection.makePlan(for: application))

        let plans = await executor.plans
        XCTAssertEqual(plans.map(\.allPaths), [[application.bundleURL.path, checkedFile.path]])
    }

    func testSwitchingBackToKeepDiscardsCleanupSelections() {
        let application = FixtureCatalog.applications[0]
        var selection = ApplicationRemovalSelection()
        selection.dataMode = .clean
        selection.selectedFileIDs.insert(application.associatedFiles[0].id)

        selection.dataMode = .keep
        XCTAssertTrue(selection.makePlan(for: application).selectedFiles.isEmpty)

        selection.dataMode = .clean
        XCTAssertTrue(selection.selectedFileIDs.isEmpty)
        XCTAssertTrue(selection.makePlan(for: application).selectedFiles.isEmpty)
    }

    func testSelectAllIncludesUnconfirmedSharedAndSavedContentButExcludesUnsafeFindings() {
        let files = [
            AssociatedFile(path: "/home/Library/Caches/com.example.app", category: .cache,
                ownershipReason: "cache", matchBasis: .exactBundleIdentifier("com.example.app")),
            AssociatedFile(path: "/home/Library/Application Support/Example", category: .support,
                ownershipReason: "name only", matchBasis: .applicationName("Example"), retentionReason: .uncertain),
            AssociatedFile(path: "/home/Library/Group Containers/team.shared", category: .groupContainer,
                ownershipReason: "shared", matchBasis: .appGroup("team.shared"), retentionReason: .shared),
            AssociatedFile(path: "/home/Library/WebKit/com.example.app", category: .cache,
                ownershipReason: "website data", matchBasis: .exactBundleIdentifier("com.example.app")),
            AssociatedFile(path: "/home/Library/Caches/unknown", category: .cache, ownershipReason: "legacy"),
            AssociatedFile(path: "/Library/Helper", category: .helper,
                ownershipReason: "receipt", matchBasis: .installationReceipt("example"), retentionReason: .outsideScope)
        ]
        var application = FixtureCatalog.applications[0]
        application.associatedFiles = files
        var selection = ApplicationRemovalSelection()
        selection.dataMode = .clean
        selection.toggleBulkSelection(for: application)

        let plan = selection.makePlan(for: application)
        XCTAssertEqual(plan.selectedFiles, Array(files.prefix(5)))
        XCTAssertEqual(plan.retainedAssociatedFiles, [files[5]])
        XCTAssertTrue(plan.coveredAssociatedFiles.contains { $0.cleanupWarnings.contains(.uncertain) })
        XCTAssertTrue(plan.coveredAssociatedFiles.contains { $0.cleanupWarnings.contains(.shared) })
        XCTAssertTrue(plan.coveredAssociatedFiles.contains { $0.cleanupWarnings.contains(.savedContent) })
        selection.toggleBulkSelection(for: application)
        XCTAssertTrue(selection.selectedFileIDs.isEmpty)
        XCTAssertTrue(selection.makePlan(for: application).selectedFiles.isEmpty)
    }

    func testForgedSelectionCannotIncludeUnsafeFindingsOrStaleIDs() {
        var application = FixtureCatalog.applications[0]
        application.associatedFiles = [
            AssociatedFile(path: "/home/Library/Caches/blocked", category: .cache,
                ownershipReason: "blocked child", retentionReason: .protectedContents),
            AssociatedFile(path: "/Library/Helper", category: .helper,
                ownershipReason: "receipt", matchBasis: .installationReceipt("example"), retentionReason: .outsideScope),
            AssociatedFile(path: "/home/Library/Caches/link", category: .cache,
                ownershipReason: "link", matchBasis: .exactBundleIdentifier("example"), retentionReason: .symbolicLink)
        ]
        var selection = ApplicationRemovalSelection()
        selection.dataMode = .clean
        selection.selectedFileIDs = Set(application.associatedFiles.map(\.id))
        selection.selectedFileIDs.insert("/not-scanned")
        XCTAssertTrue(selection.makePlan(for: application).selectedFiles.isEmpty)
    }

    func testSelectAllMovesAnOverlappingParentOnceAndKeepsChildWarningsInReview() {
        let (application, files) = overlappingApplication()
        var selection = ApplicationRemovalSelection()
        selection.dataMode = .clean
        selection.toggleBulkSelection(for: application)
        let plan = selection.makePlan(for: application)
        XCTAssertEqual(plan.selectedFiles, [files[0], files[3]])
        XCTAssertEqual(plan.coveredAssociatedFiles, files)
        XCTAssertTrue(plan.retainedAssociatedFiles.isEmpty)
        XCTAssertTrue(plan.coveredAssociatedFiles[1].cleanupWarnings.contains(.shared))
    }

    func testUncheckingAChildAlsoUnchecksItsParentSoItCannotBeRemovedIndirectly() {
        let (application, files) = overlappingApplication()
        var selection = ApplicationRemovalSelection()
        selection.dataMode = .clean
        selection.toggleBulkSelection(for: application)
        selection.setSelected(false, file: files[1], in: application)
        let plan = selection.makePlan(for: application)
        XCTAssertFalse(selection.selectedFileIDs.contains(files[0].id))
        XCTAssertEqual(plan.selectedFiles, [files[2], files[3]])
        XCTAssertFalse(plan.coveredAssociatedFiles.contains(files[1]))
        XCTAssertTrue(plan.retainedAssociatedFiles.contains(files[1]))
    }

    func testChoosingParentIncludesItsScannedChildrenAndPartialSelectionNeverMovesParent() {
        let (application, files) = overlappingApplication()
        var selection = ApplicationRemovalSelection()
        selection.dataMode = .clean
        selection.setSelected(true, file: files[0], in: application)
        XCTAssertEqual(selection.selectedFileIDs, Set(files.prefix(3).map(\.id)))
        selection.selectedFileIDs.remove(files[1].id)
        XCTAssertEqual(selection.makePlan(for: application).selectedFiles, [files[2]])
    }

    private func overlappingApplication() -> (ApplicationCandidate, [AssociatedFile]) {
        let parent = "/home/Library/Application Support/Example"
        let files = [
            AssociatedFile(path: parent, category: .support, ownershipReason: "name",
                matchBasis: .applicationName("Example"), retentionReason: .uncertain),
            AssociatedFile(path: parent + "/shared", category: .support, ownershipReason: "shared",
                matchBasis: .exactBundleIdentifier("example"), retentionReason: .shared),
            AssociatedFile(path: parent + "/cache", category: .cache, ownershipReason: "cache",
                matchBasis: .exactBundleIdentifier("example")),
            AssociatedFile(path: parent + "Other", category: .support, ownershipReason: "separate",
                matchBasis: .applicationName("ExampleOther"), retentionReason: .uncertain)
        ]
        var application = FixtureCatalog.applications[0]
        application.associatedFiles = files
        return (application, files)
    }

    @MainActor
    func testIncompleteCleanupRemovesTrashedAppFromInventory() async throws {
        let application = FixtureCatalog.applications[0]
        let file = try XCTUnwrap(application.associatedFiles.first)
        let failure = UninstallExecutionError.cleanupIncomplete(
            moved: 1,
            total: 2,
            targetURL: URL(fileURLWithPath: file.path),
            permissionDenied: true,
            reason: "Permission denied"
        )
        let model = AppModel(uninstallExecutor: RecordingUninstallExecutor(failure: failure))
        model.applications = [application]
        model.selectedApplicationID = application.id

        do {
            try await model.uninstall(UninstallPlan(application: application, selectedFiles: [file]))
            XCTFail("The cleanup failure should be shown to the user.")
        } catch let error as UninstallExecutionError {
            XCTAssertTrue(error.didMoveApplication)
        }

        XCTAssertTrue(model.applications.isEmpty)
        XCTAssertNil(model.selectedApplicationID)
        XCTAssertFalse(model.isUninstallingApplication)
    }
}

private actor RecordingUninstallExecutor: UninstallExecuting {
    private(set) var plans: [UninstallPlan] = []
    private let failure: UninstallExecutionError?

    init(failure: UninstallExecutionError? = nil) {
        self.failure = failure
    }

    func execute(plan: UninstallPlan) async throws {
        plans.append(plan)
        if let failure {
            throw failure
        }
    }
}
