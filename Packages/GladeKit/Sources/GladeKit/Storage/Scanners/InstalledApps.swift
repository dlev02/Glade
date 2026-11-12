import Foundation
import Security

/// One app bundle found on this Mac.
public struct InstalledApp: Sendable, Hashable {
  public var path: String
  public var bundleID: String
  public var name: String
  public var version: String?
  public var build: String?
  /// In /Applications (including one folder down, such as Utilities or Setapp),
  /// ~/Applications or /System/Applications.
  public var isStandardLocation: Bool
  /// Lowercased identifiers the app may write under: its own, its helpers', and its
  /// app groups.
  public var identifiers: Set<String>
  /// The developer team that signed it, when the signature says.
  public var teamID: String?

  /// "4.41" or "4.41 (441)" when the build differs.
  public var versionText: String {
    switch (version, build) {
    case (let v?, let b?) where b != v: "\(v) (\(b))"
    case (let v?, _): v
    case (nil, let b?): b
    default: "unknown version"
    }
  }
}

/// An index of the apps on this Mac and of everything else that is evidently in use
/// (launchd jobs, running processes, command-line tools), built once per scan.
public struct InstalledApps: Sendable {
  public var apps: [InstalledApp]
  /// Every identifier in use, lowercased.
  public var identifiers: Set<String>
  /// Vendor prefixes of identifiers in use ("com.tinyspeck"), lowercased.
  public var vendors: Set<String>
  /// Signing teams of installed apps.
  public var teams: Set<String>
  /// Lowercased app names with spaces and punctuation removed.
  public var compactNames: Set<String>
  /// Names of command-line tools on the search path and Homebrew formulas and casks.
  public var tools: Set<String>

  public init(
    apps: [InstalledApp] = [], extraIdentifiers: Set<String> = [], tools: Set<String> = []
  ) {
    self.apps = apps
    var ids = Set(extraIdentifiers.map { $0.lowercased() })
    var teams = Set<String>()
    var names = Set<String>()
    for app in apps {
      ids.formUnion(app.identifiers)
      if let team = app.teamID { teams.insert(team.uppercased()) }
      let compact = InstalledApps.compact(app.name)
      if compact.count >= 3 { names.insert(compact) }
    }
    identifiers = ids
    vendors = Set(ids.compactMap { InstalledApps.vendor(of: $0) })
    self.teams = teams
    compactNames = names
    self.tools = Set(tools.map { $0.lowercased() })
  }

  /// Apps in the standard install locations, by lowercased bundle identifier.
  public var standardByBundleID: [String: [InstalledApp]] {
    Dictionary(grouping: apps.filter(\.isStandardLocation), by: { $0.bundleID.lowercased() })
  }

  // MARK: Building

  /// The index for this scan. Scanners running side by side share one copy.
  public static func shared(for context: ScanContext) async -> InstalledApps {
    await cache.index(for: context)
  }

  private static let cache = Cache()

  /// The index outside a scan, for the window’s whole-disk view.
  public static func current(config: GladeConfig) async -> InstalledApps {
    await build(ScanContext(config: config))
  }

  /// An index of the apps a scan found, for sample data and for describing folders
  /// without looking at the disk again.
  public static func index(from findings: [Finding]) -> InstalledApps {
    InstalledApps(apps: findings.compactMap { finding in
      guard let app = finding.app else { return nil }
      return InstalledApp(
        path: app.bundlePath, bundleID: app.bundleID, name: app.name, version: app.version, build: nil,
        isStandardLocation: true, identifiers: [app.bundleID.lowercased()], teamID: nil
      )
    })
  }

  private actor Cache {
    private var key: Date?
    private var task: Task<InstalledApps, Never>?

    func index(for context: ScanContext) async -> InstalledApps {
      if key == context.now, let task { return await task.value }
      let task = Task { await InstalledApps.build(context) }
      key = context.now
      self.task = task
      return await task.value
    }
  }

