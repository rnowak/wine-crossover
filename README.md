# wine-crossover

Build [Wine-CrossOver](https://www.codeweavers.com/crossover/source) for macOS from CodeWeavers' open source release.

Uses a git mirror of the sources: [rnowak/wine-crossover-sources](https://github.com/rnowak/wine-crossover-sources).

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

## License

Wine is licensed under the LGPL. See the [CodeWeavers source page](https://www.codeweavers.com/crossover/source) for details on included components and their licenses.
