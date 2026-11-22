cask "ghosted" do
  version "0.2.1"
  sha256 "739b357dd7cb60fac1b97c900aee124385ed49adf880faf9794171a85b1c127b"

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
