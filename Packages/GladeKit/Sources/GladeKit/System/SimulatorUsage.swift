import Darwin
import Foundation
import Synchronization

/// The folder of simulators a device belongs to. Xcode and other tools keep their own
/// sets apart from the ones a person sees in Xcode's device list.
public enum SimulatorDeviceSet: String, Codable, Sendable, CaseIterable {
  /// `~/Library/Developer/CoreSimulator/Devices`, the set Xcode and the Simulator app show.
  case standard
  /// Xcode's SwiftUI preview devices.
  case previews
  /// Clones Xcode makes for parallel testing.
  case testing
  /// The Bitrig IDE's live preview devices.
  case bitrig
  /// Any other set, named by its folder.
  case other

  public var title: String {
    switch self {
    case .standard: "Simulators"
    case .previews: "Xcode previews"
    case .testing: "Xcode parallel testing"
    case .bitrig: "Bitrig"
    case .other: "Other set"
    }
  }

  /// Where each known set lives for the current user.
  static func knownPaths(home: String = NSHomeDirectory()) -> [(SimulatorDeviceSet, String)] {
    [
      (.standard, "\(home)/Library/Developer/CoreSimulator/Devices"),
      (.previews, "\(home)/Library/Developer/Xcode/UserData/Previews/Simulator Devices"),
      (.testing, "\(home)/Library/Developer/XCTestDevices"),
      (.bitrig, "\(home)/Library/Bitrig/Simulators"),
    ]
  }

  static func of(path: String) -> SimulatorDeviceSet {
    let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
    return knownPaths().first { $0.1 == trimmed }?.0 ?? .other
  }
}

/// One booted simulator device and what its processes are using.
public struct SimulatorUsage: Codable, Sendable, Identifiable, Hashable {
  public var udid: String
  /// "iPad Pro 13-inch (M5)". The UDID when `simctl` couldn't name it.
  public var name: String
  /// "iOS 27.2". `nil` when `simctl` couldn't say.
  public var system: String?
  public var deviceSet: SimulatorDeviceSet
  /// The set's folder, passed to `simctl --set` for anything outside the standard set.
  public var setPath: String
  /// `simctl`'s state, such as "Booted" or "Shutting Down".
  public var state: String
  /// Summed physical footprint of the device's processes, including the Mac-side
  /// rendering helpers started for it.
  public var memoryBytes: Int64
  /// Summed share of one core: 100 means one full core.
  public var cpuPercent: Double
  /// Summed share of the GPU, 0–100. `nil` when the GPU doesn't record it per process.
  public var gpuPercent: Double?
  public var processCount: Int
  public var pids: [Int32]
  /// When the device's `launchd_sim` started.
  public var bootedAt: Date?
  /// When the device was last started, from `simctl`, else `bootedAt`.
  public var lastBooted: Date?
  /// The latest sign of use Glade saw: boot, an app of the person's launched in it, or
  /// processor use above `SimulatorTracker.activeCPUPercent`.
  public var lastActivity: Date?
  /// The device the Simulator app shows in its front window. `false` when Simulator isn't open.
  public var isShownInSimulatorApp: Bool
  /// Apps the person installed (not built-in ones) that are running in it.
  public var runningApps: [String]
  /// Developer tools working with it right now: "debugger attached to Vesper", "xcodebuild".
  public var attachedTools: [String]
  /// Something is using it, so it isn't suggested for shutting down.
  public var inUse: Bool
  /// Why it counts as in use, in a few words each.
  public var inUseReasons: [String]
  /// Booted and nothing is using it: safe to suggest shutting down.
  public var isIdle: Bool
  /// A caveat about the judgement, such as Glade not knowing which device Bitrig shows.
  public var note: String?

  public var id: String { udid }
}

