#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PACKAGE_DIR="${SCRIPT_DIR:h}"
APP_PATH="${TRACEHALO_APP_PATH:-${PACKAGE_DIR}/.build/TraceHalo.app}"
ICON_SOURCE_PNG="${PACKAGE_DIR}/Resources/TraceHalo-AppIcon-Source.png"
SENSOR_HELPER_PLIST_NAME="com.tseai.tracehalo.sensor-helper.plist"
SIGNING_IDENTITY="${TRACEHALO_SIGNING_IDENTITY:--}"
UNIVERSAL_BUILD="${TRACEHALO_UNIVERSAL:-0}"
TARGET_ARCH="${TRACEHALO_TARGET_ARCH:-native}"

mkdir -p "${PACKAGE_DIR}/.build"
STAGING_ROOT="$(mktemp -d "${PACKAGE_DIR}/.build/tracehalo-app.XXXXXX")"
STAGED_APP_PATH="${STAGING_ROOT}/TraceHalo.app"
ICONSET_PATH="${STAGING_ROOT}/AppIcon.iconset"
ICON_SOURCE_DIR="${STAGING_ROOT}/IconSource"
ICON_PREPARED_PNG="${ICON_SOURCE_DIR}/TraceHalo-AppIcon.png"

cleanup_staging() {
    rm -rf "${STAGING_ROOT}"
}
trap cleanup_staging EXIT

cd "${PACKAGE_DIR}"
export SWIFTPM_MODULECACHE_OVERRIDE="${PACKAGE_DIR}/.build/codex-swiftpm-module-cache"
export SWIFT_MODULECACHE_PATH="${PACKAGE_DIR}/.build/swift-module-cache"
export CLANG_MODULE_CACHE_PATH="${PACKAGE_DIR}/.build/codex-module-cache"

SWIFT_BUILD_ARGUMENTS=(-c release)
if [[ "${TRACEHALO_DISABLE_SWIFTPM_SANDBOX:-0}" == "1" ]]; then
    SWIFT_BUILD_ARGUMENTS=(--disable-sandbox "${SWIFT_BUILD_ARGUMENTS[@]}")
fi

build_for_triple() {
    local triple="$1"
    local scratch_path="$2"
    local arguments=(
        "${SWIFT_BUILD_ARGUMENTS[@]}"
        --triple "${triple}"
        --scratch-path "${scratch_path}"
    )

    swift build "${arguments[@]}" >&2
    swift build "${arguments[@]}" --show-bin-path
}

if [[ "${UNIVERSAL_BUILD}" == "1" ]]; then
    ARM64_BIN_PATH="$(build_for_triple \
        arm64-apple-macosx14.0 \
        "${STAGING_ROOT}/release-arm64")"
    X86_64_BIN_PATH="$(build_for_triple \
        x86_64-apple-macosx14.0 \
        "${STAGING_ROOT}/release-x86_64")"
    APP_RESOURCE_BUNDLE_PATH="${ARM64_BIN_PATH}/TraceHalo_TraceHaloApp.bundle"
    CORE_RESOURCE_BUNDLE_PATH="${ARM64_BIN_PATH}/TraceHalo_TraceHaloCore.bundle"
elif [[ "${TARGET_ARCH}" == "arm64" ]]; then
    BIN_PATH="$(build_for_triple \
        arm64-apple-macosx14.0 \
        "${STAGING_ROOT}/release-arm64")"
    APP_RESOURCE_BUNDLE_PATH="${BIN_PATH}/TraceHalo_TraceHaloApp.bundle"
    CORE_RESOURCE_BUNDLE_PATH="${BIN_PATH}/TraceHalo_TraceHaloCore.bundle"
