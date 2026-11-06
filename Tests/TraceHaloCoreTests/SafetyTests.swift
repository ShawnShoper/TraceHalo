import Foundation
import XCTest
@testable import TraceHaloCore

final class SafetyTests: XCTestCase {
    private let validator = DestructiveTargetValidator()
    private let uninstallPolicy = UninstallPathPolicy()
    private let testHome = "/Users/tracehalo-test"

    func testSafetyModeUsesTraceHaloEnvironment() {
        XCTAssertEqual(
            RuntimeSafetyMode.resolve(
                arguments: ["TraceHalo"],
                environment: ["TRACEHALO_SAFE_TEST_MODE": "1"]
            ),
            .safeTest
        )
        XCTAssertEqual(
            RuntimeSafetyMode.resolve(arguments: ["TraceHalo"], environment: [:]),
            .live
        )
    }

    func testSafetyModeCommandLineFlagStillTakesPriority() {
        XCTAssertEqual(
            RuntimeSafetyMode.resolve(
                arguments: ["TraceHalo", "--safe-test-mode"],
                environment: [:]
            ),
            .safeTest
        )
    }

    func testValidatorAcceptsOnlyScopedAbsoluteTargets() throws {
        XCTAssertNoThrow(
            try validator.validate(
                paths: [
                    "/Applications/Example.app",
                    "/Users/tracehalo-test/Library/Caches/com.example.app"
                ],
                homeDirectory: testHome
            )
        )
    }

    func testValidatorExpandsTildeForAUserSubdirectoryWithoutTouchingIt() throws {
        XCTAssertNoThrow(
            try validator.validate(
                paths: ["~/Library/Caches/com.example.app"],
                homeDirectory: NSHomeDirectory()
            )
        )
    }

    func testValidatorRejectsNoTargets() {
        assertInvalidTarget(paths: [])
    }

    func testValidatorRejectsProtectedRootsAndHomeDirectory() {
        for path in ["/", "/Applications", "/Library", "/System", "/Users", testHome] {
            assertInvalidTarget(paths: [path])
        }
    }

    func testValidatorRejectsEmptyAndRelativePaths() {
        for path in ["", "   ", "relative/path", "../Library"] {
            assertInvalidTarget(paths: [path])
        }
    }

    func testValidatorRejectsTildeWhenItResolvesToHomeItself() {
        do {
            try validator.validate(paths: ["~"], homeDirectory: NSHomeDirectory())
            XCTFail("不得把用户主目录作为删除目标")
        } catch let violation as SafetyViolation {
            guard case .invalidTarget = violation else {
                return XCTFail("错误类型不正确：\(violation)")
            }
        } catch {
            XCTFail("错误类型不正确：\(error)")
        }
    }

    func testValidatorRejectsTraversalThatNormalizesToProtectedRoot() {
        assertInvalidTarget(paths: ["/Applications/Example.app/../.."])
        assertInvalidTarget(paths: ["/Users/tracehalo-test/Library/../.."])
    }

    func testUninstallPolicyAcceptsOnlyUserLibraryCandidates() throws {
        XCTAssertNoThrow(
            try uninstallPolicy.validate(
                applicationPath: "/Applications/Example.app",
                associatedPaths: [
                    "/Users/tracehalo-test/Library/Caches/com.example.app",
                    "/Users/tracehalo-test/Library/Preferences/com.example.app.plist"
                ],
                homeDirectory: testHome
            )
        )
    }

    func testUninstallPolicyRejectsSystemAndSharedContainers() {
        for path in [
            "/Library/Application Support/com.example.app",
            "/Users/tracehalo-test/Library/Group Containers/group.com.example.app",
            "/Users/tracehalo-test/Library/Caches"
        ] {
            XCTAssertThrowsError(
                try uninstallPolicy.validate(
                    applicationPath: "/Applications/Example.app",
                    associatedPaths: [path],
                    homeDirectory: testHome
                )
            )
        }
    }

    func testUninstallPolicyRejectsApplicationOutsideApplicationsAndDuplicateTargets() {
        XCTAssertThrowsError(
            try uninstallPolicy.validate(
                applicationPath: "/Users/tracehalo-test/Downloads/Example.app",
                associatedPaths: [],
                homeDirectory: testHome
            )
        )
        XCTAssertThrowsError(
            try uninstallPolicy.validate(
                applicationPath: "/Applications/Example.app",
                associatedPaths: [
                    "/Users/tracehalo-test/Library/Caches/com.example.app",
                    "/Users/tracehalo-test/Library/Caches/com.example.app"
                ],
                homeDirectory: testHome
            )
        )
    }

