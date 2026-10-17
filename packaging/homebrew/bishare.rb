cask "bishare" do
  version "2.6.3"
  sha256 "849dcb983bf25bbc57714bfa97a36b84bee5de1990e45faa923cdf62dce12ce3" # filled by packaging/bump.sh

  url "https://github.com/BIShare-project/bishare-flutter/releases/download/v#{version}/BIShare-#{version}-macos.dmg"
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
