#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PACKAGE_DIR="${SCRIPT_DIR:h}"
INFO_PLIST="${PACKAGE_DIR}/Resources/Info.plist"
INSTALL_GUIDE="${PACKAGE_DIR}/DISTRIBUTION.md"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INFO_PLIST}")"
RELEASE_CHANNEL="$(
    /usr/libexec/PlistBuddy -c 'Print :TraceHaloReleaseChannel' "${INFO_PLIST}" \
        2>/dev/null || true
)"
PUBLIC_VERSION="$("${SCRIPT_DIR}/public-version.sh" "${VERSION}")"
TEAM_ID="${TRACEHALO_TEAM_ID:-4DXU5FSLLY}"
NOTARY_PROFILE="${TRACEHALO_NOTARY_PROFILE:-tracehalo-notary}"
NOTARY_TIMEOUT="${TRACEHALO_NOTARY_TIMEOUT:-1h}"
REQUESTED_IDENTITY="${TRACEHALO_SIGNING_IDENTITY:-}"
REQUESTED_MODE="${TRACEHALO_RELEASE_MODE:-developer-id}"
RELEASE_ARCH="${TRACEHALO_RELEASE_ARCH:-universal}"
NOTARIZE="${TRACEHALO_NOTARIZE:-1}"
RELEASE_STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
GIT_COMMIT="$(git -C "${PACKAGE_DIR}" rev-parse HEAD 2>/dev/null || print unknown)"
DIST_ROOT="${PACKAGE_DIR}/.build/dist"
DMG_IDENTIFIER="com.tseai.tracehalo.dmg"

fail() {
    print -u2 -- "$1"
    exit "${2:-1}"
}

if [[ ! -f "${INSTALL_GUIDE}" ]]; then
    fail "Missing distribution guide: ${INSTALL_GUIDE}"
fi

case "${REQUESTED_MODE}" in
    adhoc|developer-id) ;;
    *)
        fail "Unsupported TRACEHALO_RELEASE_MODE: ${REQUESTED_MODE}. Supported values are adhoc and developer-id." 64
        ;;
esac

case "${RELEASE_ARCH}" in
    arm64|universal) ;;
    *)
        fail "Unsupported TRACEHALO_RELEASE_ARCH: ${RELEASE_ARCH}. Supported values are arm64 and universal." 64
        ;;
esac

case "${NOTARIZE}" in
    0|1) ;;
    *) fail "TRACEHALO_NOTARIZE must be 0 or 1." 64 ;;
esac

if [[ "${REQUESTED_MODE}" == "adhoc" && "${NOTARIZE}" == "1" ]]; then
    fail "Ad-hoc releases cannot be notarized. Set TRACEHALO_NOTARIZE=0 for a local package." 64
fi

mkdir -p "${PACKAGE_DIR}/.build" "${DIST_ROOT}"
WORK_ROOT="$(mktemp -d "${PACKAGE_DIR}/.build/tracehalo-release.XXXXXX")"
MOUNT_PATH="${WORK_ROOT}/mounted-dmg"
DMG_MOUNTED=0
NOTARY_STARTED=0
NOTARY_DIAGNOSTICS_PERSISTED=0
CURRENT_RELEASE_STAGE="initialization"
PARTIAL_DIST_DIR=""

cleanup_work_root() {
    local exit_status=$?
    if [[ "${exit_status}" != "0" \
        && "${NOTARY_STARTED}" == "1" \
        && "${NOTARY_DIAGNOSTICS_PERSISTED}" == "0" ]]; then
        persist_notary_diagnostics \
            "Release failed during ${CURRENT_RELEASE_STAGE} (exit ${exit_status})."
    fi
    if [[ "${DMG_MOUNTED}" == "1" ]]; then
        hdiutil detach "${MOUNT_PATH}" -force >/dev/null 2>&1 || true
    fi
    if [[ -n "${PARTIAL_DIST_DIR}" && -d "${PARTIAL_DIST_DIR}" ]]; then
        # This exact hidden directory is created below by this script only.
        rm -rf "${PARTIAL_DIST_DIR}"
    fi
    # WORK_ROOT is always created by this script beneath Package/.build.
    rm -rf "${WORK_ROOT}"
}
trap cleanup_work_root EXIT

