#!/usr/bin/env bash
#
# Build Wine-CrossOver from CodeWeavers FOSS source on macOS (Apple Silicon)
#
# On arm64 Macs with corporate EDR (Trend Micro), wine MUST be built as x86_64
# and run under Rosetta 2. Native arm64 wine is blocked because EDR kills any
# arm64 binary with a non-standard __PAGEZERO segment.
# See docs/arm64-edr-findings.md for full technical details.
#
# Source: https://www.codeweavers.com/crossover/source
#
# Usage:
#   ./build-wine-crossover.sh           # full build (download + compile + install)
#   ./build-wine-crossover.sh download  # just download & extract sources
#   ./build-wine-crossover.sh deps      # just install Homebrew dependencies
#   ./build-wine-crossover.sh build     # just build (sources must already exist)
#   ./build-wine-crossover.sh install   # just install (must already be built)
#
set -euo pipefail

###############################################################################
# Configuration — adjust these as needed
###############################################################################
CX_VERSION="26.1.0"
WORK_DIR="${WORK_DIR:-$HOME/crossover-build}"
INSTALL_PREFIX="${INSTALL_PREFIX:-$HOME/.local/opt/wine-crossover}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"
HOST_ARCH="$(uname -m)"  # arm64 or x86_64

# On Apple Silicon, cross-compile as x86_64 to bypass EDR restrictions.
# Rosetta 2 translates x86_64 → arm64 at runtime (~70-80% native performance).
if [[ "$HOST_ARCH" == "arm64" ]]; then
    BUILD_ARCH="x86_64"
else
    BUILD_ARCH="x86_64"
fi

###############################################################################
# Colours
###############################################################################
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

###############################################################################
# Step 0 — Install build dependencies
###############################################################################

# x86_64 libraries are built from source into this prefix
DEPS_PREFIX="${DEPS_PREFIX:-$HOME/.local/opt/x86_64-deps}"

# Dependency versions
FREETYPE_VERSION="2.13.3"
GNUTLS_VERSION="3.8.8"
SDL2_VERSION="2.30.10"
NETTLE_VERSION="3.10.1"
GMP_VERSION="6.3.0"

build_dep() {
    local name="$1" url="$2"
    shift 2
    local configure_args=("$@")

    info "  Building $name..."
    local archive="$WORK_DIR/deps-src/$(basename "$url")"
    local src_dir="$WORK_DIR/deps-src/$name"

    mkdir -p "$WORK_DIR/deps-src"

    if [[ ! -f "$archive" ]]; then
        curl -fSL "$url" -o "$archive"
    fi

    rm -rf "$src_dir"
    mkdir -p "$src_dir"
    tar xf "$archive" -C "$src_dir" --strip-components=1

    cd "$src_dir"
    # No arch -x86_64 needed: --host and CC="cc -arch x86_64" handle cross-compilation.
    # Build tools (make, etc.) run natively on arm64.
    # Unset PKG_CONFIG_PATH to avoid finding arm64 Homebrew libraries.
    PKG_CONFIG_PATH="${DEPS_PREFIX}/lib/pkgconfig" \
        ./configure --prefix="$DEPS_PREFIX" "${configure_args[@]}"
    make -j"$JOBS"
    make install
    cd "$WORK_DIR"
}

