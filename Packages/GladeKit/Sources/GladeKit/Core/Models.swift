import Foundation

// MARK: - Classification

/// The kinds of things that take up space. Every finding belongs to exactly one.
public enum StorageCategory: String, Codable, Sendable, CaseIterable, Identifiable {
  case temporaryFiles
  case appCaches
  case browserCaches
  case logs
  case trash
  case developerCaches
  case packageCaches
  case buildOutputs
  case projectDependencies
  case xcode
  case simulators
  case emulators
  case sdks
  case aiModels
  case agentHistory
  case agentWorktrees
  case editorExtensions
  case appLeftovers
  case appCopies
  case downloads
  case mediaDownloads
  case largeFiles
  case duplicates
  case games
  case deviceBackups
  case documentVersions

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .temporaryFiles: "Temporary Files"
    case .appCaches: "App Caches"
    case .browserCaches: "Browser Caches"
    case .logs: "Logs & Crash Reports"
    case .trash: "Trash"
    case .developerCaches: "Developer Tool Caches"
    case .packageCaches: "Package Caches"
    case .buildOutputs: "Build Outputs"
    case .projectDependencies: "Project Dependencies"
    case .xcode: "Xcode Build Data"
    case .simulators: "Simulators"
    case .emulators: "Emulators & Containers"
    case .sdks: "Toolkits & SDKs"
    case .aiModels: "AI Models"
    case .agentHistory: "Agent & Editor History"
    case .agentWorktrees: "Agent Worktrees"
    case .editorExtensions: "Editor Extensions"
    case .appLeftovers: "App Leftovers"
    case .appCopies: "App Copies"
    case .downloads: "Downloads & Installers"
    case .mediaDownloads: "Podcasts & Media Downloads"
    case .largeFiles: "Large & Old Files"
    case .duplicates: "Duplicates"
    case .games: "Games"
    case .deviceBackups: "Device Backups"
    case .documentVersions: "Document Versions & Snapshots"
    }
  }
}

/// What it takes to get something back after it's removed.
public enum Recovery: String, Codable, Sendable, CaseIterable {
  /// The owning app or tool rebuilds it by itself the next time it's needed.
  case automatic
  /// It downloads again when needed, which costs time and bandwidth.
  case redownload
  /// It comes back when you run a command or reinstall (for example `npm install`).
  case reinstall
  /// Nothing recreates it. Once it leaves the Trash it's gone.
  case permanent

  public var title: String {
    switch self {
    case .automatic: "Rebuilds itself"
    case .redownload: "Downloads again"
    case .reinstall: "Reinstall to restore"
    case .permanent: "Permanent"
    }
  }
}

/// How much thought removing something deserves.
public enum Risk: String, Codable, Sendable, CaseIterable, Comparable {
  /// No lasting effect beyond a slower first launch or build.
  case safe
  /// Costs time, bandwidth or some convenience (signed-in state, history) to restore.
  case caution
  /// Could be something you made or want. Never selected for you.
  case personal

  private var rank: Int {
    switch self {
    case .safe: 0
    case .caution: 1
    case .personal: 2
    }
  }

  public static func < (lhs: Risk, rhs: Risk) -> Bool { lhs.rank < rhs.rank }

  public var title: String {
    switch self {
    case .safe: "Safe"
    case .caution: "Caution"
    case .personal: "Review"
    }
  }
}

// MARK: - Findings

/// The app or tool that owns a location, used to tell whether it's in use.
public struct Owner: Codable, Sendable, Hashable {
  public var name: String
  public var bundleIDs: [String]
  public var processNames: [String]

  public init(_ name: String, bundleIDs: [String] = [], processNames: [String] = []) {
    self.name = name
    self.bundleIDs = bundleIDs
    self.processNames = processNames
  }
}

/// A reason something can't be removed right now.
public struct Blocker: Codable, Sendable, Hashable {
  public enum Kind: String, Codable, Sendable {
    case appRunning, uncommittedWork, needsAdmin, needsFullDiskAccess, inUse, reportOnly
  }

  public var kind: Kind
  public var detail: String

  public init(_ kind: Kind, _ detail: String) {
    self.kind = kind
    self.detail = detail
  }
}

/// How a finding is removed. Commands are a fixed list defined in code; nothing a
/// model or a config file says can add to it.
public enum RemovalMethod: Codable, Sendable, Hashable {
  /// Removed immediately. Used only for things that rebuild or download again.
  case delete
  /// Moved to the Trash, where it can be put back.
  case trash
  /// `xcrun simctl delete <udid>`
  case simulatorDevice(udid: String)
  /// `xcrun simctl erase <udid>`: wipes a simulator's apps and data but keeps the device.
  case simulatorErase(udid: String)
  /// `xcrun simctl delete unavailable`
  case unavailableSimulators
  /// `xcrun simctl --set <previews|testing> delete all`: the throwaway simulators Xcode
  /// makes for SwiftUI previews and for running tests in parallel.
  case simulatorSet(name: String)
  /// `xcrun simctl runtime delete <identifier>`: removes a downloaded simulator system version.
  case simulatorRuntime(identifier: String)
  /// `git worktree remove <path>`, run in the owning repository.
  case gitWorktree(repository: String)
  /// Emptying the Trash itself.
  case emptyTrash
}