NOTARY_PROFILE_CHECK="${WORK_ROOT}/notary-profile-check.json"
NOTARY_PROFILE_STDERR="${WORK_ROOT}/notary-profile-stderr.txt"
APP_NOTARY_ARCHIVE="${WORK_ROOT}/TraceHalo-app-notary.zip"
APP_NOTARY_RESULT="${WORK_ROOT}/app-notarization-result.json"
APP_NOTARY_LOG="${WORK_ROOT}/app-notarization-log.json"
APP_NOTARY_STDERR="${WORK_ROOT}/app-notarization-stderr.txt"
APP_NOTARY_STATUS=""
APP_SUBMISSION_ID=""
DMG_NOTARY_RESULT="${WORK_ROOT}/dmg-notarization-result.json"
DMG_NOTARY_LOG="${WORK_ROOT}/dmg-notarization-log.json"
DMG_NOTARY_STDERR="${WORK_ROOT}/dmg-notarization-stderr.txt"
DMG_NOTARY_STATUS=""
DMG_SUBMISSION_ID=""

persist_notary_diagnostics() {
    local reason="$1"
    local failed_dist=""
    NOTARY_DIAGNOSTICS_PERSISTED=1
    if ! failed_dist="$(mktemp -d \
        "${DIST_ROOT}/${PUBLIC_VERSION}-${RELEASE_STAMP}-notary-failed.XXXXXX")"; then
        print -u2 -- "${reason}"
        print -u2 -- "Unable to create a notarization diagnostics directory."
        return 0
    fi

    for diagnostic in \
        "${NOTARY_PROFILE_CHECK}" \
        "${NOTARY_PROFILE_STDERR}" \
        "${APP_NOTARY_RESULT}" \
        "${APP_NOTARY_LOG}" \
        "${APP_NOTARY_STDERR}" \
        "${DMG_NOTARY_RESULT}" \
        "${DMG_NOTARY_LOG}" \
        "${DMG_NOTARY_STDERR}"; do
        if [[ -f "${diagnostic}" ]]; then
            cp "${diagnostic}" "${failed_dist}/${diagnostic:t}" || true
        fi
    done
    print -r -- "${reason}" > "${failed_dist}/failure-reason.txt" || true
    print -u2 -- "${reason}"
    print -u2 -- "Notarization diagnostics: ${failed_dist}"
}

SIGNING_IDENTITY="-"
if [[ "${REQUESTED_MODE}" == "developer-id" ]]; then
    IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    if [[ -n "${REQUESTED_IDENTITY}" ]]; then
        IDENTITY_LINE="$(
            print -r -- "${IDENTITIES}" \
                | grep -F -- "${REQUESTED_IDENTITY}" \
                | grep -F -- "Developer ID Application:" \
                | grep -F -- "(${TEAM_ID})" \
                | head -n 1 || true
        )"
    else
        IDENTITY_LINE="$(
            print -r -- "${IDENTITIES}" \
                | awk -v team="(${TEAM_ID})" \
                    '/Developer ID Application:/ && index($0, team) { print; exit }'
        )"
    fi

    if [[ -z "${IDENTITY_LINE}" ]]; then
        fail "No valid Developer ID Application identity with a private key is available for Team ${TEAM_ID}. Refusing to fall back to ad-hoc signing." 2
    fi
    SIGNING_IDENTITY="$(print -r -- "${IDENTITY_LINE}" | awk '{ print $2 }')"
fi

if [[ "${REQUESTED_MODE}" == "developer-id" && "${NOTARIZE}" == "1" ]]; then
    if ! xcrun notarytool history \
        --keychain-profile "${NOTARY_PROFILE}" \
        --output-format json \
        > "${NOTARY_PROFILE_CHECK}" \
        2> "${NOTARY_PROFILE_STDERR}"; then
        persist_notary_diagnostics \
            "Notary keychain profile '${NOTARY_PROFILE}' is missing or invalid. Configure it with 'xcrun notarytool store-credentials'."
        exit 5
    fi
fi

if [[ "${RELEASE_ARCH}" == "universal" ]]; then
    UNIVERSAL_BUILD=1
    TARGET_ARCH=native
    ARCH_LABEL="arm64-x86_64"
else
    UNIVERSAL_BUILD=0
    TARGET_ARCH=arm64
    ARCH_LABEL="arm64"
fi

if [[ "${REQUESTED_MODE}" == "developer-id" ]]; then
    SIGNING_LABEL="developer-id"
