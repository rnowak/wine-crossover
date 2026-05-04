cask "wine-crossover" do
  version "26.1.0"
  sha256 :no_check

  url "https://github.com/rnowak/wine-crossover/releases/download/crossover-#{version}/wine-crossover-#{version}-macos-arm64.tar.xz"
  name "Wine Crossover"
  desc "Compatibility layer to run Windows applications (built from CodeWeavers FOSS source)"
  homepage "https://github.com/rnowak/wine-crossover"

  livecheck do
    url :url
    strategy :github_latest
    regex(/crossover-(\d+(?:\.\d+)+)/i)
  end

  conflicts_with cask: [
    "game-porting-toolkit",
    "wine-stable",
    "wine@devel",
    "wine@staging",
  ]

  depends_on macos: ">= :ventura"
  depends_on formula: [
    "freetype",
    "gnutls",
    "gstreamer",
    "gst-plugins-base",
    "molten-vk",
    "sdl2",
  ]

  binary "#{staged_path}/wine-crossover/bin/msiexec"
  binary "#{staged_path}/wine-crossover/bin/notepad"
  binary "#{staged_path}/wine-crossover/bin/regedit"
  binary "#{staged_path}/wine-crossover/bin/regsvr32"
  binary "#{staged_path}/wine-crossover/bin/wine"
  binary "#{staged_path}/wine-crossover/bin/wine-preloader"
  binary "#{staged_path}/wine-crossover/bin/wine64"
  binary "#{staged_path}/wine-crossover/bin/wine64-preloader"
  binary "#{staged_path}/wine-crossover/bin/wineboot"
  binary "#{staged_path}/wine-crossover/bin/winecfg"
  binary "#{staged_path}/wine-crossover/bin/wineconsole"
  binary "#{staged_path}/wine-crossover/bin/winefile"
  binary "#{staged_path}/wine-crossover/bin/winemine"
  binary "#{staged_path}/wine-crossover/bin/winepath"
  binary "#{staged_path}/wine-crossover/bin/wineserver"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-drs", "com.apple.quarantine", "#{staged_path}/wine-crossover"],
                   sudo: false
    system_command "/usr/bin/codesign",
                   args: ["--force", "--deep", "-s", "-", "#{staged_path}/wine-crossover"],
                   sudo: false
  end

  zap trash: [
    "~/.local/share/applications/wine*",
    "~/.local/share/icons/hicolor/**/application-x-wine*",
    "~/.local/share/mime/application/x-wine*",
    "~/.local/share/mime/packages/x-wine*",
    "~/.wine",
  ]

  caveats <<~EOS
    #{token} supports running 32-bit & 64-bit Windows binaries.

    #{token} does not support creating a 32-bit wine prefix.

    To enable noflicker set the following registry key in your prefix:
    [HKCU\\Software\\Wine\\Mac Driver]
    "ForceOpenGLBackingStore"="y"
  EOS
  caveats do
    requires_rosetta
  end
end
