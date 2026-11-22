cask "ghosted" do
  version "0.1.0"
  sha256 "cdb0430f1c9ccb7cd7fc03b4e33023139ca094cd0f350bb5cfebc37d24dd0e04"

  url "https://github.com/Igor-bite/ghosted/releases/download/v#{version}/Ghosted-#{version}.zip"
  name "Ghosted"
  desc "Virtual camera that lets you vanish into dust on video calls"
  homepage "https://github.com/Igor-bite/ghosted"

  depends_on macos: :ventura

  app "Ghosted.app"

  zap trash: [
    "~/Library/Application Support/Vanish",
    "~/Library/Group Containers/4D7YJ8BY8H.com.vanishcam.Vanish",
    "~/Library/Preferences/com.vanishcam.Vanish.plist",
  ]

  caveats <<~EOS
    On first launch Ghosted installs the "Ghosted Camera" system extension.
    Approve it in System Settings → General → Login Items & Extensions → Camera Extensions
    (macOS 13–14: Privacy & Security → Allow).
  EOS
end
