cask "bishare" do
  version "2.5.6"
  sha256 "1a35ab03eed8f4455581ce2a1883b070a0f31243b08fa4c5f2ee7fd4ebb6b47d" # filled by packaging/bump.sh

  url "https://github.com/BIShare-project/bishare-flutter/releases/download/v#{version}/BIShare-#{version}-macos.dmg",
      verified: "github.com/BIShare-project/bishare-flutter/"
  name "BIShare"
  desc "Fast, private, cross-platform file sharing"
  homepage "https://bishare.app/"

  livecheck do
    url :url
    strategy :github_latest
  end

  # The DMG is Developer ID signed and notarized (see release.yml, job macos).
  depends_on macos: :monterey

  app "BIShare.app"

  uninstall quit: "com.bishare.app"

  zap trash: [
    "~/Library/Application Support/com.bishare.app",
    "~/Library/Caches/com.bishare.app",
    "~/Library/Containers/com.bishare.app",
    "~/Library/Preferences/com.bishare.app.plist",
    "~/Library/Saved Application State/com.bishare.app.savedState",
  ]
end
