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
        assertContains(#"--identifier "${identifier}" "${helper_path}""#, in: source)

        let appSigning = try requiredRange(
            of: #"codesign --force "${SIGNING_ARGUMENTS[@]}" "${STAGED_APP_PATH}""#,
            in: source
        )
        let appVerification = try requiredRange(
            of: "codesign --verify --deep --strict",
            in: source
        )
        XCTAssertLessThan(appSigning.lowerBound, appVerification.lowerBound)
        for embedding in [
            "embed_helper TraceHaloSensorHelper com.tseai.tracehalo.sensor-helper",
            "embed_helper TraceHaloUninstallHelper com.tseai.tracehalo.uninstall-helper"
        ] {
            let helperEmbedding = try requiredRange(of: embedding, in: source)
            XCTAssertLessThan(
                helperEmbedding.lowerBound,
                appSigning.lowerBound,
                "The embedded helper must be signed before the app"
            )
        }
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

    func testAppIsAcceptedStapledAndAssessedBeforeReleaseContainersAreCreated() throws {
        let source = try script(named: "package-release.sh")

        let appArchive = try requiredRange(
            of: "ditto -c -k --sequesterRsrc --keepParent",
            in: source
        )
        let appSubmit = try requiredRange(
            of: #"notarytool submit "${APP_NOTARY_ARCHIVE}""#,
            in: source
        )
        let appAccepted = try requiredRange(
            of: #""${APP_NOTARY_STATUS}" != "Accepted""#,
            in: source
        )
        let appStaple = try requiredRange(
            of: #"stapler staple "${APP_PATH}""#,
            in: source
        )
        let appValidate = try requiredRange(
            of: #"stapler validate "${APP_PATH}""#,
            in: source
        )
        let appAssess = try requiredRange(
            of: #"spctl --assess --type execute --verbose=4 "${APP_PATH}""#,
            in: source
        )
        let stageDmg = try requiredRange(
            of: #"ditto "${APP_PATH}" "${DMG_STAGE}/TraceHalo.app""#,
            in: source
        )
        let createDmg = try requiredRange(of: "hdiutil create", in: source)
        let createZip = try requiredRange(
            of: #"ditto -c -k --norsrc --keepParent "${PAYLOAD_ROOT}" "${FINAL_ZIP}""#,
            in: source
        )
        let createTar = try requiredRange(of: "tar -czf", in: source)

        XCTAssertLessThan(appArchive.lowerBound, appSubmit.lowerBound)
        XCTAssertLessThan(appSubmit.lowerBound, appAccepted.lowerBound)
        XCTAssertLessThan(appAccepted.lowerBound, appStaple.lowerBound)
        XCTAssertLessThan(appStaple.lowerBound, appValidate.lowerBound)
        XCTAssertLessThan(appValidate.lowerBound, appAssess.lowerBound)
        XCTAssertLessThan(appAssess.lowerBound, stageDmg.lowerBound)
        XCTAssertLessThan(stageDmg.lowerBound, createDmg.lowerBound)
        XCTAssertLessThan(appStaple.lowerBound, createZip.lowerBound)
        XCTAssertLessThan(appStaple.lowerBound, createTar.lowerBound)

        let appArchiveCommand = String(source[appArchive.lowerBound..<appSubmit.lowerBound])
        assertContains(#""${APP_PATH}""#, in: appArchiveCommand)
        assertContains(#""${APP_NOTARY_ARCHIVE}""#, in: appArchiveCommand)

        let appSubmission = String(source[appSubmit.lowerBound..<appAccepted.lowerBound])
        assertContains("--wait", in: appSubmission)
    }

    func testDmgIsAcceptedStapledAndAssessedAfterContainingTheStapledApp() throws {
        let source = try script(named: "package-release.sh")

        let appValidate = try requiredRange(
            of: #"stapler validate "${APP_PATH}""#,
            in: source
        )
        let stageDmg = try requiredRange(
            of: #"ditto "${APP_PATH}" "${DMG_STAGE}/TraceHalo.app""#,
            in: source
        )
        let createDmg = try requiredRange(of: "hdiutil create", in: source)
        let signDmg = try requiredRange(of: "codesign --force", in: source)
        let dmgSubmit = try requiredRange(
            of: #"notarytool submit "${FINAL_DMG}""#,
            in: source
        )
        let dmgAccepted = try requiredRange(
            of: #""${DMG_NOTARY_STATUS}" != "Accepted""#,
            in: source
        )
        let dmgStaple = try requiredRange(
            of: #"stapler staple "${FINAL_DMG}""#,
            in: source
        )
        let dmgValidate = try requiredRange(
            of: #"stapler validate "${FINAL_DMG}""#,
            in: source
        )
        let dmgAssess = try requiredRange(of: "--type open", in: source)

        XCTAssertLessThan(appValidate.lowerBound, stageDmg.lowerBound)
        XCTAssertLessThan(stageDmg.lowerBound, createDmg.lowerBound)
        XCTAssertLessThan(createDmg.lowerBound, signDmg.lowerBound)
        XCTAssertLessThan(signDmg.lowerBound, dmgSubmit.lowerBound)
        XCTAssertLessThan(dmgSubmit.lowerBound, dmgAccepted.lowerBound)
        XCTAssertLessThan(dmgAccepted.lowerBound, dmgStaple.lowerBound)
        XCTAssertLessThan(dmgStaple.lowerBound, dmgValidate.lowerBound)
        XCTAssertLessThan(dmgValidate.lowerBound, dmgAssess.lowerBound)

        let dmgGatekeeperCommand = #"""
    spctl --assess \
        --type open \
        --context context:primary-signature \
        --verbose=4 \
        "${FINAL_DMG}"
"""#
        assertContains(dmgGatekeeperCommand, in: source)

        let dmgSubmission = String(source[dmgSubmit.lowerBound..<dmgAccepted.lowerBound])
        assertContains("--wait", in: dmgSubmission)
    }

    func testAppAndDmgNotarizationKeepSeparateEvidence() throws {
        let source = try script(named: "package-release.sh")

        for assignment in [
            #"APP_NOTARY_RESULT="${WORK_ROOT}/app-notarization-result.json""#,
            #"APP_NOTARY_LOG="${WORK_ROOT}/app-notarization-log.json""#,
            #"DMG_NOTARY_RESULT="${WORK_ROOT}/dmg-notarization-result.json""#,
            #"DMG_NOTARY_LOG="${WORK_ROOT}/dmg-notarization-log.json""#
        ] {
            assertContains(assignment, in: source)
        }

        for manifestLine in [
            #"print "App notary status: ${APP_NOTARY_STATUS:-not requested}""#,
            #"print "App notary submission ID: ${APP_SUBMISSION_ID:-none}""#,
            #"print "DMG notary status: ${DMG_NOTARY_STATUS:-not requested}""#,
            #"print "DMG notary submission ID: ${DMG_SUBMISSION_ID:-none}""#
        ] {
            assertContains(manifestLine, in: source)
        }

        let successfulEvidenceStart = try XCTUnwrap(
            source.range(of: "for diagnostic in", options: .backwards)
        )
        let successfulEvidence = String(source[successfulEvidenceStart.lowerBound...])
        for evidence in [
            #"${APP_NOTARY_RESULT}"#,
            #"${APP_NOTARY_LOG}"#,
            #"${DMG_NOTARY_RESULT}"#,
            #"${DMG_NOTARY_LOG}"#,
            #"cp "${diagnostic}" "${PARTIAL_DIST_DIR}/${diagnostic:t}""#
        ] {
            assertContains(evidence, in: successfulEvidence)
        }
    }

    func testFailedSubmissionsPreserveAnyReturnedIDWithoutAutomaticResubmission() throws {
        let source = try script(named: "package-release.sh")

        for submission in [
            (
                submit: #"notarytool submit "${APP_NOTARY_ARCHIVE}""#,
                parseID: #"APP_SUBMISSION_ID="$("#,
                failure: #"if [[ "${APP_SUBMIT_EXIT}" != "0" ]]"#
            ),
            (
                submit: #"notarytool submit "${FINAL_DMG}""#,
                parseID: #"DMG_SUBMISSION_ID="$("#,
                failure: #"if [[ "${DMG_SUBMIT_EXIT}" != "0" ]]"#
            )
        ] {
            let submit = try requiredRange(of: submission.submit, in: source)
            let parseID = try requiredRange(of: submission.parseID, in: source)
            let failure = try requiredRange(of: submission.failure, in: source)

            XCTAssertLessThan(submit.lowerBound, parseID.lowerBound)
            XCTAssertLessThan(parseID.lowerBound, failure.lowerBound)
        }

        assertContains("it will not be resubmitted automatically", in: source)
        assertContains("NOTARY_DIAGNOSTICS_PERSISTED", in: source)
        assertContains("CURRENT_RELEASE_STAGE", in: source)
    }

    func testStapledAppIsNeverResigned() throws {
        let source = try script(named: "package-release.sh")
        let appStaple = try requiredRange(
            of: #"stapler staple "${APP_PATH}""#,
            in: source
        )
        let afterStaple = String(source[appStaple.lowerBound...])

        XCTAssertEqual(
            afterStaple.components(separatedBy: "codesign --force").count - 1,
            1,
            "Only the DMG may be force-signed after the app ticket is stapled"
        )
        XCTAssertFalse(
            afterStaple.contains(#"codesign --force "${APP_PATH}""#),
            "Re-signing the app after stapling invalidates its notarization ticket"
        )
        XCTAssertFalse(
            afterStaple.contains(#"--sign "${SIGNING_IDENTITY}" "${APP_PATH}""#),
            "The stapled app must never be signed again"
        )
        assertContains(#""${FINAL_DMG}""#, in: afterStaple)
    }

    func testVerifiedArtifactsArePublishedAtomically() throws {
        let source = try script(named: "package-release.sh")
        let partialCreate = try requiredRange(
            of: #"PARTIAL_DIST_DIR="$(mktemp -d \"#,
            in: source
        )
        let artifactMove = try requiredRange(
            of: #"mv "${artifact}" "${PARTIAL_DIST_DIR}/${artifact:t}""#,
            in: source
        )
        let finalRename = try requiredRange(
            of: #"mv "${PARTIAL_DIST_DIR}" "${DIST_DIR}""#,
            in: source
        )

        XCTAssertLessThan(partialCreate.lowerBound, artifactMove.lowerBound)
        XCTAssertLessThan(artifactMove.lowerBound, finalRename.lowerBound)
        assertContains(#"PARTIAL_DIST_DIR="""#, in: source)
    }

    func testArtifactNamesUseAppVersionAndExplicitArchitecturesOnly() throws {
        let source = try script(named: "package-release.sh")

        assertContains("CFBundleShortVersionString", in: source)
        assertContains("CFBundleVersion", in: source)
        assertContains("TraceHaloReleaseChannel", in: source)
        assertContains("PUBLIC_VERSION", in: source)
        assertContains("BUILD_NUMBER", in: source)
        assertContains("RELEASE_CHANNEL", in: source)
        assertContains(#"ARCH_LABEL="arm64-x86_64""#, in: source)
        assertContains(
            #"PAYLOAD_NAME="TraceHalo-${VERSION}-${ARCH_LABEL}""#,
            in: source
        )
        XCTAssertFalse(
            source.contains(#"PAYLOAD_NAME="TraceHalo-${PUBLIC_VERSION}"#),
            "Artifact names must use the app version without the public tag prefix"
        )
        XCTAssertFalse(
            source.contains(#"PAYLOAD_NAME="TraceHalo-${VERSION_LABEL}"#),
            "Artifact names must not include build, channel, platform, or signing labels"
        )
    }

    func testPublicVersionUsesCompactSemanticTagWithoutZeroPadding() throws {
        let source = try script(named: "public-version.sh")

        assertContains(#"printf 'v%d.%d.%d\n'"#, in: source)
        XCTAssertFalse(
            source.contains("%03d"),
            "Public versions must use compact tags such as v0.1.1"
        )
    }

    func testDmgContainsNoInstallationGuide() throws {
        let source = try script(named: "package-release.sh")
        let dmgStageStart = try requiredRange(
            of: #"ditto "${APP_PATH}" "${DMG_STAGE}/TraceHalo.app""#,
            in: source
        )
        let dmgCreation = try requiredRange(of: "hdiutil create", in: source)
        let dmgStageSource = String(source[dmgStageStart.lowerBound..<dmgCreation.lowerBound])

        assertContains(#"ln -s /Applications "${DMG_STAGE}/Applications""#, in: dmgStageSource)
        XCTAssertFalse(
            dmgStageSource.contains("安装说明.md"),
            "The DMG staging directory must not receive an installation guide"
        )
        assertContains(#"[[ -e "${MOUNT_PATH}/安装说明.md" ]]"#, in: source)
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

        let staple = try requiredRange(
            of: #"stapler staple "${APP_PATH}""#,
            in: source
        )
        let zipCreation = try requiredRange(
            of: #"ditto -c -k --norsrc --keepParent "${PAYLOAD_ROOT}" "${FINAL_ZIP}""#,
            in: source
        )
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

    func testEveryPublishedArchiveContainsAnIndependentlyStapledApp() throws {
        let source = try script(named: "package-release.sh")
        let extractedLoop = try requiredRange(
            of: #"for extracted_root in "${ZIP_VERIFY_ROOT}" "${TAR_VERIFY_ROOT}"; do"#,
            in: source
        )
        let mount = try requiredRange(of: "hdiutil attach", in: source)
        let detach = try requiredRange(
            of: #"hdiutil detach "${MOUNT_PATH}" >/dev/null"#,
            in: source
        )

        let extractedVerification = String(source[extractedLoop.lowerBound..<mount.lowerBound])
        assertContains(#"stapler validate "${extracted_app}""#, in: extractedVerification)
        assertContains(
            #"spctl --assess --type execute --verbose=4 "${extracted_app}""#,
            in: extractedVerification
        )

        let mountedVerification = String(source[mount.lowerBound..<detach.lowerBound])
        assertContains(
            #"stapler validate "${MOUNT_PATH}/TraceHalo.app""#,
            in: mountedVerification
        )
        let mountedGatekeeperCommand = #"""
    spctl --assess \
        --type execute \
        --verbose=4 \
        "${MOUNT_PATH}/TraceHalo.app"
"""#
        assertContains(mountedGatekeeperCommand, in: mountedVerification)
    }

    private func releaseScripts() throws -> [(name: String, source: String)] {
        try ["build-app.sh", "package-release.sh", "public-version.sh"].map { name in
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
