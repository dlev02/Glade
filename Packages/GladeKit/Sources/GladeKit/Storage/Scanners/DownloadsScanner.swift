import CoreServices
import Foundation

/// What Spotlight remembers about a file. Reads the index only, never the file.
enum Spotlight {
  struct Record: Sendable {
    var lastUsed: Date?
    var added: Date?
    /// The website a download came from, host only.
    var source: String?
  }

  static func record(_ path: String) -> Record {
    guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString) else { return Record() }
    let lastUsed = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    let added = MDItemCopyAttribute(item, kMDItemDateAdded) as? Date
    let froms = (MDItemCopyAttribute(item, kMDItemWhereFroms) as? [String]) ?? []
    return Record(lastUsed: lastUsed, added: added, source: host(from: froms))
  }

  static func lastUsed(_ path: String) -> Date? {
    guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString) else { return nil }
    return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
  }

  /// The first web host among a download’s recorded origins. The full address can
  /// carry tokens and is never kept.
  static func host(from origins: [String]) -> String? {
    for origin in origins {
      guard let components = URLComponents(string: origin), let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https", let host = components.host, !host.isEmpty else { continue }
      return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
    return nil
  }
}

/// Installers and old downloads at the top of Downloads and the Desktop.
public struct DownloadsScanner: StorageScanner {
  public let id = "downloads"
  public let title = "Downloads & installers"

