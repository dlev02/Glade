import Foundation

/// Whose a data folder in the home folder is, for the whole-disk view: the installed app
/// it evidently belongs to, or that none does. Judged from names and the identifiers
/// apps declare, as `AppData` matches them; nothing is opened.
public enum FolderOwner {
  /// A sentence for a folder directly inside one of the places apps keep data
  /// (`~/Library/Application Support/Dreamtime`), or `nil` for any other path.
  public static func describe(_ rawPath: String, home rawHome: String = NSHomeDirectory(), apps: InstalledApps) -> String? {
    let path = Protection.clean(rawPath), home = Protection.clean(rawHome)
    let parent = (path as NSString).deletingLastPathComponent
    guard let location = AppData.locations.first(where: { parent == "\(home)/\($0.folder)" }) else { return nil }
    let name = (path as NSString).lastPathComponent
    // Apps named after their developer ("Adobe Photoshop") first, so they’re the ones named.
    let thirdParty = apps.apps.filter { !$0.path.hasPrefix("/System/") && !$0.bundleID.lowercased().hasPrefix("com.apple.") }
      .sorted { first, second in
        func named(_ app: InstalledApp) -> Bool {
          guard let maker = InstalledApps.vendor(of: app.bundleID)?.split(separator: ".").last else { return false }
          return InstalledApps.compact(app.name).hasPrefix(String(maker))
        }
        return named(first) && !named(second)
      }
    if let app = owner(name: name, in: location.folder, apps: apps.apps) { return "Used by \(app.name)" }
    let id = AppData.identifier(fromFolder: name, in: location.folder).id
    if let id {
      // macOS’s own components, and SDKs many apps share, belong to no one app.
      if id.hasPrefix("com.apple.") || id.hasPrefix("group.com.apple.") { return "Part of macOS" }
      if AppLeftoverScanner.isNeverReported(id) { return "Shared by several apps" }
      if let vendor = InstalledApps.vendor(of: id),
         let sibling = thirdParty.first(where: { InstalledApps.vendor(of: $0.bundleID) == vendor }) {
        return "From the maker of \(sibling.name)"
      }
      if apps.claim(on: id) != nil { return "Something still installed may use this" }
      return "No installed app uses this"
    }
    // A plain name: the developer’s ("Adobe"), or close to an app’s ("Claude-3p").
    let compact = InstalledApps.compact(name)
    if compact.count >= 4,
       let app = thirdParty.first(where: { InstalledApps.vendor(of: $0.bundleID)?.split(separator: ".").last.map(String.init) == compact }) {
      return "From the maker of \(app.name)"
    }
    if compact.count >= 5, let app = thirdParty.first(where: { app in
      let theirs = InstalledApps.compact(app.name)
      return theirs.count >= 5 && (theirs.hasPrefix(compact) || compact.hasPrefix(theirs))
    }) {
      return "Probably \(app.name)’s"
    }
    if apps.tools.contains(name.lowercased()) || apps.tools.contains(compact) { return "Something still installed may use this" }
    return "No installed app uses this"
  }

  /// The installed app a folder is named after, by identifier or by name.
  static func owner(name: String, in folder: String, apps: [InstalledApp]) -> InstalledApp? {
    let id = AppData.identifier(fromFolder: name, in: folder).id
    let lowered = name.lowercased()
    // Apps in the usual places first, so a copy in Downloads doesn’t take the credit.
    for app in apps.sorted(by: { $0.isStandardLocation && !$1.isStandardLocation }) {
      let main = app.bundleID.lowercased()
      if let id {
        let own = Set(app.identifiers.map(AppData.normalised))
        if own.contains(id) || id.hasPrefix(main + ".") { return app }
      }
      let file = ((app.path as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
      if AppData.namedLocations.contains(folder), [app.name.lowercased(), file].contains(lowered) { return app }
    }
    return nil
  }
}
