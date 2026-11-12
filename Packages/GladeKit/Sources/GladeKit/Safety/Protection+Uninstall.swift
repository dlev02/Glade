import Foundation

/// The check made before an app is moved to the Trash. It is separate from
/// `verdict(forRemoving:)`, which never allows anything outside the home folder: this
/// allows one thing only, an ordinary app bundle in an Applications folder, and the
/// data the app keeps in the home folder is still checked path by path with
/// `verdict(forRemoving:)`.
extension Protection {
  /// Identifiers Glade has shipped under, release and development.
  static let gladeBundleIDs: [String] = ["io.github.dlev02.glade", "io.github.dlev02.glade.dev"]

  /// Apple apps macOS keeps whatever the person does, wherever they turn up.
  static let keptByMacOS: Set<String> = [
    "com.apple.safari", "com.apple.finder", "com.apple.systempreferences", "com.apple.appstore",
    "com.apple.systemsettings", "com.apple.mail", "com.apple.mobilesms", "com.apple.facetime",
    "com.apple.photos", "com.apple.music", "com.apple.tv", "com.apple.findmy",
  ]

  /// The folders apps may be uninstalled from: the Mac’s and the person’s own.
  public var applicationFolders: [String] { ["/Applications", home + "/Applications"].map(Protection.clean) }

  /// Whether Glade may move this app to the Trash. Allowed only for a real app bundle
  /// (not a link) directly in `/Applications` or `~/Applications`, or one plain folder
  /// below either, on the same disk, that is neither part of macOS nor Glade itself.
  /// Whether it is running is asked separately, at the moment of removal.
  public func verdict(forUninstalling rawPath: String) -> Verdict {
    // Written out in full: no relative paths, no `.` or `..` anywhere.
    guard rawPath.hasPrefix("/") else { return .outOfScope }
    let written = rawPath.split(separator: "/", omittingEmptySubsequences: true)
    guard !written.contains(where: { $0 == ".." || $0 == "." }) else { return .outOfScope }
    let path = Protection.clean(rawPath)
    let name = (path as NSString).lastPathComponent
    guard name.count > 4, name.lowercased().hasSuffix(".app") else { return .notAnApp }
    if path.hasPrefix("/System/") || path == "/System" { return .partOfMacOS }

    // A real folder, never a link to one: removing a link would leave the app, and
    // following it could lead anywhere.
    var info = stat()
    guard lstat(path, &info) == 0 else { return .notAnApp }
    if (info.st_mode & S_IFMT) == S_IFLNK { return .escapesViaLink }
    guard (info.st_mode & S_IFMT) == S_IFDIR else { return .notAnApp }

    // Where it sits: an Applications folder, or one plain folder (a vendor's, Setapp,
    // Utilities) inside one. Never inside another bundle.
    let parent = (path as NSString).deletingLastPathComponent
    let root: String
    if applicationFolders.contains(parent) {
      root = parent
    } else {
      let grandparent = (parent as NSString).deletingLastPathComponent
      guard applicationFolders.contains(grandparent) else { return .outsideApplications }
      var folder = stat()
      guard lstat(parent, &folder) == 0 else { return .outsideApplications }
      if (folder.st_mode & S_IFMT) == S_IFLNK { return .escapesViaLink }
      let folderName = (parent as NSString).lastPathComponent
      guard (folder.st_mode & S_IFMT) == S_IFDIR, !folderName.contains(".") else { return .outsideApplications }
      root = grandparent
    }
    var rootInfo = stat()
    guard lstat(root, &rootInfo) == 0 else { return .outsideApplications }
    if (rootInfo.st_mode & S_IFMT) == S_IFLNK { return .escapesViaLink }

    // The real location must be the path as written: nothing on the way is a link.
    guard let real = Protection.realPath(path), Protection.clean(real) == path else { return .escapesViaLink }
    if let zone = zone(for: path) { return .protected(zone: zone.id, title: zone.title) }
    if let zone = zoneBeneath(path) { return .containsProtected(zone: zone.id, title: zone.title) }

    // Not part of macOS: nothing on a read-only (sealed) volume, nothing System
    // Integrity Protection guards.
    if info.st_flags & UInt32(SF_RESTRICTED) != 0 || info.st_flags & UInt32(SF_IMMUTABLE) != 0 { return .partOfMacOS }
    var volume = statfs()
    if statfs(path, &volume) == 0, volume.f_flags & UInt32(MNT_RDONLY) != 0 { return .partOfMacOS }

    // The same disk as the folder it’s in: a disk mounted inside Applications is
    // another disk, not an app.
    var parentInfo = stat()
    guard lstat(parent, &parentInfo) == 0, parentInfo.st_dev == info.st_dev, rootInfo.st_dev == info.st_dev else {
      return .otherVolume
    }

    // What it is. An app that doesn’t say is not uninstalled.
    guard let identifier = InstalledApps.infoPlist(of: path)?["CFBundleIdentifier"] as? String, !identifier.isEmpty else {
      return .notAnApp
    }
    if Protection.isGlade(identifier: identifier, path: path) { return .isGlade }
    if Protection.keptByMacOS.contains(identifier.lowercased()) { return .partOfMacOS }
    return .allowed
  }

  /// Glade by any of its identifiers, or the copy that is running now.
  static func isGlade(identifier: String, path: String) -> Bool {
    let id = identifier.lowercased()
    if gladeBundleIDs.contains(where: { id == $0 || id.hasPrefix($0 + ".") }) { return true }
    let running = [Brand.appBundle.bundlePath, Bundle.main.bundlePath, Bundle.main.executablePath ?? ""]
      .filter { !$0.isEmpty }
      .map { Protection.clean(realPath($0) ?? $0) }
    return running.contains { $0 == path || $0.hasPrefix(path + "/") }
  }

  /// Where a path really is, every link followed, or `nil` when it doesn’t exist.
  static func realPath(_ path: String) -> String? {
    guard let resolved = realpath(path, nil) else { return nil }
    defer { free(resolved) }
    return String(cString: resolved)
  }
}
