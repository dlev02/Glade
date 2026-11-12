import Darwin
import Foundation

/// One running process.
public struct ProcessSample: Codable, Sendable, Identifiable, Hashable {
  public var pid: Int32
  public var parentPID: Int32
  public var name: String
  public var executablePath: String?
  public var userID: UInt32
  /// Owned by the person running Glade, so it can be measured fully.
  public var isCurrentUser: Bool
  /// Share of one core: 100 means one full core, like Activity Monitor and `top`.
  /// `nil` when the process couldn’t be read.
  public var cpuPercent: Double?
  /// Physical footprint (Activity Monitor’s "Memory"). For restricted processes in a
  /// full listing this is resident size from `ps` instead.
  public var memoryBytes: Int64?
  public var threadCount: Int?
  public var startTime: Date?
  /// Share of the GPU’s time, 0–100. `nil` when the GPU doesn’t record it per process.
  public var gpuPercent: Double?
  /// Owned by another user (root, `_windowserver`), so usage can’t be read directly.
  public var isRestricted: Bool
  /// Energy the kernel has billed to the process since it started, in nanojoules.
  /// Counts the processor (and the neural engine); the graphics chip isn’t included.
  public var energyNanojoules: UInt64?
  /// Average power since the last listing, in watts. `nil` on the first listing.
  public var energyWatts: Double?

  public var id: Int32 { pid }

  public init(
    pid: Int32, parentPID: Int32, name: String, executablePath: String?, userID: UInt32, isCurrentUser: Bool,
    cpuPercent: Double?, memoryBytes: Int64?, threadCount: Int?, startTime: Date?, gpuPercent: Double?, isRestricted: Bool,
    energyNanojoules: UInt64? = nil, energyWatts: Double? = nil
  ) {
    self.pid = pid
    self.parentPID = parentPID
    self.name = name
    self.executablePath = executablePath
    self.userID = userID
    self.isCurrentUser = isCurrentUser
    self.cpuPercent = cpuPercent
    self.memoryBytes = memoryBytes
    self.threadCount = threadCount
    self.startTime = startTime
    self.gpuPercent = gpuPercent
    self.isRestricted = isRestricted
    self.energyNanojoules = energyNanojoules
    self.energyWatts = energyWatts
  }
}

/// What libproc reports for one process at one moment.
struct RawProcess: Sendable {
  var pid: pid_t
  var parentPID: pid_t
  var userID: uid_t
  var name: String
  var path: String?
  /// Microseconds since 1970; with the pid, identifies a process across samples.
  var startKey: UInt64
  var cpuNanos: UInt64?
  var footprint: UInt64?
  var threads: Int?
  var energy: UInt64?
}

/// Path and name never change for a process, so they’re read once per pid.
struct ProcessIdentity: Sendable {
  var startKey: UInt64
  var path: String?
  var name: String
}

/// Reads processes through libproc. Processes owned by other users refuse the task and
/// usage calls; they’re returned with whatever the BSD info call allows.
enum ProcessTable {
  static let currentUser = getuid()

  static func pids() -> [pid_t] {
    let capacity = Int(proc_listallpids(nil, 0))
    guard capacity > 0 else {
      SystemIssues.warn("proc_listallpids", "proc_listallpids failed (errno \(errno)); no processes listed")
      return []
    }
    var pids = [pid_t](repeating: 0, count: capacity + 64)
    let filled = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
    guard filled > 0 else { return [] }
    return Array(pids.prefix(filled).filter { $0 > 0 })
  }

