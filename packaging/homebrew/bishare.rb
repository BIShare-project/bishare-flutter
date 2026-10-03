cask "bishare" do
  version "2.5.9"
  sha256 "2983a4d3402d82af3a2bfdd20ac85aa03c8ca67659f53da4d1e00eaf9c7daf8e" # filled by packaging/bump.sh

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
