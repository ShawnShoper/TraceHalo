import Foundation
import XCTest

final class ReleaseScriptContractTests: XCTestCase {
    func testReleaseScriptsStopOnErrorsAndUnsetVariables() throws {
        for script in try releaseScripts() {
            XCTAssertTrue(
                script.source.contains("set -euo pipefail"),
                "\(script.name) must stop when a command fails or a required variable is unset"
            )
        }
    }

    func testDeveloperIDReleaseFailsClosedAndValidatesTheTraceHaloTeam() throws {
        let source = try script(named: "package-release.sh")

        assertContains(#"TRACEHALO_RELEASE_MODE:-developer-id"#, in: source)
        assertContains(#"TRACEHALO_RELEASE_ARCH:-universal"#, in: source)
        assertContains(#"TRACEHALO_NOTARIZE:-1"#, in: source)
        assertContains(#"TRACEHALO_TEAM_ID:-4DXU5FSLLY"#, in: source)
        assertContains("Developer ID Application", in: source)
        assertContains("4DXU5FSLLY", in: source)
        assertContains("TeamIdentifier", in: source)
        assertContains("Timestamp=", in: source)
        assertContains(#"flags=.*\(runtime\)"#, in: source)
        XCTAssertFalse(
            source.contains("Falling back to an ad-hoc signed package"),
            "A Developer ID release must fail instead of silently producing an ad-hoc artifact"
        )
        XCTAssertFalse(
            source.contains("notarization will be skipped"),
            "A requested notarization must fail instead of silently producing an unnotarized artifact"
        )
    }

    func testBuildAppUsesHardenedRuntimeTimestampAndStrictVerification() throws {
        let source = try script(named: "build-app.sh")

        assertContains("--options runtime", in: source)
        assertContains("--timestamp", in: source)
        assertContains("com.tseai.tracehalo.sensor-helper", in: source)
        assertContains("codesign --verify --deep --strict", in: source)

        let helperSigning = try XCTUnwrap(
            source.range(of: #"--identifier com.tseai.tracehalo.sensor-helper"#)
        )
        let appVerification = try XCTUnwrap(
            source.range(of: #"codesign --verify --deep --strict"#)
        )
        XCTAssertLessThan(
            helperSigning.lowerBound,
            appVerification.lowerBound,
            "The embedded helper must be signed before the completed app is verified"
        )
    }

    func testReleaseCreatesDmgZipAndTarArchives() throws {
        let source = try script(named: "package-release.sh")

        assertContains("hdiutil create", in: source)
        assertContains("-format UDZO", in: source)
        assertContains(".dmg", in: source)
        assertContains(".zip", in: source)
        assertContains("tar", in: source)
        assertContains(".tar.gz", in: source)
        assertContains("com.tseai.tracehalo.dmg", in: source)
    }

    func testNotarizationIsWaitedForStapledAndAssessedByGatekeeper() throws {
        let source = try script(named: "package-release.sh")

        let createDmg = try requiredRange(of: "hdiutil create", in: source)
        let signDmg = try requiredRange(of: "codesign --force", in: source)
        let submit = try requiredRange(of: "notarytool submit", in: source)
        let wait = try requiredRange(of: "--wait", in: source)
        let accepted = try requiredRange(of: #"!= "Accepted""#, in: source)
        let staple = try requiredRange(of: "stapler staple", in: source)
        let validate = try requiredRange(of: "stapler validate", in: source)
        let assess = try requiredRange(of: "spctl --assess", in: source)

        XCTAssertLessThan(createDmg.lowerBound, signDmg.lowerBound)
        XCTAssertLessThan(signDmg.lowerBound, submit.lowerBound)
        XCTAssertLessThan(submit.lowerBound, wait.lowerBound)
        XCTAssertLessThan(wait.lowerBound, accepted.lowerBound)
        XCTAssertLessThan(accepted.lowerBound, staple.lowerBound)
        XCTAssertLessThan(wait.lowerBound, staple.lowerBound)
        XCTAssertLessThan(staple.lowerBound, validate.lowerBound)
        XCTAssertLessThan(validate.lowerBound, assess.lowerBound)
    }

    func testArtifactNamesCarryVersionBuildChannelAndArchitecture() throws {
        let source = try script(named: "package-release.sh")

        assertContains("CFBundleShortVersionString", in: source)
        assertContains("CFBundleVersion", in: source)
        assertContains("TraceHaloReleaseChannel", in: source)
        assertContains("PUBLIC_VERSION", in: source)
        assertContains("BUILD_NUMBER", in: source)
        assertContains("RELEASE_CHANNEL", in: source)
        assertContains("universal2-arm64-x86_64", in: source)
        assertContains("developer-id", in: source)
        assertContains("notarized", in: source)
        assertContains("TraceHalo-", in: source)
        assertContains("-macOS-", in: source)
        assertContains(#"VERSION_LABEL="${PUBLIC_VERSION}""#, in: source)
        assertContains(
            #"VERSION_LABEL="${VERSION_LABEL}-${SAFE_RELEASE_CHANNEL}""#,
            in: source
        )
        assertContains(#"VERSION_LABEL="${VERSION_LABEL}-build${BUILD_NUMBER}""#, in: source)
        assertContains(
            #"PAYLOAD_NAME="TraceHalo-${VERSION_LABEL}-macOS-${ARCH_LABEL}-${VERIFICATION_LABEL}""#,
            in: source
        )
    }

    func testEveryReleaseArchiveGetsASha256Sidecar() throws {
        let source = try script(named: "package-release.sh")

        assertContains("shasum -a 256", in: source)
        assertContains(".sha256", in: source)
        assertContains(".dmg", in: source)
        assertContains(".zip", in: source)
        assertContains(".tar.gz", in: source)
        assertContains("release-manifest.txt", in: source)

        let checksumCommandCount = source.components(separatedBy: "shasum -a 256").count - 1
        let checksumLoopCoversArtifacts = source.contains("for artifact")
            || source.contains("for ARTIFACT")
        XCTAssertTrue(
            checksumCommandCount >= 3 || checksumLoopCoversArtifacts,
            "The DMG, ZIP, and tar.gz must each receive a SHA-256 sidecar"
        )
    }

    func testTarContainsTheStapledAppAndIsUnpackedForVerification() throws {
        let source = try script(named: "package-release.sh")

        let staple = try requiredRange(of: "stapler staple", in: source)
        let zipCreation = try requiredRange(of: "ditto -c -k", in: source)
        let tarCreation = try requiredRange(of: "tar -czf", in: source)
        let tarExtraction = try requiredRange(of: "tar -x", in: source)
        let strictVerification = try requiredRange(
            of: "codesign --verify --deep --strict",
            in: String(source[tarExtraction.lowerBound...])
        )

        XCTAssertLessThan(
            staple.lowerBound,
            tarCreation.lowerBound,
            "The tar archive must be created from the already-stapled application"
        )
        XCTAssertLessThan(
            staple.lowerBound,
            zipCreation.lowerBound,
            "The ZIP archive must be created from the already-stapled application"
        )
        XCTAssertLessThan(zipCreation.lowerBound, tarExtraction.lowerBound)
        XCTAssertLessThan(tarCreation.lowerBound, tarExtraction.lowerBound)
        XCTAssertFalse(strictVerification.isEmpty)
    }

    private func releaseScripts() throws -> [(name: String, source: String)] {
        try ["build-app.sh", "package-release.sh"].map { name in
            (name, try script(named: name))
        }
    }

    private func script(named name: String) throws -> String {
        try String(
            contentsOf: packageRoot
                .appendingPathComponent("scripts", isDirectory: true)
                .appendingPathComponent(name),
            encoding: .utf8
        )
    }

    private func requiredRange(
        of value: String,
        in source: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Range<String.Index> {
        try XCTUnwrap(
            source.range(of: value),
            "Missing release contract: \(value)",
            file: file,
            line: line
        )
    }

    private func assertContains(
        _ value: String,
        in source: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            source.contains(value),
            "Missing release contract: \(value)",
            file: file,
            line: line
        )
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
