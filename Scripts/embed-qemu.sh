#!/bin/bash
#
# Xcode Run Script build phase: builds qemu-img (build-qemu-img.sh) and installs
# it at Contents/Helpers/qemu-img, signed so it can run inside the app's sandbox.
#
# Needs ENABLE_USER_SCRIPT_SANDBOXING = NO: the first build downloads the pinned
# sources, and the build cache lives outside the build directory.

set -euo pipefail

log() { echo "note: [embed-qemu] $*"; }
die() { echo "error: [embed-qemu] $*" >&2; exit 1; }

: "${SRCROOT:?must be run from an Xcode build phase}"
: "${BUILT_PRODUCTS_DIR:?must be run from an Xcode build phase}"
: "${CONTENTS_FOLDER_PATH:?must be run from an Xcode build phase}"

HELPERS_DIR="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/Helpers"
HELPER="${HELPERS_DIR}/qemu-img"
ENTITLEMENTS="${SRCROOT}/Disk Snapshot Tool/Configuration/qemu-img-helper.entitlements"

[ -f "$ENTITLEMENTS" ] || die "missing entitlements file: $ENTITLEMENTS"

mkdir -p "$HELPERS_DIR"

# With ONLY_ACTIVE_ARCH=YES (Debug) Xcode passes one slice, so day-to-day builds
# never pay for the architecture they are not using.
read -r -a ARCH_LIST <<< "${ARCHS:-$(uname -m)}"

# Xcode exports hundreds of build settings, and make, meson and configure read
# the environment: zstd's Makefile takes BUILD_DIR as its object directory, which
# in an archive is a path with spaces. The helper is built from a clean
# environment so its result does not depend on how Xcode was invoked.
BUILD_ENV=(
    "HOME=$HOME"
    "PATH=/usr/bin:/bin:/usr/sbin:/sbin"
    "TMPDIR=${TMPDIR:-/tmp}"
    "LANG=en_US.UTF-8"
)
[ -z "${DEVELOPER_DIR:-}" ]        || BUILD_ENV+=("DEVELOPER_DIR=$DEVELOPER_DIR")
[ -z "${QEMU_IMG_BUILD_ROOT:-}" ]  || BUILD_ENV+=("QEMU_IMG_BUILD_ROOT=$QEMU_IMG_BUILD_ROOT")

env -i "${BUILD_ENV[@]}" "${SRCROOT}/Scripts/build-qemu-img.sh" "$HELPER" "${ARCH_LIST[@]}" \
    || die "failed to build qemu-img"

[ -x "$HELPER" ] || die "qemu-img was not installed at $HELPER"

# Signed here rather than by Xcode because the entitlements must be exactly
# app-sandbox + inherit. Xcode injects get-task-allow into Debug builds, and any
# third entitlement breaks sandbox inheritance — the helper is then killed at
# launch. No --deep: it would sign nested code with the wrong entitlements.
if [ "${CODE_SIGNING_ALLOWED:-YES}" = "NO" ]; then
    log "code signing disabled for this build; leaving qemu-img unsigned"
    exit 0
fi

IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-}"
[ -n "$IDENTITY" ] || IDENTITY="-"

# Notarization needs a secure timestamp, which costs a round trip to Apple on
# every build; local Debug builds skip it.
if [ "${CONFIGURATION:-}" = "Debug" ]; then
    TIMESTAMP_ARG="--timestamp=none"
else
    TIMESTAMP_ARG="--timestamp"
fi

codesign --force \
         --sign "$IDENTITY" \
         "$TIMESTAMP_ARG" \
         --options=runtime \
         --entitlements "$ENTITLEMENTS" \
         "$HELPER" \
    || die "failed to sign $HELPER"

ENTS="$(codesign -d --entitlements - "$HELPER" 2>&1 \
        | grep -oE 'com\.apple\.security\.[a-z.-]+' | sort -u || true)"
EXPECTED="com.apple.security.app-sandbox
com.apple.security.inherit"
if [ "$ENTS" != "$EXPECTED" ]; then
    rm -f "$HELPER"
    die "qemu-img must be signed with exactly app-sandbox + inherit, got:
$ENTS
A third entitlement breaks sandbox inheritance and the helper is killed at launch."
fi

log "qemu-img embedded and signed (${ARCH_LIST[*]})"