/// One removable thing: a folder, a file, or a small set of paths that belong together.
public struct Finding: Codable, Sendable, Identifiable, Hashable {
  /// Stable across scans: derived from the rule and the path.
  public var id: String
  public var ruleID: String
  public var category: StorageCategory
  public var title: String
  /// One plain sentence: what this is and what happens if it's removed.
  public var detail: String
  public var paths: [String]
  /// Remove what's inside each path but keep the folder itself.
  public var contentsOnly: Bool
  public var bytes: Int64
  public var fileCount: Int
  /// The most recent time anything inside was modified or read.
  public var lastUsed: Date?
  public var recovery: Recovery
  public var risk: Risk
  public var owner: Owner?
  public var blockers: [Blocker]
  public var method: RemovalMethod
  /// Facts that led to this classification, shown to people and to the assistant.
  public var evidence: [String]
  /// The project this belongs to, for build outputs, dependencies and worktrees.
  public var project: String?
  /// For duplicates: the copy that stays.
  public var keeps: String?
  /// The gentlest clean level allowed to select this without being asked, or `nil`
  /// when only a person may select it.
  public var autoLevel: CleanLevel?
  /// How long it must have sat untouched before a clean level selects it.
  public var idleDaysRequired: Int
  /// The owning app must be closed before this is removed.
  public var needsOwnerClosed: Bool
  /// The finding this one sits inside, if any. Its space is counted there.
  public var within: String?

  public init(
    id: String, ruleID: String, category: StorageCategory, title: String, detail: String,
    paths: [String], contentsOnly: Bool = false, bytes: Int64, fileCount: Int = 0,
    lastUsed: Date? = nil, recovery: Recovery, risk: Risk, owner: Owner? = nil,
    blockers: [Blocker] = [], method: RemovalMethod, evidence: [String] = [],
    project: String? = nil, keeps: String? = nil, autoLevel: CleanLevel? = nil, idleDaysRequired: Int = 0,
    needsOwnerClosed: Bool = false
  ) {
    self.id = id
    self.ruleID = ruleID
    self.category = category
    self.title = title
    self.detail = detail
    self.paths = paths
    self.contentsOnly = contentsOnly
    self.bytes = bytes
    self.fileCount = fileCount
    self.lastUsed = lastUsed
    self.recovery = recovery
    self.risk = risk
    self.owner = owner
    self.blockers = blockers
    self.method = method
    self.evidence = evidence
    self.project = project
    self.keeps = keeps
    self.autoLevel = autoLevel
    self.idleDaysRequired = idleDaysRequired
    self.needsOwnerClosed = needsOwnerClosed
  }

  public var isBlocked: Bool { !blockers.isEmpty }

  public func idleDays(asOf now: Date = Date()) -> Int? {
    guard let lastUsed else { return nil }
    return max(0, Int(now.timeIntervalSince(lastUsed) / 86_400))
  }

  /// Finding identifiers are short hashes so they're easy to pass on a command line
  /// and impossible to mistake for a path.
  public static func makeID(rule: String, path: String) -> String {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in "\(rule)\u{1F}\(path)".utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 0x0000_0100_0000_01B3
    }
    return String(hash, radix: 36)
  }
}

// MARK: - Scan results

public struct VolumeInfo: Codable, Sendable {
  public var name: String
  public var totalBytes: Int64
  /// Free space right now, as the file system counts it.
  public var freeBytes: Int64
  /// Free space including what macOS will clear on demand (purgeable).
  public var availableBytes: Int64

  public var usedBytes: Int64 { max(0, totalBytes - availableBytes) }
  public var purgeableBytes: Int64 { max(0, availableBytes - freeBytes) }
  public var freeFraction: Double { totalBytes > 0 ? Double(availableBytes) / Double(totalBytes) : 0 }

  public init(name: String, totalBytes: Int64, freeBytes: Int64, availableBytes: Int64) {
    self.name = name
    self.totalBytes = totalBytes
    self.freeBytes = freeBytes
    self.availableBytes = availableBytes
  }

  public static func current(path: String = NSHomeDirectory()) -> VolumeInfo {
    let url = URL(fileURLWithPath: path)
    let values = try? url.resourceValues(forKeys: [
      .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
      .volumeAvailableCapacityForImportantUsageKey,
    ])
    let free = Int64(values?.volumeAvailableCapacity ?? 0)
    return VolumeInfo(
      name: values?.volumeName ?? "Macintosh HD",
      totalBytes: Int64(values?.volumeTotalCapacity ?? 0),
      freeBytes: free,
      availableBytes: max(free, values?.volumeAvailableCapacityForImportantUsage ?? 0)
    )
  }
}

