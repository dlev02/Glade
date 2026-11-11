import Foundation

/// The answer to "may Glade remove this path?".
public enum Verdict: Sendable, Equatable {
  case allowed
  /// Inside (or is) a protected zone.
  case protected(zone: String, title: String)
  /// Not under the home folder or the user's temporary folders.
  case outOfScope
  /// A structural folder such as `~/Library` or `~/Downloads` itself.
  case structural
  /// A folder that is a version-control repository.
  case repository
  /// Has a protected zone somewhere beneath it.
  case containsProtected(zone: String, title: String)
  /// On a different disk, or the mount point of one.
  case otherVolume
  /// Reached through a symbolic link that leads somewhere else.
  case escapesViaLink

  public var isAllowed: Bool { self == .allowed }

  public var explanation: String {
    switch self {
    case .allowed: "Allowed"
    case .protected(_, let title): "Protected: \(title)"
    case .outOfScope: "Outside your home folder"
    case .structural: "A system folder that other things depend on"
    case .repository: "A version-control repository"
    case .containsProtected(_, let title): "Contains protected items (\(title))"
    case .otherVolume: "On another disk"
    case .escapesViaLink: "A link that leads outside the allowed area"
    }
  }
}

/// The safety policy. Scanners ask it what they may look at, and the cleaner asks it
/// again, independently, before removing anything. It works on paths only and never
/// reads file contents.
public struct Protection: Sendable {
  public let home: String
  public let zones: [ProtectedZone]
  /// Roots under which removal is possible at all.
  public let scopes: [String]
  private let prefixRules: [PrefixRule]
  private let nameRules: [NameRule]
  private let userPaths: [String]

  private struct PrefixRule: Sendable {
    var components: [String]
    var zone: Int
    var hasGlob: Bool
  }

  private struct NameRule: Sendable {
    var pattern: String
    var zone: Int
    var isGlob: Bool
  }

  public init(config: GladeConfig = GladeConfig(), home rawHome: String = NSHomeDirectory(), extraScopes: [String]? = nil) {
    // Every rule is expanded against the same normalised home, so a home folder
    // reached through an alias (/var → /private/var) can't slip past the rules.
    let home = Protection.clean(rawHome)
    self.home = home
    var active: [ProtectedZone] = ProtectedZones.builtIn.filter { $0.locked || !config.unlockedZones.contains($0.id) }
    let custom = config.protectedPaths.map { Protection.clean(Protection.expand($0, home: home)) }
    if !custom.isEmpty {
      active.append(ProtectedZone(
        id: "custom", title: "Your Protected Folders", reason: "Folders you've put off limits.",
        paths: custom, locked: false, strictInside: true
      ))
    }
    // With iCloud's Desktop & Documents turned on, those two folders are cloud
    // storage: removing a file removes it from every device.
    if Protection.isInICloud(home + "/Documents") || Protection.isInICloud(home + "/Desktop") {
      active.append(ProtectedZone(
        id: "icloud-desktop", title: "iCloud Desktop & Documents",
        reason: "These folders sync through iCloud, so removing a file removes it from every device.",
        paths: [home + "/Desktop", home + "/Documents"], locked: false
      ))
      active.removeAll { $0.id == "icloud-desktop" && config.unlockedZones.contains("icloud-desktop") }
    }
    zones = active
    userPaths = custom

    var prefixes: [PrefixRule] = []
    var names: [NameRule] = []
    for (index, zone) in active.enumerated() {
      for pattern in zone.paths {
        let parts = Protection.components(Protection.clean(Protection.expand(pattern, home: home)))
        prefixes.append(PrefixRule(components: parts, zone: index, hasGlob: pattern.contains("*")))
      }
      for name in zone.names {
        names.append(NameRule(pattern: name, zone: index, isGlob: name.contains("*")))
      }
    }
    prefixRules = prefixes
    nameRules = names

    var roots = [home]
    for root in extraScopes ?? Protection.temporaryRoots() {
      roots.append(Protection.clean(root))
    }
    scopes = roots
  }

  // MARK: Queries