else
    SIGNING_LABEL="adhoc"
fi
PAYLOAD_NAME="TraceHalo-${VERSION}-${ARCH_LABEL}"
PAYLOAD_ROOT="${WORK_ROOT}/${PAYLOAD_NAME}"
APP_PATH="${PAYLOAD_ROOT}/TraceHalo.app"
DMG_STAGE="${WORK_ROOT}/dmg-stage"
FINAL_DMG="${WORK_ROOT}/${PAYLOAD_NAME}.dmg"
FINAL_ZIP="${WORK_ROOT}/${PAYLOAD_NAME}.zip"
FINAL_TAR="${WORK_ROOT}/${PAYLOAD_NAME}.tar.gz"
RELEASE_MANIFEST="${WORK_ROOT}/release-manifest.txt"

mkdir -p "${PAYLOAD_ROOT}" "${DMG_STAGE}"

print "Building TraceHalo ${PUBLIC_VERSION} (Apple ${VERSION}, build ${BUILD_NUMBER}, channel ${RELEASE_CHANNEL:-none}) for ${ARCH_LABEL} with ${SIGNING_LABEL} signing..."
TRACEHALO_APP_PATH="${APP_PATH}" \
TRACEHALO_DISABLE_SWIFTPM_SANDBOX=1 \
TRACEHALO_SIGNING_IDENTITY="${SIGNING_IDENTITY}" \
TRACEHALO_UNIVERSAL="${UNIVERSAL_BUILD}" \
TRACEHALO_TARGET_ARCH="${TARGET_ARCH}" \
    "${SCRIPT_DIR}/build-app.sh"

cp "${INSTALL_GUIDE}" "${PAYLOAD_ROOT}/安装说明.md"

MAIN_EXECUTABLE="${APP_PATH}/Contents/MacOS/TraceHalo"
SENSOR_HELPER="${APP_PATH}/Contents/Resources/TraceHaloSensorHelper"
UNINSTALL_HELPER="${APP_PATH}/Contents/Resources/TraceHaloUninstallHelper"

verify_architectures() {
    local executable="$1"
    local architectures
    architectures="$(lipo -archs "${executable}")"

    if [[ "${RELEASE_ARCH}" == "universal" ]]; then
        if [[ " ${architectures} " != *" arm64 "* \
            || " ${architectures} " != *" x86_64 "* ]]; then
            fail "Universal 2 verification failed for ${executable}: ${architectures}" 3
        fi
    elif [[ " ${architectures} " != *" arm64 "* ]]; then
        fail "arm64 verification failed for ${executable}: ${architectures}" 3
    fi
}

verify_developer_signature() {
    local item="$1"
    local expected_identifier="$2"
    local details

    codesign --verify --strict --verbose=4 "${item}"
    details="$(codesign -d --verbose=4 "${item}" 2>&1)"
    print -r -- "${details}" | grep -Fx -- "Identifier=${expected_identifier}" >/dev/null \
        || fail "Unexpected signing identifier for ${item}." 3
    print -r -- "${details}" | grep -F -- "Authority=Developer ID Application:" >/dev/null \
        || fail "Developer ID authority is missing for ${item}." 3
    print -r -- "${details}" | grep -Fx -- "TeamIdentifier=${TEAM_ID}" >/dev/null \
        || fail "TeamIdentifier ${TEAM_ID} is missing for ${item}." 3
    print -r -- "${details}" | grep -E -- 'flags=.*\(runtime\)' >/dev/null \
        || fail "Hardened Runtime is missing for ${item}." 3
    print -r -- "${details}" | grep -F -- "Timestamp=" >/dev/null \
        || fail "A trusted timestamp is missing for ${item}." 3
}

verify_architectures "${MAIN_EXECUTABLE}"
verify_architectures "${SENSOR_HELPER}"
verify_architectures "${UNINSTALL_HELPER}"
codesign --verify --deep --strict --verbose=4 "${APP_PATH}"

if [[ "${REQUESTED_MODE}" == "developer-id" ]]; then
    verify_developer_signature \
        "${SENSOR_HELPER}" \
        "com.tseai.tracehalo.sensor-helper"
    verify_developer_signature \
        "${UNINSTALL_HELPER}" \
        "com.tseai.tracehalo.uninstall-helper"
    verify_developer_signature "${APP_PATH}" "com.tseai.tracehalo"
