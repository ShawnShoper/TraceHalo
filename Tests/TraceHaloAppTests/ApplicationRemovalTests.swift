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