/// A place the scan couldn't read, and why.
public struct SkippedArea: Codable, Sendable, Hashable {
  public var path: String
  public var reason: String

  public init(path: String, reason: String) {
    self.path = path
    self.reason = reason
  }
}

public struct ScanResult: Codable, Sendable, Identifiable {
  public var id: String
  public var started: Date
  public var finished: Date
  public var volume: VolumeInfo
  public var findings: [Finding]
  public var skipped: [SkippedArea]
  /// Seconds each scanner took, for diagnostics.
  public var timings: [String: Double]
  public var hasFullDiskAccess: Bool

  public init(
    id: String = UUID().uuidString, started: Date, finished: Date, volume: VolumeInfo,
    findings: [Finding], skipped: [SkippedArea], timings: [String: Double], hasFullDiskAccess: Bool
  ) {
    self.id = id
    self.started = started
    self.finished = finished
    self.volume = volume
    self.findings = findings
    self.skipped = skipped
    self.timings = timings
    self.hasFullDiskAccess = hasFullDiskAccess
  }

  /// Everything found, with nested findings counted once.
  public var totalBytes: Int64 { findings.filter { $0.within == nil }.reduce(0) { $0 + $1.bytes } }

  public func bytes(in category: StorageCategory) -> Int64 {
    findings.filter { $0.category == category && $0.within == nil }.reduce(0) { $0 + $1.bytes }
  }

  public func finding(_ id: String) -> Finding? { findings.first { $0.id == id } }

  /// The scan without the findings a clean removed, so they aren't offered again.
  public func removing(_ receipt: Receipt) -> ScanResult {
    let gone = Set(receipt.entries.compactMap { entry -> String? in
      switch entry.outcome {
      case .deleted, .trashed: entry.id
      default: nil
      }
    })
    // Anything inside a removed finding went with it.
    let roots = findings.filter { gone.contains($0.id) }.flatMap { $0.paths.map { $0 + "/" } }
    var copy = self
    copy.findings.removeAll { finding in
      gone.contains(finding.id)
        || (!finding.paths.isEmpty && finding.paths.allSatisfy { path in roots.contains { path.hasPrefix($0) } })
    }
    copy.volume = .current()
    return copy
  }
}

// MARK: - Cleaning

public enum Initiator: Codable, Sendable, Hashable {
  case user
  case commandLine
  case assistant(provider: String)
  case automation(rule: String)

  public var title: String {
    switch self {
    case .user: "You"
    case .commandLine: "Command line"
    case .assistant(let provider): "Assistant (\(provider))"
    case .automation(let rule): "Automation (\(rule))"
    }
  }
}

public enum RemovalOutcome: Codable, Sendable, Hashable {
  case deleted
  /// Moved to the Trash; each original path maps to where it now sits.
  case trashed(locations: [String: String])
  case skipped(reason: String)
  case failed(reason: String)
  /// A dry run: what would have happened.
  case wouldRemove

  public var freedSpace: Bool {
    if case .deleted = self { return true }
    return false
  }
}

public struct ReceiptEntry: Codable, Sendable, Identifiable {
  public var id: String
  public var title: String
  public var category: StorageCategory
  public var paths: [String]
  public var bytes: Int64
  public var outcome: RemovalOutcome

  public init(id: String, title: String, category: StorageCategory, paths: [String], bytes: Int64, outcome: RemovalOutcome) {
    self.id = id
    self.title = title
    self.category = category
    self.paths = paths
    self.bytes = bytes
    self.outcome = outcome
  }
}

/// The record of one clean: what was removed, how, and who asked.
public struct Receipt: Codable, Sendable, Identifiable {
  public var id: String
  public var date: Date
  public var initiator: Initiator
  public var dryRun: Bool
  public var entries: [ReceiptEntry]
  public var freeBefore: Int64
  public var freeAfter: Int64

  public init(id: String, date: Date, initiator: Initiator, dryRun: Bool, entries: [ReceiptEntry], freeBefore: Int64, freeAfter: Int64) {
    self.id = id
    self.date = date
    self.initiator = initiator
    self.dryRun = dryRun
    self.entries = entries
    self.freeBefore = freeBefore
    self.freeAfter = freeAfter
  }

  public var removedBytes: Int64 {
    entries.reduce(0) {
      switch $1.outcome {
      case .deleted, .trashed, .wouldRemove: $0 + $1.bytes
      default: $0
      }
    }
  }

  /// Space actually freed: what was deleted. Things in the Trash still take up space
  /// until the Trash is emptied, so they don't count here.
  public var freedBytes: Int64 {
    entries.reduce(0) {
      if case .deleted = $1.outcome { return $0 + $1.bytes }
      return $0
    }
  }

  public var trashedBytes: Int64 {
    entries.reduce(0) {
      if case .trashed = $1.outcome { return $0 + $1.bytes }
      return $0
    }
  }

  public var failures: [ReceiptEntry] {
    entries.filter {
      if case .failed = $0.outcome { return true }
      return false
    }
  }
}