/// The breakdown of the "Simulator devices" row: each device, plus the CoreSimulator
/// services shared by all of them.
public struct SimulatorBreakdown: Codable, Sendable {
  public var date: Date
  public var devices: [SimulatorUsage]
  /// CoreSimulatorService, the disk image and launch helpers, Simulator itself: shared
  /// by every device and freed only when the last one shuts down.
  public var sharedBytes: Int64
  public var sharedProcessCount: Int
  /// Simulator processes Glade couldn't tie to a device or to the shared services.
  public var unattributedPIDs: [Int32]
  public var unattributedBytes: Int64
  /// Everything above: what the apps listing shows as one row.
  public var totalBytes: Int64
  public var totalProcessCount: Int
}

/// Reads another process's arguments and environment with `KERN_PROCARGS2`. Works for
/// processes of the same user; returns `nil` for others.
enum ProcessArguments {
  static let maximumSize: Int = Int(Sysctl.integer("kern.argmax") ?? 1_048_576)

  static func read(_ pid: pid_t) -> (arguments: [String], environment: [String])? {
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = maximumSize
    var buffer = [UInt8](repeating: 0, count: size)
    let status = buffer.withUnsafeMutableBytes { sysctl(&mib, 3, $0.baseAddress, &size, nil, 0) }
    guard status == 0, size > MemoryLayout<Int32>.size else { return nil }
    let argc = buffer.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
    var index = MemoryLayout<Int32>.size
    // The executable path, then padding.
    while index < size, buffer[index] != 0 { index += 1 }
    while index < size, buffer[index] == 0 { index += 1 }
    var strings: [String] = []
    var start = index
    while index < size {
      if buffer[index] == 0 {
        if index == start {
          // An empty string after the arguments ends the environment.
          if strings.count >= argc { break }
        } else {
          strings.append(String(decoding: buffer[start..<index], as: UTF8.self))
        }
        start = index + 1
      }
      index += 1
    }
    let arguments = Array(strings.prefix(argc))
    let environment = Array(strings.dropFirst(argc))
    return (arguments, environment)
  }

  /// The UDID and set folder named in a path such as `…/Devices/<UDID>/data/var/run/launchd_bootstrap.plist`.
  static func device(inPath path: String) -> (udid: String, setPath: String)? {
    guard let range = path.range(of: "/data/") ?? (path.hasSuffix("/data") ? path.range(of: "/data", options: .backwards) : nil) else { return nil }
    let before = path[..<range.lowerBound]
    guard let slash = before.lastIndex(of: "/") else { return nil }
    let candidate = String(before[before.index(after: slash)...])
    guard UUID(uuidString: candidate) != nil else { return nil }
    return (candidate.uppercased(), String(before[..<slash]))
  }
}

/// Builds simulator breakdowns and remembers what's slow to learn: which device each
/// process belongs to, and device names from `simctl`. Owned by a `SystemSampler`.
final class SimulatorTracker: Sendable {
  /// A device using at least this share of one core over the sample counts as busy.
  static let activeCPUPercent = 15.0
  /// A device busy this recently still counts as in use.
  static let recentBusySeconds: TimeInterval = 5 * 60
  /// A device started this recently is still settling, so it isn't judged idle.
  static let settlingSeconds: TimeInterval = 120
  /// An IDE used this recently may be showing its preview devices.
  static let recentIDEMinutes = 20.0
  /// Device names are refetched after this long, or sooner when an unknown device boots.
  static let metadataRefresh: TimeInterval = 600
  /// Mac-side rendering helpers start just before their device's `launchd_sim`.
  static let helperStartWindow: TimeInterval = 15

  struct DeviceRef: Sendable, Hashable {
    var udid: String
    var setPath: String
  }

  struct Metadata: Sendable {
    var name: String
    var system: String?
    var state: String
    var lastBooted: Date?
  }

  private struct Assignment: Sendable {
    var start: Date?
    /// `nil` once looked up and found to belong to no device.
    var device: DeviceRef?
  }

  private struct State {
    var assignments: [pid_t: Assignment] = [:]
    var toolMentions: [pid_t: (start: Date?, udids: Set<String>, attachPIDs: Set<pid_t>)] = [:]
    var metadata: [String: (fetched: Date, devices: [String: Metadata])] = [:]
    var lastBusy: [String: Date] = [:]
  }

