import Foundation

/// The same app more than once: stray copies in Downloads, the Desktop or Documents of
/// an app that's installed, and two versions side by side in Applications.
public struct AppCopyScanner: StorageScanner {
  public let id = "app-copies"
  public let title = "Extra copies of apps"

  /// How far below each personal folder to look.
  static let maximumDepth = 3
  /// Build products and dependencies are not copies.
  static let buildFolders: Set<String> = [
    "DerivedData", ".build", "build", "Build", "Products", "node_modules", "Pods", "Carthage", "dist", "out", "target",
  ]

  public init() {}

  public func scan(_ context: ScanContext) async -> [Finding] {
    let roots = ["Downloads", "Desktop", "Documents"].map { "\(context.home)/\($0)" }.filter { context.protection.canScan($0) }
    let strays = await context.background { Self.strayBundles(roots, context) }
    let apps = await InstalledApps.shared(for: context)
    let installed = apps.standardByBundleID

    var findings: [Finding] = []
    for stray in strays {
      if context.cancel.isCancelled { return findings }
      guard let copies = installed[stray.bundleID.lowercased()], let original = copies.first(where: { !$0.path.hasPrefix("/System/") }) ?? copies.first else {
        continue
      }
      guard context.protection.verdict(forRemoving: stray.path).isAllowed else { continue }
      let measure = await context.measure([stray.path])
      guard !measure.cancelled, measure.bytes > 0 else { continue }
      findings.append(copyFinding(stray, original: original, measure, context))
    }
    findings += await sideBySide(installed, context)
    return findings
  }

  /// App bundles in the personal folders, outside build and dependency folders.
  static func strayBundles(_ roots: [String], _ context: ScanContext) -> [InstalledApp] {
    var found: [String] = []
    var counter = 0
    DiskWalk.walk(roots) { entry in
      counter += 1
      if counter & 0xFFF == 0, context.cancel.isCancelled { return .stop }
      guard entry.isDirectory else { return .proceed }
      if entry.depth == 0 { return .proceed }
      if entry.isDataless { return .skip }
      let name = entry.name
      if name.hasPrefix(".") || buildFolders.contains(name) || context.protection.isProtectedName(name) { return .skip }
      let ext = (name as NSString).pathExtension.lowercased()
      if ext == "app" {
        let path = entry.path
        if context.protection.canScan(path) { found.append(path) }
        return .skip
      }
      // Other packages (archives, projects, libraries) hold nothing to report.
      if !ext.isEmpty, PersonalWalk.packageExtensions.contains(ext) { return .skip }
      if entry.depth >= maximumDepth { return .skip }
      return context.protection.canScan(entry.path) ? .proceed : .skip
    }
    return found.compactMap { InstalledApps.read($0, standard: false, cancel: context.cancel) }
  }

  private func copyFinding(_ stray: InstalledApp, original: InstalledApp, _ measure: Measure, _ context: ScanContext) -> Finding {
    let personal = context.protection.isPersonalArea(stray.path)
    let folder = context.tilde((stray.path as NSString).deletingLastPathComponent)
    let same = stray.versionText == original.versionText
    let comparison = same ? "the same version is installed" : "the installed one is \(original.versionText)"
    var evidence = [
      "Bundle identifier \(stray.bundleID), the same as \(context.tilde(original.path)).",
      "This copy is \(stray.versionText); \(comparison).",
    ]
    if let days = context.days(since: measure.lastUsed) {
      evidence.append(days == 0 ? "Used today." : "Last touched \(Format.age(measure.lastUsed, now: context.now)).")
    }
    return Finding(
      id: Finding.makeID(rule: "copies.stray", path: stray.path),
      ruleID: "copies.stray", category: .appCopies, title: "Copy of \(stray.name) \(stray.versionText)",
      detail: "A copy of \(stray.name) \(stray.versionText) in \(folder); \(comparison) in Applications. Removing this copy leaves the installed app alone.",
      paths: [stray.path], bytes: measure.bytes, fileCount: measure.files, lastUsed: measure.lastUsed,
      recovery: .redownload, risk: personal ? .personal : .caution, owner: Owner(stray.name, bundleIDs: [stray.bundleID]),
      method: .trash, evidence: evidence, autoLevel: nil, idleDaysRequired: 0
    )
  }

  /// Two or more installs of the same app in Applications. Shown, never removed:
  /// people remove apps from Applications themselves.
  private func sideBySide(_ installed: [String: [InstalledApp]], _ context: ScanContext) async -> [Finding] {
    var findings: [Finding] = []
    for (_, copies) in installed.sorted(by: { $0.key < $1.key }) {
      let editable = copies.filter { !$0.path.hasPrefix("/System/") }
      let distinct = Self.distinctBundles(editable)
      guard distinct.count >= 2 else { continue }
      let sorted = distinct.sorted { ($0.version ?? "").compare($1.version ?? "", options: .numeric) == .orderedDescending }
      var others = Measure()
      for app in sorted.dropFirst() { others = others + (await context.measure([app.path])) }
      guard !others.cancelled else { continue }
      let newest = sorted[0]
      let evidence = sorted.map { "\(context.tilde($0.path)): \($0.versionText)" }
        + ["All share the bundle identifier \(newest.bundleID)."]
      findings.append(Finding(
        id: Finding.makeID(rule: "copies.installed", path: newest.bundleID.lowercased()),
        ruleID: "copies.installed", category: .appCopies, title: "\(newest.name) installed \(sorted.count) times",
        detail: "\(sorted.count) copies of \(newest.name) are installed. The size shown is what the older ones use; keep the one you open.",
        paths: sorted.map(\.path), bytes: others.bytes, fileCount: others.files, lastUsed: others.lastUsed,
        recovery: .redownload, risk: .caution, owner: Owner(newest.name, bundleIDs: [newest.bundleID]),
        blockers: [Blocker(.reportOnly, "Remove the one you don't use from Applications yourself.")],
        method: .trash, evidence: evidence, autoLevel: nil, idleDaysRequired: 0
      ))
    }
    return findings
  }

  /// Leaves out paths that are the same bundle reached another way (a link, a firmlink).
  static func distinctBundles(_ apps: [InstalledApp]) -> [InstalledApp] {
    var seen = Set<FileIdentity>()
    return apps.filter { app in
      var info = stat()
      guard stat(app.path, &info) == 0 else { return false }
      return seen.insert(FileIdentity(device: info.st_dev, inode: UInt64(info.st_ino))).inserted
    }
  }
}
