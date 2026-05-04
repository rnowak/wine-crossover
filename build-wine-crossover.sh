#!/usr/bin/env bash
#
# Build Wine-CrossOver from CodeWeavers FOSS source on macOS (Apple Silicon)
#
# Source: https://www.codeweavers.com/crossover/source
# This replaces the now-deleted Gcenx/winecx prebuilt binaries.
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
SOURCE_URL="https://media.codeweavers.com/pub/crossover/source/crossover-sources-${CX_VERSION}.tar.gz"
WORK_DIR="${WORK_DIR:-$HOME/crossover-build}"
INSTALL_PREFIX="${INSTALL_PREFIX:-$(brew --prefix 2>/dev/null || echo /usr/local)/opt/wine-crossover}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"
ARCH="$(uname -m)"  # arm64 or x86_64

###############################################################################
# Colours
###############################################################################
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

###############################################################################
# Step 0 — Install build dependencies via Homebrew
###############################################################################
install_deps() {
    info "Installing build dependencies via Homebrew..."

    local deps=(
        # Core build tools
        bison               # parser generator (macOS ships outdated version)
        flex                # lexer generator
        pkg-config          # library discovery
        gettext             # i18n support
        # Cross-compiler for PE/Windows DLLs
        mingw-w64
        # Clang/LLVM (for macOS native code)
        llvm
        # Libraries Wine needs
        freetype            # font rendering
        gnutls              # TLS/SSL (schannel)
        sdl2                # gamepad/joystick support
        gstreamer           # multimedia codecs
        gst-plugins-base    # base GStreamer plugins
        molten-vk           # Vulkan → Metal translation layer
    )

    for dep in "${deps[@]}"; do
        if brew list "$dep" &>/dev/null; then
            info "  ✓ $dep already installed"
        else
            info "  → installing $dep"
            brew install "$dep"
        fi
    done

    info "Dependencies installed."
}

###############################################################################
# Step 1 — Download & extract CrossOver FOSS source
###############################################################################
download_source() {
    mkdir -p "$WORK_DIR"
    local tarball="$WORK_DIR/crossover-sources-${CX_VERSION}.tar.gz"

    if [[ -d "$WORK_DIR/sources/wine" ]]; then
        info "Sources already extracted at $WORK_DIR/sources/wine — skipping download."
        return
    fi

    if [[ ! -f "$tarball" ]]; then
        info "Downloading CrossOver ${CX_VERSION} FOSS source..."
        curl -L -o "$tarball" "$SOURCE_URL"
    fi

    info "Extracting..."
    tar xzf "$tarball" -C "$WORK_DIR"
    info "Source extracted to $WORK_DIR/sources/"

    # Patch: D3DMetal support is gated behind #if defined(__x86_64__) but
    # cocoa_window.m and event handling reference these symbols unconditionally.
    # Provide arm64 stubs via #else branches.
    local winemac="$WORK_DIR/sources/wine/dlls/winemac.drv"
    if [[ -f "$winemac/d3dmetal_objc.h" ]] && grep -q '#if defined(__x86_64__)' "$winemac/d3dmetal_objc.h"; then
        info "Patching D3DMetal files: adding arm64 stubs..."

        # Header — remove arch guard so declaration is visible everywhere
        sed -i '' 's/^#if defined(__x86_64__)$//' "$winemac/d3dmetal_objc.h"
        sed -i '' '/^#endif$/d' "$winemac/d3dmetal_objc.h"

        # d3dmetal_objc.m — add stub @implementation for arm64
        sed -i '' '$ s/^#endif$//' "$winemac/d3dmetal_objc.m"
        cat >> "$winemac/d3dmetal_objc.m" << 'EOF'
#else

#import <QuartzCore/QuartzCore.h>
#import "d3dmetal_objc.h"

@implementation WineMetalLayer
@end

#endif
EOF

        # d3dmetal.c — add stub macdrv_client_surface_presented for arm64
        sed -i '' '$ s/^#endif$//' "$winemac/d3dmetal.c"
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
    # If molten-vk is installed via Homebrew, we can skip building from source.
    if brew list molten-vk &>/dev/null; then
        info "Using Homebrew MoltenVK (molten-vk)."
        export MOLTENVK_PREFIX="$(brew --prefix molten-vk)"
        return
    fi

    info "Building MoltenVK from included source..."
    local mvk_dir="$WORK_DIR/sources/moltenvk"
    cd "$mvk_dir"

    # MoltenVK has its own dependency fetcher
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
    # Use Homebrew's newer bison (macOS ships an ancient one)
    export PATH="$(brew --prefix bison)/bin:$(brew --prefix flex)/bin:$(brew --prefix llvm)/bin:$PATH"

    # Help configure find Homebrew libraries
    export PKG_CONFIG_PATH="$(brew --prefix freetype)/lib/pkgconfig:$(brew --prefix gnutls)/lib/pkgconfig:$(brew --prefix sdl2)/lib/pkgconfig:$(brew --prefix gstreamer)/lib/pkgconfig:$(brew --prefix gst-plugins-base)/lib/pkgconfig:$(brew --prefix molten-vk)/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

    export CFLAGS="-O2 -g -I$(brew --prefix molten-vk)/include"
    export CXXFLAGS="$CFLAGS"
    export LDFLAGS="${LDFLAGS:-} -L$(brew --prefix molten-vk)/lib"

    # MinGW cross-compiler for PE DLLs
    export CROSSCC="x86_64-w64-mingw32-gcc"

    # MoltenVK / Vulkan headers
    if [[ -n "${MOLTENVK_PREFIX:-}" ]]; then
        export CFLAGS="$CFLAGS -I${MOLTENVK_PREFIX}/include"
        export LDFLAGS="${LDFLAGS:-} -L${MOLTENVK_PREFIX}/lib"
    fi

    # ── Configure ──────────────────────────────────────────────────────
    info "Configuring Wine (CrossOver ${CX_VERSION})..."
    info "  Architecture : $ARCH"
    info "  Install to   : $INSTALL_PREFIX"
    info "  Build jobs   : $JOBS"

    local configure_args=(
        --prefix="$INSTALL_PREFIX"
        --without-wayland        # not on macOS
    )

    # On Apple Silicon, build native aarch64 + cross-compiled x86_64
    # (this is Wine's "new WoW64" mode for running 32/64-bit Windows apps)
    if [[ "$ARCH" == "arm64" ]]; then
        configure_args+=(
            --enable-archs=x86_64,i386
        )
    fi

    "$wine_src/configure" "${configure_args[@]}" 2>&1 | tee "$WORK_DIR/configure.log"

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