  /// The zone a path falls in, if any. A path is protected when it is the zone, is
  /// inside it, or any of its components carries a protected name.
  public func zone(for path: String) -> ProtectedZone? {
    let parts = Protection.components(Protection.clean(path))
    for rule in prefixRules where parts.count >= rule.components.count {
      if Protection.matches(rule.components, prefixOf: parts, glob: rule.hasGlob) { return zones[rule.zone] }
    }
    for part in parts {
      if let rule = nameRule(for: part) { return zones[rule.zone] }
    }
    return nil
  }

  /// Whether a single file or folder name is protected wherever it appears.
  /// Directory walkers use this to prune without building full paths.
  public func isProtectedName(_ name: String) -> Bool {
    nameRule(for: name) != nil
  }

  /// A name that makes every folder containing it off limits (photo libraries, backups).
  public func isStrictName(_ name: String) -> Bool {
    guard let rule = nameRule(for: name) else { return false }
    return zones[rule.zone].strictInside
  }

  /// Scanners may list and measure a path only when this returns true.
  public func canScan(_ path: String) -> Bool {
    zone(for: path) == nil
  }

  /// A zone that lies somewhere beneath this folder, judged from path rules alone.
  public func zoneBeneath(_ path: String) -> ProtectedZone? {
    let parts = Protection.components(Protection.clean(path))
    for rule in prefixRules where rule.components.count > parts.count {
      if Protection.matches(Array(rule.components.prefix(parts.count)), prefixOf: parts, glob: rule.hasGlob, exact: true) {
        return zones[rule.zone]
      }
    }
    return nil
  }

  /// Folders where everything is presumed to be yours: findings here are sent to the
  /// Trash and are never selected automatically.
  public func isPersonalArea(_ path: String) -> Bool {
    let cleaned = Protection.clean(path)
    return Protection.personalFolders.contains { cleaned == "\(home)/\($0)" || cleaned.hasPrefix("\(home)/\($0)/") }
  }

  public static let personalFolders = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public", "Sites"]

  /// The full check made before anything is removed.
  /// - Parameter allowRepository: Set only for worktrees, which git removes itself.
  public func verdict(forRemoving rawPath: String, allowRepository: Bool = false) -> Verdict {
    let path = Protection.clean(rawPath)
    guard path.hasPrefix("/"), !path.contains("/../"), !path.hasSuffix("/..") else { return .outOfScope }

    if scopes.contains(path) { return .structural }
    guard let scope = scopes.first(where: { path.hasPrefix($0 + "/") }) else { return .outOfScope }
    if let zone = zone(for: path) { return .protected(zone: zone.id, title: zone.title) }

    // Depth: nothing directly in the home folder, and nothing directly in ~/Library.
    let relative = Protection.components(String(path.dropFirst(scope.count)))
    if scope == home {
      let minimum = relative.first == "Library" ? 3 : 2
      if relative.count < minimum { return .structural }
      if Protection.structural.contains(relative.joined(separator: "/")) { return .structural }
    } else if relative.isEmpty {
      return .structural
    }

    if let zone = zoneBeneath(path) { return .containsProtected(zone: zone.id, title: zone.title) }

    // The real location, following links in every component except the last (removing
    // a link removes the link, never what it points at).
    let url = URL(fileURLWithPath: path)
    let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().path
    let resolved = Protection.clean(parent + "/" + url.lastPathComponent)
    if resolved != path {
      guard scopes.contains(where: { resolved.hasPrefix($0 + "/") }) else { return .escapesViaLink }
      if let zone = zone(for: resolved) { return .protected(zone: zone.id, title: zone.title) }
      if let zone = zoneBeneath(resolved) { return .containsProtected(zone: zone.id, title: zone.title) }
    }

    var info = stat()
    guard lstat(path, &info) == 0 else { return .allowed }
    let isDirectory = (info.st_mode & S_IFMT) == S_IFDIR
    if isDirectory {
      var parentInfo = stat()
      if lstat(parent, &parentInfo) == 0, parentInfo.st_dev != info.st_dev { return .otherVolume }
      if !allowRepository {
        for marker in [".git", ".jj", ".hg", ".svn"] {
          var markerInfo = stat()
          if lstat(path + "/" + marker, &markerInfo) == 0, (markerInfo.st_mode & S_IFMT) == S_IFDIR {
            return .repository
          }
        }
      }
    }
    return .allowed
  }

