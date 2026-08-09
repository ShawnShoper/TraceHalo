#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PACKAGE_DIR="${SCRIPT_DIR:h}"
INFO_PLIST="${PACKAGE_DIR}/Resources/Info.plist"
INSTALL_GUIDE="${PACKAGE_DIR}/DISTRIBUTION.md"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INFO_PLIST}")"
PUBLIC_VERSION="$("${SCRIPT_DIR}/public-version.sh" "${VERSION}")"
NOTARY_PROFILE="${TRACEHALO_NOTARY_PROFILE:-tracehalo-notary}"
REQUESTED_IDENTITY="${TRACEHALO_SIGNING_IDENTITY:-}"
REQUESTED_MODE="${TRACEHALO_RELEASE_MODE:-adhoc}"
RELEASE_ARCH="${TRACEHALO_RELEASE_ARCH:-arm64}"
NOTARIZE="${TRACEHALO_NOTARIZE:-0}"
STRICT_SIGNING="${TRACEHALO_STRICT_SIGNING:-0}"
RELEASE_STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
DIST_ROOT="${PACKAGE_DIR}/.build/dist"

if [[ ! -f "${INSTALL_GUIDE}" ]]; then
    print -u2 "Missing distribution guide: ${INSTALL_GUIDE}"
    exit 1
fi

case "${REQUESTED_MODE}" in
    adhoc|developer-id) ;;
    *)
        print -u2 "Unsupported TRACEHALO_RELEASE_MODE: ${REQUESTED_MODE}"
        print -u2 "Supported values are adhoc and developer-id."
        exit 1
        ;;
esac

case "${RELEASE_ARCH}" in
    arm64|universal) ;;
    *)
        print -u2 "Unsupported TRACEHALO_RELEASE_ARCH: ${RELEASE_ARCH}"
        print -u2 "Supported values are arm64 and universal."
        exit 1
        ;;
esac

case "${NOTARIZE}" in
    0|1) ;;
    *)
        print -u2 "TRACEHALO_NOTARIZE must be 0 or 1."
        exit 1
        ;;
esac

case "${STRICT_SIGNING}" in
    0|1) ;;
    *)
        print -u2 "TRACEHALO_STRICT_SIGNING must be 0 or 1."
        exit 1
        ;;
esac

mkdir -p "${PACKAGE_DIR}/.build" "${DIST_ROOT}"
WORK_ROOT="$(mktemp -d "${PACKAGE_DIR}/.build/tracehalo-release.XXXXXX")"

cleanup_work_root() {
    # WORK_ROOT is always created by this script beneath Package/.build.
    rm -rf "${WORK_ROOT}"
}
trap cleanup_work_root EXIT

EFFECTIVE_MODE="${REQUESTED_MODE}"
SIGNING_IDENTITY="-"
if [[ "${REQUESTED_MODE}" == "developer-id" ]]; then
    IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    if [[ -n "${REQUESTED_IDENTITY}" ]]; then
        if print -r -- "${IDENTITIES}" | grep -F -- "${REQUESTED_IDENTITY}" >/dev/null; then
            SIGNING_IDENTITY="${REQUESTED_IDENTITY}"
        fi
    else
        SIGNING_IDENTITY="$(
            print -r -- "${IDENTITIES}" \
                | awk '/Developer ID Application:/ { print $2; exit }'
        )"
    fi

    if [[ -z "${SIGNING_IDENTITY}" || "${SIGNING_IDENTITY}" == "-" ]]; then
        if [[ "${STRICT_SIGNING}" == "1" ]]; then
            print -u2 "No requested Developer ID Application identity is available."
            exit 2
        fi
        print -u2 "Warning: no Developer ID Application identity is available."
        print -u2 "Falling back to an ad-hoc signed package; Apple verification prompts may appear."
        EFFECTIVE_MODE="adhoc"
        SIGNING_IDENTITY="-"
    fi
fi

if [[ "${EFFECTIVE_MODE}" == "adhoc" && "${NOTARIZE}" == "1" ]]; then
    print -u2 "Warning: notarization requires Developer ID signing; notarization will be skipped."
    NOTARIZE="0"
fi

ARCH_LABEL="${RELEASE_ARCH}"
SIGNING_LABEL="${EFFECTIVE_MODE}"
PAYLOAD_NAME="TraceHalo-${PUBLIC_VERSION}-macOS-${ARCH_LABEL}-${SIGNING_LABEL}"
PAYLOAD_ROOT="${WORK_ROOT}/${PAYLOAD_NAME}"
APP_PATH="${PAYLOAD_ROOT}/TraceHalo.app"
NOTARY_ZIP="${WORK_ROOT}/TraceHalo-${PUBLIC_VERSION}-notary-submission.zip"
NOTARY_RESULT="${WORK_ROOT}/notarization-result.json"
NOTARY_LOG="${WORK_ROOT}/notarization-log.json"

mkdir -p "${PAYLOAD_ROOT}"

if [[ "${RELEASE_ARCH}" == "universal" ]]; then
    UNIVERSAL_BUILD=1
    TARGET_ARCH=native
else
    UNIVERSAL_BUILD=0
    TARGET_ARCH=arm64
fi