fi

if [[ "${NOTARIZE}" == "1" ]]; then
    # notarytool accepts ZIP, DMG, or flat PKG containers, not a bare .app.
    # Notarize and staple the app before copying it into any public archive.
    ditto -c -k --sequesterRsrc --keepParent \
        "${APP_PATH}" \
        "${APP_NOTARY_ARCHIVE}"
    NOTARY_STARTED=1
    CURRENT_RELEASE_STAGE="app notarization submission"
    print "Submitting signed app to Apple notarization with keychain profile '${NOTARY_PROFILE}'..."
    APP_SUBMIT_EXIT=0
    if xcrun notarytool submit "${APP_NOTARY_ARCHIVE}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --wait \
        --timeout "${NOTARY_TIMEOUT}" \
        --output-format json \
        > "${APP_NOTARY_RESULT}" \
        2> "${APP_NOTARY_STDERR}"; then
        APP_SUBMIT_EXIT=0
    else
        APP_SUBMIT_EXIT=$?
    fi

    APP_NOTARY_STATUS="$(
        plutil -extract status raw -o - "${APP_NOTARY_RESULT}" 2>/dev/null || true
    )"
    APP_SUBMISSION_ID="$(
        plutil -extract id raw -o - "${APP_NOTARY_RESULT}" 2>/dev/null || true
    )"
    if [[ -n "${APP_SUBMISSION_ID}" ]]; then
        xcrun notarytool log "${APP_SUBMISSION_ID}" \
            --keychain-profile "${NOTARY_PROFILE}" \
            "${APP_NOTARY_LOG}" \
            2>> "${APP_NOTARY_STDERR}" || true
    fi

    if [[ "${APP_SUBMIT_EXIT}" != "0" ]]; then
        persist_notary_diagnostics \
            "Apple app notarization command failed (exit ${APP_SUBMIT_EXIT}, submission ${APP_SUBMISSION_ID:-unknown}); it will not be resubmitted automatically."
        exit 6
    fi

    if [[ "${APP_NOTARY_STATUS}" != "Accepted" ]]; then
        persist_notary_diagnostics \
            "Apple notarization did not accept the app: ${APP_NOTARY_STATUS:-unknown status}."
        exit 7
    fi

    CURRENT_RELEASE_STAGE="app ticket and Gatekeeper validation"
    if ! xcrun stapler staple "${APP_PATH}" \
        || ! xcrun stapler validate "${APP_PATH}"; then
        persist_notary_diagnostics \
            "Unable to staple or validate the app ticket; refusing to create release archives."
        exit 8
    fi

    codesign --verify --deep --strict --verbose=4 "${APP_PATH}"
    spctl --assess --type execute --verbose=4 "${APP_PATH}"
fi

# Every public container is created from the already-stapled app. Never
# re-sign APP_PATH after this copy: re-signing invalidates its notarization ticket.
CURRENT_RELEASE_STAGE="DMG creation and signing"
ditto "${APP_PATH}" "${DMG_STAGE}/TraceHalo.app"
ln -s /Applications "${DMG_STAGE}/Applications"

hdiutil create \
    -volname "TraceHalo ${VERSION}${RELEASE_CHANNEL:+ ${RELEASE_CHANNEL}}" \
    -srcfolder "${DMG_STAGE}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    "${FINAL_DMG}" \
    >/dev/null

if [[ "${REQUESTED_MODE}" == "developer-id" ]]; then
    codesign --force \
        --sign "${SIGNING_IDENTITY}" \
        --timestamp \
        --identifier "${DMG_IDENTIFIER}" \
        "${FINAL_DMG}"
    codesign --verify --strict --verbose=4 "${FINAL_DMG}"
fi
hdiutil verify "${FINAL_DMG}" >/dev/null