install_deps() {
    info "Installing build dependencies..."

    # arm64 Homebrew tools (build tools run natively, only LIBRARIES need x86_64)
    local brew_tools=(
        bison flex pkg-config gettext mingw-w64 llvm
    )
    for dep in "${brew_tools[@]}"; do
        if brew list "$dep" &>/dev/null; then
            info "  ✓ $dep (native tool)"
        else
            info "  → installing $dep"
            brew install "$dep"
        fi
    done

    # Build x86_64 libraries from source into $DEPS_PREFIX
    mkdir -p "$DEPS_PREFIX"

    if [[ -f "$DEPS_PREFIX/lib/libfreetype.dylib" ]]; then
        info "  ✓ freetype (x86_64, cached)"
    else
        build_dep freetype \
            "https://download.savannah.gnu.org/releases/freetype/freetype-${FREETYPE_VERSION}.tar.xz" \
            --host=x86_64-apple-darwin \
            CC="cc -arch x86_64" \
            --with-zlib=yes --without-bzip2 --without-png --without-harfbuzz --without-brotli
    fi

    if [[ -f "$DEPS_PREFIX/lib/libgmp.dylib" ]]; then
        info "  ✓ gmp (x86_64, cached)"
    else
        build_dep gmp \
            "https://ftp.gnu.org/gnu/gmp/gmp-${GMP_VERSION}.tar.xz" \
            --host=x86_64-apple-darwin \
            CC="cc -arch x86_64" CXX="c++ -arch x86_64"
    fi

    if [[ -f "$DEPS_PREFIX/lib/libnettle.dylib" ]]; then
        info "  ✓ nettle (x86_64, cached)"
    else
        build_dep nettle \
            "https://ftp.gnu.org/gnu/nettle/nettle-${NETTLE_VERSION}.tar.gz" \
            --host=x86_64-apple-darwin \
            CC="cc -arch x86_64" \
            LDFLAGS="-L$DEPS_PREFIX/lib" \
            CPPFLAGS="-I$DEPS_PREFIX/include"
    fi

    if [[ -f "$DEPS_PREFIX/lib/libgnutls.dylib" ]]; then
        info "  ✓ gnutls (x86_64, cached)"
    else
        build_dep gnutls \
            "https://www.gnupg.org/ftp/gcrypt/gnutls/v${GNUTLS_VERSION%.*}/gnutls-${GNUTLS_VERSION}.tar.xz" \
            --host=x86_64-apple-darwin \
            CC="cc -arch x86_64" CXX="c++ -arch x86_64" \
            --with-included-libtasn1 --with-included-unistring \
            --without-p11-kit --without-idn --without-zlib --without-brotli --without-zstd \
            --disable-cxx --disable-tools --disable-tests --disable-doc \
            LDFLAGS="-L$DEPS_PREFIX/lib" \
            CPPFLAGS="-I$DEPS_PREFIX/include"
    fi

    if [[ -f "$DEPS_PREFIX/lib/libSDL2.dylib" ]]; then
        info "  ✓ sdl2 (x86_64, cached)"
    else
        build_dep sdl2 \
            "https://github.com/libsdl-org/SDL/releases/download/release-${SDL2_VERSION}/SDL2-${SDL2_VERSION}.tar.gz" \
            --host=x86_64-apple-darwin \
            CC="cc -arch x86_64" CXX="c++ -arch x86_64"
    fi

    info ""
    info "x86_64 dependencies installed to: $DEPS_PREFIX"
    info "Dependencies ready."
}

###############################################################################
# Step 1 — Download & extract CrossOver FOSS source
###############################################################################
download_source() {
    mkdir -p "$WORK_DIR"

    if [[ -d "$WORK_DIR/sources/wine" ]]; then
        info "Sources already extracted at $WORK_DIR/sources/wine — skipping download."
        return
    fi

    info "Cloning CrossOver ${CX_VERSION} FOSS source from mirror..."
    git clone --depth 1 --branch "v${CX_VERSION}" \
        "git@ghpriv:rnowak/wine-crossover-sources.git" \
        "$WORK_DIR/sources"
    info "Source cloned to $WORK_DIR/sources/"

    # Patch: D3DMetal support is gated behind #if defined(__x86_64__) but
    # cocoa_window.m and event handling reference these symbols unconditionally.
    # Provide arm64 stubs via #else branches.
    local winemac="$WORK_DIR/sources/wine/dlls/winemac.drv"
    if [[ -f "$winemac/d3dmetal_objc.h" ]] && grep -q '#if defined(__x86_64__)' "$winemac/d3dmetal_objc.h"; then
        info "Patching D3DMetal files: adding arm64 stubs..."

        # Header — remove arch guard so declaration is visible everywhere
        /usr/bin/sed -i '' 's/^#if defined(__x86_64__)$//' "$winemac/d3dmetal_objc.h"
        /usr/bin/sed -i '' '/^#endif$/d' "$winemac/d3dmetal_objc.h"

        # d3dmetal_objc.m — add stub @implementation for arm64
        /usr/bin/sed -i '' '$ s/^#endif$//' "$winemac/d3dmetal_objc.m"
        cat >> "$winemac/d3dmetal_objc.m" << 'EOF'
#else

#import <QuartzCore/QuartzCore.h>
#import "d3dmetal_objc.h"

@implementation WineMetalLayer
@end

#endif
EOF

        # d3dmetal.c — add stub macdrv_client_surface_presented for arm64
        /usr/bin/sed -i '' '$ s/^#endif$//' "$winemac/d3dmetal.c"
        cat >> "$winemac/d3dmetal.c" << 'EOF'
#else

#include "macdrv_cocoa.h"
void macdrv_client_surface_presented(const macdrv_event *event) { }

#endif
EOF
    fi
}

