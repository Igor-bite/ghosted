cask "ghosted" do
  version "0.2.0"
  sha256 "831951268fbed18473778b408c117a16b1240bda69c6ec54401d8557d8c0079a"

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