print "Building TraceHalo ${PUBLIC_VERSION} (Apple ${VERSION}, build ${BUILD_NUMBER}) for ${ARCH_LABEL} with ${SIGNING_LABEL} signing..."
TRACEHALO_APP_PATH="${APP_PATH}" \
TRACEHALO_DISABLE_SWIFTPM_SANDBOX=1 \
TRACEHALO_SIGNING_IDENTITY="${SIGNING_IDENTITY}" \
TRACEHALO_UNIVERSAL="${UNIVERSAL_BUILD}" \
TRACEHALO_TARGET_ARCH="${TARGET_ARCH}" \
    "${SCRIPT_DIR}/build-app.sh"

cp "${INSTALL_GUIDE}" "${PAYLOAD_ROOT}/安装说明.md"

MAIN_EXECUTABLE="${APP_PATH}/Contents/MacOS/TraceHalo"
SENSOR_HELPER="${APP_PATH}/Contents/Resources/TraceHaloSensorHelper"

for executable in "${MAIN_EXECUTABLE}" "${SENSOR_HELPER}"; do
    ARCHITECTURES="$(lipo -archs "${executable}")"
    if [[ "${RELEASE_ARCH}" == "universal" ]]; then
        if [[ " ${ARCHITECTURES} " != *" arm64 "* \
            || " ${ARCHITECTURES} " != *" x86_64 "* ]]; then
            print -u2 "Universal 2 verification failed for ${executable}: ${ARCHITECTURES}"
            exit 3
        fi
    elif [[ " ${ARCHITECTURES} " != *" arm64 "* ]]; then
        print -u2 "arm64 verification failed for ${executable}: ${ARCHITECTURES}"
        exit 3
    fi
done

codesign --verify --deep --strict --verbose=4 "${APP_PATH}"

NOTARIZED_SUFFIX=""
if [[ "${NOTARIZE}" == "1" ]]; then
    # Apple accepts a ZIP for notarization but cannot staple a ticket to it.
    # Submit a temporary app-only archive, staple the app, then package it.
    ditto -c -k --norsrc --keepParent "${APP_PATH}" "${NOTARY_ZIP}"

    print "Submitting to Apple notarization with keychain profile '${NOTARY_PROFILE}'..."
    xcrun notarytool submit "${NOTARY_ZIP}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --wait \
        --output-format json \
        > "${NOTARY_RESULT}"

    NOTARY_STATUS="$(plutil -extract status raw -o - "${NOTARY_RESULT}")"
    SUBMISSION_ID="$(plutil -extract id raw -o - "${NOTARY_RESULT}")"
    xcrun notarytool log "${SUBMISSION_ID}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        "${NOTARY_LOG}"

    if [[ "${NOTARY_STATUS}" != "Accepted" ]]; then
        FAILED_DIST="$(mktemp -d \
            "${DIST_ROOT}/${PUBLIC_VERSION}-${RELEASE_STAMP}-notary-failed.XXXXXX")"
        cp "${NOTARY_RESULT}" "${FAILED_DIST}/notarization-result.json"
        cp "${NOTARY_LOG}" "${FAILED_DIST}/notarization-log.json"
        print -u2 "Apple notarization did not accept this build: ${NOTARY_STATUS}"
        print -u2 "See ${FAILED_DIST}/notarization-log.json"
        exit 4
    fi

    xcrun stapler staple "${APP_PATH}"
    xcrun stapler validate "${APP_PATH}"
    spctl --assess --type execute --verbose=4 "${APP_PATH}"
    NOTARIZED_SUFFIX="-notarized"
fi

FINAL_BASENAME="TraceHalo-${PUBLIC_VERSION}-macOS-${ARCH_LABEL}-${SIGNING_LABEL}${NOTARIZED_SUFFIX}.zip"
FINAL_ZIP="${WORK_ROOT}/${FINAL_BASENAME}"
FINAL_SHA="${FINAL_ZIP}.sha256"
ditto -c -k --norsrc --keepParent "${PAYLOAD_ROOT}" "${FINAL_ZIP}"
ZIP_SHA256="$(shasum -a 256 "${FINAL_ZIP}" | awk '{ print $1 }')"
print -r -- "${ZIP_SHA256}  ${FINAL_BASENAME}" > "${FINAL_SHA}"

DIST_DIR="$(mktemp -d "${DIST_ROOT}/${PUBLIC_VERSION}-${RELEASE_STAMP}.XXXXXX")"
mv "${FINAL_ZIP}" "${DIST_DIR}/${FINAL_BASENAME}"
mv "${FINAL_SHA}" "${DIST_DIR}/${FINAL_BASENAME}.sha256"
if [[ -f "${NOTARY_RESULT}" ]]; then
    cp "${NOTARY_RESULT}" "${DIST_DIR}/notarization-result.json"
fi
if [[ -f "${NOTARY_LOG}" ]]; then
    cp "${NOTARY_LOG}" "${DIST_DIR}/notarization-log.json"
fi

print "Release package: ${DIST_DIR}/${FINAL_BASENAME}"
print "SHA-256: ${DIST_DIR}/${FINAL_BASENAME}.sha256"
if [[ "${EFFECTIVE_MODE}" == "adhoc" ]]; then
    print "This package is ad-hoc signed and not notarized; Gatekeeper prompts may still appear."
fi