  private let state = Mutex(State())

  /// Mac-side tools that work with a simulator: their arguments name the device or the
  /// process they attach to.
  static let toolNames: Set<String> = ["xcodebuild", "lldb", "lldb-rpc-server", "debugserver", "simctl", "xctest"]

  static let sharedServiceMarkers = ["/CoreSimulator.framework/", "Simulator.app/"]
  static let renderHelperNames = ["SimRenderServer", "SimMetalHost"]
  static let userAppMarker = "/data/Containers/Bundle/Application/"

  // MARK: Breakdown

  func breakdown(processes: [ProcessSample], activity: ActivityLog, now: Date = Date()) async -> SimulatorBreakdown {
    let started = MachTime.now()
    let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
    let launchers = processes.filter { $0.name == "launchd_sim" && $0.isCurrentUser }
    guard !launchers.isEmpty else {
      let members = processes.filter { AppGrouper.isSimulator($0.executablePath) }
      let bytes = members.reduce(Int64(0)) { $0 + ($1.memoryBytes ?? 0) }
      return SimulatorBreakdown(
        date: now, devices: [], sharedBytes: bytes, sharedProcessCount: members.count, unattributedPIDs: [],
        unattributedBytes: 0, totalBytes: bytes, totalProcessCount: members.count
      )
    }

    var cache = state.withLock { $0.assignments }
    let live = Set(processes.map(\.pid))
    cache = cache.filter { live.contains($0.key) }

    func cached(_ process: ProcessSample) -> Assignment? {
      guard let hit = cache[process.pid], hit.start == process.startTime else { return nil }
      return hit
    }

    // Each device's launchd_sim names its data folder in its arguments.
    var launcherDevice: [pid_t: DeviceRef] = [:]
    for launcher in launchers {
      if let hit = cached(launcher), let device = hit.device {
        launcherDevice[launcher.pid] = device
        continue
      }
      var found: DeviceRef?
      if let read = ProcessArguments.read(launcher.pid) {
        for argument in read.arguments {
          if let device = ProcessArguments.device(inPath: argument) {
            found = DeviceRef(udid: device.udid, setPath: device.setPath)
            break
          }
        }
        if found == nil, let udid = Self.environmentUDID(read.environment) {
          found = DeviceRef(udid: udid, setPath: Self.setPath(containing: udid))
        }
      }
      if found == nil { SystemIssues.warn("simulator.launchd.\(launcher.pid)", "launchd_sim pid \(launcher.pid) didn't name its device") }
      cache[launcher.pid] = Assignment(start: launcher.startTime, device: found)
      if let found { launcherDevice[launcher.pid] = found }
    }

    // Membership matches the apps listing's "Simulator devices" row: anything run from
    // CoreSimulator or a simulator runtime, plus everything under a launchd_sim.
    func ancestorLauncher(_ process: ProcessSample) -> pid_t? {
      var cursor = process.parentPID
      var steps = 0
      while cursor > 1, steps < 32, let parent = byPID[cursor] {
        if launcherDevice[cursor] != nil { return cursor }
        cursor = parent.parentPID
        steps += 1
      }
      return nil
    }

    let sortedLaunchers = launchers.compactMap { launcher in launcher.startTime.map { (launcher.pid, $0) } }
    func helperDevice(_ process: ProcessSample) -> DeviceRef? {
      guard Self.renderHelperNames.contains(where: { process.name.hasPrefix($0) }), let start = process.startTime else { return nil }
      let candidates = sortedLaunchers.filter { $0.1 >= start.addingTimeInterval(-1) && $0.1.timeIntervalSince(start) <= Self.helperStartWindow }
      guard let nearest = candidates.min(by: { $0.1 < $1.1 }) else { return nil }
      return launcherDevice[nearest.0]
    }

    var deviceMembers: [DeviceRef: [ProcessSample]] = [:]
    var shared: [ProcessSample] = []
    var unattributed: [ProcessSample] = []
    for process in processes where process.isCurrentUser || AppGrouper.isSimulator(process.executablePath) {
      if let device = launcherDevice[process.pid] {
        deviceMembers[device, default: []].append(process)
        continue
      }
      let isSimulatorPath = AppGrouper.isSimulator(process.executablePath)
      let isSimulatorApp = process.executablePath?.contains("/Simulator.app/") == true
      let launcher = ancestorLauncher(process)
      guard isSimulatorPath || isSimulatorApp || launcher != nil else { continue }
      if let launcher, let device = launcherDevice[launcher] {
        deviceMembers[device, default: []].append(process)
        continue
      }
      if let hit = cached(process) {
        if let device = hit.device { deviceMembers[device, default: []].append(process) } else { shared.append(process) }
        continue
      }
      var device = helperDevice(process)
      if device == nil, process.isCurrentUser, let read = ProcessArguments.read(process.pid), let udid = Self.environmentUDID(read.environment) {
        device = DeviceRef(udid: udid, setPath: Self.setPath(containing: udid))
      }
      if let device {
        cache[process.pid] = Assignment(start: process.startTime, device: device)
        deviceMembers[device, default: []].append(process)
      } else if isSimulatorApp || Self.sharedServiceMarkers.contains(where: { process.executablePath?.contains($0) == true }) {
        cache[process.pid] = Assignment(start: process.startTime, device: nil)
        shared.append(process)
      } else {
        unattributed.append(process)
      }
    }

    // Debuggers and test runs on the Mac side.
    let memberPIDs = Dictionary(deviceMembers.flatMap { device, members in members.map { ($0.pid, device) } }, uniquingKeysWith: { first, _ in first })
    let knownUDIDs = Set(launcherDevice.values.map(\.udid))
    var toolMentions = state.withLock { $0.toolMentions }.filter { live.contains($0.key) }
    var tools: [DeviceRef: Set<String>] = [:]
    var testRunning = false
    for process in processes where process.isCurrentUser && Self.toolNames.contains(process.name) {
      if process.name == "xcodebuild" || process.name == "xctest" { testRunning = true }
      var mention = toolMentions[process.pid]
      if mention == nil || mention?.start != process.startTime {
        var udids = Set<String>()
        var attach = Set<pid_t>()
        if let read = ProcessArguments.read(process.pid) {
          for text in read.arguments + read.environment {
            let upper = text.uppercased()
            for udid in knownUDIDs where upper.contains(udid) { udids.insert(udid) }
            if let value = text.split(separator: "=").last, text.hasPrefix("--attach="), let pid = pid_t(value) { attach.insert(pid) }
          }
          if process.name == "debugserver", let last = read.arguments.last, let pid = pid_t(last) { attach.insert(pid) }
        }
        mention = (process.startTime, udids, attach)
        toolMentions[process.pid] = mention
      }
      guard let mention else { continue }
      for (device, _) in deviceMembers where mention.udids.contains(device.udid) {
        tools[device, default: []].insert(process.name)
      }
      for pid in mention.attachPIDs {
        if let device = memberPIDs[pid] { tools[device, default: []].insert("\(process.name) attached to \(byPID[pid]?.name ?? "pid \(pid)")") }
      }
    }
    // A traced process inside a device has a debugger attached, whichever tool started it.
    for (pid, device) in memberPIDs {
      var info = proc_bsdinfo()
      let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
      guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_flags & UInt32(PROC_FLAG_TRACED) != 0 else { continue }
      tools[device, default: []].insert("debugger attached to \(byPID[pid]?.name ?? "pid \(pid)")")
    }

    let devices = Array(deviceMembers.keys)
    let metadata = await metadata(for: devices, now: now)
    let context = IDEContext.current(activity: activity, now: now)

    var lastBusy = state.withLock { $0.lastBusy }
    var usages: [SimulatorUsage] = []
    for device in devices {
      let members = deviceMembers[device] ?? []
      let meta = metadata[device.udid]
      let set = SimulatorDeviceSet.of(path: device.setPath)
      var cpu = 0.0, memory: Int64 = 0
      var gpu: Double?
      var apps: [String] = []
      var newestAppStart: Date?
      var runner = false
      for process in members {
        cpu += process.cpuPercent ?? 0
        memory += process.memoryBytes ?? 0
        if let value = process.gpuPercent { gpu = (gpu ?? 0) + value }
        if let path = process.executablePath, path.contains(Self.userAppMarker), let bundle = AppGrouper.appBundle(in: path) {
          let name = ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
          if path.hasPrefix(bundle + "/") && !path.contains(".appex/") && !apps.contains(name) { apps.append(name) }
          if let start = process.startTime, start > (newestAppStart ?? .distantPast) { newestAppStart = start }
        }
        if process.name.hasSuffix("-Runner") || process.name == "xctest" || process.name == "XCTRunner" { runner = true }
      }
      let launcher = members.first { $0.name == "launchd_sim" }
      let bootedAt = launcher?.startTime
      if cpu >= Self.activeCPUPercent { lastBusy[device.udid] = now }
      let busyAt = lastBusy[device.udid]
      let lastActivity = [bootedAt, newestAppStart, busyAt].compactMap { $0 }.max()

      var reasons: [String] = []
      var note: String?
      if cpu >= Self.activeCPUPercent {
        reasons.append("using \(Int(cpu.rounded()))% CPU")
      } else if let busyAt, now.timeIntervalSince(busyAt) < Self.recentBusySeconds {
        reasons.append("was busy \(Durations.phrase(now.timeIntervalSince(busyAt))) ago")
      }
      let attached = (tools[device] ?? []).sorted()
      if !attached.isEmpty { reasons.append(attached.joined(separator: ", ")) }
      if runner { reasons.append("running tests") }
      let shown = context.simulatorFrontUDID == device.udid
      if shown { reasons.append("shown in the Simulator app") }
      if let bootedAt, now.timeIntervalSince(bootedAt) < Self.settlingSeconds { reasons.append("started \(Int(now.timeIntervalSince(bootedAt)))s ago") }
      switch set {
      case .bitrig:
        if let bitrig = context.bitrig {
          if bitrig.frontmost {
            reasons.append("Bitrig is in front and may be showing it")
          } else if let idle = bitrig.idleFor, bitrig.recent {
            reasons.append("Bitrig was used \(idle < 120 ? "a minute" : Durations.phrase(idle)) ago and may be showing it")
          } else if bitrig.recent {
            reasons.append("Bitrig is open and Glade hasn’t seen when it was last used")
          } else if let idle = bitrig.idleFor {
            note = "Bitrig is open but hasn’t been used for \(Durations.phrase(idle)); Glade can’t tell which preview device it shows."
          }
        }
      case .previews:
        if let xcode = context.xcode, xcode.recent { reasons.append("Xcode may be showing previews in it") }
      case .testing:
        if testRunning { reasons.append("a test run is going") }
      case .standard:
        // Bitrig drives standard-set simulators too (its own set may have none booted).
        if let bitrig = context.bitrig, bitrig.recent {
          note = "Bitrig is open and may be showing it; Glade can’t tell which simulator Bitrig shows."
        }
      case .other:
        break
      }
      let booted = meta?.state ?? "Booted"
      let inUse = !reasons.isEmpty
      // A caveat only matters for a device that would otherwise be judged idle.
      if inUse { note = nil }
      usages.append(SimulatorUsage(
        udid: device.udid, name: meta?.name ?? device.udid, system: meta?.system, deviceSet: set, setPath: device.setPath,
        state: booted, memoryBytes: memory, cpuPercent: cpu, gpuPercent: gpu, processCount: members.count,
        pids: members.map(\.pid).sorted(), bootedAt: bootedAt, lastBooted: meta?.lastBooted ?? bootedAt,
        lastActivity: lastActivity, isShownInSimulatorApp: shown, runningApps: apps, attachedTools: attached,
        inUse: inUse, inUseReasons: reasons, isIdle: booted == "Booted" && !inUse, note: note
      ))
    }
    usages.sort { $0.memoryBytes > $1.memoryBytes }

    let finalCache = cache
    let finalMentions = toolMentions
    let liveUDIDs = Set(devices.map(\.udid))
    let finalBusy = lastBusy.filter { liveUDIDs.contains($0.key) }
    state.withLock {
      $0.assignments = finalCache
      $0.toolMentions = finalMentions
      $0.lastBusy = finalBusy
    }

    let sharedBytes = shared.reduce(Int64(0)) { $0 + ($1.memoryBytes ?? 0) }
    let unattributedBytes = unattributed.reduce(Int64(0)) { $0 + ($1.memoryBytes ?? 0) }
    let deviceBytes = usages.reduce(Int64(0)) { $0 + $1.memoryBytes }
    let count = usages.reduce(0) { $0 + $1.processCount } + shared.count + unattributed.count
    if !unattributed.isEmpty {
      Log.debug(.system, "Simulator breakdown: \(unattributed.count) processes not tied to a device: \(unattributed.prefix(5).map(\.name).joined(separator: ", "))")
    }
    // This runs every few seconds while a window shows, so only note the slow ones.
    let milliseconds = Double(MachTime.now() &- started) / 1e6
    if milliseconds > 400 {
      Log.debug(.system, "Simulator breakdown: \(usages.count) devices, \(count) processes in \(String(format: "%.0f", milliseconds)) ms")
    }
    return SimulatorBreakdown(
      date: now, devices: usages, sharedBytes: sharedBytes, sharedProcessCount: shared.count,
      unattributedPIDs: unattributed.map(\.pid).sorted(), unattributedBytes: unattributedBytes,
      totalBytes: deviceBytes + sharedBytes + unattributedBytes, totalProcessCount: count
    )
  }

