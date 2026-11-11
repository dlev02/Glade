import Foundation

/// Signs that something on disk is being used right now, read from names and process
/// listings only. Scanners use them to hold findings back, and the cleaner asks again
/// at the moment of removal.
public enum InUse {
  /// The app whose Chromium or Electron profile holds `path`, when that app is running.
  ///
  /// Chromium-based apps (Slack, Discord, VS Code, Docker Desktop and others) keep a
  /// `SingletonLock` link in their `~/Library/Application Support/<App>` folder while
  /// they run, pointing at `<host>-<pid>`. Only the link's target is read. A lock that
  /// names another computer (a migrated Mac) or a process that has exited is stale; a
  /// lock that can't be read counts as live.
  public static func liveAppLock(for rawPath: String, home: String) -> String? {
    let path = Protection.clean(rawPath)
    let support = Protection.clean(home) + "/Library/Application Support/"
    guard path.hasPrefix(support) else { return nil }
    let rest = path.dropFirst(support.count)
    guard let app = rest.split(separator: "/").first.map(String.init), !app.isEmpty else { return nil }
    let lock = support + app + "/SingletonLock"

    var info = stat()
    guard lstat(lock, &info) == 0 else { return nil }
    guard (info.st_mode & S_IFMT) == S_IFLNK,
          let target = try? FileManager.default.destinationOfSymbolicLink(atPath: lock) else {
      return app
    }
    guard let dash = target.lastIndex(of: "-"), let pid = pid_t(target[target.index(after: dash)...]) else {
      return app
    }
    let host = String(target[..<dash])
    if !host.isEmpty, !hostName.isEmpty, host.caseInsensitiveCompare(hostName) != .orderedSame { return nil }
    return isAlive(pid) ? app : nil
  }

  /// The running program whose executable lies at or inside `path`, if any. A toolkit,
  /// runtime or agent version that a process was started from is in use.
  public static func runningExecutable(inside rawPath: String, executables: [String]) -> String? {
    let path = Protection.clean(rawPath)
    let folder = path + "/"
    guard let match = executables.first(where: { executable in
      let cleaned = executable.hasPrefix("/var/") || executable.hasPrefix("/tmp/") ? Protection.clean(executable) : executable
      return cleaned == path || cleaned.hasPrefix(folder)
    }) else { return nil }
    return (match as NSString).lastPathComponent
  }

  /// The executable path of every process this user can see.
  static func executablePaths() -> [String] {
    let capacity = Int(proc_listallpids(nil, 0))
    guard capacity > 0 else { return [] }
    var pids = [pid_t](repeating: 0, count: capacity + 64)
    let filled = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
    guard filled > 0 else { return [] }
    var paths = Set<String>()
    var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    for pid in pids.prefix(filled) where pid > 0 {
      let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
      if length > 0 {
        paths.insert(String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self))
      }
    }
    return paths.sorted()
  }

  static func isAlive(_ pid: pid_t) -> Bool {
    guard pid > 0 else { return false }
    return kill(pid, 0) == 0 || errno == EPERM
  }

  static let hostName: String = {
    var buffer = [CChar](repeating: 0, count: 256)
    guard gethostname(&buffer, buffer.count) == 0 else { return "" }
    let length = buffer.firstIndex(of: 0) ?? buffer.count
    return String(decoding: buffer[..<length].map { UInt8(bitPattern: $0) }, as: UTF8.self)
  }()
}