    func testSafetyViolationDescriptionsAreActionable() {
        XCTAssertEqual(
            SafetyViolation.deniedInSafeTestMode(.uninstall).localizedDescription(
                locale: Locale(identifier: "zh-Hans")
            ),
            "安全测试模式已阻止卸载操作。"
        )
        XCTAssertEqual(SafetyViolation.invalidTarget("bad target").errorDescription, "bad target")
        XCTAssertEqual(SafetyViolation.unsupported("not supported").errorDescription, "not supported")
    }

    func testDenyAllUninstallExecutorAlwaysRejects() async {
        let application = ApplicationCandidate(
            name: "Example",
            bundleIdentifier: "com.example.app",
            version: "1",
            bundleURL: URL(fileURLWithPath: "/Applications/Example.app")
        )
        let plan = UninstallPlan(application: application, selectedFiles: [])

        do {
            try await DenyAllUninstallExecutor().execute(plan: plan)
            XCTFail("拒绝执行器不应成功")
        } catch {
            XCTAssertEqual(error as? SafetyViolation, .deniedInSafeTestMode(.uninstall))
        }
    }

    func testTrashExecutorWaitsForApplicationMoveBeforeCleaningSelectedFiles() async throws {
        try await withUninstallFixture { home, plan in
            var attempted: [String] = []
            try await TrashUninstallExecutor().execute(
                plan: plan,
                homeDirectory: home,
                moveApplicationToTrash: { url in
                    await Task.yield()
                    attempted.append(url.path)
                },
                moveAssociatedFileToTrash: { attempted.append($0.path) }
            )
            XCTAssertEqual(attempted, plan.allPaths)
            XCTAssertEqual(attempted.count, 3)
        }
    }

    func testDeniedApplicationMoveLeavesAllAssociatedFilesUntouched() async throws {
        try await withUninstallFixture { home, plan in
            var attempted: [String] = []
            let permissionError = NSError(
                domain: NSCocoaErrorDomain,
                code: CocoaError.fileWriteUnknown.rawValue,
                userInfo: [NSUnderlyingErrorKey: POSIXError(.EACCES)]
            )
            do {
                try await TrashUninstallExecutor().execute(
                    plan: plan,
                    homeDirectory: home,
                    moveApplicationToTrash: { target in
                        await Task.yield()
                        attempted.append(target.path)
                        throw permissionError
                    },
                    moveAssociatedFileToTrash: { attempted.append($0.path) }
                )
                XCTFail("Expected the app move to fail before any changes")
            } catch let error as UninstallExecutionError {
                guard case .moveFailed(_, true, true, _) = error else {
                    return XCTFail("Expected the app move to fail before any changes: \(error)")
                }
                XCTAssertFalse(error.didMoveApplication)
                XCTAssertTrue(error.isPermissionDenied)
                XCTAssertEqual(error.failedTargetURL?.path, plan.application.bundleURL.path)
                let message = error.localizedDescription(locale: Locale(identifier: "zh-Hans"))
                XCTAssertTrue(message.contains("需要额外权限"))
                XCTAssertTrue(message.contains("本次未移动任何项目"))
            }
            XCTAssertEqual(attempted, [plan.application.bundleURL.path])
        }
    }

    func testUnconfirmedApplicationMoveStopsCleanupAndPreservesTheUncertainResult() async throws {
        try await withUninstallFixture { home, plan in
            do {
                try await TrashUninstallExecutor().execute(
                    plan: plan,
                    homeDirectory: home,
                    moveApplicationToTrash: { url in
                        throw UninstallAppMoveUnconfirmed(applicationURL: url)
                    },
                    moveAssociatedFileToTrash: { _ in
                        XCTFail("Data cleanup requires confirmation that the app reached the Trash")
                    }
                )
                XCTFail("Expected the move result to remain unconfirmed")
            } catch let error as UninstallAppMoveUnconfirmed {
                XCTAssertEqual(error.applicationURL.path, plan.application.bundleURL.path)
            }
        }
    }

