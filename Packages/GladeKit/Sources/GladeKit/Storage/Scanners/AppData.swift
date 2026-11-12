import Foundation

/// Works out which folders in the home folder belong to one installed app: those named
/// after one of its own identifiers (its own, its helpers', its app groups), or after
/// the app itself in the places apps write under their name. A folder stays when the
/// safety policy wouldn’t allow removing it or another installed app has a claim on it.
/// Names only; nothing is opened.
enum AppData {
  /// One folder that matched, before the safety checks.
  struct Match: Sendable, Hashable {
    var path: String
    var label: String
  }

  /// The places apps keep per-user data, as `AppLeftoverScanner` searches them.
  static var locations: [(folder: String, label: String)] { AppLeftoverScanner.locations }

  /// Places where apps also write under their plain name ("Application Support/Blender").
  static let namedLocations: Set<String> = ["Library/Application Support", "Library/Caches", "Library/Logs"]

  /// A listing of every data location, made once per scan and shared by every app.
  struct Listing: Sendable {
    /// Lowercased identifier → folders named after it.
    var byIdentifier: [String: [Match]] = [:]
    /// Lowercased plain name → folders with that name.
    var byName: [String: [Match]] = [:]
    /// The developer team prefix of group containers, by path.
    var teams: [String: String] = [:]
  }

  static func listing(home: String, protection: Protection) -> Listing {
    var listing = Listing()
    for (folder, label) in locations {
      let root = "\(home)/\(folder)"
      guard protection.canScan(root) else { continue }
      for path in DiskWalk.children(of: root) {
        guard protection.canScan(path) else { continue }
        let name = (path as NSString).lastPathComponent
        let match = Match(path: path, label: label)
        let parsed = identifier(fromFolder: name, in: folder)
        if let id = parsed.id {
          listing.byIdentifier[id, default: []].append(match)
          if let team = parsed.team { listing.teams[path] = team }
        }
        if namedLocations.contains(folder) {
          listing.byName[name.lowercased(), default: []].append(match)
        }
      }
    }
    return listing
  }

  /// The identifier a data folder is named after, lowercased, and the team prefix of a
  /// group container. Unlike `AppLeftoverScanner`, Apple’s identifiers count: this
  /// matches exact identifiers an installed app declares, it doesn’t guess at owners.
  static func identifier(fromFolder name: String, in folder: String) -> (id: String?, team: String?) {
    var base = name
    for suffix in [".savedState", ".binarycookies"] where base.hasSuffix(suffix) {
      base = String(base.dropLast(suffix.count))
    }
    var parts = base.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    var team: String?
    if folder.hasSuffix("Containers") {
      if let first = parts.first, AppLeftoverScanner.isTeamID(first), parts.count > 1 {
        team = first
        parts.removeFirst()
      }
      if parts.first?.lowercased() == "group", parts.count > 1 { parts.removeFirst() }
    }
    guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty }) else { return (nil, team) }
    return (parts.joined(separator: ".").lowercased(), team)
  }

  /// An identifier an app declares, in the form folders are named after: group
  /// identifiers lose their `group.` or team prefix. Declared identifiers are kept
  /// lowercased, so the team prefix is recognised in either case.
  static func normalised(_ declared: String) -> String {
    var parts = declared.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    // Team identifiers carry digits; a ten-letter word ("macromedia") is a vendor.
    if let first = parts.first, parts.count > 2, first.contains(where: \.isNumber), AppLeftoverScanner.isTeamID(first.uppercased()) {
      parts.removeFirst()
    }
    if parts.first?.lowercased() == "group", parts.count > 2 { parts.removeFirst() }
    return parts.joined(separator: ".").lowercased()
  }

  /// The folders that go with `app`, and those that look like its but stay.
  static func folders(
    for app: InstalledApp, among apps: [InstalledApp], listing: Listing, protection: Protection
  ) -> (goes: [Match], stays: [AppDetails.Kept]) {
    let own = Set(app.identifiers.map(normalised))
    let main = app.bundleID.lowercased()
    var matches: [Match] = []
    var seen = Set<String>()
    for (id, found) in listing.byIdentifier where own.contains(id) || id.hasPrefix(main + ".") {
      for match in found where seen.insert(match.path).inserted { matches.append(match) }
    }
    let fileName = ((app.path as NSString).lastPathComponent as NSString).deletingPathExtension
    for name in Set([app.name.lowercased(), fileName.lowercased()]) where name.count >= 3 {
      for match in listing.byName[name] ?? [] where seen.insert(match.path).inserted { matches.append(match) }
    }

    let others = apps.filter { $0.path != app.path && $0.bundleID.lowercased() != main }
    var goes: [Match] = []
    var stays: [AppDetails.Kept] = []
    for match in matches.sorted(by: { $0.path < $1.path }) {
      let verdict = protection.verdict(forRemoving: match.path)
      guard verdict.isAllowed else {
        stays.append(AppDetails.Kept(path: match.path, label: match.label, reason: verdict.explanation))
        continue
      }
      if let other = claimant(of: match, app: app, own: own, others: others, listing: listing) {
        stays.append(AppDetails.Kept(path: match.path, label: match.label, reason: "\(other) uses it too."))
        continue
      }
      goes.append(match)
    }
    return (goes, stays)
  }

  /// Another installed app with a claim on a folder: it declares the identifier (or one
  /// inside it), the folder is named after the other app, or it’s a group container
  /// shared by the same developer. A folder the app declares exactly isn’t another’s
  /// just because that one declares a wider identifier ("com.apple.iwork").
  static func claimant(of match: Match, app: InstalledApp, own: Set<String>, others: [InstalledApp], listing: Listing) -> String? {
    let name = (match.path as NSString).lastPathComponent
    let folder = locations.first { match.label == $0.label }?.folder ?? ""
    let id = identifier(fromFolder: name, in: folder).id
    let isGroup = match.label == "Group Containers"
    for other in others {
      let theirs = Set(other.identifiers.map(normalised))
      if let id {
        if theirs.contains(id) { return other.name }
        if theirs.contains(where: { $0.hasPrefix(id + ".") }) { return other.name }
        if !own.contains(id), theirs.contains(where: { id.hasPrefix($0 + ".") }) { return other.name }
      }
      let otherFile = ((other.path as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
      if [other.name.lowercased(), otherFile].contains(name.lowercased()) { return other.name }
      // A group container is shared by its developer’s apps, so while another of them
      // is installed it stays.
      if isGroup {
        if let team = listing.teams[match.path], other.teamID?.uppercased() == team.uppercased() { return other.name }
        if let team = app.teamID, other.teamID?.uppercased() == team.uppercased() { return other.name }
        if let id, let vendor = InstalledApps.vendor(of: id), let otherVendor = InstalledApps.vendor(of: other.bundleID), vendor == otherVendor {
          return other.name
        }
      }
    }
    return nil
  }
}