if [[ "${NOTARIZE}" == "1" ]]; then
    CURRENT_RELEASE_STAGE="DMG notarization submission"
    print "Submitting signed DMG to Apple notarization with keychain profile '${NOTARY_PROFILE}'..."
    DMG_SUBMIT_EXIT=0
    if xcrun notarytool submit "${FINAL_DMG}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --wait \
        --timeout "${NOTARY_TIMEOUT}" \
        --output-format json \
        > "${DMG_NOTARY_RESULT}" \
        2> "${DMG_NOTARY_STDERR}"; then
        DMG_SUBMIT_EXIT=0
    else
        DMG_SUBMIT_EXIT=$?
    fi

    DMG_NOTARY_STATUS="$(
        plutil -extract status raw -o - "${DMG_NOTARY_RESULT}" 2>/dev/null || true
    )"
    DMG_SUBMISSION_ID="$(
        plutil -extract id raw -o - "${DMG_NOTARY_RESULT}" 2>/dev/null || true
    )"
    if [[ -n "${DMG_SUBMISSION_ID}" ]]; then
        xcrun notarytool log "${DMG_SUBMISSION_ID}" \
            --keychain-profile "${NOTARY_PROFILE}" \
            "${DMG_NOTARY_LOG}" \
            2>> "${DMG_NOTARY_STDERR}" || true
    fi

    if [[ "${DMG_SUBMIT_EXIT}" != "0" ]]; then
        persist_notary_diagnostics \
            "Apple DMG notarization command failed (exit ${DMG_SUBMIT_EXIT}, submission ${DMG_SUBMISSION_ID:-unknown}); it will not be resubmitted automatically."
        exit 9
    fi

    if [[ "${DMG_NOTARY_STATUS}" != "Accepted" ]]; then
        persist_notary_diagnostics \
            "Apple notarization did not accept the DMG: ${DMG_NOTARY_STATUS:-unknown status}."
        exit 10
    fi

    CURRENT_RELEASE_STAGE="DMG ticket and Gatekeeper validation"
    if ! xcrun stapler staple "${FINAL_DMG}" \
        || ! xcrun stapler validate "${FINAL_DMG}"; then
        persist_notary_diagnostics "Unable to staple or validate the DMG ticket."
        exit 11
    fi

    codesign --verify --strict --verbose=4 "${FINAL_DMG}"
    hdiutil verify "${FINAL_DMG}" >/dev/null
    spctl --assess \
        --type open \
        --context context:primary-signature \
        --verbose=4 \
        "${FINAL_DMG}"
fi

# Create transport archives only after the app ticket is stapled. TAR itself
# cannot be signed or notarized; the signed, notarized app inside is verified
# again after extraction below.
CURRENT_RELEASE_STAGE="ZIP and TAR creation"
ditto -c -k --norsrc --keepParent "${PAYLOAD_ROOT}" "${FINAL_ZIP}"
tar -czf "${FINAL_TAR}" -C "${WORK_ROOT}" "${PAYLOAD_NAME}"

ZIP_VERIFY_ROOT="${WORK_ROOT}/zip-verify"
TAR_VERIFY_ROOT="${WORK_ROOT}/tar-verify"
mkdir -p "${ZIP_VERIFY_ROOT}" "${TAR_VERIFY_ROOT}"
ditto -x -k "${FINAL_ZIP}" "${ZIP_VERIFY_ROOT}"
tar -xzf "${FINAL_TAR}" -C "${TAR_VERIFY_ROOT}"

for extracted_root in "${ZIP_VERIFY_ROOT}" "${TAR_VERIFY_ROOT}"; do
    CURRENT_RELEASE_STAGE="transport archive app validation"
    extracted_app="${extracted_root}/${PAYLOAD_NAME}/TraceHalo.app"
    extracted_main="${extracted_app}/Contents/MacOS/TraceHalo"
    extracted_helper="${extracted_app}/Contents/Resources/TraceHaloSensorHelper"
    verify_architectures "${extracted_main}"
    verify_architectures "${extracted_helper}"
    verify_architectures "${extracted_app}/Contents/Resources/TraceHaloUninstallHelper"
    codesign --verify --deep --strict --verbose=4 "${extracted_app}"
    if [[ "${NOTARIZE}" == "1" ]]; then
        xcrun stapler validate "${extracted_app}"
        spctl --assess --type execute --verbose=4 "${extracted_app}"
    fi
done

mkdir -p "${MOUNT_PATH}"
CURRENT_RELEASE_STAGE="mounted DMG app validation"
hdiutil attach \
    -readonly \
    -nobrowse \
    -mountpoint "${MOUNT_PATH}" \
    "${FINAL_DMG}" \
    >/dev/null
