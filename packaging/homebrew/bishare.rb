cask "bishare" do
  version "2.5.1"
  sha256 "d1886d25fdc6277e55cae55024bd8d0be7c68f1eb8642c0c3509e242a6b88e1c" # filled by packaging/bump.sh

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