  static func environmentUDID(_ environment: [String]) -> String? {
    for entry in environment where entry.hasPrefix("SIMULATOR_UDID=") {
      let value = String(entry.dropFirst("SIMULATOR_UDID=".count))
      if UUID(uuidString: value) != nil { return value.uppercased() }
    }
    return nil
  }

  /// The known set whose folder holds this UDID, else the standard set.
  static func setPath(containing udid: String) -> String {
    let sets = SimulatorDeviceSet.knownPaths()
    for (_, path) in sets where FileManager.default.fileExists(atPath: "\(path)/\(udid)") { return path }
    return sets[0].1
  }

  // MARK: Names from simctl

  private struct DeviceList: Decodable {
    var devices: [String: [Device]]
  }

  private struct Device: Decodable {
    var udid: String
    var name: String
    var state: String?
    var lastBootedAt: String?
    var lastUsedAt: String?
  }

  /// Names and systems for the booted devices, from one `simctl list` per set. Cached;
  /// refetched when a device isn't known yet or the cache is old.
  private func metadata(for devices: [DeviceRef], now: Date) async -> [String: Metadata] {
    let bySet = Dictionary(grouping: devices, by: \.setPath)
    var result: [String: Metadata] = [:]
    for (setPath, members) in bySet {
      let cached = state.withLock { $0.metadata[setPath] }
      let fresh = cached.map { now.timeIntervalSince($0.fetched) < Self.metadataRefresh } ?? false
      if let cached, fresh, members.allSatisfy({ cached.devices[$0.udid] != nil }) {
        for member in members { result[member.udid] = cached.devices[member.udid] }
        continue
      }
      guard let listed = await Self.list(setPath: setPath) else {
        for member in members { result[member.udid] = cached?.devices[member.udid] }
        continue
      }
      state.withLock { $0.metadata[setPath] = (now, listed) }
      for member in members { result[member.udid] = listed[member.udid] }
    }
    return result
  }

