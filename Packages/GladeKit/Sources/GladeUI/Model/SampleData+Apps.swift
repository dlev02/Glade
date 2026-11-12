import Foundation
import GladeKit

/// Made-up installed apps for screenshots: well-known ones, so their icons draw where
/// they’re installed and nothing of the person’s own shows.
extension SampleData {
  static func sampleApps() -> [Finding] {
    let home = NSHomeDirectory()
    let day: TimeInterval = 86_400
    func app(
      _ name: String, _ bundleID: String, path: String, version: String, _ gigabytes: Double, daysAgo: Double?,
      source: AppSource, data: [(String, String, Double)] = [], kept: [(String, String, String)] = [],
      uninstaller: String? = nil, blocker: Blocker? = nil
    ) -> Finding {
      let parts = data.map { AppDetails.Part(path: "\(home)/Library/\($0.0)", label: $0.1, bytes: Int64($0.2 * 1e9)) }
      let opened = daysAgo.map { Date().addingTimeInterval(-$0 * day) }
      let details = AppDetails(
        bundleID: bundleID, name: name, version: version, source: source, bundlePath: path,
        bundleBytes: Int64(gigabytes * 1e9), parts: parts,
        kept: kept.map { AppDetails.Kept(path: "\(home)/Library/\($0.0)", label: $0.1, reason: $0.2) },
        lastOpened: opened, uninstaller: uninstaller, needsAdministrator: blocker?.kind == .needsAdmin
      )
      var blockers: [Blocker] = []
      if uninstaller != nil {
        blockers.append(Blocker(.ownUninstaller, "\(name) comes with its own uninstaller, which removes parts Glade can’t reach."))
      }
      if let blocker { blockers.append(blocker) }
      var finding = Finding(
        id: Finding.makeID(rule: "sample.app", path: path), ruleID: InstalledAppScanner.ruleID, category: .installedApps,
        title: name,
        detail: uninstaller != nil
          ? "This app comes with its own uninstaller. Use it, then scan again to clear anything it leaves behind."
          : "The app and the settings, caches and data it keeps in your home folder. They go to the Trash, so you can put them back.",
        paths: [path] + parts.map(\.path), bytes: details.bundleBytes + details.dataBytes, lastUsed: opened,
        recovery: .reinstall, risk: .personal, owner: Owner(name, bundleIDs: [bundleID]), blockers: blockers,
        method: .uninstallApp(bundleID: bundleID),
        evidence: [
          "Version \(version), from \(source == .other ? "a download" : source.title).",
          opened.map { "Last opened \(Format.age($0)), as Spotlight recorded it." } ?? "macOS hasn’t recorded when it was last opened.",
        ],
        autoLevel: nil, needsOwnerClosed: true
      )
      finding.app = details
      return finding
    }
    return [
      app(
        "Final Cut Pro", "com.apple.FinalCut", path: "/Applications/Final Cut Pro.app", version: "11.0.1", 5.98, daysAgo: 420,
        source: .appStore,
        data: [("Containers/com.apple.FinalCut", "Containers", 2.4), ("Application Support/Final Cut Pro", "Application Support", 0.3), ("Caches/com.apple.FinalCut", "Caches", 0.6)],
        kept: [("Group Containers/group.com.apple.ProApps", "Group Containers", "Logic Pro uses it too.")]
      ),
      app(
        "iMovie", "com.apple.iMovieApp", path: "/Applications/iMovie.app", version: "10.4.5", 3.98, daysAgo: 240,
        source: .appStore, data: [("Containers/com.apple.iMovieApp", "Containers", 1.2)]
      ),
      app(
        "Adobe Photoshop 2025", "com.adobe.Photoshop", path: "/Applications/Adobe Photoshop 2025/Adobe Photoshop 2025.app",
        version: "26.10.0", 6.12, daysAgo: 44, source: .other,
        uninstaller: "/Applications/Adobe Photoshop 2025/Uninstall Adobe Photoshop 2025"
      ),
      app(
        "Android Studio", "com.google.android.studio", path: "/Applications/Android Studio Preview.app", version: "2026.2", 3.45, daysAgo: 64,
        source: .other, data: [("Application Support/Google/AndroidStudio2026.2", "Application Support", 1.9), ("Caches/Google/AndroidStudio2026.2", "Caches", 2.8), ("Logs/Google/AndroidStudio2026.2", "Logs", 0.1)]
      ),
      app(
        "Minecraft", "com.mojang.minecraftlauncher", path: "/Applications/Minecraft.app", version: "1.2.5", 0.34, daysAgo: 330,
        source: .homebrew, data: [("Application Support/minecraft", "Application Support", 2.9)]
      ),
      app(
        "Blender", "org.blenderfoundation.blender", path: "/Applications/Blender.app", version: "5.2.2", 0.95, daysAgo: 36,
        source: .other, data: [("Application Support/Blender", "Application Support", 0.2)]
      ),
      app(
        "Xcode", "com.apple.dt.Xcode", path: "/Applications/Xcode.app", version: "27.2", 4.23, daysAgo: 1, source: .appStore,
        blocker: Blocker(.needsAdmin, "macOS asks for your password to remove this app, so move it to the Trash in Finder.")
      ),
      app(
        "Docker", "com.docker.docker", path: "/Applications/Docker.app", version: "4.52", 2.1, daysAgo: 0, source: .homebrew,
        data: [("Containers/com.docker.docker", "Containers", 11.5)], blocker: Blocker(.appRunning, "Docker is open. Quit it first.")
      ),
    ]
  }
}
