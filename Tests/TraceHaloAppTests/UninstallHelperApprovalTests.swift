import ServiceManagement
import XCTest
@testable import TraceHaloApp

final class UninstallHelperApprovalTests: XCTestCase {
    @MainActor
    func testFirstUseRegistersWhenStatusIsNotFound() async throws {
        var status = SMAppService.Status.notFound
        var actions: [String] = []

        try PrivilegedUninstallClient.requestApproval(
            status: { status },
            register: {
                actions.append("register")
                status = .requiresApproval
            },
            openApprovalSettings: { actions.append("open settings") }
        )

        XCTAssertEqual(actions, ["register", "open settings"])
    }

    @MainActor
    func testRegisteredHelperAwaitingApprovalOpensSettingsDirectly() async throws {
        var openedSettings = false

        try PrivilegedUninstallClient.requestApproval(
            status: { .requiresApproval },
            register: { XCTFail("An installed helper awaiting approval does not need registration.") },
            openApprovalSettings: { openedSettings = true }
        )

        XCTAssertTrue(openedSettings)
    }

    @MainActor
    func testEnabledHelperNeedsNoRegistrationOrSettings() async throws {
        try PrivilegedUninstallClient.requestApproval(
            status: { .enabled },
            register: { XCTFail("An enabled helper does not need registration.") },
            openApprovalSettings: { XCTFail("An enabled helper does not need approval in Settings.") }
        )
    }

    @MainActor
    func testRegistrationErrorStillOpensSettingsWhenSystemShowsApprovalIsPending() async throws {
        var status = SMAppService.Status.notRegistered
        var openedSettings = false

        try PrivilegedUninstallClient.requestApproval(
            status: { status },
            register: {
                status = .requiresApproval
                throw NSError(domain: "UninstallHelperApprovalTests", code: Int(kSMErrorLaunchDeniedByUser))
            },
            openApprovalSettings: { openedSettings = true }
        )

        XCTAssertTrue(openedSettings)
    }

    @MainActor
    func testFailedRegistrationPreservesTheActualError() async {
        let underlyingError = NSError(domain: "UninstallHelperApprovalTests", code: Int(kSMErrorInternalFailure))

        XCTAssertThrowsError(try PrivilegedUninstallClient.requestApproval(
            status: { .notFound },
            register: { throw underlyingError },
            openApprovalSettings: { XCTFail("Registration failed without an approval to review.") }
        )) { error in
            guard case let PrivilegedUninstallClientError.helperRegistrationFailed(domain, code) = error else {
                return XCTFail("Unexpected registration error: \(error)")
            }
            XCTAssertEqual(domain, underlyingError.domain)
            XCTAssertEqual(code, underlyingError.code)
        }
    }

    @MainActor
    func testSuccessfulRegisterWithNoSystemRecordDoesNotAskTheUserToApprove() async {
        XCTAssertThrowsError(try PrivilegedUninstallClient.requestApproval(
            status: { .notFound },
            register: {},
            openApprovalSettings: { XCTFail("The system has no registration for the user to approve.") }
        )) { error in
            guard case PrivilegedUninstallClientError.helperRegistrationNotConfirmed = error else {
                return XCTFail("Unexpected registration error: \(error)")
            }
        }
    }

    @MainActor
    func testUpdatedHelperRetriesTransientPermissionErrorUntilRegistrationSucceeds() async throws {
        var attempts = 0
        var delays: [Duration] = []

        try await PrivilegedUninstallClient.retryHelperRegistrationAfterUpdate(
            register: {
                attempts += 1
                if attempts <= 3 {
                    throw PrivilegedUninstallClientError.helperRegistrationFailed(
                        domain: "SMAppServiceErrorDomain", code: Int(EPERM)
                    )
                }
            },
            wait: { delays.append($0) }
        )

        XCTAssertEqual(attempts, 4)
        XCTAssertEqual(delays, [.seconds(1), .seconds(2), .seconds(3)])
    }

    @MainActor
    func testUpdatedHelperStopsRetryingAfterTheLastAttempt() async {
        var attempts = 0
        var delays: [Duration] = []

        do {
            try await PrivilegedUninstallClient.retryHelperRegistrationAfterUpdate(
                register: {
                    attempts += 1
                    throw PrivilegedUninstallClientError.helperRegistrationFailed(
                        domain: "SMAppServiceErrorDomain", code: Int(EPERM)
                    )
                },
                wait: { delays.append($0) }
            )
            XCTFail("Persistent registration errors must be surfaced.")
        } catch PrivilegedUninstallClientError.helperRegistrationFailed(let domain, let code) {
            XCTAssertEqual(domain, "SMAppServiceErrorDomain")
            XCTAssertEqual(code, Int(EPERM))
        } catch {
            XCTFail("Unexpected registration error: \(error)")
        }

        XCTAssertEqual(attempts, 4)
        XCTAssertEqual(delays, [.seconds(1), .seconds(2), .seconds(3)])
    }

    @MainActor
    func testUpdatedHelperDoesNotRetryPermissionErrorsFromAnotherDomain() async {
        var attempts = 0

        do {
            try await PrivilegedUninstallClient.retryHelperRegistrationAfterUpdate(
                register: {
                    attempts += 1
                    throw PrivilegedUninstallClientError.helperRegistrationFailed(
                        domain: NSPOSIXErrorDomain, code: Int(EPERM)
                    )
                },
                wait: { _ in XCTFail("An unrelated error must be surfaced immediately.") }
            )
            XCTFail("Unrelated registration errors must be surfaced.")
        } catch PrivilegedUninstallClientError.helperRegistrationFailed(let domain, let code) {
            XCTAssertEqual(domain, NSPOSIXErrorDomain)
            XCTAssertEqual(code, Int(EPERM))
        } catch {
            XCTFail("Unexpected registration error: \(error)")
        }

        XCTAssertEqual(attempts, 1)
    }
}
