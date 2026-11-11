import Foundation

/// The folders a walk through the person's own files steps around: everything another
/// scanner owns, everything protected, and everything an app manages as a unit.
struct PersonalWalk: Sendable {
  let home: String
  let protection: Protection

  /// Folders an app or tool manages as one unit. They're never entered or reported.
  static let packageExtensions: Set<String> = [
    "app", "appex", "bundle", "framework", "plugin", "kext", "xpc", "prefpane", "qlgenerator",
    "mdimporter", "saver", "component", "vst", "vst3", "aaxplugin", "wdgt", "xcarchive", "xcodeproj",
    "xcworkspace", "playground", "xcassets", "dsym", "docarchive", "mlmodelc", "mlpackage", "scnassets",
    "rcproject", "nib", "storyboardc", "photoslibrary", "photolibrary", "aplibrary", "musiclibrary",
    "tvlibrary", "imovielibrary", "fcpbundle", "logicx", "band", "lrdata", "lrlibrary", "pages", "numbers",
    "key", "rtfd", "sketch", "dtbase2", "sparsebundle", "pkg", "mpkg", "download", "localized-library",
    "theater", "dvdmedia", "pvm", "vmwarevm", "utm", "vbox", "cleanshotvideo", "screenflow", "cmproj",
    "dtbase", "graffle", "scriv", "nosync",
  ]

  /// Dependency and build folders, never entered wherever they appear.
  static let alwaysPruned: Set<String> = [
    "node_modules", "DerivedData", "Pods", "Carthage", "bower_components", "__pycache__",
    "site-packages", "jspm_packages", "elm-stuff", "_build", "deps", "zig-cache", "zig-out",
  ]

  /// Folder names that are build output only when a project file sits beside them.
  static let projectOutputs: [String: [String]] = [
    "build": ["build.gradle", "build.gradle.kts", "CMakeLists.txt", "package.json", "Package.swift",
              "setup.py", "pyproject.toml", "Makefile", "meson.build", "pubspec.yaml", "build.xml"],
    "Build": ["Products", "Intermediates.noindex"],
    "target": ["Cargo.toml", "pom.xml", "build.sbt", "project.clj"],
    "dist": ["package.json", "pyproject.toml", "setup.py"],
    "out": ["package.json", "build.gradle", "build.gradle.kts"],
    "vendor": ["composer.json", "go.mod", "Gemfile"],
    "obj": ["Directory.Build.props", "global.json"],
  ]

  /// Folders inside the personal areas that a media app manages. Removing a file
  /// inside breaks that app's library.
  static let managedMediaFolders = [
    "Music/Music", "Music/iTunes", "Music/Audio Music Apps", "Music/GarageBand", "Movies/TV",
    "Movies/Final Cut Backups.localized", "Movies/Motion Templates.localized", "Pictures/Photo Booth Library",
  ]

  /// Whether to step around a folder met during the walk. `depth` is the walk's own.
  func shouldPrune(_ entry: WalkEntry) -> Bool {
    if entry.depth == 0 { return false }
    // Listing a cloud folder that isn't on this Mac would fetch it.
    if entry.isDataless { return true }
    let name = entry.name
    if name.hasPrefix(".") { return true }
    if protection.isProtectedName(name) { return true }
    if PersonalWalk.alwaysPruned.contains(name) { return true }
    let ext = (name as NSString).pathExtension.lowercased()
    if !ext.isEmpty, PersonalWalk.packageExtensions.contains(ext) { return true }
    let path = entry.path
    // Bare repositories ("Project.git", or any folder holding HEAD, objects and refs)
    // are commit history, protected like a .git folder.
    if name.lowercased().hasSuffix(".git") { return true }
    if name == "objects" || name == "refs" {
      let parent = (path as NSString).deletingLastPathComponent
      if PersonalWalk.exists("\(parent)/HEAD") { return true }
    }
    if let markers = PersonalWalk.projectOutputs[name] {
      let parent = (path as NSString).deletingLastPathComponent
      let base = name == "Build" ? path : parent
      for marker in markers where PersonalWalk.exists("\(base)/\(marker)") { return true }
    }
    if PersonalWalk.exists("\(path)/pyvenv.cfg") { return true }
    if path.hasPrefix(home + "/") {
      let relative = String(path.dropFirst(home.count + 1))
      if !relative.contains("/") {
        // Directly in the home folder: Library and Applications belong to other scanners.
        if name == "Library" || name == "Applications" { return true }
      }
      if PersonalWalk.managedMediaFolders.contains(relative) { return true }
    }
    return !protection.canScan(path)
  }

  /// Whether a file that passed the size test may be reported.
  func allowsFile(_ entry: WalkEntry) -> Bool {
    if entry.isDataless || entry.isSymlink { return false }
    let name = entry.name
    if name.hasPrefix(".") || protection.isProtectedName(name) { return false }
    return protection.canScan(entry.path)
  }

  static func exists(_ path: String) -> Bool {
    var info = stat()
    return lstat(path, &info) == 0
  }

