#!/bin/bash
#
# Builds a self-contained qemu-img from the sources pinned in versions.env.
#
#   Usage: build-qemu-img.sh <output-binary> [arch ...]
#
# GLib, proxy-libintl and zstd are linked statically and only macOS system
# libraries stay dynamic (macOS has no static libc), so the binary needs nothing
# else in the app bundle.
#
# Every step writes a stamp when it has finished and is trusted only if stamped,
# so an interrupted build redoes the unfinished step instead of reusing it.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSIONS_FILE="$SCRIPT_DIR/versions.env"

log()  { echo "note: [qemu-img] $*"; }
die()  { echo "error: [qemu-img] $*" >&2; exit 1; }

[ -f "$VERSIONS_FILE" ] || die "missing $VERSIONS_FILE"
# shellcheck source=versions.env
. "$VERSIONS_FILE"

OUT="${1:-}"
[ -n "$OUT" ] || die "usage: $(basename "$0") <output-binary> [arch ...]"
shift

ARCHS=("$@")
if [ ${#ARCHS[@]} -eq 0 ]; then ARCHS=("$(uname -m)"); fi
IFS=$'\n' read -r -d '' -a ARCHS < <(printf '%s\n' "${ARCHS[@]}" | sort -u && printf '\0')

for a in "${ARCHS[@]}"; do
    case "$a" in
        arm64|x86_64) ;;
        *) die "unsupported architecture '$a' (expected arm64 or x86_64)" ;;
    esac
done

# Outside DerivedData so Clean Build Folder does not force a rebuild, and outside
# the project because its path contains spaces, which autotools and libtool
# cannot handle.
BUILD_ROOT="${QEMU_IMG_BUILD_ROOT:-$HOME/Library/Caches/ch.jo-tools.disk-snapshot-tool/qemu-img}"
DL_DIR="$BUILD_ROOT/downloads"

case "$BUILD_ROOT" in
    *[[:space:]]*)
        die "build root contains whitespace, which breaks autotools/libtool:
       $BUILD_ROOT
       Set QEMU_IMG_BUILD_ROOT to a path without spaces."
        ;;
esac

# The architecture list is deliberately not part of the key: sources, tools and
# each per-architecture build are shared, so switching between a single-arch
# Debug build and a universal archive does not rebuild everything.
#
# Whole-line comments and blank lines are left out, so editing a comment does
# not force a rebuild. Neither file has a heredoc line starting with '#'; one
# that did would be invisible to the key.
KEY="$(sed -E '/^[[:space:]]*(#|$)/d' "$VERSIONS_FILE" "${BASH_SOURCE[0]}" \
        | shasum -a 256 | cut -c1-16)"
ARCH_TAG="$(IFS=-; printf '%s' "${ARCHS[*]}")"

PREFIX="$BUILD_ROOT/$KEY"
STAMPS="$PREFIX/stamps"
FINAL="$PREFIX/qemu-img-$ARCH_TAG"
TOOLS="$PREFIX/tools"
SRC_DIR="$PREFIX/src"
LOG_DIR="$PREFIX/logs"

NCPU="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

is_done()   { [ -f "$STAMPS/$1" ]; }
mark_done() { touch "$STAMPS/$1"; }

emit() {
    mkdir -p "$(dirname "$OUT")"
    if [ ! -f "$OUT" ] || ! cmp -s "$FINAL" "$OUT"; then
        cp -f "$FINAL" "$OUT.partial"
        chmod +x "$OUT.partial"
        mv -f "$OUT.partial" "$OUT"
    fi
}

if is_done "final-$ARCH_TAG" && [ -x "$FINAL" ]; then
    emit
    log "up to date (${ARCHS[*]}, cache $KEY)"
    exit 0
fi

log "building qemu-img $QEMU_VERSION for ${ARCHS[*]} from source (a minute or two)"
log "cache: $PREFIX"

mkdir -p "$DL_DIR" "$STAMPS" "$TOOLS/bin" "$SRC_DIR" "$LOG_DIR"