elif [[ "${TARGET_ARCH}" == "native" ]]; then
    NATIVE_BUILD_ARGUMENTS=(
        "${SWIFT_BUILD_ARGUMENTS[@]}"
        --scratch-path "${STAGING_ROOT}/release-native"
    )
    swift build "${NATIVE_BUILD_ARGUMENTS[@]}"
    BIN_PATH="$(swift build "${NATIVE_BUILD_ARGUMENTS[@]}" --show-bin-path)"
    APP_RESOURCE_BUNDLE_PATH="${BIN_PATH}/TraceHalo_TraceHaloApp.bundle"
    CORE_RESOURCE_BUNDLE_PATH="${BIN_PATH}/TraceHalo_TraceHaloCore.bundle"
else
    print -u2 "Unsupported TRACEHALO_TARGET_ARCH: ${TARGET_ARCH}"
    print -u2 "Supported values are native and arm64."
    exit 1
fi

mkdir -p "${STAGED_APP_PATH}/Contents/MacOS"
mkdir -p "${STAGED_APP_PATH}/Contents/Resources"
mkdir -p "${STAGED_APP_PATH}/Contents/Library/LaunchDaemons"
mkdir -p "${ICONSET_PATH}"
mkdir -p "${ICON_SOURCE_DIR}"

swift "${PACKAGE_DIR}/scripts/prepare-app-icon.swift" "${ICON_SOURCE_PNG}" "${ICON_PREPARED_PNG}"
[[ -f "${ICON_PREPARED_PNG}" ]] || { print -u2 "Unable to prepare TraceHalo app icon"; exit 1; }

sips -z 16 16 "${ICON_PREPARED_PNG}" --out "${ICONSET_PATH}/icon_16x16.png" >/dev/null
sips -z 32 32 "${ICON_PREPARED_PNG}" --out "${ICONSET_PATH}/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "${ICON_PREPARED_PNG}" --out "${ICONSET_PATH}/icon_32x32.png" >/dev/null
sips -z 64 64 "${ICON_PREPARED_PNG}" --out "${ICONSET_PATH}/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "${ICON_PREPARED_PNG}" --out "${ICONSET_PATH}/icon_128x128.png" >/dev/null
sips -z 256 256 "${ICON_PREPARED_PNG}" --out "${ICONSET_PATH}/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "${ICON_PREPARED_PNG}" --out "${ICONSET_PATH}/icon_256x256.png" >/dev/null
sips -z 512 512 "${ICON_PREPARED_PNG}" --out "${ICONSET_PATH}/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "${ICON_PREPARED_PNG}" --out "${ICONSET_PATH}/icon_512x512.png" >/dev/null
sips -z 1024 1024 "${ICON_PREPARED_PNG}" --out "${ICONSET_PATH}/icon_512x512@2x.png" >/dev/null
swift "${PACKAGE_DIR}/scripts/make-icns.swift" \
        "${STAGED_APP_PATH}/Contents/Resources/AppIcon.icns" \
        "icp4=${ICONSET_PATH}/icon_16x16.png" \
        "icp5=${ICONSET_PATH}/icon_32x32.png" \
        "icp6=${ICONSET_PATH}/icon_32x32@2x.png" \
        "ic07=${ICONSET_PATH}/icon_128x128.png" \
        "ic08=${ICONSET_PATH}/icon_256x256.png" \
        "ic09=${ICONSET_PATH}/icon_512x512.png" \
        "ic10=${ICONSET_PATH}/icon_512x512@2x.png" \
        "ic11=${ICONSET_PATH}/icon_16x16@2x.png" \
        "ic12=${ICONSET_PATH}/icon_32x32@2x.png" \
        "ic13=${ICONSET_PATH}/icon_128x128@2x.png" \
        "ic14=${ICONSET_PATH}/icon_256x256@2x.png"

if [[ "${UNIVERSAL_BUILD}" == "1" ]]; then
    lipo -create \
        "${ARM64_BIN_PATH}/TraceHalo" \
        "${X86_64_BIN_PATH}/TraceHalo" \
        -output "${STAGED_APP_PATH}/Contents/MacOS/TraceHalo"
    lipo -create \
        "${ARM64_BIN_PATH}/TraceHaloSensorHelper" \
        "${X86_64_BIN_PATH}/TraceHaloSensorHelper" \
        -output "${STAGED_APP_PATH}/Contents/Resources/TraceHaloSensorHelper"