DMG_MOUNTED=1
verify_architectures "${MOUNT_PATH}/TraceHalo.app/Contents/MacOS/TraceHalo"
verify_architectures \
    "${MOUNT_PATH}/TraceHalo.app/Contents/Resources/TraceHaloSensorHelper"
verify_architectures \
    "${MOUNT_PATH}/TraceHalo.app/Contents/Resources/TraceHaloUninstallHelper"
codesign --verify --deep --strict --verbose=4 "${MOUNT_PATH}/TraceHalo.app"
if [[ "${NOTARIZE}" == "1" ]]; then
    xcrun stapler validate "${MOUNT_PATH}/TraceHalo.app"
    spctl --assess \
        --type execute \
        --verbose=4 \
        "${MOUNT_PATH}/TraceHalo.app"
fi
if [[ -e "${MOUNT_PATH}/安装说明.md" ]]; then
    fail "The DMG must not contain an installation guide." 3
fi
hdiutil detach "${MOUNT_PATH}" >/dev/null
DMG_MOUNTED=0

{
    print "Product: TraceHalo"
    print "Apple version: ${VERSION}"
    print "Public version: ${PUBLIC_VERSION}"
    print "Build: ${BUILD_NUMBER}"
    print "Release channel: ${RELEASE_CHANNEL:-none}"
    print "Architecture: ${ARCH_LABEL}"
    print "Signing mode: ${SIGNING_LABEL}"
    print "Team ID: ${TEAM_ID}"
    print "Signing identity SHA-1: ${SIGNING_IDENTITY}"
    print "Notarized: ${NOTARIZE}"
    print "App notary status: ${APP_NOTARY_STATUS:-not requested}"
    print "App notary submission ID: ${APP_SUBMISSION_ID:-none}"
    print "DMG notary status: ${DMG_NOTARY_STATUS:-not requested}"
    print "DMG notary submission ID: ${DMG_SUBMISSION_ID:-none}"
    print "Git commit: ${GIT_COMMIT}"
    print "Built at UTC: ${RELEASE_STAMP}"
} > "${RELEASE_MANIFEST}"

for artifact in "${FINAL_DMG}" "${FINAL_ZIP}" "${FINAL_TAR}"; do
    artifact_name="${artifact:t}"
    artifact_sha="$(shasum -a 256 "${artifact}" | awk '{ print $1 }')"
    print -r -- "${artifact_sha}  ${artifact_name}" > "${artifact}.sha256"
done

PARTIAL_DIST_DIR="$(mktemp -d \
    "${DIST_ROOT}/.${VERSION}-${RELEASE_STAMP}.partial.XXXXXX")"
PARTIAL_DIST_NAME="${PARTIAL_DIST_DIR:t}"
DIST_SUFFIX="${PARTIAL_DIST_NAME##*.}"
DIST_DIR="${DIST_ROOT}/${VERSION}-${RELEASE_STAMP}.${DIST_SUFFIX}"
CURRENT_RELEASE_STAGE="publishing verified artifacts"
for artifact in \
    "${FINAL_DMG}" \
    "${FINAL_DMG}.sha256" \
    "${FINAL_ZIP}" \
    "${FINAL_ZIP}.sha256" \
    "${FINAL_TAR}" \
    "${FINAL_TAR}.sha256" \
    "${RELEASE_MANIFEST}"; do
    mv "${artifact}" "${PARTIAL_DIST_DIR}/${artifact:t}"
done
for diagnostic in \
    "${APP_NOTARY_RESULT}" \
    "${APP_NOTARY_LOG}" \
    "${DMG_NOTARY_RESULT}" \
    "${DMG_NOTARY_LOG}"; do
    if [[ -f "${diagnostic}" ]]; then
        cp "${diagnostic}" "${PARTIAL_DIST_DIR}/${diagnostic:t}"
    fi
done

mv "${PARTIAL_DIST_DIR}" "${DIST_DIR}"
PARTIAL_DIST_DIR=""
NOTARY_DIAGNOSTICS_PERSISTED=1

print "Release directory: ${DIST_DIR}"
print "DMG: ${DIST_DIR}/${FINAL_DMG:t}"
print "ZIP: ${DIST_DIR}/${FINAL_ZIP:t}"
print "TAR: ${DIST_DIR}/${FINAL_TAR:t}"
if [[ "${NOTARIZE}" == "0" ]]; then
    print "This package is explicitly UNNOTARIZED and must not be published as an Apple-verified release."
fi