    func testTrashPermissionPreflightChecksSelectedFilesBeforeMovingTheApp() async throws {
        guard geteuid() != 0 else { throw XCTSkip("Root can bypass directory permission bits") }
        try await withUninstallFixture { home, plan in
            let path = plan.selectedFiles[0].path
            let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
            let manager = FileManager.default
            try manager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: parent)
            defer { try? manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parent) }

            do {
                try await TrashUninstallExecutor().execute(
                    plan: plan,
                    homeDirectory: home,
                    moveApplicationToTrash: { _ in XCTFail("Preflight must finish before the app moves") },
                    moveAssociatedFileToTrash: { _ in XCTFail("Preflight must finish before data moves") }
                )
                XCTFail("Expected the selected file preflight to fail")
            } catch let error as UninstallExecutionError {
                guard case .moveFailed(_, false, true, _) = error else {
                    return XCTFail("Expected a selected file permission failure: \(error)")
                }
                XCTAssertFalse(error.didMoveApplication)
                XCTAssertEqual(error.failedTargetURL?.path, path)
            }
        }
    }

    func testCleanupFailureReportsAppAlreadyMovedAndRemainingData() async throws {
        try await withUninstallFixture { home, plan in
            let deniedPath = plan.selectedFiles[1].path
            do {
                try await TrashUninstallExecutor().execute(
                    plan: plan,
                    homeDirectory: home,
                    moveApplicationToTrash: { _ in },
                    moveAssociatedFileToTrash: { target in
                        if target.path == deniedPath { throw CocoaError(.fileWriteNoPermission) }
                    }
                )
                XCTFail("Expected cleanup to stop on the denied file")
            } catch let error as UninstallExecutionError {
                guard case .cleanupIncomplete(2, 3, _, true, _) = error else {
                    return XCTFail("Expected one remaining data item after the app and first file moved: \(error)")
                }
                XCTAssertTrue(error.didMoveApplication)
                XCTAssertTrue(error.isPermissionDenied)
                XCTAssertEqual(error.failedTargetURL?.path, deniedPath)
                let message = error.localizedDescription(locale: Locale(identifier: "zh-Hans"))
                XCTAssertTrue(message.contains("应用已移到废纸篓，已清理 1/2 项所选文件"))
            }
        }
    }

    func testDenyAllStartupItemMutatorAlwaysRejects() async {
        let item = StartupItem(
            label: "com.example.agent",
            displayName: "Example Agent",
            kind: .launchAgent,
            path: "/Users/tracehalo-test/Library/LaunchAgents/com.example.agent.plist",
            isEnabled: true,
            scope: "当前用户"
        )

        do {
            try await DenyAllStartupItemMutator().setEnabled(false, item: item)
            XCTFail("拒绝执行器不应成功")
        } catch {
            XCTAssertEqual(error as? SafetyViolation, .deniedInSafeTestMode(.startupItemChange))
        }
    }

    private func assertInvalidTarget(paths: [String], file: StaticString = #filePath, line: UInt = #line) {
        do {
            try validator.validate(paths: paths, homeDirectory: testHome)
            XCTFail("应拒绝目标：\(paths)", file: file, line: line)
        } catch let violation as SafetyViolation {
            guard case .invalidTarget = violation else {
                return XCTFail("错误类型不正确：\(violation)", file: file, line: line)
            }
        } catch {
            XCTFail("错误类型不正确：\(error)", file: file, line: line)
        }
    }

    private func withUninstallFixture(_ test: (URL, UninstallPlan) async throws -> Void) async throws {
        let manager = FileManager.default
        let home = manager.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("TraceHalo-Uninstall-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: home) }

        let app = home.appendingPathComponent("Applications/Example.app", isDirectory: true)
        try manager.createDirectory(at: app, withIntermediateDirectories: true)
        let files = try ["Caches", "Preferences", "Logs"].map { folder in
            let directory = home.appendingPathComponent("Library/\(folder)", isDirectory: true)
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("com.example.app")
            try Data().write(to: file)
            return AssociatedFile(path: file.path, category: .other, ownershipReason: "test fixture")
        }
        let application = ApplicationCandidate(
            name: "Example", bundleIdentifier: "com.example.app", version: "1", bundleURL: app,
            associatedFiles: files
        )
        try await test(home, UninstallPlan(application: application, selectedFiles: Array(files.prefix(2))))
    }
}
