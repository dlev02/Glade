import Foundation

/// The apps installed in the Applications folders, each as one finding: the app and the
/// data it keeps in the home folder. Only a person ever selects one; a clean moves it
/// to the Trash, so Put Back and `glade undo` restore it.
///
/// Apps that come with their own uninstaller are listed but can’t be removed here, and
/// apps the system account owns are listed for Finder to remove. Glade itself, macOS’s
/// apps and anything outside the Applications folders are left out.
public struct InstalledAppScanner: StorageScanner {
  public let id = "installed-apps"
  public let title = "Installed apps"

  public static let ruleID = "apps.installed"

  /// Only apps whose name, file name or identifier matches, for uninstalling one app
  /// without measuring them all.
  public var only: String?

  public init(only: String? = nil) {
    self.only = only
  }

  /// One app bundle found in an Applications folder.
  struct Candidate: Sendable, Hashable {
    /// Where the app really is.
    var path: String
    /// The folder it was found in. Differs from the real parent when a vendor folder
    /// lists the app through a link.
    var listedIn: String
    var throughLink: Bool
  }

  public func scan(_ context: ScanContext) async -> [Finding] {
    let protection = context.protection
    let folders = protection.applicationFolders
    let candidates = await context.background { Self.candidates(in: folders) }
    guard !candidates.isEmpty, !context.cancel.isCancelled else { return [] }
    let index = await InstalledApps.shared(for: context)
    let home = context.home
    let listing = await context.background { AppData.listing(home: home, protection: protection) }
    let casks = await context.background { Self.caskApps() }
    let cancel = context.cancel
    let read = await context.background {
      candidates.compactMap { candidate in
        InstalledApps.read(candidate.path, standard: true, cancel: cancel).map { (candidate, $0) }
      }
    }
    let wanted = only.map { Self.matching(read.map(\.1), $0) }

    var findings: [Finding] = []
    for (candidate, app) in read {
      if context.cancel.isCancelled { break }
      if let wanted, !wanted.contains(app.path) { continue }
      if VendorUninstaller.isUninstallerName(app.name) || VendorUninstaller.isUninstallerName((app.path as NSString).lastPathComponent) { continue }
      let verdict = protection.verdict(forUninstalling: app.path)
      if verdict == .isGlade || verdict == .partOfMacOS { continue }
      let uninstaller = VendorUninstaller.find(
        bundle: app.path, name: app.name, bundleID: app.bundleID, listedIn: candidate.listedIn, applicationFolders: folders
      )
      // An app reached through a link is listed only to point at its uninstaller.
      if candidate.throughLink, uninstaller?.path == nil { continue }
      guard verdict.isAllowed || uninstaller != nil else { continue }

      let data = AppData.folders(for: app, among: index.apps, listing: listing, protection: protection)
      let bundle = await context.measure([app.path], checkingLibraries: false)
      guard !bundle.cancelled else { break }
      var parts: [AppDetails.Part] = []
      var kept = data.stays
      for match in data.goes {
        let measure = await context.measure([match.path])
        if measure.cancelled { break }
        if measure.containsStrict {
          kept.append(AppDetails.Kept(path: match.path, label: match.label, reason: "Holds a library or backup that must stay whole."))
          continue
        }
        parts.append(AppDetails.Part(path: match.path, label: match.label, bytes: measure.bytes))
      }
      findings.append(make(
        app, bundle: bundle, parts: parts, kept: kept, uninstaller: uninstaller, verdict: verdict,
        source: Self.source(of: app, casks: casks), context: context
      ))
    }
    return findings
  }

  // MARK: Finding apps

  /// App bundles directly in each Applications folder or one plain folder down, and
  /// apps a vendor folder lists through a link (Creative Cloud does). Links straight
  /// in Applications (Safari’s) are macOS’s and are left out.
  static func candidates(in folders: [String]) -> [Candidate] {
    var found: [Candidate] = []
    var seen = Set<String>()
    func add(_ path: String, listedIn: String, throughLink: Bool) {
      guard let real = Protection.realPath(path).map(Protection.clean), real.hasSuffix(".app"),
            !real.hasPrefix("/System/"), seen.insert(real).inserted else { return }
      found.append(Candidate(path: real, listedIn: listedIn, throughLink: throughLink))
    }
    for root in folders {
      for child in DiskWalk.children(of: root).sorted() {
        let kind = FileKind.of(child)
        if child.hasSuffix(".app"), kind == .directory {
          add(child, listedIn: root, throughLink: false)
        } else if kind == .directory, !(child as NSString).lastPathComponent.contains(".") {
          for inner in DiskWalk.children(of: child).sorted() {
            switch FileKind.of(inner) {
            case .directory where inner.hasSuffix(".app"): add(inner, listedIn: child, throughLink: false)
            case .link: add(inner, listedIn: child, throughLink: true)
            default: break
            }
          }
        }
      }
    }
    return found
  }

  enum FileKind {
    case directory, link, other, missing

    static func of(_ path: String) -> FileKind {
      var info = stat()
      guard lstat(path, &info) == 0 else { return .missing }
      switch info.st_mode & S_IFMT {
      case S_IFDIR: return .directory
      case S_IFLNK: return .link
      default: return .other
      }
    }
  }

