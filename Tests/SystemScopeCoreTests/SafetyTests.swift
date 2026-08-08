import Foundation
import XCTest
@testable import SystemScopeCore

final class SafetyTests: XCTestCase {
    private let validator = DestructiveTargetValidator()
    private let uninstallPolicy = UninstallPathPolicy()
    private let testHome = "/Users/systemscope-test"

    func testValidatorAcceptsOnlyScopedAbsoluteTargets() throws {
        XCTAssertNoThrow(
            try validator.validate(
                paths: [
                    "/Applications/Example.app",
                    "/Users/systemscope-test/Library/Caches/com.example.app"
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
        assertInvalidTarget(paths: ["/Users/systemscope-test/Library/../.."])
    }

    func testUninstallPolicyAcceptsOnlyUserLibraryCandidates() throws {
        XCTAssertNoThrow(
            try uninstallPolicy.validate(
                applicationPath: "/Applications/Example.app",
                associatedPaths: [
                    "/Users/systemscope-test/Library/Caches/com.example.app",
                    "/Users/systemscope-test/Library/Preferences/com.example.app.plist"
                ],
                homeDirectory: testHome
            )
        )
    }

    func testUninstallPolicyRejectsSystemAndSharedContainers() {
        for path in [
            "/Library/Application Support/com.example.app",
            "/Users/systemscope-test/Library/Group Containers/group.com.example.app",
            "/Users/systemscope-test/Library/Caches"
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
                applicationPath: "/Users/systemscope-test/Downloads/Example.app",
                associatedPaths: [],
                homeDirectory: testHome
            )
        )
        XCTAssertThrowsError(
            try uninstallPolicy.validate(
                applicationPath: "/Applications/Example.app",
                associatedPaths: [
                    "/Users/systemscope-test/Library/Caches/com.example.app",
                    "/Users/systemscope-test/Library/Caches/com.example.app"
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

    func testDenyAllStartupItemMutatorAlwaysRejects() async {
        let item = StartupItem(
            label: "com.example.agent",
            displayName: "Example Agent",
            kind: .launchAgent,
            path: "/Users/systemscope-test/Library/LaunchAgents/com.example.agent.plist",
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
}