  static func build(_ context: ScanContext) async -> InstalledApps {
    let started = Date()
    let home = context.home
    // Reading names and small plists only, so this runs beside the size measurements
    // rather than waiting behind them for a slot.
    let standard = await Task.detached(priority: .utility) { InstalledApps.standardBundles(home: home) }.value
    let spotlight = await spotlightApps()
    let labels = await launchdLabels()
    let tools = await Task.detached(priority: .utility) { InstalledApps.toolNames() }.value

    var seen = Set<String>()
    var bundles: [(String, Bool)] = []
    for path in standard where seen.insert(path).inserted { bundles.append((path, true)) }
    for path in spotlight where seen.insert(path).inserted { bundles.append((path, false)) }
    let list = bundles
    let apps = await Task.detached(priority: .utility) {
      list.compactMap { path, isStandard in InstalledApps.read(path, standard: isStandard, cancel: context.cancel) }
    }.value
    var extra = Set(labels)
    extra.formUnion(context.running.bundleIDs)
    let index = InstalledApps(apps: apps, extraIdentifiers: extra, tools: tools)
    Log.info(.scan, "Installed apps: \(apps.count) bundles, \(index.identifiers.count) identifiers, \(labels.count) launchd jobs, \(tools.count) tools in \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
    return index
  }

  /// App bundles in the usual install folders.
  static func standardBundles(home: String) -> [String] {
    var found: [String] = []
    for root in ["/Applications", "\(home)/Applications"] {
      for child in DiskWalk.children(of: root).sorted() {
        if child.hasSuffix(".app") {
          found.append(child)
        } else if InstalledApps.isPlainFolder(child) {
          // One level down: Utilities, Setapp, vendor folders.
          found += DiskWalk.children(of: child).filter { $0.hasSuffix(".app") }.sorted()
        }
      }
    }
    for root in ["/System/Applications", "/System/Applications/Utilities"] {
      found += DiskWalk.children(of: root).filter { $0.hasSuffix(".app") }.sorted()
    }
    return found
  }

  private static func spotlightApps() async -> [String] {
    do {
      let result = try await Shell.run(
        "mdfind", ["kMDItemContentType == 'com.apple.application-bundle'"], timeout: 10, quiet: true
      )
      if result.timedOut { Log.warning(.scan, "Spotlight app search timed out; using install folders only") }
      return result.stdout.split(separator: "\n").map(String.init).filter { $0.hasPrefix("/") }
    } catch {
      Log.warning(.scan, "Spotlight app search failed: \(error.localizedDescription)")
      return []
    }
  }

  /// Labels of launchd jobs loaded for this user, plus the names of system-wide agents,
  /// daemons and privileged helpers. `~/Library/LaunchAgents` itself is a protected
  /// zone, so its jobs are learned from `launchctl` rather than by reading the folder.
  private static func launchdLabels() async -> [String] {
    var labels: [String] = []
    if let result = try? await Shell.run("launchctl", ["list"], timeout: 5, quiet: true), result.succeeded {
      for line in result.stdout.split(separator: "\n").dropFirst() {
        if let label = line.split(separator: "\t").last { labels.append(String(label)) }
      }
    }
    for folder in ["/Library/LaunchAgents", "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools"] {
      for path in DiskWalk.children(of: folder) {
        var name = (path as NSString).lastPathComponent
        if name.hasSuffix(".plist") { name = String(name.dropLast(6)) }
        labels.append(name)
      }
    }
    return labels
  }

  /// Executables on the search path, and Homebrew formulas and casks. Command-line
  /// tools write bundle-identifier-shaped folders too, and have no app to find.
  static func toolNames() -> Set<String> {
    var names = Set<String>()
    var folders = Shell.searchPaths
    folders += ["/opt/homebrew/Cellar", "/opt/homebrew/Caskroom", "/usr/local/Cellar", "/usr/local/Caskroom"]
    for folder in folders {
      for name in (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [] {
        names.insert(name.lowercased())
      }
    }
    // Third-party taps ("homebrew-autoupdate") install tools that write under the
    // tap’s own identifier.
    for prefix in ["/opt/homebrew", "/usr/local/Homebrew"] {
      for owner in DiskWalk.children(of: "\(prefix)/Library/Taps") {
        for tap in DiskWalk.children(of: owner) { names.insert((tap as NSString).lastPathComponent.lowercased()) }
      }
    }
    return names
  }

  // MARK: Reading a bundle

  /// Reads an app bundle’s identity, its helpers' identifiers and its app groups.
  static func read(_ path: String, standard: Bool, cancel: CancelFlag) -> InstalledApp? {
    if cancel.isCancelled { return nil }
    guard let info = infoPlist(of: path), let bundleID = info["CFBundleIdentifier"] as? String, !bundleID.isEmpty else {
      return nil
    }
    let fallback = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? fallback
    var ids: Set<String> = [bundleID.lowercased()]
    for helper in nestedBundles(of: path) {
      if let id = infoPlist(of: helper)?["CFBundleIdentifier"] as? String { ids.insert(id.lowercased()) }
    }
    let signing = signingInfo(path)
    for group in signing.groups { ids.insert(group.lowercased()) }
    return InstalledApp(
      path: path, bundleID: bundleID, name: name.isEmpty ? fallback : name,
      version: info["CFBundleShortVersionString"] as? String, build: info["CFBundleVersion"] as? String,
      isStandardLocation: standard, identifiers: ids, teamID: signing.team
    )
  }

  /// A bundle’s Info.plist, skipped when it’s a cloud placeholder.
  static func infoPlist(of bundle: String) -> [String: Any]? {
    for candidate in ["\(bundle)/Contents/Info.plist", "\(bundle)/Info.plist", "\(bundle)/WrappedBundle/Info.plist"] {
      var info = stat()
      guard stat(candidate, &info) == 0 else { continue }
      if info.st_flags & UInt32(SF_DATALESS) != 0 { return nil }
      guard info.st_size < 4_000_000, let data = FileManager.default.contents(atPath: candidate) else { continue }
      if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
        return plist
      }
    }
    return nil
  }

  /// Helpers, XPC services, login items and extensions bundled inside an app.
  static func nestedBundles(of app: String) -> [String] {
    var found: [String] = []
    for folder in ["PlugIns", "XPCServices", "Library/LoginItems", "Helpers", "Library/LaunchServices", "Frameworks"] {
      for child in DiskWalk.children(of: "\(app)/Contents/\(folder)") {
        let ext = (child as NSString).pathExtension.lowercased()
        if folder == "Frameworks" {
          if ext == "app" { found.append(child) }
        } else if ["app", "appex", "xpc", "bundle", "plugin"].contains(ext) {
          found.append(child)
        }
      }
    }
    return found
  }

  /// App groups and team from the code signature, read in-process without validating.
  static func signingInfo(_ path: String) -> (groups: [String], team: String?) {
    var code: SecStaticCode?
    guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess, let code else {
      return ([], nil)
    }
    var information: CFDictionary?
    let flags = SecCSFlags(rawValue: kSecCSSigningInformation | kSecCSRequirementInformation)
    guard SecCodeCopySigningInformation(code, flags, &information) == errSecSuccess,
          let dictionary = information as? [String: Any] else { return ([], nil) }
    let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    var groups: [String] = []
    if let entitlements = dictionary[kSecCodeInfoEntitlementsDict as String] as? [String: Any] {
      for key in ["com.apple.security.application-groups", "com.apple.developer.icloud-container-identifiers"] {
        groups += (entitlements[key] as? [String]) ?? []
      }
    }
    return (groups, team)
  }

  private static func isPlainFolder(_ path: String) -> Bool {
    var info = stat()
    guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { return false }
    return !(path as NSString).lastPathComponent.contains(".")
  }

  // MARK: Matching

  /// "Google Chrome" → "googlechrome".
  static func compact(_ text: String) -> String {
    String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
  }

  /// Hosting domains where the third component, not the second, names the developer.
  static let sharedDomains: Set<String> = [
    "com.github", "io.github", "com.gitlab", "io.gitlab", "org.sourceforge", "net.sourceforge",
    "com.electron", "com.todesktop", "com.bitbucket", "app.netlify", "com.vercel", "com.herokuapp",
  ]

  /// The developer part of an identifier: "com.tinyspeck" from "com.tinyspeck.slackmacgap".
  /// Edition suffixes are dropped, so "com.raycast-x" and "com.raycast" are one developer.
  static func vendor(of identifier: String) -> String? {
    var parts = identifier.lowercased().split(separator: ".").map(String.init)
    guard parts.count >= 3 else { return nil }
    let shared = sharedDomains.contains(parts.prefix(2).joined(separator: "."))
    if shared, parts.count < 4 { return nil }
    let index = shared ? 2 : 1
    if let cut = parts[index].firstIndex(where: { $0 == "-" || $0 == "_" }), cut != parts[index].startIndex {
      parts[index] = String(parts[index][..<cut])
    }
    return parts.prefix(index + 1).joined(separator: ".")
  }

  /// Why an identifier is evidently in use, or `nil` when nothing claims it.
  /// - Parameter team: The 10-character team prefix of a group container, if it had one.
  public func claim(on identifier: String, team: String? = nil) -> String? {
    let id = identifier.lowercased()
    if identifiers.contains(id) { return "An installed app, helper or background item uses \(identifier)." }
    // Prefix in either direction: com.vendor.app vs com.vendor.app.helper.
    for known in identifiers where known.hasPrefix(id + ".") || id.hasPrefix(known + ".") {
      return "Related to \(known), which is in use."
    }
    if let vendor = InstalledApps.vendor(of: id), vendors.contains(vendor) {
      return "Another app from the same developer (\(vendor)) is installed, and may share this data."
    }
    if let team, teams.contains(team.uppercased()) {
      return "An installed app is signed by the same developer team (\(team))."
    }
    let last = id.split(separator: ".").last.map(String.init) ?? id
    let lastCompact = InstalledApps.compact(last)
    if lastCompact.count >= 3, compactNames.contains(lastCompact) {
      return "An installed app is named \(last)."
    }
    if tools.contains(last) || (lastCompact.count >= 3 && tools.contains(lastCompact)) {
      return "A command-line tool named \(last) is installed."
    }
    return nil
  }
}
