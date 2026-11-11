import Foundation

/// The size of a file or folder as the disk counts it.
public struct Measure: Sendable, Equatable {
  /// Space actually allocated, with hard links counted once.
  public var bytes: Int64 = 0
  public var files: Int = 0
  public var newestModification: Date?
  public var newestAccess: Date?
  /// Entries that couldn’t be read (usually a missing permission).
  public var unreadable: Int = 0
  /// Something inside is a photo library, backup or similar that must not be split up.
  public var containsStrict: Bool = false
  public var cancelled: Bool = false

  public var lastUsed: Date? {
    switch (newestModification, newestAccess) {
    case (let a?, let b?): max(a, b)
    case (let a?, nil): a
    case (nil, let b?): b
    default: nil
    }
  }

  public static func + (lhs: Measure, rhs: Measure) -> Measure {
    var total = lhs
    total.bytes += rhs.bytes
    total.files += rhs.files
    total.unreadable += rhs.unreadable
    total.containsStrict = lhs.containsStrict || rhs.containsStrict
    total.cancelled = lhs.cancelled || rhs.cancelled
    total.newestModification = [lhs.newestModification, rhs.newestModification].compactMap { $0 }.max()
    total.newestAccess = [lhs.newestAccess, rhs.newestAccess].compactMap { $0 }.max()
    return total
  }
}

/// One file or folder met during a walk. Valid only inside the visit callback.
public struct WalkEntry {
  let entry: UnsafeMutablePointer<FTSENT>

  public var name: String {
    withUnsafePointer(to: &entry.pointee.fts_name) {
      String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
    }
  }

  public var path: String { String(cString: entry.pointee.fts_path) }
  /// 0 for the root, 1 for its children, and so on.
  public var depth: Int { Int(entry.pointee.fts_level) }
  public var isDirectory: Bool { Int32(entry.pointee.fts_info) == FTS_D }
  public var isSymlink: Bool {
    let info = Int32(entry.pointee.fts_info)
    return info == FTS_SL || info == FTS_SLNONE
  }

  private var status: stat { entry.pointee.fts_statp.pointee }

  /// Space allocated on disk.
  public var allocated: Int64 { Int64(status.st_blocks) * 512 }
  /// The logical length of the file.
  public var length: Int64 { Int64(status.st_size) }
  public var modified: Date { Date(timeIntervalSince1970: TimeInterval(status.st_mtimespec.tv_sec)) }
  public var accessed: Date { Date(timeIntervalSince1970: TimeInterval(status.st_atimespec.tv_sec)) }
  public var created: Date { Date(timeIntervalSince1970: TimeInterval(status.st_birthtimespec.tv_sec)) }
  public var linkCount: Int { Int(status.st_nlink) }
  public var inode: UInt64 { UInt64(status.st_ino) }
  public var device: Int32 { status.st_dev }
  /// A cloud file whose contents aren’t on this Mac. Reading it would download it.
  public var isDataless: Bool { status.st_flags & UInt32(SF_DATALESS) != 0 }
}

public enum WalkDecision {
  case proceed
  /// Don’t look inside this folder.
  case skip
  case stop
}

/// Walks folder trees without following links or crossing onto other disks.
public enum DiskWalk {
  /// Visits every entry under `roots`, parents before children.
  /// - Parameter unreadable: Called for anything that couldn’t be opened.
  public static func walk(
    _ roots: [String],
    unreadable: ((String) -> Void)? = nil,
    visit: (WalkEntry) -> WalkDecision
  ) {
    let existing = roots.filter { path in
      var info = stat()
      return lstat(path, &info) == 0
    }
    guard !existing.isEmpty else { return }
    var pointers: [UnsafeMutablePointer<CChar>?] = existing.map { strdup($0) }
    pointers.append(nil)
    defer { for pointer in pointers { free(pointer) } }
    guard let stream = fts_open(pointers, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return }
    defer { fts_close(stream) }

    while let entry = fts_read(stream) {
      switch Int32(entry.pointee.fts_info) {
      case FTS_D, FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
        switch visit(WalkEntry(entry: entry)) {
        case .proceed: break
        case .skip: fts_set(stream, entry, FTS_SKIP)
        case .stop: return
        }
      case FTS_DNR, FTS_ERR, FTS_NS:
        unreadable?(String(cString: entry.pointee.fts_path))
      default:
        break
      }
    }
  }

  /// Adds up the space used by files and folders.
  /// - Parameters:
  ///   - protection: When given, folders that are protected are left out of the total
  ///     and libraries that can’t be split are flagged.
  ///   - isCancelled: Checked every few thousand entries.
  public static func measure(
    _ paths: [String],
    protection: Protection? = nil,
    isCancelled: () -> Bool = { false }
  ) -> Measure {
    var result = Measure()
    var hardLinks = Set<HardLink>()
    var newestModified: Int = 0
    var newestAccessed: Int = 0
    var counter = 0

    walk(paths, unreadable: { _ in result.unreadable += 1 }) { entry in
      counter += 1
      if counter & 0xFFF == 0, isCancelled() {
        result.cancelled = true
        return .stop
      }
      let info = entry.entry.pointee.fts_statp.pointee
      if entry.isDirectory {
        result.bytes += Int64(info.st_blocks) * 512
        if let protection, entry.depth > 0 {
          let name = entry.name
          if protection.isStrictName(name) {
            result.containsStrict = true
            return .skip
          }
        }
        return .proceed
      }
      if info.st_nlink > 1 {
        guard hardLinks.insert(HardLink(device: info.st_dev, inode: UInt64(info.st_ino))).inserted else { return .proceed }
      }
      result.bytes += Int64(info.st_blocks) * 512
      result.files += 1
      newestModified = max(newestModified, info.st_mtimespec.tv_sec)
      newestAccessed = max(newestAccessed, info.st_atimespec.tv_sec)
      if let protection, info.st_size > 64_000_000, protection.isStrictName(entry.name) {
        result.containsStrict = true
      }
      return .proceed
    }
    if newestModified > 0 { result.newestModification = Date(timeIntervalSince1970: TimeInterval(newestModified)) }
    if newestAccessed > 0 { result.newestAccess = Date(timeIntervalSince1970: TimeInterval(newestAccessed)) }
    return result
  }

  /// The immediate children of a folder, or an empty list when it can’t be read.
  public static func children(of path: String) -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: path))?.map { path + "/" + $0 } ?? []
  }

  /// Expands a pattern such as `~/Library/Caches/com.apple.*` into the paths that
  /// exist. `*` matches within a single path component.
  public static func expand(_ pattern: String, home: String = NSHomeDirectory()) -> [String] {
    let full = Protection.expand(pattern, home: home)
    guard full.contains("*") else {
      var info = stat()
      return lstat(full, &info) == 0 ? [full] : []
    }
    var matches = ["/"]
    for part in Protection.components(full) {
      var next: [String] = []
      for base in matches {
        let prefix = base == "/" ? "/" : base + "/"
        if part.contains("*") {
          let names = (try? FileManager.default.contentsOfDirectory(atPath: base)) ?? []
          for name in names where fnmatch(part, name, 0) == 0 { next.append(prefix + name) }
        } else {
          let candidate = prefix + part
          var info = stat()
          if lstat(candidate, &info) == 0 { next.append(candidate) }
        }
      }
      matches = next
      if matches.isEmpty { break }
    }
    return matches.sorted()
  }

  private struct HardLink: Hashable {
    var device: Int32
    var inode: UInt64
  }
}
