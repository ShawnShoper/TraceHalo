import Foundation
import XCTest
@testable import TraceHaloApp

@MainActor
final class UninstallPermissionSetupTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "TraceHalo-permission-tests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testFirstLaunchOnlyOffersSetupOnceAndDoesNotRequestPermissions() async {
        let service = PermissionServiceFixture()
        let controller = makeController(service)
        let first = await controller.prepareFirstRunIfNeeded()
        let second = await controller.prepareFirstRunIfNeeded()
        XCTAssertTrue(first)
        XCTAssertFalse(second)
        XCTAssertFalse(controller.isReady)
        XCTAssertEqual(service.requestCount, 0)
        XCTAssertEqual(service.diskSettingsCount, 0)
        XCTAssertEqual(service.checkCount, 0, "An unregistered helper must not be contacted")
    }

    func testExistingReadyInstallationSkipsTheIntroduction() async {
        let service = PermissionServiceFixture(helper: .enabled)
        let controller = makeController(service)
        let show = await controller.prepareFirstRunIfNeeded()
        XCTAssertFalse(show)
        XCTAssertTrue(controller.isReady)
        XCTAssertEqual(service.checkCount, 1)
        XCTAssertEqual(service.requestCount, 0)
    }

    func testSkippingTheIntroductionPersistsAcrossControllerLifetimes() async {
        let service = PermissionServiceFixture()
        let first = makeController(service)
        let initialOffer = await first.prepareFirstRunIfNeeded()
        XCTAssertTrue(initialOffer)
        let relaunched = makeController(service)
        let repeatedOffer = await relaunched.prepareFirstRunIfNeeded()
        XCTAssertFalse(repeatedOffer)
        XCTAssertFalse(relaunched.isReady, "The persisted introduction marker must not imply granted access")
        XCTAssertEqual(service.requestCount, 0)
    }

    func testOpeningSettingsNeverCountsAsGrantingAccess() async {
        let service = PermissionServiceFixture(helper: .enabled)
        service.checkError = PrivilegedUninstallClientError.trashAccessDenied
        let controller = makeController(service)
        await controller.refresh()
        controller.openDiskSettings()
        XCTAssertEqual(service.diskSettingsCount, 1)
        XCTAssertEqual(controller.trashAccess, .denied)
        XCTAssertFalse(controller.isReady)
        service.checkError = nil
        await controller.refresh()
        XCTAssertTrue(controller.isReady)
        XCTAssertEqual(service.requestCount, 0)
    }

    func testExplicitSetupRegistersThenRechecksActualAccess() async {
        let service = PermissionServiceFixture()
        service.stateAfterRequest = .enabled
        let controller = makeController(service)
        await controller.requestHelper()
        XCTAssertEqual(service.requestCount, 1)
        XCTAssertEqual(service.checkCount, 1)
        XCTAssertTrue(controller.isReady)
    }

    func testOutdatedHelperRequiresAnExplicitUpdate() async {
        let service = PermissionServiceFixture(helper: .updateRequired)
        let controller = makeController(service)
        let show = await controller.prepareFirstRunIfNeeded()
        XCTAssertTrue(show)
        XCTAssertFalse(controller.isReady)
        XCTAssertEqual(service.requestCount, 0)
        XCTAssertEqual(service.checkCount, 0)
        await controller.requestHelper()
        XCTAssertEqual(service.requestCount, 1)
        XCTAssertTrue(controller.isReady)
    }

    func testRevokedHelperApprovalClearsPreviouslyVerifiedTrashAccess() async {
        let service = PermissionServiceFixture(helper: .enabled)
        let controller = makeController(service)
        await controller.refresh()
        service.helperState = .awaitingApproval
        await controller.refresh()
        XCTAssertFalse(controller.isReady)
        XCTAssertEqual(controller.trashAccess, .notChecked)
        XCTAssertEqual(service.checkCount, 1)
    }

    func testPendingSystemApprovalDoesNotPretendHelperIsEnabled() async {
        let service = PermissionServiceFixture()
        service.stateAfterRequest = .awaitingApproval
        let controller = makeController(service)
        await controller.requestHelper()
        XCTAssertEqual(controller.helperState, .awaitingApproval)
        XCTAssertEqual(controller.trashAccess, .notChecked)
        XCTAssertEqual(service.checkCount, 0)
        XCTAssertFalse(controller.isReady)
        service.helperState = .enabled
        await controller.refresh()
        XCTAssertTrue(controller.isReady)
        XCTAssertEqual(service.requestCount, 1, "Returning from Settings must not register again")
    }

    func testRevokedAccessIsDetectedWithoutRepeatingTheIntroduction() async {
        let service = PermissionServiceFixture(helper: .enabled)
        let controller = makeController(service)
        _ = await controller.prepareFirstRunIfNeeded()
        XCTAssertTrue(controller.isReady)
        service.checkError = PrivilegedUninstallClientError.trashAccessDenied
        await controller.refresh()
        XCTAssertFalse(controller.isReady)
        XCTAssertEqual(controller.trashAccess, .denied)
        let repeatIntroduction = await controller.prepareFirstRunIfNeeded()
        XCTAssertFalse(repeatIntroduction)
        XCTAssertEqual(service.requestCount, 0)
    }

    func testConnectionFailureIsNotMisreportedAsDiskPermissionDenial() async {
        let service = PermissionServiceFixture(helper: .enabled)
        service.checkError = PrivilegedUninstallClientError.helperConnectionFailed
        let controller = makeController(service)
        await controller.refresh()
        XCTAssertEqual(controller.trashAccess, .notChecked)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertFalse(controller.isReady)
    }

    func testFailedRegistrationCannotReportReady() async {
        let service = PermissionServiceFixture()
        service.requestError = PrivilegedUninstallClientError.helperNotPackaged
        let controller = makeController(service)
        await controller.requestHelper()
        XCTAssertFalse(controller.isReady)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertEqual(service.checkCount, 0)
        XCTAssertFalse(controller.isBusy)
    }

    func testFirstRunCancelledBeforePresentationDoesNotConsumeTheIntroduction() async {
        let service = PermissionServiceFixture(helper: .enabled)
        service.suspendsChecks = true
        let controller = makeController(service)
        let pending = Task { await controller.prepareFirstRunIfNeeded() }
        await waitForPendingProbe(service)
        pending.cancel()
        service.finishProbe(error: PrivilegedUninstallClientError.trashAccessDenied)
        let showCancelled = await pending.value
        XCTAssertFalse(showCancelled)
        XCTAssertFalse(defaults.bool(forKey: UninstallPermissionController.introductionKey))
        service.suspendsChecks = false
        service.checkError = PrivilegedUninstallClientError.trashAccessDenied
        let showNextTime = await controller.prepareFirstRunIfNeeded()
        XCTAssertTrue(showNextTime)
    }

    func testCurrentDenialCannotBeOverwrittenByAnOlderSuccessfulProbe() async {
        let service = PermissionServiceFixture(helper: .enabled)
        service.suspendsChecks = true
        let controller = makeController(service)
        let pending = Task { await controller.refresh() }
        await waitForPendingProbe(service)
        controller.recordTrashAccessDenied()
        service.finishProbe()
        await pending.value
        XCTAssertEqual(controller.trashAccess, .denied)
        XCTAssertFalse(controller.isReady)
    }

    func testConcurrentReadinessChecksShareOneProbe() async {
        let service = PermissionServiceFixture(helper: .enabled)
        service.suspendsChecks = true
        let controller = makeController(service)
        let first = Task { await controller.refresh() }
        await waitForPendingProbe(service)
        let second = Task { await controller.refresh() }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(service.checkCount, 1)
        service.finishProbe()
        await first.value
        await second.value
        XCTAssertTrue(controller.isReady)
        XCTAssertEqual(service.checkCount, 1)
    }

    func testOpeningSetupElsewherePreventsADuplicateStartupSheet() async {
        let service = PermissionServiceFixture(helper: .enabled)
        service.suspendsChecks = true
        let controller = makeController(service)
        let pending = Task { await controller.prepareFirstRunIfNeeded() }
        await waitForPendingProbe(service)
        controller.acknowledgeIntroduction()
        service.finishProbe(error: PrivilegedUninstallClientError.trashAccessDenied)
        let show = await pending.value
        XCTAssertFalse(show)
    }

    private func makeController(_ service: PermissionServiceFixture) -> UninstallPermissionController {
        UninstallPermissionController(service: service, defaults: defaults)
    }

    private func waitForPendingProbe(_ service: PermissionServiceFixture) async {
        for _ in 0..<1_000 {
            if service.pendingProbe != nil { return }
            await Task.yield()
        }
        XCTFail("The asynchronous readiness probe did not start")
    }
}

@MainActor
private final class PermissionServiceFixture: UninstallPermissionServicing {
    var helperState: UninstallHelperSetupState
    var stateAfterRequest: UninstallHelperSetupState = .enabled
    var checkError: (any Error)?
    var requestError: (any Error)?
    var requestCount = 0
    var checkCount = 0
    var diskSettingsCount = 0
    var suspendsChecks = false
    var pendingProbe: CheckedContinuation<Void, any Error>?

    init(helper: UninstallHelperSetupState = .notEnabled) { helperState = helper }
    func requestHelper() async throws {
        requestCount += 1
        if let requestError { throw requestError }
        helperState = stateAfterRequest
    }
    func checkTrashAccess() async throws {
        checkCount += 1
        if suspendsChecks {
            try await withCheckedThrowingContinuation { pendingProbe = $0 }
        } else if let checkError { throw checkError }
    }
    func openDiskSettings() { diskSettingsCount += 1 }
    func finishProbe(error: (any Error)? = nil) {
        let probe = pendingProbe
        pendingProbe = nil
        if let error { probe?.resume(throwing: error) } else { probe?.resume() }
    }
}