###############################################################################
# Step 2 — Build MoltenVK (Vulkan→Metal, needed for DXVK/Vulkan games)
###############################################################################
build_moltenvk() {
    # MoltenVK from Homebrew (arm64) provides universal headers and the ICD.
    # At runtime, macOS loads the correct arch slice automatically.
    if brew list molten-vk &>/dev/null; then
        info "Using Homebrew MoltenVK (molten-vk)."
        export MOLTENVK_PREFIX="$(brew --prefix molten-vk)"
        return
    fi

    info "Building MoltenVK from included source..."
    local mvk_dir="$WORK_DIR/sources/moltenvk"
    cd "$mvk_dir"

    ./fetchDependencies --macos
    make macos -j"$JOBS"

    export MOLTENVK_PREFIX="$mvk_dir/Package/Latest/MoltenVK"
    info "MoltenVK built."
}

###############################################################################
# Step 3 — Build Wine (the main event)
###############################################################################
build_wine() {
    local wine_src="$WORK_DIR/sources/wine"
    local build_dir="$WORK_DIR/build-wine"

    [[ -d "$wine_src" ]] || error "Wine source not found at $wine_src. Run download first."

    mkdir -p "$build_dir"
    cd "$build_dir"

    # ── Environment setup ──────────────────────────────────────────────
    # Native arm64 Homebrew provides build tools (bison, flex, llvm, mingw)
    export PATH="$(brew --prefix bison)/bin:$(brew --prefix flex)/bin:$(brew --prefix llvm)/bin:$PATH"

    # Point pkg-config at our x86_64 libraries
    export PKG_CONFIG_PATH="$DEPS_PREFIX/lib/pkgconfig"

    export CFLAGS="-O2 -g -I$DEPS_PREFIX/include"
    export CXXFLAGS="$CFLAGS"
    export LDFLAGS="-L$DEPS_PREFIX/lib"

    # Define SONAME_LIBVULKAN even without Vulkan — CrossOver code references it
    # unconditionally. At runtime, dlopen will just fail gracefully.
    export CFLAGS="$CFLAGS -DSONAME_LIBVULKAN='\"libvulkan.1.dylib\"'"

    # MinGW cross-compiler for PE DLLs
    export CROSSCC="x86_64-w64-mingw32-gcc"

    # ── Configure ──────────────────────────────────────────────────────
    info "Configuring Wine (CrossOver ${CX_VERSION})..."
    info "  Build arch   : $BUILD_ARCH (via Rosetta 2)"
    info "  Host arch    : $HOST_ARCH"
    info "  Deps prefix  : $DEPS_PREFIX"
    info "  Install to   : $INSTALL_PREFIX"
    info "  Build jobs   : $JOBS"

    local configure_args=(
        --prefix="$INSTALL_PREFIX"
        --build=x86_64-apple-darwin
        --host=x86_64-apple-darwin
        --without-wayland        # not on macOS
        --without-vulkan         # MoltenVK is arm64-only from Homebrew; add later if needed
        --enable-archs=i386,x86_64  # WoW64: both 32-bit and 64-bit PE DLLs
    )

    # Pass --build/--host to override config.guess (which ignores arch -x86_64).
    # CC/CXX with -arch x86_64 ensures compiler always produces x86_64 output.
    arch -x86_64 "$wine_src/configure" "${configure_args[@]}" \
        CC="cc -arch x86_64" CXX="c++ -arch x86_64" \
        2>&1 | tee "$WORK_DIR/configure.log"

    # ── Post-configure fixups ─────────────────────────────────────────
    # CrossOver's dlls/win32u/vulkan.c uses SONAME_LIBVULKAN without an #ifdef
    # guard, but --without-vulkan leaves it #undef'd in config.h. Patch it.
    local config_h="$build_dir/include/config.h"
    if grep -q '/\* #undef SONAME_LIBVULKAN \*/' "$config_h"; then
        perl -pi -e 's{/\* #undef SONAME_LIBVULKAN \*/}{#define SONAME_LIBVULKAN "libvulkan.1.dylib"}' "$config_h"
        info "Patched config.h: defined SONAME_LIBVULKAN (CrossOver workaround)"
    fi

    # ── Build ──────────────────────────────────────────────────────────
    info "Building Wine with $JOBS parallel jobs..."
    make -j"$JOBS" 2>&1 | tee "$WORK_DIR/build.log"

    info "Wine built successfully."
}