  static func list(setPath: String) async -> [String: Metadata]? {
    let standard = SimulatorDeviceSet.of(path: setPath) == .standard
    let arguments = ["simctl"] + (standard ? [] : ["--set", setPath]) + ["list", "devices", "-j"]
    do {
      let result = try await Shell.run("xcrun", arguments, timeout: 30, quiet: true)
      guard result.succeeded else {
        Log.warning(.system, "simctl list for \(standard ? "the standard set" : setPath) failed (exit \(result.status)): \(result.stderr.prefix(200))")
        return nil
      }
      let list = try JSONDecoder().decode(DeviceList.self, from: Data(result.stdout.utf8))
      let parser = ISO8601DateFormatter()
      var devices: [String: Metadata] = [:]
      for (runtime, entries) in list.devices {
        for entry in entries {
          let booted = (entry.lastBootedAt ?? entry.lastUsedAt).flatMap { parser.date(from: $0) }
          devices[entry.udid.uppercased()] = Metadata(name: entry.name, system: systemName(runtime), state: entry.state ?? "Booted", lastBooted: booted)
        }
      }
      return devices
    } catch {
      Log.warning(.system, "Couldn’t read the simulator list for \(setPath): \(error)")
      return nil
    }
  }

  /// "com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4" → "iOS 27.2".
  static func systemName(_ runtime: String) -> String {
    guard let last = runtime.split(separator: ".").last else { return runtime }
    let parts = last.split(separator: "-")
    guard let platform = parts.first else { return runtime }
    let version = parts.dropFirst().prefix { $0.allSatisfy(\.isNumber) }
    return version.isEmpty ? String(platform) : "\(platform) \(version.joined(separator: "."))"
  }
}