  /// A plain word for what a file is, judged from its extension.
  static func kind(of path: String) -> String {
    let lower = path.lowercased()
    if lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tar.xz") || lower.hasSuffix(".tar.zst") { return "archive" }
    switch (lower as NSString).pathExtension {
    case "mov", "mp4", "m4v", "mkv", "avi", "webm", "wmv", "flv", "mpg", "mpeg", "mts", "m2ts", "mxf", "braw", "r3d", "insv", "360":
      return "video"
    case "dmg", "iso", "img", "sparseimage", "toast", "cdr":
      return "disk image"
    case "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "zst", "xip", "lz4":
      return "archive"
    case "vdi", "vhd", "vhdx", "hdd", "qcow", "raw", "vmem", "nvram":
      return "virtual disk"
    case "gguf", "ggml", "safetensors", "ckpt", "pt", "pth", "onnx", "mlmodel", "h5", "tflite", "mlx", "npz":
      return "model weights"
    case "wav", "aif", "aiff", "flac", "mp3", "m4a", "caf", "alac", "w64":
      return "audio"
    case "pkg", "mpkg", "ipa", "apk", "aab", "msi", "exe":
      return "installer"
    case "psd", "psb", "tif", "tiff", "dng", "cr2", "cr3", "nef", "arw", "heic", "exr":
      return "image"
    case "sqlite", "sqlite3", "db", "realm":
      return "database"
    case "log", "csv", "json", "jsonl", "parquet", "txt":
      return "data"
    case "pdf":
      return "document"
    default:
      return "file"
    }
  }
}

/// Big files anywhere in the home folder, outside Library and the places other
/// scanners cover.
public struct LargeFileScanner: StorageScanner {
  public let id = "large-files"
  public let title = "Large files"

  /// Files at least this big are always listed.
  static let largeBytes: Int64 = 500_000_000
  /// Files at least this big are listed when nothing has touched them for a while.
  static let staleBytes: Int64 = 100_000_000
  static let staleDays = 180
  static let maximumFindings = 200

  public init() {}

  struct Candidate: Sendable {
    var path: String
    var allocated: Int64
    var modified: Date
    var accessed: Date
    var created: Date
  }

  public func scan(_ context: ScanContext) async -> [Finding] {
    guard context.protection.canScan(context.home) else { return [] }
    let started = Date()
    let candidates = await context.background {
      Self.collect(context).map { ($0, context.cancel.isCancelled ? nil : Spotlight.lastUsed($0.path)) }
    }
    guard !context.cancel.isCancelled else { return [] }

    var findings: [Finding] = []
    for (candidate, spotlight) in candidates {
      let touched = [candidate.modified, candidate.accessed, spotlight].compactMap { $0 }.max() ?? candidate.modified
      let idle = context.days(since: touched) ?? 0
      guard candidate.allocated >= Self.largeBytes || idle >= Self.staleDays else { continue }
      findings.append(make(candidate, spotlight: spotlight, touched: touched, context: context))
    }
    findings.sort { $0.bytes > $1.bytes }
    if findings.count > Self.maximumFindings { findings.removeLast(findings.count - Self.maximumFindings) }
    Log.info(.scan, "Large files: \(findings.count) of \(candidates.count) candidates in \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
    return findings
  }

  /// One pass over the home folder, keeping only files over the smaller threshold.
  static func collect(_ context: ScanContext) -> [Candidate] {
    let rules = PersonalWalk(home: context.home, protection: context.protection)
    var found: [Candidate] = []
    var links = Set<FileIdentity>()
    var counter = 0
    DiskWalk.walk([context.home]) { entry in
      counter += 1
      if counter & 0xFFF == 0, context.cancel.isCancelled { return .stop }
      if entry.isDirectory { return rules.shouldPrune(entry) ? .skip : .proceed }
      // Size first: most files are small, and this needs no allocation.
      guard entry.allocated >= staleBytes, rules.allowsFile(entry) else { return .proceed }
      if entry.linkCount > 1, !links.insert(FileIdentity(device: entry.device, inode: entry.inode)).inserted {
        return .proceed
      }
      found.append(Candidate(
        path: entry.path, allocated: entry.allocated, modified: entry.modified,
        accessed: entry.accessed, created: entry.created
      ))
      return .proceed
    }
    return found
  }

  private func make(_ candidate: Candidate, spotlight: Date?, touched: Date, context: ScanContext) -> Finding {
    let name = (candidate.path as NSString).lastPathComponent
    let kind = PersonalWalk.kind(of: candidate.path)
    var evidence = ["\(Format.bytes(candidate.allocated)) on disk.", "Kind: \(kind)."]
    if let spotlight {
      evidence.append("Last opened \(Format.age(spotlight, now: context.now)) (\(Self.day(spotlight))).")
    } else {
      evidence.append("No record of being opened; last read or changed \(Format.age(touched, now: context.now)) (\(Self.day(touched))).")
    }
    evidence.append("Created \(Self.day(candidate.created)); last modified \(Self.day(candidate.modified)).")
    let folder = context.tilde((candidate.path as NSString).deletingLastPathComponent)
    return Finding(
      id: Finding.makeID(rule: "large.file", path: candidate.path),
      ruleID: "large.file", category: .largeFiles, title: name,
      detail: "A large \(kind) in \(folder). Moving it to the Trash frees the space once the Trash is emptied; nothing recreates it.",
      paths: [candidate.path], bytes: candidate.allocated, fileCount: 1, lastUsed: touched,
      recovery: .permanent, risk: .personal, method: .trash, evidence: evidence,
      autoLevel: nil, idleDaysRequired: 0
    )
  }

  static func day(_ date: Date) -> String {
    date.formatted(.dateTime.year().month(.abbreviated).day())
  }
}

/// A file's identity on disk. Hard links share one.
struct FileIdentity: Hashable, Sendable {
  var device: Int32
  var inode: UInt64
}