die_log() {
    local name="$1"; shift
    echo "error: [qemu-img] $*" >&2
    echo "error: [qemu-img] last 30 lines of $LOG_DIR/$name.log:" >&2
    tail -30 "$LOG_DIR/$name.log" >&2 2>/dev/null || true
    exit 1
}

fetch() {
    local file="$1" url="$2" want="$3" path="$DL_DIR/$1" got
    if [ -f "$path" ]; then
        got="$(shasum -a 256 "$path" | cut -d' ' -f1)"
        [ "$got" = "$want" ] && return 0
        log "cached $file has wrong checksum, re-downloading"
        rm -f "$path"
    fi
    log "downloading $file"
    curl -fL --retry 3 --connect-timeout 30 -o "$path.partial" "$url" \
        || die "download failed: $url"
    got="$(shasum -a 256 "$path.partial" | cut -d' ' -f1)"
    if [ "$got" != "$want" ]; then
        rm -f "$path.partial"
        die "checksum mismatch for $file
       expected: $want
       actual:   $got
       Refusing to build. Verify the pinned value in versions.env."
    fi
    mv "$path.partial" "$path"
}

# Unpacked beside the target and renamed into place, so a source directory
# either is complete or does not exist.
extract() {
    local tarball="$1" dir="$2" tmp
    [ -d "$SRC_DIR/$dir" ] && return 0
    log "extracting $tarball"
    tmp="$(mktemp -d "$SRC_DIR/.extract.XXXXXX")"
    tar -xf "$DL_DIR/$tarball" -C "$tmp" || die "could not extract $tarball"
    [ -d "$tmp/$dir" ] || die "expected $dir after extracting $tarball"
    mv "$tmp/$dir" "$SRC_DIR/$dir"
    rm -rf "$tmp"
}

# Builds that write into their source tree get a fresh copy, so the extracted
# source stays pristine and a retry never starts from a half-built tree.
fresh_copy() { rm -rf "$2"; cp -R "$1" "$2"; }

rm -rf "$SRC_DIR"/.extract.*

QEMU_TAR="qemu-${QEMU_VERSION}.tar.xz";        QEMU_SRC="$SRC_DIR/qemu-${QEMU_VERSION}"
GLIB_TAR="glib-${GLIB_VERSION}.tar.xz";        GLIB_SRC="$SRC_DIR/glib-${GLIB_VERSION}"
ZSTD_TAR="zstd-${ZSTD_VERSION}.tar.gz";        ZSTD_SRC="$SRC_DIR/zstd-${ZSTD_VERSION}"
PKGCONF_TAR="pkgconf-${PKGCONF_VERSION}.tar.xz"; PKGCONF_SRC="$SRC_DIR/pkgconf-${PKGCONF_VERSION}"
NINJA_TAR="ninja-${NINJA_VERSION}.tar.gz";     NINJA_SRC="$SRC_DIR/ninja-${NINJA_VERSION}"
TOMLI_WHL="tomli-${TOMLI_VERSION}-py3-none-any.whl"

fetch "$QEMU_TAR"    "$QEMU_URL"    "$QEMU_SHA256"
fetch "$GLIB_TAR"    "$GLIB_URL"    "$GLIB_SHA256"
fetch "$ZSTD_TAR"    "$ZSTD_URL"    "$ZSTD_SHA256"
fetch "$PKGCONF_TAR" "$PKGCONF_URL" "$PKGCONF_SHA256"
fetch "$NINJA_TAR"   "$NINJA_URL"   "$NINJA_SHA256"
fetch "$TOMLI_WHL"   "$TOMLI_URL"   "$TOMLI_SHA256"

extract "$QEMU_TAR"    "qemu-${QEMU_VERSION}"
extract "$GLIB_TAR"    "glib-${GLIB_VERSION}"
extract "$ZSTD_TAR"    "zstd-${ZSTD_VERSION}"
extract "$PKGCONF_TAR" "pkgconf-${PKGCONF_VERSION}"
extract "$NINJA_TAR"   "ninja-${NINJA_VERSION}"

# Build tools, host architecture only; none of them ships.
export PATH="$TOOLS/bin:$PATH"