###############################################################################
# Step 4 — Install
###############################################################################
install_wine() {
    local build_dir="$WORK_DIR/build-wine"
    [[ -d "$build_dir" ]] || error "Build directory not found. Run build first."

    cd "$build_dir"
    info "Installing to $INSTALL_PREFIX ..."
    make install

    local bindir="$INSTALL_PREFIX/bin"

    # ── Runtime library discovery ─────────────────────────────────────
    # Wine's .so modules use dlopen() for libraries like libfreetype.6.dylib.
    # They have @loader_path/ in LC_RPATH, so placing libs (or symlinks) in
    # the x86_64-unix directory lets dlopen find them reliably.
    # (DYLD_LIBRARY_PATH doesn't survive wine's internal process spawning.)
    local unix_dir="$INSTALL_PREFIX/lib/wine/x86_64-unix"
    local deplib_dst="$INSTALL_PREFIX/lib/x86_64-deps"
    mkdir -p "$deplib_dst"
    cp -a "$DEPS_PREFIX"/lib/lib*.dylib "$deplib_dst/" 2>/dev/null || true

    # Symlink each dep library into the unix module directory
    for lib in "$deplib_dst"/lib*.dylib; do
        [[ -f "$lib" ]] || continue
        local libname
        libname="$(basename "$lib")"
        ln -sf "$lib" "$unix_dir/$libname"
    done
    info "  Linked x86_64 dep libraries into $unix_dir"

    # Create convenience wrapper scripts for Windows tools if missing
    for tool in wineboot winecfg msiexec regedit; do
        if [[ ! -f "$bindir/$tool" ]]; then
            printf '#!/bin/sh\nexec "$(dirname "$0")/wine" %s.exe "$@"\n' "$tool" > "$bindir/$tool"
            chmod +x "$bindir/$tool"
            info "  Created wrapper: $tool"
        fi
    done

    # Ensure wine64 exists
    if [[ ! -f "$bindir/wine64" ]]; then
        ln -s wine "$bindir/wine64"
        info "  Created symlink: wine64 -> wine"
    fi

    info ""
    info "============================================================"
    info "Wine-CrossOver ${CX_VERSION} installed to: $INSTALL_PREFIX"
    info ""
    info "Add to your PATH:"
    info "  export PATH=\"$INSTALL_PREFIX/bin:\$PATH\""
    info ""
    info "Quick test:"
    info "  $INSTALL_PREFIX/bin/wine --version"
    info "  $INSTALL_PREFIX/bin/wine notepad"
    info "============================================================"
}

###############################################################################
# Main
###############################################################################
main() {
    local cmd="${1:-all}"

    case "$cmd" in
        deps)
            install_deps
            ;;
        download)
            download_source
            ;;
        build)
            build_moltenvk
            build_wine
            ;;
        install)
            install_wine
            ;;
        all)
            install_deps
            download_source
            build_moltenvk
            build_wine
            install_wine
            ;;
        *)
            echo "Usage: $0 {deps|download|build|install|all}"
            exit 1
            ;;
    esac
}

main "$@"
