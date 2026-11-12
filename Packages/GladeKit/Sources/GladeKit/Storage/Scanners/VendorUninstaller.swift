import Foundation

/// Finds an app’s own uninstaller. Some apps (Adobe’s above all) spread parts across
/// the system that only their uninstaller removes, so Glade opens that instead of
/// moving the app to the Trash. Judged from names only; nothing is opened or read.
enum VendorUninstaller {
  /// Where Adobe keeps the uninstallers for each of its apps.
  static let adobeInstallers = "/Applications/Utilities/Adobe Installers"
  /// Creative Cloud removes any Adobe app it installed.
  static let creativeCloud = "/Applications/Utilities/Adobe Creative Cloud/ACC/Creative Cloud.app"
  static let creativeCloudUninstaller = "/Applications/Utilities/Adobe Creative Cloud/Utils/Creative Cloud Uninstaller.app"

  struct Found: Sendable, Equatable {
    /// What to open, or `nil` when the vendor’s uninstaller couldn’t be found.
    var path: String?
    /// Who makes it, for the sentence explaining why Glade doesn’t remove the app.
    var vendor: String?
  }

  /// Whether a name is an uninstaller’s: "Uninstall Resolve.app", "Acrobat Uninstaller".
  static func isUninstallerName(_ name: String) -> Bool {
    name.localizedCaseInsensitiveContains("uninstall")
  }

  /// The uninstaller for an app, if it has one.
  /// - Parameters:
  ///   - bundle: The app’s real location.
  ///   - listedIn: The folder the app was found in (a vendor folder may list it
  ///     through a link, as Creative Cloud’s does).
  ///   - applicationFolders: `/Applications` and `~/Applications`.
  static func find(
    bundle: String, name: String, bundleID: String, listedIn: String, applicationFolders: [String]
  ) -> Found? {
    let isAdobe = bundleID.lowercased().hasPrefix("com.adobe.")
    let fileName = ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
    let names = Set([name, fileName].map { $0.lowercased() })

    // In the vendor’s folder beside the app: "Adobe Photoshop 2025/Uninstall Adobe
    // Photoshop 2025", "DaVinci Resolve/Uninstall Resolve.app". Only in a folder of
    // the vendor’s own, never loose in Applications or Utilities, where it could be
    // anyone’s.
    let loose = applicationFolders + applicationFolders.map { $0 + "/Utilities" }
    var folders = [listedIn]
    let realParent = (bundle as NSString).deletingLastPathComponent
    if realParent != listedIn { folders.append(realParent) }
    for folder in folders where !loose.contains(folder) {
      let items = DiskWalk.children(of: folder).filter { isUninstallerName(($0 as NSString).lastPathComponent) }
      if let best = preferred(items, names: names) { return Found(path: best, vendor: isAdobe ? "Adobe" : nil) }
    }

    // Loose in Applications, the name must say whose it is.
    for folder in loose {
      for item in DiskWalk.children(of: folder) {
        let base = ((item as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
        guard isUninstallerName(base) else { continue }
        let rest = base.replacingOccurrences(of: "uninstaller", with: "").replacingOccurrences(of: "uninstall", with: "")
          .trimmingCharacters(in: .whitespaces)
        if names.contains(rest) { return Found(path: item, vendor: nil) }
      }
    }

    // Inside the app itself.
    for folder in ["Contents/Resources", "Contents/SharedSupport", "Contents/Helpers"] {
      let items = DiskWalk.children(of: "\(bundle)/\(folder)").filter {
        $0.hasSuffix(".app") && isUninstallerName(($0 as NSString).lastPathComponent)
      }
      if let first = items.sorted().first { return Found(path: first, vendor: isAdobe ? "Adobe" : nil) }
    }

    // Adobe’s apps always need Adobe’s own tools: its per-app uninstaller, or Creative
    // Cloud, which removes anything it installed.
    guard isAdobe else { return nil }
    let perApp = DiskWalk.children(of: adobeInstallers).filter {
      let base = ($0 as NSString).lastPathComponent.lowercased()
      return isUninstallerName(base) && names.contains { base.hasSuffix($0) }
    }
    if let best = preferred(perApp, names: names) { return Found(path: best, vendor: "Adobe") }
    let isCreativeCloud = bundleID.lowercased().hasPrefix("com.adobe.acc")
    let fallback = isCreativeCloud ? creativeCloudUninstaller : creativeCloud
    return Found(path: FileManager.default.fileExists(atPath: fallback) ? fallback : nil, vendor: "Adobe")
  }

  /// The item whose name mentions the app, else the first by name.
  private static func preferred(_ items: [String], names: Set<String>) -> String? {
    let sorted = items.filter { !($0 as NSString).lastPathComponent.hasPrefix(".") }.sorted()
    return sorted.first { item in
      let base = (item as NSString).lastPathComponent.lowercased()
      return names.contains { base.contains($0) }
    } ?? sorted.first
  }

  /// The sentence shown where the tick box would be.
  static func reason(_ found: Found, appName: String) -> String {
    if found.path == nil, let vendor = found.vendor {
      return "\(vendor) apps must be removed with \(vendor)’s own uninstaller, which removes parts Glade can’t reach."
    }
    return "\(appName) comes with its own uninstaller, which removes parts Glade can’t reach."
  }
}
