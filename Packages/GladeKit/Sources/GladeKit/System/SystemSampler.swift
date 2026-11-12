import Darwin
import Foundation
import Synchronization

/// Takes readings of the Mac. Processor, per-process and GPU figures are rates, so the
/// sampler remembers the previous counters and reports the change since the last call.
/// It owns no timers or threads: callers decide how often to sample.
///
/// Use one sampler per cadence (the menu bar loop, a window, a command): two callers
/// sharing one would each see only the interval since the other’s last call.
public final class SystemSampler: Sendable {
  public static let shared = SystemSampler()

  private struct ProcessMark: Sendable {
    var startKey: UInt64
    var cpuNanos: UInt64
    var energy: UInt64?
  }

  private struct State {
    var ticks: [CoreTicks]?
    var ticksTime: UInt64 = 0
    var processTime: UInt64 = 0
    var processCPU: [pid_t: ProcessMark] = [:]
    var gpuTimes: [pid_t: UInt64]?
    var identities: [pid_t: ProcessIdentity] = [:]
    var volume: VolumeInfo?
    var volumeTime: UInt64 = 0
    var power: PowerStats?
    var powerTime: UInt64 = 0
  }

  /// Disk free space changes slowly and its query can take several milliseconds.
  static let volumeRefresh: UInt64 = 30_000_000_000
  /// Power state changes rarely; the power-source query is an IPC round trip.
  static let powerRefresh: UInt64 = 10_000_000_000

  private let state = Mutex(State())
  private let gpu = GPURegistry()
  private let simulatorTracker = SimulatorTracker()

  public init() {}

  // MARK: Snapshot

  /// One reading of the whole Mac. The first call waits 200 ms to have an interval to
  /// measure processor use over; later calls return immediately.
  public func snapshot() async -> SystemSnapshot {
    if state.withLock({ $0.ticks == nil }) {
      let ticks = HostReader.coreTicks()
      let now = MachTime.now()
      state.withLock {
        $0.ticks = ticks
        $0.ticksTime = now
      }
      try? await Task.sleep(for: .milliseconds(200))
    }
    return snapshotNow()
  }

  /// One reading without waiting. Processor use reads 0 on a sampler’s first call.
  public func snapshotNow() -> SystemSnapshot {
    let ticks = HostReader.coreTicks()
    let now = MachTime.now()
    let cached = state.withLock { state -> (previous: [CoreTicks]?, previousTime: UInt64, volume: VolumeInfo?, power: PowerStats?) in
      let previous = (state.ticks, state.ticksTime)
      if let ticks {
        state.ticks = ticks
        state.ticksTime = now
      }
      let volume = now &- state.volumeTime < Self.volumeRefresh ? state.volume : nil
      let power = now &- state.powerTime < Self.powerRefresh ? state.power : nil
      return (previous.0, previous.1, volume, power)
    }

    let volume = cached.volume ?? VolumeInfo.current()
    let power = cached.power ?? HostReader.power()
    if cached.volume == nil || cached.power == nil {
      state.withLock {
        if cached.volume == nil {
          $0.volume = volume
          $0.volumeTime = now
        }
        if cached.power == nil {
          $0.power = power
          $0.powerTime = now
        }
      }
    }

    let bootDate = HostReader.bootDate
    let date = Date()
    return SystemSnapshot(
      date: date,
      intervalSeconds: cached.previousTime > 0 ? Double(now &- cached.previousTime) / 1e9 : 0,
      cpu: HostReader.cpu(from: cached.previous, to: ticks),
      memory: HostReader.memory(),
      gpu: gpu.stats(),
      disk: volume,
      thermal: ThermalState(ProcessInfo.processInfo.thermalState),
      power: power,
      bootDate: bootDate,
      uptimeSeconds: bootDate.map { date.timeIntervalSince($0) } ?? ProcessInfo.processInfo.systemUptime
    )
  }

  // MARK: Processes

  /// Every process with its processor, memory and GPU use since the last call.
  ///
  /// - Parameter full: Also fill in usage for other users' processes from one `ps` call.
  ///   Leave off in periodic loops.
  /// The first call waits half a second to have an interval to measure over.
  public func processes(full: Bool = false) async -> [ProcessSample] {
    if state.withLock({ $0.processTime == 0 }) {
      _ = processesNow()
      try? await Task.sleep(for: .milliseconds(500))
    }
    var list = processesNow()
    if full {
      let usage = await ProcessTable.psUsage()
      for index in list.indices where list[index].isRestricted {
        guard let value = usage[list[index].pid] else { continue }
        list[index].memoryBytes = value.rssBytes
        list[index].cpuPercent = value.cpuPercent
      }
    }
    return list
  }