  static func read(_ pid: pid_t, identities: inout [pid_t: ProcessIdentity]) -> RawProcess? {
    var all = proc_taskallinfo()
    let allSize = Int32(MemoryLayout<proc_taskallinfo>.stride)
    var bsd: proc_bsdinfo
    var threads: Int?
    if proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &all, allSize) == allSize {
      bsd = all.pbsd
      threads = Int(all.ptinfo.pti_threadnum)
    } else {
      bsd = proc_bsdinfo()
      let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.stride)
      guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, bsdSize) == bsdSize else { return shortInfo(pid, identities: &identities) }
    }
    let startKey = UInt64(bsd.pbi_start_tvsec) * 1_000_000 + UInt64(bsd.pbi_start_tvusec)

    let identity: ProcessIdentity
    if let cached = identities[pid], cached.startKey == startKey {
      identity = cached
    } else {
      let path = executablePath(pid)
      var name = path.map(displayName) ?? ""
      if name.isEmpty { name = CText.string(bsd.pbi_name) }
      if name.isEmpty { name = CText.string(bsd.pbi_comm) }
      identity = ProcessIdentity(startKey: startKey, path: path, name: name)
      identities[pid] = identity
    }

    // Version 6 adds the energy counter; the call costs the same as version 4.
    var usage = rusage_info_v6()
    let usageResult = withUnsafeMutablePointer(to: &usage) { pointer in
      pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
    }
    let readable = usageResult == 0
    return RawProcess(
      pid: pid, parentPID: pid_t(bsd.pbi_ppid), userID: bsd.pbi_uid, name: identity.name, path: identity.path,
      startKey: startKey,
      cpuNanos: readable ? MachTime.nanos(fromTicks: usage.ri_user_time + usage.ri_system_time) : nil,
      footprint: readable ? usage.ri_phys_footprint : nil,
      threads: threads,
      energy: readable ? usage.ri_energy_nj : nil
    )
  }

  /// The minimal call every process allows.
  private static func shortInfo(_ pid: pid_t, identities: inout [pid_t: ProcessIdentity]) -> RawProcess? {
    var short = proc_bsdshortinfo()
    let size = Int32(MemoryLayout<proc_bsdshortinfo>.stride)
    guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &short, size) == size else { return nil }
    let path = identities[pid]?.path ?? executablePath(pid)
    var name = path.map(displayName) ?? ""
    if name.isEmpty { name = CText.string(short.pbsi_comm) }
    identities[pid] = ProcessIdentity(startKey: 0, path: path, name: name)
    return RawProcess(
      pid: pid, parentPID: pid_t(short.pbsi_ppid), userID: short.pbsi_uid, name: name, path: path,
      startKey: 0, cpuNanos: nil, footprint: nil, threads: nil
    )
  }

  /// The executable’s file name, except for tools installed as a bare version number
  /// (`~/.local/share/claude/versions/2.1.319`), which take the name of the folder above.
  static func displayName(_ path: String) -> String {
    let components = path.split(separator: "/")
    guard let last = components.last else { return "" }
    func isVersion(_ text: Substring) -> Bool { text.contains(".") && text.allSatisfy { $0.isNumber || $0 == "." } }
    guard isVersion(last) else { return String(last) }
    for component in components.dropLast().reversed()
    where !isVersion(component) && !["versions", "bin", "current", "libexec"].contains(component.lowercased()) {
      return String(component)
    }
    return String(last)
  }

  static func executablePath(_ pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    guard length > 0 else { return nil }
    return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
  }

  /// One `ps` call for the usage of processes libproc can’t read. `/bin/ps` is setuid
  /// root, so it sees everything. Only used for full listings, never in a periodic loop.
  static func psUsage() async -> [pid_t: (rssBytes: Int64, cpuPercent: Double)] {
    guard let result = try? await Shell.run("/bin/ps", ["-axo", "pid=,rss=,pcpu="], timeout: 5, quiet: true), result.succeeded else {
      SystemIssues.warn("ps", "/bin/ps -axo pid,rss,pcpu failed; other users' processes show no usage")
      return [:]
    }
    var usage: [pid_t: (Int64, Double)] = [:]
    for line in result.stdout.split(separator: "\n") {
      let fields = line.split(separator: " ", omittingEmptySubsequences: true)
      guard fields.count >= 3, let pid = pid_t(fields[0]), let rss = Int64(fields[1]), let cpu = Double(fields[2]) else { continue }
      usage[pid] = (rss * 1024, cpu)
    }
    return usage
  }
}
