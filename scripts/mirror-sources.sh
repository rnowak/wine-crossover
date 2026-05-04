#!/usr/bin/env bash
#
# Mirror CrossOver FOSS source to GitHub
#
# Downloads the CodeWeavers FOSS tarball, extracts it, and pushes to
# rnowak/wine-crossover-sources with a version tag.
#
# Usage:
#   ./scripts/mirror-sources.sh              # mirror current version (26.1.0)
#   ./scripts/mirror-sources.sh 26.2.0       # mirror a specific version
#
# Prerequisites:
#   - SSH access to git@ghpriv:rnowak/wine-crossover-sources
#
set -euo pipefail

VERSION="${1:-26.1.0}"
REPO_URL="git@ghpriv:rnowak/wine-crossover-sources.git"
SOURCE_URL="https://media.codeweavers.com/pub/crossover/source/crossover-sources-${VERSION}.tar.gz"
WORK_DIR="$(mktemp -d)"

trap 'rm -rf "$WORK_DIR"' EXIT

info()  { echo -e "\033[0;32m[INFO]\033[0m  $*"; }
error() { echo -e "\033[0;31m[ERROR]\033[0m $*"; exit 1; }

###############################################################################
# Clone the existing repo
###############################################################################
info "Cloning ${REPO_URL}..."
git clone "$REPO_URL" "$WORK_DIR/repo"
cd "$WORK_DIR/repo"

# Check if tag already exists
if git tag -l "v${VERSION}" | grep -q "v${VERSION}"; then
    error "Tag v${VERSION} already exists. Nothing to do."
fi

###############################################################################
# Download and extract source
###############################################################################
info "Downloading CrossOver ${VERSION} FOSS source..."
curl -L "$SOURCE_URL" -o "$WORK_DIR/source.tar.gz"

info "Extracting..."
tar xzf "$WORK_DIR/source.tar.gz" -C "$WORK_DIR"

SOURCE_DIR="$WORK_DIR/sources"
[[ -d "$SOURCE_DIR/wine" ]] || error "Expected sources/wine directory not found after extraction"

###############################################################################
# Replace repo contents with new version and push
###############################################################################
info "Replacing repo contents with v${VERSION}..."

# Remove old content (keep .git)
find . -maxdepth 1 ! -name '.git' ! -name '.' -exec rm -rf {} +

# Copy new source in
cp -a "$SOURCE_DIR"/. .

info "Adding files (this may take a moment for large source trees)..."
git add -A
git commit -q -m "CrossOver FOSS source ${VERSION}

Downloaded from: ${SOURCE_URL}
License: LGPL/GPL (CodeWeavers FOSS release)"

info "Tagging as v${VERSION}..."
git tag "v${VERSION}"

info "Pushing..."
git push origin main --tags

info ""
info "============================================================"
info "Done! Source mirrored with tag: v${VERSION}"
info "============================================================"