  /// The apps a name refers to: an exact name, file name or identifier if there is
  /// one, otherwise every app whose name contains it.
  static func matching(_ apps: [InstalledApp], _ query: String) -> Set<String> {
    let wanted = query.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: ".app", with: "")
    func names(_ app: InstalledApp) -> [String] {
      [app.name.lowercased(), ((app.path as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased(), app.bundleID.lowercased()]
    }
    let exact = apps.filter { names($0).contains(wanted) }
    if !exact.isEmpty { return Set(exact.map(\.path)) }
    return Set(apps.filter { names($0).dropLast().contains { $0.contains(wanted) } }.map(\.path))
  }

  /// Apps Homebrew installed, by their file names, from the links in its Caskroom.
  static func caskApps() -> Set<String> {
    var names = Set<String>()
    for root in ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"] {
      for cask in DiskWalk.children(of: root) {
        for version in DiskWalk.children(of: cask) {
          for item in DiskWalk.children(of: version) where item.hasSuffix(".app") {
            names.insert((item as NSString).lastPathComponent.lowercased())
          }
        }
      }
    }
    return names
  }

  static func source(of app: InstalledApp, casks: Set<String>) -> AppSource {
    var info = stat()
    if lstat(app.path + "/Contents/_MASReceipt", &info) == 0 { return .appStore }
    let id = app.bundleID.lowercased()
    if app.path.contains("/Setapp/") || id.hasSuffix("-setapp") || id.hasSuffix(".setapp") { return .setapp }
    if casks.contains((app.path as NSString).lastPathComponent.lowercased()) { return .homebrew }
    return .other
  }

  /// When the app was last opened: the latest of Spotlight’s record, Glade’s own record
  /// of apps coming to the front, and when its program was last read.
  static func lastOpened(_ app: InstalledApp) -> (date: Date?, source: String?) {
    var best: (Date, String)?
    func consider(_ date: Date?, _ source: String) {
      // A time of zero, or one in the future, isn’t a record of anything.
      guard let date, date > Date(timeIntervalSinceReferenceDate: 0), date <= Date().addingTimeInterval(3600) else { return }
      if best == nil || date > best!.0 { best = (date, source) }
    }
    consider(Spotlight.lastUsed(app.path), "Spotlight")
    consider(ActivityLog.shared.lastActive(bundleID: app.bundleID), "Glade")
    if let executable = InstalledApps.infoPlist(of: app.path)?["CFBundleExecutable"] as? String, !executable.contains("/") {
      var info = stat()
      if lstat("\(app.path)/Contents/MacOS/\(executable)", &info) == 0 {
        consider(Date(timeIntervalSince1970: TimeInterval(info.st_atimespec.tv_sec)), "program")
      }
    }
    return (best?.0, best?.1)
  }

  // MARK: The finding

  private func make(
    _ app: InstalledApp, bundle: Measure, parts: [AppDetails.Part], kept: [AppDetails.Kept],
    uninstaller: VendorUninstaller.Found?, verdict: Verdict, source: AppSource, context: ScanContext
  ) -> Finding {
    let opened = Self.lastOpened(app)
    let parent = (app.path as NSString).deletingLastPathComponent
    let needsAdministrator = access(app.path, W_OK) != 0 || access(parent, W_OK) != 0
    // By identifier only: program names ("applet", "Electron") are shared by many apps.
    let owner = Owner(app.name, bundleIDs: [app.bundleID])

    var blockers: [Blocker] = []
    if let uninstaller {
      blockers.append(Blocker(.ownUninstaller, VendorUninstaller.reason(uninstaller, appName: app.name)))
    } else if !verdict.isAllowed {
      blockers.append(Blocker(.reportOnly, verdict.explanation))
    }
    if context.running.runningName(of: owner) != nil
      || InUse.runningExecutable(inside: app.path, executables: context.running.executablePaths) != nil {
      blockers.append(Blocker(.appRunning, "\(app.name) is open. Quit it first."))
    }
    if uninstaller == nil, needsAdministrator {
      blockers.append(Blocker(.needsAdmin, "macOS asks for your password to remove this app, so move it to the Trash in Finder."))
    }

    var evidence: [String] = []
    evidence.append("Version \(app.versionText), from \(source == .other ? "a download" : source.title).")
    switch opened.source {
    case "Spotlight": evidence.append("Last opened \(Format.age(opened.date)), as Spotlight recorded it.")
    case "Glade": evidence.append("Last in front \(Format.age(opened.date)), as Glade saw it.")
    case "program": evidence.append("Its program was last read \(Format.age(opened.date)); macOS doesn’t record when it was last opened.")
    default: evidence.append("macOS hasn’t recorded when it was last opened.")
    }
    if !parts.isEmpty {
      evidence.append("Its data in your home folder: \(Format.bytes(parts.reduce(0) { $0 + $1.bytes })) in \(parts.count == 1 ? "1 folder" : "\(parts.count) folders").")
    }
    if bundle.unreadable > 0 { evidence.append("\(bundle.unreadable) items inside couldn’t be read, so it may be larger.") }

    let details = AppDetails(
      bundleID: app.bundleID, name: app.name, version: app.version, source: source, bundlePath: app.path,
      bundleBytes: bundle.bytes, parts: parts, kept: kept, lastOpened: opened.date,
      uninstaller: uninstaller?.path, needsAdministrator: needsAdministrator
    )
    let detail = uninstaller != nil
      ? "This app comes with its own uninstaller. Use it, then scan again to clear anything it leaves behind."
      : "The app and the settings, caches and data it keeps in your home folder. They go to the Trash, so you can put them back."
    var finding = Finding(
      id: Finding.makeID(rule: Self.ruleID, path: app.path), ruleID: Self.ruleID, category: .installedApps,
      title: app.name, detail: detail, paths: [app.path] + parts.map(\.path),
      bytes: bundle.bytes + parts.reduce(0) { $0 + $1.bytes }, fileCount: bundle.files,
      lastUsed: opened.date, recovery: .reinstall, risk: .personal, owner: owner, blockers: blockers,
      method: .uninstallApp(bundleID: app.bundleID), evidence: evidence, autoLevel: nil, idleDaysRequired: 0,
      needsOwnerClosed: true
    )
    finding.app = details
    return finding
  }
}
