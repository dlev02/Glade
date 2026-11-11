import Foundation

/// Byte-identical files in the person’s own folders.
///
/// Files are grouped by length, then by a fingerprint of their first and last 64 KB,
/// and only then hashed in full, so most files are never read at all.
public struct DuplicateScanner: StorageScanner {
  public let id = "duplicates"
  public let title = "Duplicate files"
  public let isDeep = true

  static let minimumLength: Int64 = 1_000_000

  public init() {}

  struct File: Sendable {
    var path: String
    var length: Int64
    var allocated: Int64
    var identity: FileIdentity
    var created: Date
    var modified: Date
  }

  /// The folders searched, plus app folders known to keep copies of your files.
  static func roots(_ context: ScanContext) -> [String] {
    var roots = ["Downloads", "Desktop", "Documents", "Movies", "Pictures", "Music"].map { "\(context.home)/\($0)" }
    // CleanShot keeps its own copy of every capture it also saves to the Desktop.
    roots.append("\(context.home)/Library/Application Support/CleanShot")
    return roots.filter { PersonalWalk.exists($0) && context.protection.canScan($0) }
  }

  public func scan(_ context: ScanContext) async -> [Finding] {
    let started = Date()
    let roots = Self.roots(context)
    let files = await context.background { Self.collect(roots, context) }
    guard !context.cancel.isCancelled else { return [] }
    let sets = await context.background { Self.identicalSets(files, cancel: context.cancel) }
    guard !context.cancel.isCancelled else { return [] }
    let findings = sets.compactMap { make($0, context) }.sorted { $0.bytes > $1.bytes }
    Log.info(.scan, "Duplicates: \(files.count) files of 1 MB or more, \(findings.count) duplicate sets in \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
    return findings
  }

  /// Every regular file of at least 1 MB, one path per file on disk.
  static func collect(_ roots: [String], _ context: ScanContext) -> [File] {
    let rules = PersonalWalk(home: context.home, protection: context.protection)
    var files: [File] = []
    var seen = Set<FileIdentity>()
    var counter = 0
    DiskWalk.walk(roots) { entry in
      counter += 1
      if counter & 0xFFF == 0, context.cancel.isCancelled { return .stop }
      if entry.isDirectory { return rules.shouldPrune(entry) ? .skip : .proceed }
      guard !entry.isSymlink, entry.length >= minimumLength, rules.allowsFile(entry) else { return .proceed }
      // Hard links are one file under two names, not two files.
      let identity = FileIdentity(device: entry.device, inode: entry.inode)
      guard seen.insert(identity).inserted else { return .proceed }
      files.append(File(
        path: entry.path, length: entry.length, allocated: entry.allocated, identity: identity,
        created: entry.created, modified: entry.modified
      ))
      return .proceed
    }
    return files
  }

  /// Groups of files whose contents are identical.
  static func identicalSets(_ files: [File], cancel: CancelFlag) -> [[File]] {
    struct SizeKey: Hashable {
      var device: Int32
      var length: Int64
    }
    let bySize = Dictionary(grouping: files) { SizeKey(device: $0.identity.device, length: $0.length) }
    var sets: [[File]] = []
    for (_, group) in bySize where group.count >= 2 {
      if cancel.isCancelled { return [] }
      var byEdges: [Data: [File]] = [:]
      for file in group {
        guard let hash = FileHashing.edgeHash(file.path, expectedLength: file.length) else { continue }
        byEdges[hash, default: []].append(file)
      }
      for (_, candidates) in byEdges where candidates.count >= 2 {
        var byContent: [Data: [File]] = [:]
        for file in candidates {
          if cancel.isCancelled { return [] }
          guard let hash = FileHashing.fullHash(file.path, expectedLength: file.length, cancel: cancel) else { continue }
          byContent[hash, default: []].append(file)
        }
        sets += byContent.values.filter { $0.count >= 2 }
      }
    }
    return sets
  }

  // MARK: Choosing what stays

  /// Orders copies so the one to keep comes first.
  static func keeperFirst(_ files: [File], home: String) -> [File] {
    files.sorted { a, b in
      let ka = rank(a, home: home), kb = rank(b, home: home)
      if ka.managed != kb.managed { return ka.managed }
      if ka.inTransit != kb.inTransit { return !ka.inTransit }
      if ka.copyName != kb.copyName { return !ka.copyName }
      if a.created != b.created { return a.created < b.created }
      if a.path.count != b.path.count { return a.path.count < b.path.count }
      return a.path < b.path
    }
  }

  private static func rank(_ file: File, home: String) -> (managed: Bool, inTransit: Bool, copyName: Bool) {
    let managed = file.path.hasPrefix(home + "/Library/")
    let inTransit = ["Downloads", "Desktop"].contains { file.path.hasPrefix("\(home)/\($0)/") }
    return (managed, inTransit, isCopyName(file.path))
  }

  /// "x copy.bin", "x copy 2.bin", "x (1).bin", "x 2.bin".
  static func isCopyName(_ path: String) -> Bool {
    let stem = (((path as NSString).lastPathComponent) as NSString).deletingPathExtension
    return stem.range(of: #"( copy( \d+)?| \(\d+\)| \d+)$"#, options: [.regularExpression, .caseInsensitive]) != nil
  }

  /// The app that owns a copy inside ~/Library, named from its Application Support folder.
  static func managingApp(_ path: String, home: String) -> String? {
    let prefix = home + "/Library/Application Support/"
    guard path.hasPrefix(prefix) else { return path.hasPrefix(home + "/Library/") ? "an app" : nil }
    return path.dropFirst(prefix.count).split(separator: "/").first.map(String.init)
  }

  private func make(_ set: [File], _ context: ScanContext) -> Finding? {
    let ordered = Self.keeperFirst(set, home: context.home)
    let library = context.home + "/Library/"
    let yours = ordered.filter { !$0.path.hasPrefix(library) }
    let managed = ordered.filter { $0.path.hasPrefix(library) }
    // Copies an app keeps of its own files are the app’s business, not duplicates of yours.
    guard !yours.isEmpty else { return nil }
    let keeper: File
    let removable: [File]
    if yours.count >= 2 {
      // Keep the best of your copies; an app’s own copy is never offered for removal.
      keeper = Self.keeperFirst(yours, home: context.home)[0]
      removable = yours.filter { $0.path != keeper.path }
    } else {
      // Your only copy duplicates one an app keeps: show it, but the fix is in the app.
      keeper = managed[0]
      removable = yours
    }
    let name = (keeper.path as NSString).lastPathComponent
    var evidence = ["Keeps \(context.tilde(keeper.path))."]
    evidence += removable.map { "Copy: \(context.tilde($0.path))" }
    evidence += managed.filter { $0.path != keeper.path }.map { "Also kept by an app: \(context.tilde($0.path))" }
    evidence.append("Contents are byte-identical (SHA-256 match), \(Format.bytes(keeper.length)) each.")
    evidence.append("If one is a Finder duplicate of the other, removing it may free less than shown.")
    var blockers: [Blocker] = []
    if let app = ordered.lazy.compactMap({ Self.managingApp($0.path, home: context.home) }).first {
      blockers.append(Blocker(.reportOnly, "One copy is managed by \(app); clear it from that app’s history."))
    }
    return Finding(
      id: Finding.makeID(rule: "duplicates.set", path: keeper.path),
      ruleID: "duplicates.set", category: .duplicates, title: "\(name) – \(set.count) copies",
      detail: "Identical copies of the same file. Removing the extra \(removable.count == 1 ? "copy" : "copies") keeps \(context.tilde(keeper.path)); what’s removed can’t be brought back once the Trash is emptied.",
      paths: removable.map(\.path), bytes: removable.reduce(0) { $0 + $1.allocated }, fileCount: removable.count,
      lastUsed: set.map(\.modified).max(), recovery: .permanent, risk: .personal, blockers: blockers,
      method: .trash, evidence: evidence, keeps: keeper.path, autoLevel: nil, idleDaysRequired: 0
    )
  }
}