else
    cp "${BIN_PATH}/TraceHalo" "${STAGED_APP_PATH}/Contents/MacOS/TraceHalo"
    cp "${BIN_PATH}/TraceHaloSensorHelper" \
        "${STAGED_APP_PATH}/Contents/Resources/TraceHaloSensorHelper"
fi
if [[ -d "${APP_RESOURCE_BUNDLE_PATH}" ]]; then
    ditto "${APP_RESOURCE_BUNDLE_PATH}" \
        "${STAGED_APP_PATH}/Contents/Resources/TraceHalo_TraceHaloApp.bundle"
fi
if [[ ! -d "${CORE_RESOURCE_BUNDLE_PATH}" ]]; then
    print -u2 "Missing TraceHaloCore localization bundle: ${CORE_RESOURCE_BUNDLE_PATH}"
    exit 1
fi
ditto "${CORE_RESOURCE_BUNDLE_PATH}" \
    "${STAGED_APP_PATH}/Contents/Resources/TraceHalo_TraceHaloCore.bundle"
for localization in en zh-Hans; do
    resource_localization="${localization}"
    if [[ "${localization}" == "zh-Hans" ]]; then
        resource_localization="zh-hans"
    fi
    localization_source="${APP_RESOURCE_BUNDLE_PATH}/${resource_localization}.lproj"
    if [[ ! -d "${localization_source}" ]]; then
        print -u2 "Missing required localization resources: ${localization_source}"
        exit 1
    fi
    ditto "${localization_source}" \
        "${STAGED_APP_PATH}/Contents/Resources/${localization}.lproj"
done
cp "${PACKAGE_DIR}/Resources/${SENSOR_HELPER_PLIST_NAME}" \
    "${STAGED_APP_PATH}/Contents/Library/LaunchDaemons/${SENSOR_HELPER_PLIST_NAME}"
cp "${PACKAGE_DIR}/Resources/Info.plist" "${STAGED_APP_PATH}/Contents/Info.plist"
chmod 755 "${STAGED_APP_PATH}/Contents/Resources/TraceHaloSensorHelper"
plutil -lint \
    "${STAGED_APP_PATH}/Contents/Library/LaunchDaemons/${SENSOR_HELPER_PLIST_NAME}" \
    >/dev/null

if [[ "${SIGNING_IDENTITY}" == "-" ]]; then
    codesign --force \
        --sign - \
        --timestamp=none \
        --identifier com.tseai.tracehalo.sensor-helper \
        "${STAGED_APP_PATH}/Contents/Resources/TraceHaloSensorHelper"
    codesign --force --sign - --timestamp=none "${STAGED_APP_PATH}"
else
    codesign --force \
        --sign "${SIGNING_IDENTITY}" \
        --options runtime \
        --timestamp \
        --identifier com.tseai.tracehalo.sensor-helper \
        "${STAGED_APP_PATH}/Contents/Resources/TraceHaloSensorHelper"
    codesign --force \
        --sign "${SIGNING_IDENTITY}" \
        --options runtime \
        --timestamp \
        "${STAGED_APP_PATH}"
fi

codesign --verify --deep --strict --verbose=2 "${STAGED_APP_PATH}"

# The app bundle is assembled in a unique staging directory so a rebuild can
# never inherit obsolete resources from an older package. Only the generated
# artifact at the explicit output path is replaced.
if [[ -e "${APP_PATH}" ]]; then
    case "${APP_PATH}" in
        "${PACKAGE_DIR}"/.build/*.app) rm -rf "${APP_PATH}" ;;
        *)
            print -u2 "Refusing to replace app outside ${PACKAGE_DIR}/.build: ${APP_PATH}"
            exit 1
            ;;
    esac
fi
ditto "${STAGED_APP_PATH}" "${APP_PATH}"

print "Built ${APP_PATH}"
