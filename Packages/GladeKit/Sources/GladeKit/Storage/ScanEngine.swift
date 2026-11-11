import AppKit
import Foundation

/// What's running right now, so a scan can tell which caches are in use.
public struct RunningApps: Sendable {
  public var bundleIDs: Set<String>
  public var processNames: Set<String>
  /// Lowercased app names, for owners known only by the folder they write to.
  public var appNames: Set<String>

  public init(bundleIDs: Set<String> = [], processNames: Set<String> = [], appNames: Set<String> = []) {
    self.bundleIDs = bundleIDs
    self.processNames = processNames
    self.appNames = appNames
  }

  public static func current() -> RunningApps {
    var bundleIDs = Set<String>(), appNames = Set<String>(), processNames = Set<String>()
    for app in NSWorkspace.shared.runningApplications {
      if let id = app.bundleIdentifier { bundleIDs.insert(id.lowercased()) }
      if let name = app.localizedName { appNames.insert(name.lowercased()) }
      if let executable = app.executableURL?.lastPathComponent { processNames.insert(executable.lowercased()) }
    }
    for name in ProcessNames.all() { processNames.insert(name.lowercased()) }
    return RunningApps(bundleIDs: bundleIDs, processNames: processNames, appNames: appNames)
  }

  private static func normalise(_ name: String) -> String {
    String(name.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
  }

  /// The running app or process that owns something, if any.
  public func runningName(of owner: Owner) -> String? {
    for id in owner.bundleIDs {
      let wanted = id.lowercased()
      if wanted.hasSuffix("*") {
        let prefix = String(wanted.dropLast())
        if bundleIDs.contains(where: { $0.hasPrefix(prefix) }) { return owner.name }
      } else if bundleIDs.contains(wanted) {
        return owner.name
      }
    }
    for name in owner.processNames where processNames.contains(name.lowercased()) { return owner.name }
    // Owners known only by the folder they write to ("claude-cli-nodejs", "aside-memory"):
    // treat the folder as in use when its name starts with a running app's or tool's name.
    if owner.bundleIDs.isEmpty || owner.bundleIDs.allSatisfy({ !$0.contains(".") }) {
      let folder = Self.normalise(owner.bundleIDs.first ?? owner.name)
      for name in appNames.union(processNames) {
        let candidate = Self.normalise(name)
        if candidate.count >= 4, folder.hasPrefix(candidate) { return name.capitalized }
      }
    }
    return nil
  }
}

enum ProcessNames {
  /// The names of every process this user can see.
  static func all() -> [String] {
    let capacity = Int(proc_listallpids(nil, 0))
    guard capacity > 0 else { return [] }
    var pids = [pid_t](repeating: 0, count: capacity + 64)
    let filled = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
    guard filled > 0 else { return [] }
    var names: [String] = []
    var buffer = [CChar](repeating: 0, count: 256)
    for pid in pids.prefix(filled) where pid > 0 {
      let length = proc_name(pid, &buffer, UInt32(buffer.count))
      if length > 0 {
        names.append(String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self))
      }
    }
    return names
  }
}

/// A thread-safe flag scanners poll so a scan can be stopped.
public final class CancelFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false

  public init() {}
  public var isCancelled: Bool { lock.withLock { cancelled } }
  public func cancel() { lock.withLock { cancelled = true } }
}

public struct ScanProgress: Sendable {
  public var scanner: String
  public var message: String
  public var finished: Int
  public var total: Int
}

/// Everything a scanner needs. Scanners never reach outside this.
public struct ScanContext: Sendable {
  public let config: GladeConfig
  public let protection: Protection
  public let home: String
  public let now: Date
  public let running: RunningApps
  public let cancel: CancelFlag
  public let progress: @Sendable (ScanProgress) -> Void
  private let limiter: Limiter

  public init(
    config: GladeConfig, protection: Protection? = nil, home: String = NSHomeDirectory(),
    now: Date = Date(), running: RunningApps = .current(), cancel: CancelFlag = CancelFlag(),
    concurrency: Int = 6, progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
  ) {
    self.config = config
    self.protection = protection ?? Protection(config: config, home: home)
    self.home = home
    self.now = now
    self.running = running
    self.cancel = cancel
    self.progress = progress
    limiter = Limiter(concurrency)
  }

  /// Measures paths off the main thread, a few at a time, at background priority.
  /// - Parameter checkingLibraries: Pass false for places that hold libraries of their
  ///   own, so those are counted instead of flagged.
  public func measure(_ paths: [String], checkingLibraries: Bool = true) async -> Measure {
    await limiter.acquire()
    let protection: Protection? = checkingLibraries ? self.protection : nil
    let cancel = self.cancel
    let result = await Task.detached(priority: .utility) {
      DiskWalk.measure(paths, protection: protection) { cancel.isCancelled }
    }.value
    await limiter.release()
    return result
  }

  /// Runs blocking file-system work at background priority, a few at a time.
  public func background<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    await limiter.acquire()
    let result = await Task.detached(priority: .utility, operation: work).value
    await limiter.release()
    return result
  }

  public func days(since date: Date?) -> Int? {
    guard let date else { return nil }
    return max(0, Int(now.timeIntervalSince(date) / 86_400))
  }

  public func tilde(_ path: String) -> String {
    path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
  }
}

