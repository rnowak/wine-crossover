# wine-crossover

Build and distribute [Wine-CrossOver](https://www.codeweavers.com/crossover/source) for macOS from CodeWeavers' open source release.

This replaces the now-removed `Gcenx/winecx` prebuilt binaries with a fully automated CI build.

## Install via Homebrew

```bash
brew tap rnowak/wine-crossover https://github.com/rnowak/wine-crossover
brew install --cask wine-crossover
```

## What this is

CodeWeavers publishes the FOSS portions of CrossOver under GPL/LGPL. This includes their patched Wine with macOS-specific improvements. The GitHub Actions workflow in this repo:

1. Downloads the official FOSS source tarball from CodeWeavers
2. Compiles Wine on a macOS Apple Silicon runner
3. Packages and publishes it as a GitHub release
4. The Homebrew cask points to those releases

## Build locally

```bash
# Full build (installs deps, downloads source, compiles, installs)
./build-wine-crossover.sh

# Or step-by-step
./build-wine-crossover.sh deps      # install Homebrew dependencies
./build-wine-crossover.sh download  # download & extract source
./build-wine-crossover.sh build     # compile
./build-wine-crossover.sh install   # install to ~/.local/wine-crossover
```

## Triggering a CI build

Go to **Actions → Build Wine-CrossOver → Run workflow** and specify the CrossOver source version (e.g. `26.1.0`).

After the build completes, update the cask SHA256:
1. Copy the SHA256 from the release job summary
2. Update `Casks/wine-crossover.rb` with the new version and sha256

## License

Wine is licensed under the LGPL. See the [CodeWeavers source page](https://www.codeweavers.com/crossover/source) for details on included components and their licenses.