  /// Processes without waiting. Processor and GPU use are `nil` and 0 on the first call.
  public func processesNow() -> [ProcessSample] {
    let pids = ProcessTable.pids()
    let gpuTimes = gpu.processGPUTimes()
    var identities = state.withLock { $0.identities }
    var raws: [RawProcess] = []
    raws.reserveCapacity(pids.count)
    for pid in pids {
      if let raw = ProcessTable.read(pid, identities: &identities) { raws.append(raw) }
    }
    let now = MachTime.now()
    let live = Set(raws.map(\.pid))
    identities = identities.filter { live.contains($0.key) }
    var marks: [pid_t: ProcessMark] = [:]
    marks.reserveCapacity(raws.count)
    for raw in raws {
      if let cpu = raw.cpuNanos { marks[raw.pid] = ProcessMark(startKey: raw.startKey, cpuNanos: cpu, energy: raw.energy) }
    }
    let previous = state.withLock { state -> (cpu: [pid_t: ProcessMark], gpu: [pid_t: UInt64]?, time: UInt64) in
      let old = (state.processCPU, state.gpuTimes, state.processTime)
      state.processCPU = marks
      state.gpuTimes = gpuTimes
      state.processTime = now
      state.identities = identities
      return old
    }

    let elapsed = previous.time > 0 ? Double(now &- previous.time) : 0
    let user = ProcessTable.currentUser
    return raws.map { raw in
      var cpu: Double?
      var watts: Double?
      if let nanos = raw.cpuNanos, elapsed > 0 {
        if let mark = previous.cpu[raw.pid], mark.startKey == raw.startKey {
          cpu = Double(nanos &- min(nanos, mark.cpuNanos)) / elapsed * 100
          // Nanojoules over nanoseconds is watts.
          if let energy = raw.energy, let before = mark.energy { watts = Double(energy &- min(energy, before)) / elapsed }
        } else {
          cpu = 0
          watts = raw.energy == nil ? nil : 0
        }
      }
      var gpuPercent: Double?
      if let gpuTimes {
        gpuPercent = 0
        if elapsed > 0, let current = gpuTimes[raw.pid], let old = previous.gpu?[raw.pid], current > old {
          gpuPercent = min(100, Double(current - old) / elapsed * 100)
        }
      }
      return ProcessSample(
        pid: raw.pid, parentPID: raw.parentPID, name: raw.name, executablePath: raw.path,
        userID: raw.userID, isCurrentUser: raw.userID == user, cpuPercent: cpu,
        memoryBytes: raw.footprint.map { Int64(clamping: $0) }, threadCount: raw.threads,
        startTime: raw.startKey > 0 ? Date(timeIntervalSince1970: Double(raw.startKey) / 1_000_000) : nil,
        gpuPercent: gpuPercent, isRestricted: raw.cpuNanos == nil,
        energyNanojoules: raw.energy, energyWatts: watts
      )
    }
  }

  // MARK: Apps and context

  /// Processes folded into apps, with audio, sleep, window and activity details.
  public func apps(full: Bool = false, activity: ActivityLog = .shared) async -> [AppUsage] {
    AppGrouper.group(await processes(full: full), activity: activity)
  }

  // MARK: Simulators

  /// Each booted simulator device with its memory, processor and GPU use, and whether
  /// anything is using it. The apps listing shows all of them as one "Simulator devices" row.
  public func simulators(activity: ActivityLog = .shared) async -> [SimulatorUsage] {
    await simulatorBreakdown(activity: activity).devices
  }

  /// The apps and, when Simulator is running, its devices, from one process listing:
  /// for the live screens, which refresh both every few seconds.
  public func appsAndSimulators(activity: ActivityLog = .shared) async -> (apps: [AppUsage], simulators: [SimulatorUsage]) {
    let list = await processes()
    let apps = AppGrouper.group(list, activity: activity)
    // Only worth working out when simulators are actually running.
    guard apps.contains(where: { $0.name.localizedCaseInsensitiveContains("simulator") }) else { return (apps, []) }
    return (apps, await simulatorBreakdown(processes: list, activity: activity).devices)
  }

  /// The devices plus the CoreSimulator services they share.
  ///
  /// Not for periodic loops: the first call per device set runs `simctl list` (a few
  /// hundred milliseconds); later calls reuse the names and the process-to-device mapping.
  /// - Parameter processes: A listing already taken, so one interval serves both the
  ///   apps listing and the breakdown. Takes a fresh one when `nil`.
  public func simulatorBreakdown(processes: [ProcessSample]? = nil, activity: ActivityLog = .shared) async -> SimulatorBreakdown {
    let list: [ProcessSample]
    if let processes {
      list = processes
    } else {
      list = await self.processes()
    }
    return await simulatorTracker.breakdown(processes: list, activity: activity)
  }

  /// What the person is doing right now, built from a fresh apps listing.
  public func context(activity: ActivityLog = .shared) async -> ActivityContext {
    let apps = await apps(activity: activity)
    return ActivityContext.current(apps: apps, power: state.withLock { $0.power })
  }
}
