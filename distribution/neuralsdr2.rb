cask "neuralsdr2" do
  version "1.0.0"
  sha256 "CHECKSUM_HERE"

  url "https://github.com/USER/NeuralSDR2/releases/download/v#{version}/NeuralSDR2-v#{version}.dmg"
  name "NeuralSDR2"
  desc "Professional Software Defined Radio application for macOS"
  homepage "https://github.com/USER/NeuralSDR2"

  depends_on macos: ">= :ventura"
  depends_on cask: "librtlsdr"

  app "NeuralSDR2.app"

  caveats <<~EOS
    NeuralSDR2 requires an RTL-SDR compatible USB dongle to receive signals.
    Install librtlsdr for RTL-SDR driver support:
      brew install librtlsdr

    If macOS blocks the app on first launch, right-click and select "Open",
    or run: xattr -cr /Applications/NeuralSDR2.app
  EOS

  zap trash: [
    "~/Library/Application Support/NeuralSDR2",
    "~/Library/Preferences/com.neuralsdr2.app.plist",
    "~/Library/Caches/com.neuralsdr2.app",
  ]
end