# Bootstrapped from source so every input stays checksum-pinned, rather than
# pulling an unpinned wheel from PyPI.
if ! is_done ninja; then
    log "bootstrapping ninja $NINJA_VERSION"
    fresh_copy "$NINJA_SRC" "$TOOLS/ninja-src"
    ( cd "$TOOLS/ninja-src" && /usr/bin/python3 configure.py --bootstrap ) \
        >"$LOG_DIR/ninja.log" 2>&1 || die_log ninja "ninja bootstrap failed"
    cp "$TOOLS/ninja-src/ninja" "$TOOLS/bin/ninja"
    mark_done ninja
fi

if ! is_done pkgconf; then
    log "building pkgconf $PKGCONF_VERSION"
    fresh_copy "$PKGCONF_SRC" "$TOOLS/pkgconf-src"
    ( cd "$TOOLS/pkgconf-src" \
        && ./configure --prefix="$TOOLS" --disable-shared --enable-static \
        && make -j"$NCPU" \
        && make install ) \
        >"$LOG_DIR/pkgconf.log" 2>&1 || die_log pkgconf "pkgconf build failed"
    ln -sf pkgconf "$TOOLS/bin/pkg-config"
    mark_done pkgconf
fi

# QEMU vendors a pinned meson wheel, so meson's version follows QEMU_VERSION.
if ! is_done meson; then
    log "installing meson from QEMU's vendored wheel"
    MESON_WHEELS=("$QEMU_SRC"/python/wheels/meson-*.whl)
    [ -f "${MESON_WHEELS[0]}" ] || die "no meson wheel in $QEMU_SRC/python/wheels"
    rm -rf "$TOOLS/venv"
    /usr/bin/python3 -m venv "$TOOLS/venv" >/dev/null || die "venv creation failed"
    "$TOOLS/venv/bin/python3" -m pip install --quiet --no-index \
        "${MESON_WHEELS[0]}" "$DL_DIR/$TOMLI_WHL" \
        || die "meson install failed"
    ln -sf "$TOOLS/venv/bin/meson" "$TOOLS/bin/meson"
    mark_done meson
fi

# GLib's .pc files put its real dependencies in Libs.private, which pkg-config
# reports only in --static mode. Meson cannot ask for that per dependency, and
# QEMU's -Dprefer_static=true appends a bare '-static' that Apple's linker
# rejects. Folding Libs.private into Libs is correct because these libraries are
# only ever linked statically.
flatten_pc() {
    local dir="$1"
    [ -d "$dir" ] || return 0
    /usr/bin/python3 - "$dir" <<'PY'
import pathlib, sys, re
for pc in pathlib.Path(sys.argv[1]).glob("*.pc"):
    lines, libs, priv = pc.read_text().splitlines(), None, None
    for i, ln in enumerate(lines):
        if re.match(r"^Libs:", ln):             libs = i
        elif re.match(r"^Libs\.private:", ln):  priv = i
    if libs is None or priv is None:
        continue
    extra = lines[priv].split(":", 1)[1].strip()
    if not extra:
        continue
    lines[libs] = lines[libs].rstrip() + " " + extra
    lines[priv] = "Libs.private:"
    pc.write_text("\n".join(lines) + "\n")
PY
}

# meson's cc.has_function() declares the symbol itself instead of using the SDK
# header, which discards the availability attribute: it answers YES for an API
# the deployment target does not have, and that API is NULL at runtime. No flag
# can correct the probe, so its answer is corrected before anything compiles
# against it.
#
# Each entry is a config.h define whose function the current SDK introduced
# after QEMU_IMG_MACOS_MIN. Extend the list when a new SDK adds another.
scrub_too_new_defines() {
    local config="$1"
    local d
    [ -f "$config" ] || return 0
    for d in HAVE_PIPE2; do
        if grep -q "^#define $d " "$config"; then
            log "  dropping $d (SDK declares it; unavailable at macOS $QEMU_IMG_MACOS_MIN)"
            sed -i '' "/^#define $d /d" "$config"
        fi
    done
}