actor Limiter {
  private var available: Int
  private var waiters: [CheckedContinuation<Void, Never>] = []

  init(_ count: Int) { available = max(1, count) }

  func acquire() async {
    if available > 0 {
      available -= 1
      return
    }
    await withCheckedContinuation { waiters.append($0) }
  }

  func release() {
    if waiters.isEmpty {
      available += 1
    } else {
      waiters.removeFirst().resume()
    }
  }
}

/// One way of finding removable things.
public protocol StorageScanner: Sendable {
  var id: String { get }
  /// What the scanner is looking at, for progress display.
  var title: String { get }
  /// Scanners that take a long time (duplicates, whole-disk walks) run only when asked.
  var isDeep: Bool { get }
  func scan(_ context: ScanContext) async -> [Finding]
}

extension StorageScanner {
  public var isDeep: Bool { false }
}

/// Runs scanners and assembles their findings into one result.
public enum ScanEngine {
  /// The scanners a normal scan runs, in priority order: when two scanners report the
  /// same path, the earlier one wins.
  public static var standard: [any StorageScanner] {
    [
      CatalogScanner(),
      AgentHistoryScanner(),
      SimulatorScanner(),
      WorktreeScanner(),
      ProjectScanner(),
      EditorExtensionScanner(),
      DownloadsScanner(),
      AppCopyScanner(),
      AppLeftoverScanner(),
      LargeFileScanner(),
      DuplicateScanner(),
    ]
  }

  public static func run(
    config: GladeConfig = ConfigStore.load(),
    scanners: [any StorageScanner]? = nil,
    deep: Bool = false,
    cancel: CancelFlag = CancelFlag(),
    progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
  ) async -> ScanResult {
    let started = Date()
    let context = ScanContext(config: config, cancel: cancel, progress: progress)
    let active = (scanners ?? standard).filter { deep || !$0.isDeep }
    let fullDiskAccess = FullDiskAccess.isGranted
    Log.info(.scan, "Scan started: \(active.count) scanners, Full Disk Access \(fullDiskAccess ? "on" : "off")")

    var collected: [(order: Int, findings: [Finding], id: String, seconds: Double)] = []
    await withTaskGroup(of: (Int, [Finding], String, Double).self) { group in
      for (order, scanner) in active.enumerated() {
        group.addTask {
          let begin = Date()
          let findings = await scanner.scan(context)
          return (order, findings, scanner.id, Date().timeIntervalSince(begin))
        }
      }
      var finished = 0
      for await (order, findings, id, seconds) in group {
        finished += 1
        collected.append((order, findings, id, seconds))
        let bytes = findings.reduce(0) { $0 + $1.bytes }
        Log.info(.scan, "Scanner \(id): \(findings.count) findings, \(Format.bytes(bytes)), \(String(format: "%.1f", seconds))s")
        progress(ScanProgress(scanner: id, message: "", finished: finished, total: active.count))
      }
    }

    var findings: [Finding] = []
    var claimed: [String: String] = [:]
    for batch in collected.sorted(by: { $0.order < $1.order }) {
      for finding in batch.findings where !config.ignoredCategories.contains(finding.category) {
        // Belt and braces: a scanner bug must not surface a protected path.
        guard finding.paths.allSatisfy({ context.protection.canScan($0) }) else {
          Log.error(.safety, "Dropped finding \(finding.ruleID) from \(batch.id): it points into a protected zone")
          continue
        }
        guard finding.paths.allSatisfy({ claimed[$0] == nil }) else { continue }
        for path in finding.paths { claimed[path] = finding.id }
        findings.append(finding)
      }
    }
    // A finding that sits inside another one (a worktree's node_modules) is still
    // offered, but its space is already counted by the one that contains it.
    let roots = findings.flatMap { finding in finding.paths.map { ($0 + "/", finding.id) } }
    for index in findings.indices where !findings[index].paths.isEmpty {
      let finding = findings[index]
      let container = roots.first { root, owner in
        owner != finding.id && finding.paths.allSatisfy { $0.hasPrefix(root) }
      }
      findings[index].within = container?.1
    }
    findings.sort { $0.bytes > $1.bytes }

    var skipped: [SkippedArea] = []
    if !fullDiskAccess {
      skipped.append(SkippedArea(
        path: "~/Library and other guarded folders",
        reason: "Full Disk Access is off, so the Trash, app containers and some app data couldn't be measured."
      ))
    }
    let result = ScanResult(
      started: started, finished: Date(), volume: .current(), findings: findings, skipped: skipped,
      timings: Dictionary(uniqueKeysWithValues: collected.map { ($0.id, $0.seconds) }),
      hasFullDiskAccess: fullDiskAccess
    )
    Log.info(.scan, "Scan finished: \(findings.count) findings, \(Format.bytes(result.totalBytes)) in \(String(format: "%.1f", result.finished.timeIntervalSince(started)))s\(cancel.isCancelled ? " (cancelled)" : "")")
    return result
  }

  /// Saves a result so a later `clean` can refer to findings by identifier.
  public static func save(_ result: ScanResult) {
    do {
      try JSONFiles.write(result, to: GladePaths.lastScan)
    } catch {
      Log.error(.scan, "Couldn’t save scan result: \(error)")
    }
  }

  public static func loadLast() -> ScanResult? {
    JSONFiles.read(ScanResult.self, from: GladePaths.lastScan)
  }
}