  // MARK: Fixed rules

  /// Folders (relative to home) that other things live in. Their contents may be
  /// removed; the folders themselves may not.
  static let structural: Set<String> = [
    "Library/Application Support", "Library/Caches", "Library/Containers", "Library/Group Containers",
    "Library/Developer", "Library/Developer/Xcode", "Library/Developer/CoreSimulator",
    "Library/Developer/Xcode/DerivedData", "Library/Developer/Xcode/Archives",
    "Library/Developer/CoreSimulator/Devices", "Library/Developer/Xcode/UserData",
    "Library/Logs", "Library/Saved Application State", "Library/WebKit", "Library/HTTPStorages",
    "Library/Application Support/Code", "Library/Application Support/Cursor",
    "Library/Application Support/Claude", "Library/Android", "Library/Android/sdk",
  ]

  /// Whether a folder is kept in iCloud Drive.
  static func isInICloud(_ path: String) -> Bool {
    let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isUbiquitousItemKey])
    return values?.isUbiquitousItem == true
  }

  // MARK: Path helpers

  static func expand(_ pattern: String, home: String) -> String {
    if pattern == "~" { return home }
    if pattern.hasPrefix("~/") { return home + pattern.dropFirst(1) }
    return pattern
  }

  /// Normalises a path without touching the disk: collapses `//` and `/./`, drops a
  /// trailing slash, and maps the `/var`, `/tmp` and `/etc` aliases to `/private`.
  public static func clean(_ path: String) -> String {
    var result = (path as NSString).standardizingPath
    for alias in ["/var/", "/tmp/", "/etc/"] where result.hasPrefix(alias) {
      result = "/private" + result
    }
    if result == "/tmp" || result == "/var" { result = "/private" + result }
    while result.count > 1, result.hasSuffix("/") { result.removeLast() }
    return result
  }

  static func components(_ path: String) -> [String] {
    path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
  }

  private static func matches(_ pattern: [String], prefixOf parts: [String], glob: Bool, exact: Bool = false) -> Bool {
    if exact, pattern.count != parts.count { return false }
    guard parts.count >= pattern.count else { return false }
    for (index, expected) in pattern.enumerated() {
      let actual = parts[index]
      if expected == actual { continue }
      if glob, expected.contains("*"), fnmatch(expected, actual, 0) == 0 { continue }
      // The default volume is case-insensitive, so compare that way too.
      if expected.caseInsensitiveCompare(actual) == .orderedSame { continue }
      return false
    }
    return true
  }

  private func nameRule(for name: String) -> NameRule? {
    for rule in nameRules {
      if rule.isGlob {
        if fnmatch(rule.pattern, name, FNM_CASEFOLD) == 0 { return rule }
      } else if rule.pattern.caseInsensitiveCompare(name) == .orderedSame {
        return rule
      }
    }
    return nil
  }

  /// The per-user temporary and cache folders macOS assigns (under /private/var/folders).
  static func temporaryRoots() -> [String] {
    var roots: [String] = []
    for name in [_CS_DARWIN_USER_TEMP_DIR, _CS_DARWIN_USER_CACHE_DIR] {
      var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
      if confstr(name, &buffer, buffer.count) > 0 {
        let length = buffer.firstIndex(of: 0) ?? buffer.count
        let path = String(decoding: buffer[..<length].map { UInt8(bitPattern: $0) }, as: UTF8.self)
        roots.append(URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
      }
    }
    return roots
  }
}

/// Whether this process may read the parts of the disk macOS guards behind Full Disk
/// Access. Checked by opening a file every Mac has, without reading it.
public enum FullDiskAccess {
  public static var isGranted: Bool {
    let probe = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"
    let descriptor = open(probe, O_RDONLY)
    if descriptor >= 0 {
      close(descriptor)
      return true
    }
    return false
  }

  public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")!
}