build_arch() {
    local arch="$1"
    local stage="$PREFIX/$arch/stage"
    local out="$PREFIX/$arch/qemu-img"

    if is_done "qemu-img-$arch"; then
        log "$arch: already built"
        return 0
    fi

    local host_arch; host_arch="$(uname -m)"
    local target="${arch}-apple-macos${QEMU_IMG_MACOS_MIN}"

    # An API the SDK declares but the deployment target predates is weak-imported
    # and resolves to NULL at runtime; calling it segfaults. These two flags turn
    # that into a compile error and, failing that, a link error.
    local cflags="-O2 -target $target -Werror=unguarded-availability-new"
    local ldflags="-target $target -Wl,-no_weak_imports"

    mkdir -p "$stage/lib/pkgconfig" "$stage/include"

    export PKG_CONFIG_LIBDIR="$stage/lib/pkgconfig"
    export PKG_CONFIG_PATH="$stage/lib/pkgconfig"

    if ! is_done "zstd-$arch"; then
        log "$arch: building zstd $ZSTD_VERSION"
        local zsrc="$PREFIX/$arch/zstd"
        fresh_copy "$ZSTD_SRC" "$zsrc"
        # Static targets only: zstd's dylib link line combines
        # -compatibility_version with -target, which clang rejects.
        make -C "$zsrc/lib" -j"$NCPU" \
            install-static install-includes install-pc \
            PREFIX="$stage" \
            CC="clang" \
            CFLAGS="$cflags" \
            LDFLAGS="$ldflags" \
            >"$LOG_DIR/zstd-$arch.log" 2>&1 || die_log "zstd-$arch" "$arch: zstd build failed"
        [ -f "$stage/lib/libzstd.a" ] || die "$arch: zstd did not install libzstd.a"
        mark_done "zstd-$arch"
    fi

    # pcre2, libffi and proxy-libintl come from GLib's own meson wraps, whose
    # hashes are pinned in the GLib tarball. Meson unpacks them into the source
    # tree, hence the fresh copy; the downloads themselves are kept in DL_DIR.
    # zlib is not forced to a wrap: the macOS SDK provides it.
    if ! is_done "glib-$arch"; then
        log "$arch: building glib $GLIB_VERSION (static)"
        local gsrc="$PREFIX/$arch/glib-src"
        local gbuild="$PREFIX/$arch/glib-build"
        fresh_copy "$GLIB_SRC" "$gsrc"
        rm -rf "$gbuild"

        local -a meson_extra=()
        if [ "$arch" != "$host_arch" ]; then
            local cross="$PREFIX/$arch/cross.ini"
            cat > "$cross" <<CROSS
[binaries]
c = ['clang', '-target', '$target']
cpp = ['clang++', '-target', '$target']
objc = ['clang', '-target', '$target']
objcpp = ['clang++', '-target', '$target']
ar = 'ar'
strip = 'strip'
pkg-config = '$TOOLS/bin/pkgconf'

[host_machine]
system = 'darwin'
subsystem = 'macos'
kernel = 'xnu'
cpu_family = '$arch'
cpu = '$arch'
endian = 'little'
CROSS
            meson_extra+=(--cross-file "$cross")
        fi

        MESON_PACKAGE_CACHE_DIR="$DL_DIR/glib-${GLIB_VERSION}-wraps" \
        CFLAGS="$cflags" LDFLAGS="$ldflags" \
        meson setup "$gbuild" "$gsrc" \
            --prefix="$stage" \
            --buildtype=release \
            --default-library=static \
            --force-fallback-for=libffi,pcre2,proxy-libintl \
            -Dtests=false \
            -Dnls=disabled \
            -Dintrospection=disabled \
            -Dman-pages=disabled \
            -Ddocumentation=false \
            -Dlibmount=disabled \
            -Dselinux=disabled \
            -Ddtrace=disabled \
            -Dsystemtap=disabled \
            -Dsysprof=disabled \
            -Dlibelf=disabled \
            ${meson_extra[@]+"${meson_extra[@]}"} \
            >"$LOG_DIR/glib-$arch-setup.log" 2>&1 \
            || die_log "glib-$arch-setup" "$arch: glib meson setup failed"

        scrub_too_new_defines "$gbuild/config.h"

        meson compile -C "$gbuild" >"$LOG_DIR/glib-$arch-build.log" 2>&1 \
            || die_log "glib-$arch-build" "$arch: glib build failed"
        meson install -C "$gbuild" --quiet >"$LOG_DIR/glib-$arch-install.log" 2>&1 \
            || die_log "glib-$arch-install" "$arch: glib install failed"
        flatten_pc "$stage/lib/pkgconfig"
        mark_done "glib-$arch"
    fi

    log "$arch: configuring qemu $QEMU_VERSION"
    local qbuild="$PREFIX/$arch/qemu-build"
    rm -rf "$qbuild"; mkdir -p "$qbuild"

    local -a qemu_cross=()
    if [ "$arch" != "$host_arch" ]; then
        qemu_cross+=(--cross-prefix="")
    fi

    # --without-default-features keeps the network block drivers, the LUKS
    # crypto backends and all display code out: a smaller binary and a smaller
    # license surface. The local image formats are enabled again so the app can
    # identify them; without their drivers qemu-img reports every unrecognised
    # file as raw. They are in-tree C with no library dependencies.
    ( cd "$qbuild" && "$QEMU_SRC/configure" \
        --prefix="$stage" \
        --python="$TOOLS/venv/bin/python3" \
        --cpu="$arch" \
        --cc="clang" \
        --host-cc="clang" \
        --extra-cflags="$cflags" \
        --extra-ldflags="$ldflags" \
        --without-default-features \
        --enable-vmdk \
        --enable-vdi \
        --enable-vhdx \
        --enable-vpc \
        --enable-qed \
        --enable-parallels \
        --disable-system \
        --disable-user \
        --enable-tools \
        --enable-zstd \
        --disable-docs \
        --disable-guest-agent \
        --disable-install-blobs \
        --disable-debug-info \
        --disable-pixman \
        ${qemu_cross[@]+"${qemu_cross[@]}"} ) \
        >"$LOG_DIR/qemu-$arch-configure.log" 2>&1 \
        || die_log "qemu-$arch-configure" "$arch: qemu configure failed"

    log "$arch: building qemu-img"
    ninja -C "$qbuild" qemu-img >"$LOG_DIR/qemu-$arch-build.log" 2>&1 \
        || die_log "qemu-$arch-build" "$arch: qemu-img build failed"

    [ -x "$qbuild/qemu-img" ] || die "$arch: qemu-img was not produced"
    cp "$qbuild/qemu-img" "$out"
    strip -S "$out" 2>/dev/null || true
    mark_done "qemu-img-$arch"
}

