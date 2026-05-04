cask "wine-crossover" do
  version "26.1.0"
  sha256 "f13be33a0574a902db5776de49912ba15ac0e349b072ac1ec48b7842c7c47c9c"

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
  ]

  preflight do
    # Wine's make install doesn't always create convenience wrappers for
    # Windows tools. Create any missing ones before Homebrew symlinks them.
    bindir = "#{staged_path}/wine-crossover/bin"
    { "wine64" => :symlink, "wineboot" => :script, "winecfg" => :script,
      "msiexec" => :script, "regedit" => :script }.each do |tool, type|
      path = "#{bindir}/#{tool}"
      next if File.exist?(path)

      if type == :symlink
        File.symlink("wine", path)
      else
        File.write(path, "#!/bin/sh\nexec \"$(dirname \"$0\")/wine\" #{tool}.exe \"$@\"\n")
        File.chmod(0755, path)
      end
    end
  end

  binary "#{staged_path}/wine-crossover/bin/wine"
  binary "#{staged_path}/wine-crossover/bin/wine64"
  binary "#{staged_path}/wine-crossover/bin/wineserver"
  binary "#{staged_path}/wine-crossover/bin/wineboot"
  binary "#{staged_path}/wine-crossover/bin/winecfg"
  binary "#{staged_path}/wine-crossover/bin/msiexec"
  binary "#{staged_path}/wine-crossover/bin/regedit"

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

    On first run, macOS Gatekeeper will block wine. Go to:
      System Settings → Privacy & Security → "Allow Anyway"
    then retry. You may need to repeat this for wineserver.

    For optional features, install:
      brew install gstreamer   # multimedia (WMA/WMV/MP3)
      brew install molten-vk   # Vulkan (DXVK games)
      brew install sdl2        # gamepad/joystick support

    To enable noflicker set the following registry key in your prefix:
    [HKCU\\Software\\Wine\\Mac Driver]
    "ForceOpenGLBackingStore"="y"
  EOS
  caveats do
    requires_rosetta
  end
end