  /// Installers idle this long, for an app that’s installed, may be selected by a clean level.
  static let installerIdleDays = 14
  static let staleDays = 90
  /// Old items at least this big are listed one by one; smaller ones are grouped.
  static let individualBytes: Int64 = 20_000_000
  static let minimumInstallerBytes: Int64 = 1_000_000
  static let inProgress: Set<String> = ["download", "crdownload", "part", "partial", "opdownload", "fdmdownload"]
  static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "xip", "ipa", "iso", "msi", "exe"]
  /// Disk images and packages: the only kinds that may be selected without a person.
  static let autoExtensions: Set<String> = ["dmg", "pkg", "mpkg"]

  public init() {}

  struct Item: Sendable {
    var path: String
    var name: String
    var isDirectory: Bool
    var modified: Date
    var accessed: Date
    var spotlight: Spotlight.Record
  }

  public func scan(_ context: ScanContext) async -> [Finding] {
    let roots = ["Downloads", "Desktop"].map { "\(context.home)/\($0)" }.filter { context.protection.canScan($0) }
    let items = await context.background { roots.map { ($0, Self.list($0, context)) } }
    guard items.contains(where: { !$0.1.isEmpty }) else { return [] }
    let apps = await InstalledApps.shared(for: context)
    let installable = apps.apps.filter { $0.isStandardLocation && !$0.bundleID.lowercased().hasPrefix("com.apple.") }
    let mounted = items.contains { $0.1.contains { $0.name.lowercased().hasSuffix(".dmg") } } ? await Self.mountedImages() : []

    var findings: [Finding] = []
    for (root, list) in items {
      var older: [(Item, Measure)] = []
      for item in list {
        if context.cancel.isCancelled { return findings }
        let measure = await context.measure([item.path])
        guard !measure.cancelled, !measure.containsStrict else { continue }
        let touched = Self.lastTouched(item, measure)
        let idle = context.days(since: touched) ?? 0
        if let installer = installerFinding(item, measure, touched, idle, installable, mounted, context) {
          findings.append(installer)
        } else if idle >= Self.staleDays {
          if measure.bytes >= Self.individualBytes {
            findings.append(staleFinding(item, measure, touched, root: root, context))
          } else {
            older.append((item, measure))
          }
        }
      }
      if let summary = olderFinding(older, root: root, context) { findings.append(summary) }
    }
    for root in roots {
      if let partial = await partialFinding(root, context) { findings.append(partial) }
    }
    return findings
  }

  // MARK: Unfinished browser downloads

  /// Hidden files Chromium-based browsers write while a download is in progress
  /// (".com.google.Chrome.a1B2c3"). One left behind is a download that failed or was
  /// cancelled.
  static let partialPattern = #"^\.(com\.google\.Chrome|company\.thebrowser\.Browser|org\.chromium\.Chromium|com\.brave\.Browser|com\.microsoft\.edgemac|com\.vivaldi\.Vivaldi|com\.operasoftware\.Opera|ai\.perplexity\.comet|company\.thebrowser\.dia)(\.[A-Za-z]+)?\.[A-Za-z0-9]{6}$"#
  static let partialIdleDays = 7

  private func partialFinding(_ root: String, _ context: ScanContext) async -> Finding? {
    struct Partial: Sendable {
      var path: String
      var bytes: Int64
      var modified: Date
    }
    let partials: [Partial] = await context.background {
      DiskWalk.children(of: root).compactMap { path in
        let name = (path as NSString).lastPathComponent
        guard name.range(of: Self.partialPattern, options: .regularExpression) != nil else { return nil }
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_flags & UInt32(SF_DATALESS) == 0 else { return nil }
        let modified = Date(timeIntervalSince1970: TimeInterval(max(info.st_mtimespec.tv_sec, info.st_atimespec.tv_sec)))
        guard (context.days(since: modified) ?? 0) >= Self.partialIdleDays else { return nil }
        return Partial(path: path, bytes: Int64(info.st_blocks) * 512, modified: modified)
      }
    }
    let total = partials.reduce(0) { $0 + $1.bytes }
    guard !partials.isEmpty, total >= 1_000_000 else { return nil }
    let dates = partials.map(\.modified)
    let place = (root as NSString).lastPathComponent
    var evidence = [
      "\(partials.count) hidden temporary \(partials.count == 1 ? "file" : "files") in \(context.tilde(root)) named the way Chromium-based browsers name a download in progress.",
    ]
    if let oldest = dates.min(), let newest = dates.max() {
      let span = LargeFileScanner.day(oldest) == LargeFileScanner.day(newest)
        ? "on \(LargeFileScanner.day(newest))" : "between \(LargeFileScanner.day(oldest)) and \(LargeFileScanner.day(newest))"
      evidence.append("Last touched \(span); none in the last \(Self.partialIdleDays) days.")
    }
    return Finding(
      id: Finding.makeID(rule: "downloads.partial", path: root),
      ruleID: "downloads.partial", category: .downloads,
      title: "Unfinished browser downloads (\(partials.count) \(partials.count == 1 ? "file" : "files"))",
      detail: "Pieces of downloads that failed or were cancelled, hidden in \(place). They can’t be opened; download the file again if you still need it.",
      paths: partials.map(\.path).sorted(), bytes: total, fileCount: partials.count, lastUsed: dates.max(),
      recovery: .redownload, risk: .personal, method: .trash, evidence: evidence, autoLevel: nil, idleDaysRequired: 0
    )
  }

  /// The top-level entries worth looking at.
  static func list(_ root: String, _ context: ScanContext) -> [Item] {
    var items: [Item] = []
    for path in DiskWalk.children(of: root).sorted() {
      let name = (path as NSString).lastPathComponent
      if name.hasPrefix(".") || context.protection.isProtectedName(name) { continue }
      if inProgress.contains((name as NSString).pathExtension.lowercased()) { continue }
      guard context.protection.canScan(path) else { continue }
      var info = stat()
      guard lstat(path, &info) == 0 else { continue }
      let type = info.st_mode & S_IFMT
      guard type == S_IFREG || type == S_IFDIR else { continue }
      // A cloud placeholder takes no space here.
      if info.st_flags & UInt32(SF_DATALESS) != 0 { continue }
      let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
      // Possibly still being written.
      if context.now.timeIntervalSince(modified) < 3600 { continue }
      items.append(Item(
        path: path, name: name, isDirectory: type == S_IFDIR, modified: modified,
        accessed: Date(timeIntervalSince1970: TimeInterval(info.st_atimespec.tv_sec)),
        spotlight: Spotlight.record(path)
      ))
    }
    return items
  }

  /// Spotlight’s last-opened date when it has one, else the later of modified and read;
  /// for a folder, also the newest thing inside.
  static func lastTouched(_ item: Item, _ measure: Measure) -> Date {
    if let used = item.spotlight.lastUsed {
      return item.isDirectory ? max(used, measure.lastUsed ?? used) : used
    }
    let own = max(item.modified, item.accessed)
    return item.isDirectory ? max(own, measure.lastUsed ?? own) : own
  }

  // MARK: Installers

  private func installerFinding(
    _ item: Item, _ measure: Measure, _ touched: Date, _ idle: Int, _ apps: [InstalledApp],
    _ mounted: Set<String>, _ context: ScanContext
  ) -> Finding? {
    let lower = item.name.lowercased()
    let ext = (lower as NSString).pathExtension
    let match = Self.matchingApp(item.name, apps)
    let isArchive = ext == "zip" || ext == "tgz" || lower.hasSuffix(".tar.gz")
    let isInstaller = Self.installerExtensions.contains(ext) || lower.hasSuffix(".app.zip") || (isArchive && match != nil)
    guard isInstaller, measure.bytes >= Self.minimumInstallerBytes else { return nil }

    var evidence: [String] = []
    var blockers: [Blocker] = []
    let opened = item.spotlight.lastUsed == nil ? "last touched" : "last opened"
    let ago = idle == 0 ? "today" : Format.age(touched, now: context.now)
    var automatic = false
    if let match {
      evidence.append("\(match.name) is installed (\(match.versionText)); this installer was \(opened) \(ago).")
      let fileVersion = Self.version(in: item.name)
      if let fileVersion, let installed = match.version, fileVersion.compare(installed, options: .numeric) == .orderedDescending {
        evidence.append("Its name says \(fileVersion), newer than the installed \(installed): it may be an update you haven’t installed yet.")
      } else {
        automatic = Self.autoExtensions.contains(ext) && idle >= Self.installerIdleDays
      }
    } else {
      evidence.append("No installed app matches its name. It was \(opened) \(ago).")
    }
    if let source = item.spotlight.source { evidence.append("Downloaded from \(source).") }
    if ext == "dmg", mounted.contains(Protection.clean(item.path)) {
      blockers.append(Blocker(.inUse, "This disk image is open. Eject it first."))
      automatic = false
    }

    let detail: String
    if let match {
      detail = "An installer for \(match.name), which is already installed. Removing it only matters if you want to reinstall offline; the developer offers it again."
    } else {
      detail = "An installer or disk image you downloaded. Nothing shows it’s still needed, but it may not be available to download again."
    }
    return Finding(
      id: Finding.makeID(rule: "downloads.installer", path: item.path),
      ruleID: "downloads.installer", category: .downloads, title: item.name, detail: detail,
      paths: [item.path], bytes: measure.bytes, fileCount: max(1, measure.files), lastUsed: touched,
      recovery: match == nil ? .permanent : .redownload, risk: automatic ? .caution : .personal,
      blockers: blockers, method: .trash, evidence: evidence,
      autoLevel: automatic ? .balanced : nil, idleDaysRequired: automatic ? Self.installerIdleDays : 0
    )
  }

  /// The installed app whose name appears in a file name as whole words, ignoring case
  /// and punctuation: "Slack-4.41.0-macOS.dmg" → Slack, but "Archive.zip" ↛ Arc.
  static func matchingApp(_ fileName: String, _ apps: [InstalledApp]) -> InstalledApp? {
    let tokens = words(fileName)
    guard !tokens.isEmpty else { return nil }
    let ignored: Set<String> = ["install", "installer", "setup", "uninstall", "update", "updater", "app", "helper", "launcher"]
    var best: (app: InstalledApp, length: Int)?
    for app in apps {
      let nameWords = words(app.name)
      let joined = nameWords.joined()
      guard joined.count >= 3, !ignored.contains(joined) else { continue }
      var found = tokens.contains(joined)
      if !found, nameWords.count > 1, tokens.count >= nameWords.count {
        for start in 0...(tokens.count - nameWords.count) where Array(tokens[start..<start + nameWords.count]) == nameWords {
          found = true
          break
        }
      }
      if found, joined.count > (best?.length ?? 0) { best = (app, joined.count) }
    }
    return best?.app
  }

  /// Lowercased runs of letters, and runs of digits, from a name.
  static func words(_ text: String) -> [String] {
    var result: [String] = []
    var current = ""
    var currentIsDigit = false
    for character in text.lowercased() {
      let isLetter = character.isLetter, isDigit = character.isNumber
      if isLetter || isDigit {
        if !current.isEmpty, isDigit != currentIsDigit {
          result.append(current)
          current = ""
        }
        current.append(character)
        currentIsDigit = isDigit
      } else if !current.isEmpty {
        result.append(current)
        current = ""
      }
    }
    if !current.isEmpty { result.append(current) }
    return result
  }

  /// The first dotted version number in a name, such as "4.41.0".
  static func version(in name: String) -> String? {
    guard let range = name.range(of: #"\d+(\.\d+)+"#, options: .regularExpression) else { return nil }
    return String(name[range])
  }

  /// Disk images that are attached right now.
  static func mountedImages() async -> Set<String> {
    guard let result = try? await Shell.run("hdiutil", ["info", "-plist"], timeout: 5, quiet: true), result.succeeded,
          let plist = try? PropertyListSerialization.propertyList(from: Data(result.stdout.utf8), format: nil) as? [String: Any],
          let images = plist["images"] as? [[String: Any]] else { return [] }
    return Set(images.compactMap { ($0["image-path"] as? String).map(Protection.clean) })
  }

  // MARK: Old downloads

  private func staleFinding(_ item: Item, _ measure: Measure, _ touched: Date, root: String, _ context: ScanContext) -> Finding {
    let place = (root as NSString).lastPathComponent
    var evidence = ["Untouched for \(Format.age(touched, now: context.now).replacingOccurrences(of: " ago", with: "")) (since \(LargeFileScanner.day(touched)))."]
    if let added = item.spotlight.added { evidence.append("Added to \(place) \(LargeFileScanner.day(added)).") }
    if let source = item.spotlight.source { evidence.append("Downloaded from \(source).") }
    if item.isDirectory { evidence.append("A folder of \(measure.files) files.") }
    if measure.unreadable > 0 { evidence.append("\(measure.unreadable) items couldn’t be read, so the real size may be larger.") }
    let what = place == "Downloads" ? "Something you downloaded" : "Something on your Desktop"
    return Finding(
      id: Finding.makeID(rule: "downloads.stale", path: item.path),
      ruleID: "downloads.stale", category: .downloads, title: item.name,
      detail: "\(what) that hasn’t been opened in \(Format.age(touched, now: context.now).replacingOccurrences(of: " ago", with: "")). Moving it to the Trash frees the space; nothing recreates it.",
      paths: [item.path], bytes: measure.bytes, fileCount: max(1, measure.files), lastUsed: touched,
      recovery: .permanent, risk: .personal, method: .trash, evidence: evidence,
      autoLevel: nil, idleDaysRequired: 0
    )
  }

  private func olderFinding(_ items: [(Item, Measure)], root: String, _ context: ScanContext) -> Finding? {
    let total = items.map(\.1).reduce(Measure(), +)
    guard !items.isEmpty, total.bytes >= 1_000_000 else { return nil }
    let place = (root as NSString).lastPathComponent
    let count = "\(items.count) \(items.count == 1 ? "item" : "items")"
    let title = place == "Downloads" ? "Older downloads (\(count))" : "Older Desktop items (\(count))"
    let newest = items.map { Self.lastTouched($0.0, $0.1) }.max()
    let names = items.sorted { $0.1.bytes > $1.1.bytes }.prefix(5).map(\.0.name)
    var evidence = ["\(count) in \(context.tilde(root)), each under \(Format.bytes(Self.individualBytes)), none opened in the last \(Self.staleDays) days."]
    evidence.append("Largest: \(names.joined(separator: ", "))\(items.count > names.count ? ", …" : "").")
    return Finding(
      id: Finding.makeID(rule: "downloads.older", path: root),
      ruleID: "downloads.older", category: .downloads, title: title,
      detail: "Small files in \(place) that haven’t been opened in over three months. Moving them to the Trash frees the space; nothing recreates them.",
      paths: items.map(\.0.path), bytes: total.bytes, fileCount: total.files, lastUsed: newest,
      recovery: .permanent, risk: .personal, method: .trash, evidence: evidence,
      autoLevel: nil, idleDaysRequired: 0
    )
  }
}