for arch in "${ARCHS[@]}"; do
    build_arch "$arch"
done

rm -f "$STAMPS/final-$ARCH_TAG"
SLICES=()
for arch in "${ARCHS[@]}"; do SLICES+=("$PREFIX/$arch/qemu-img"); done

if [ ${#SLICES[@]} -eq 1 ]; then
    cp "${SLICES[0]}" "$FINAL"
else
    log "creating universal binary (${ARCHS[*]})"
    lipo -create -output "$FINAL" "${SLICES[@]}" || die "lipo failed"
fi
chmod +x "$FINAL"

if otool -l "$FINAL" | grep -q LC_RPATH; then
    otool -l "$FINAL" | grep -A2 LC_RPATH >&2
    die "qemu-img has LC_RPATH entries; it is not self-contained"
fi
# Only indented lines are dependencies; for a universal binary otool -L also
# prints an unindented "(architecture ...)" header per slice.
BAD="$(otool -L "$FINAL" | grep -E '^[[:space:]]' \
        | grep -vE '^[[:space:]]+(/usr/lib/|/System/Library/)' || true)"
if [ -n "$BAD" ]; then
    echo "$BAD" >&2
    die "qemu-img links non-system libraries; it is not self-contained"
fi

mark_done "final-$ARCH_TAG"
emit
log "built $(basename "$FINAL") ($(lipo -archs "$FINAL" 2>/dev/null || echo "$(uname -m)"))"