/// What the IDEs that own simulators are doing, read once per breakdown.
struct IDEContext: Sendable {
  struct IDE: Sendable {
    var frontmost: Bool
    /// When it was last in front, from the activity log.
    var lastActive: Date?
    /// In front, used within `SimulatorTracker.recentIDEMinutes`, or never seen in front
    /// (so Glade can't rule it out).
    var recent: Bool
    /// Seconds since it was last in front; `nil` when Glade has never seen it there.
    var idleFor: TimeInterval?
  }

  var bitrig: IDE?
  var xcode: IDE?
  /// The device in the Simulator app's front window, when Simulator is open.
  var simulatorFrontUDID: String?

  static let bitrigBundleIDs: Set<String> = ["app.bitrig.bitrigapp", "app.bitrig.bitrig", "com.bitrig.bitrig"]
  static let xcodeBundleID = "com.apple.dt.Xcode"
  static let simulatorBundleID = "com.apple.iphonesimulator"

  static func current(activity: ActivityLog, now: Date) -> IDEContext {
    let (launched, frontmost) = LaunchedApps.current()
    func ide(_ match: (LaunchedApp) -> Bool) -> IDE? {
      guard let app = launched.first(where: match) else { return nil }
      let front = app.pid == frontmost
      let last = front ? now : app.bundleID.flatMap { activity.lastActive(bundleID: $0) }
      let gap = last.map { now.timeIntervalSince($0) }
      let recent = front || gap.map { $0 < SimulatorTracker.recentIDEMinutes * 60 } ?? true
      return IDE(frontmost: front, lastActive: last, recent: recent, idleFor: front ? 0 : gap)
    }
    let bitrig = ide { app in
      app.bundleID.map { bitrigBundleIDs.contains($0.lowercased()) } == true || app.name == "Bitrig"
    }
    let xcode = ide { $0.bundleID == xcodeBundleID }
    var front: String?
    if launched.contains(where: { $0.bundleID == simulatorBundleID }) {
      CFPreferencesAppSynchronize(simulatorBundleID as CFString)
      if let value = CFPreferencesCopyAppValue("CurrentDeviceUDID" as CFString, simulatorBundleID as CFString) as? String {
        front = value.uppercased()
      }
    }
    return IDEContext(bitrig: bitrig, xcode: xcode, simulatorFrontUDID: front)
  }
}
