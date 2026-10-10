cask "bishare" do
  version "2.6.1"
  sha256 "7b3481a78143500358f8611cb10f18e049b79a7d088074decd9898c27dccb2e6" # filled by packaging/bump.sh

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
