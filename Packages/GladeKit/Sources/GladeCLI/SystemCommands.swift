import ArgumentParser
import Foundation
import GladeKit

/// What `cpuPercent` means in every listing, spelled out for agents reading the JSON.
private let cpuPercentMeaning = "share of one core: 100 means one full core, as in Activity Monitor"

enum UsageSort: String, ExpressibleByArgument, CaseIterable, Encodable {
  case memory, cpu, gpu
}

struct Status: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Show processor, memory, GPU, disk and power right now."
  )

  @OptionGroup var output: OutputOptions

  @Option(name: .long, help: "Keep printing a reading every this many seconds until stopped.")
  var watch: Double?

  func run() async throws {
    let sampler = SystemSampler()
    var snapshot = await sampler.snapshot()
    guard let watch else {
      emit(snapshot, json: output.json) { printStatus(snapshot) }
      return
    }
    let interval = max(0.5, watch)
    while !Task.isCancelled {
      if output.json {
        print(JSONFiles.string(snapshot, pretty: false))
      } else {
        printStatus(snapshot)
        print("")
      }
      fflush(stdout)
      try await Task.sleep(for: .seconds(interval))
      snapshot = sampler.snapshotNow()
    }
  }

  private func printStatus(_ s: SystemSnapshot) {
    let cpu = s.cpu
    let cores = [cpu.performanceCores.map { "\($0)P" }, cpu.efficiencyCores.map { "\($0)E" }].compactMap { $0 }.joined(separator: "+")
    print("CPU     \(pct(cpu.totalPercent)) (user \(pct(cpu.userPercent)), system \(pct(cpu.systemPercent))) on \(cpu.logicalCores) cores\(cores.isEmpty ? "" : " (\(cores))"), load \(cpu.loadAverage.map { String(format: "%.2f", $0) }.joined(separator: " "))")
    let m = s.memory
    print("Memory  \(Format.bytes(m.usedBytes)) used of \(Format.bytes(m.totalBytes)), pressure \(m.pressure.rawValue)\(m.freePercent.map { " (\($0)% free)" } ?? "")")
    print("        app \(Format.bytes(m.appBytes)), wired \(Format.bytes(m.wiredBytes)), compressed \(Format.bytes(m.compressedBytes)), cached files \(Format.bytes(m.cachedFilesBytes)), free \(Format.bytes(m.freeBytes))")
    print("        swap \(Format.bytes(m.swapUsedBytes)) of \(Format.bytes(m.swapTotalBytes))")
    if let gpu = s.gpu {
      print("GPU     \(gpu.utilizationPercent.map(pct) ?? "?")\(gpu.name.map { " on \($0)" } ?? "")\(gpu.coreCount.map { " (\($0) cores)" } ?? ""), memory \(gpu.inUseMemoryBytes.map(Format.bytes) ?? "?") in use of \(gpu.allocatedMemoryBytes.map(Format.bytes) ?? "?") allocated")
    } else {
      print("GPU     not reported")
    }
    print("Disk    \(Format.bytes(s.disk.availableBytes)) available of \(Format.bytes(s.disk.totalBytes)) on \(s.disk.name)")
    var power = s.power.onBattery ? "on battery" : "on power adapter"
    if let percent = s.power.batteryPercent { power += ", battery \(percent)%\(s.power.isCharging == true ? " charging" : "")" }
    if s.power.lowPowerMode { power += ", Low Power Mode" }
    print("Power   \(power); thermal \(s.thermal.rawValue); up \(uptime(s.uptimeSeconds))")
  }

  private func uptime(_ seconds: Double) -> String {
    let minutes = Int(seconds / 60)
    let days = minutes / 1440, hours = (minutes % 1440) / 60
    return days > 0 ? "\(days)d \(hours)h" : "\(hours)h \(minutes % 60)m"
  }
}

struct Processes: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "List processes by memory, processor or GPU use."
  )

  @OptionGroup var output: OutputOptions

  @Option(name: .long, help: "Sort by memory, cpu or gpu.")
  var sort: UsageSort = .memory

  @Option(name: .long, help: "How many processes to list.")
  var limit = 25

  @Flag(name: .long, help: "Include other users' processes (root, system daemons), measured with ps.")
  var all = false

  struct Report: Encodable {
    var date: Date
    var sort: UsageSort
    var cpuPercentMeans: String
    var total: Int
    var processes: [ProcessSample]
  }

  func run() async throws {
    var list = await SystemSampler().processes(full: all)
    if !all { list = list.filter(\.isCurrentUser) }
    list.sort { lhs, rhs in
      switch sort {
      case .memory: (lhs.memoryBytes ?? 0) > (rhs.memoryBytes ?? 0)
      case .cpu: (lhs.cpuPercent ?? 0) > (rhs.cpuPercent ?? 0)
      case .gpu: (lhs.gpuPercent ?? 0) > (rhs.gpuPercent ?? 0)
      }
    }
    let shown = Array(list.prefix(max(0, limit)))
    let report = Report(date: Date(), sort: sort, cpuPercentMeans: cpuPercentMeaning, total: list.count, processes: shown)
    emit(report, json: output.json) {
      print("\("PID".leftPadded(7))  \("CPU".leftPadded(6))  \("MEMORY".leftPadded(9))  \("GPU".leftPadded(5))  \("THR".leftPadded(4))  NAME")
      for p in shown {
        let gpu = p.gpuPercent.map { String(format: "%.1f", $0) } ?? "-"
        let cpu = p.cpuPercent.map { String(format: "%.1f", $0) } ?? "-"
        let memory = p.memoryBytes.map(Format.bytes) ?? "-"
        let note = p.isRestricted ? (p.isCurrentUser ? " (unreadable)" : " (other user)") : ""
        print("\(String(p.pid).leftPadded(7))  \(cpu.leftPadded(6))  \(memory.leftPadded(9))  \(gpu.leftPadded(5))  \((p.threadCount.map(String.init) ?? "-").leftPadded(4))  \(p.name)\(note)")
      }
      if list.count > shown.count { print("… \(list.count - shown.count) more (raise --limit)") }
    }
  }
}

struct Apps: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "List apps with their helpers grouped, and what each is doing."
  )

  @OptionGroup var output: OutputOptions

  @Option(name: .long, help: "Sort by memory, cpu or gpu.")
  var sort: UsageSort = .memory

  @Option(name: .long, help: "How many apps to list.")
  var limit = 25

  @Flag(name: .long, help: "Include system processes and other users' processes.")
  var all = false

  struct Report: Encodable {
    var date: Date
    var sort: UsageSort
    var cpuPercentMeans: String
    var total: Int
    var apps: [AppUsage]
  }

  func run() async throws {
    var apps = await SystemSampler().apps(full: all)
    if !all { apps = apps.filter { !$0.isSystem } }
    apps.sort { lhs, rhs in
      switch sort {
      case .memory: lhs.memoryBytes > rhs.memoryBytes
      case .cpu: lhs.cpuPercent > rhs.cpuPercent
      case .gpu: (lhs.gpuPercent ?? 0) > (rhs.gpuPercent ?? 0)
      }
    }
    let shown = Array(apps.prefix(max(0, limit)))
    let report = Report(date: Date(), sort: sort, cpuPercentMeans: cpuPercentMeaning, total: apps.count, apps: shown)
    let now = Date()
    emit(report, json: output.json) {
      print("\("CPU".leftPadded(6))  \("MEMORY".leftPadded(9))  \("GPU".leftPadded(5))  \("PROCS".leftPadded(5))  \("WIN".leftPadded(3))  \("LAST USED".padding(toLength: 11, withPad: " ", startingAt: 0))  NAME")
      for app in shown {
        let gpu = app.gpuPercent.map { String(format: "%.1f", $0) } ?? "-"
        let lastUsed: String =
          if app.isFrontmost { "now" } else if let last = app.lastActive { "\(Elapsed.short(now.timeIntervalSince(last))) ago" } else { "-" }
        var flags: [String] = []
        if app.isFrontmost { flags.append("frontmost") }
        if app.isHidden { flags.append("hidden") }
        if app.isPlayingAudio { flags.append("playing audio") }
        if app.isCapturingAudio { flags.append("recording") }
        if let reason = app.preventingSleep { flags.append("keeping awake: \(reason)") }
        if app.isGame { flags.append("game") }
        if app.isFullScreen { flags.append("full screen") }
        if app.isSystem { flags.append("system") }
        if app.kind == .process { flags.append("process") }
        let suffix = flags.isEmpty ? "" : "  [\(flags.joined(separator: ", "))]"
        print("\(String(format: "%.1f", app.cpuPercent).leftPadded(6))  \(Format.bytes(app.memoryBytes).leftPadded(9))  \(gpu.leftPadded(5))  \(String(app.pids.count).leftPadded(5))  \(String(app.windowCount).leftPadded(3))  \(lastUsed.padding(toLength: 11, withPad: " ", startingAt: 0))  \(app.name)\(suffix)")
      }
      if apps.count > shown.count { print("… \(apps.count - shown.count) more (raise --limit)") }
    }
  }
}

struct Context: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Describe what the person is doing right now: front app, idle time, games, calls, busy apps."
  )

  @OptionGroup var output: OutputOptions

  func run() async throws {
    let context = await SystemSampler().context()
    emit(context, json: output.json) {
      if let front = context.frontmostApp {
        print("Front app: \(front.name)\(front.bundleIdentifier.map { " (\($0))" } ?? "")\(front.category.map { ", \($0)" } ?? "")\(front.isFullScreen ? ", full screen" : "")")
      } else {
        print("Front app: none")
      }
      print("Last input: \(Elapsed.short(context.secondsSinceInput)) ago")
      let screen = context.isScreenLocked == true ? "locked" : context.isDisplayAsleep == true ? "asleep" : "on"
      print("Screen: \(screen); \(context.onBattery ? "on battery" : "on power adapter")\(context.lowPowerMode ? ", Low Power Mode" : "")")
      print("Gaming: \(context.gamingReason ?? "no")")
      if context.signals.isEmpty {
        print("Active work: nothing notable")
      } else {
        print("Active work:")
        for signal in context.signals { print("  \(signal.appName): \(signal.detail)") }
      }
    }
  }
}

struct Suggest: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Suggest apps to quit or relaunch, and idle simulators to shut down, to free memory, processor or GPU. Changes nothing."
  )

  @OptionGroup var output: OutputOptions

  struct Report: Encodable {
    var date: Date
    var memoryPressure: MemoryPressure
    var memoryUsedBytes: Int64
    var memoryTotalBytes: Int64
    var cpuPercentMeans: String
    var suggestions: [PerformanceSuggestion]
  }

  func run() async throws {
    let sampler = SystemSampler()
    async let snapshotReading = sampler.snapshot()
    let processes = await sampler.processes()
    let apps = AppGrouper.group(processes)
    let simulators = await sampler.simulatorBreakdown(processes: processes).devices
    let snapshot = await snapshotReading
    let context = ActivityContext.current(apps: apps, power: snapshot.power)
    let suggestions = PerformanceAdvisor.suggestions(snapshot: snapshot, apps: apps, context: context, simulators: simulators)
    let report = Report(
      date: Date(), memoryPressure: snapshot.memory.pressure, memoryUsedBytes: snapshot.memory.usedBytes,
      memoryTotalBytes: snapshot.memory.totalBytes, cpuPercentMeans: cpuPercentMeaning, suggestions: suggestions
    )
    emit(report, json: output.json) {
      print("Memory \(Format.bytes(snapshot.memory.usedBytes)) used of \(Format.bytes(snapshot.memory.totalBytes)), pressure \(snapshot.memory.pressure.rawValue)\n")
      if suggestions.isEmpty {
        print("Nothing to suggest right now.")
        return
      }
      for s in suggestions {
        print("• \(s.title)  [\(s.kind.rawValue), \(s.confidence.rawValue) confidence\(s.actionable ? "" : ", look only")]")
        print("  \(s.reason)")
        if let udid = s.simulatorUDID {
          print("  shut down: \(Brand.cli) simulators shutdown \(udid)")
        } else {
          print("  id: \(s.appID)")
        }
      }
    }
  }
}

struct Simulators: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "List booted simulators with their memory and processor use, and shut down idle ones.",
    discussion: "Shutting a simulator down is like turning a phone off: its apps stop, its apps and data stay.",
    subcommands: [List.self, Shutdown.self],
    defaultSubcommand: List.self
  )

  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List booted simulators, what each uses, and whether it's idle.")

    @OptionGroup var output: OutputOptions

    struct Report: Encodable {
      var date: Date
      var cpuPercentMeans: String
      var breakdown: SimulatorBreakdown
    }

    func run() async throws {
      let breakdown = await SystemSampler().simulatorBreakdown()
      let report = Report(date: Date(), cpuPercentMeans: cpuPercentMeaning, breakdown: breakdown)
      emit(report, json: output.json) {
        if breakdown.devices.isEmpty {
          print("No simulators are booted.")
          return
        }
        let now = Date()
        print("\("CPU".leftPadded(6))  \("MEMORY".leftPadded(9))  \("PROCS".leftPadded(5))  \("UP".leftPadded(4))  \("STATE".padding(toLength: 7, withPad: " ", startingAt: 0))  NAME")
        for s in breakdown.devices {
          let up = s.bootedAt.map { Elapsed.short(now.timeIntervalSince($0)) } ?? "-"
          let state = s.state != "Booted" ? s.state : s.isIdle ? "idle" : "in use"
          let set = s.deviceSet == .standard ? "" : ", \(s.deviceSet.title)"
          print("\(String(format: "%.1f", s.cpuPercent).leftPadded(6))  \(Format.bytes(s.memoryBytes).leftPadded(9))  \(String(s.processCount).leftPadded(5))  \(up.leftPadded(4))  \(state.padding(toLength: 7, withPad: " ", startingAt: 0))  \(s.name)\(s.system.map { " (\($0)\(set))" } ?? (set.isEmpty ? "" : " (\(set.dropFirst(2)))"))")
          var details: [String] = []
          if !s.inUseReasons.isEmpty { details.append(s.inUseReasons.joined(separator: "; ")) }
          if !s.runningApps.isEmpty { details.append("running \(s.runningApps.joined(separator: ", "))") }
          if let note = s.note { details.append(note) }
          details.append(s.udid)
          print("        \(details.joined(separator: " · "))")
        }
        print("")
        print("Shared simulator services: \(Format.bytes(breakdown.sharedBytes)) in \(breakdown.sharedProcessCount) processes")
        if !breakdown.unattributedPIDs.isEmpty {
          print("Not tied to a device: \(Format.bytes(breakdown.unattributedBytes)) in \(breakdown.unattributedPIDs.count) processes")
        }
        print("Total: \(Format.bytes(breakdown.totalBytes)) in \(breakdown.totalProcessCount) processes")
      }
    }
  }

  struct Shutdown: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Shut down a booted simulator, or every idle one. Its apps and data are kept.",
      discussion: "A simulator that looks in use (busy, debugged, shown in Simulator, or likely an IDE's preview) is refused unless --force is given."
    )

    @OptionGroup var output: OutputOptions

    @Argument(help: "The simulator's UDID or name.")
    var simulator: String?

    @Flag(name: .long, help: "Shut down every simulator judged idle.")
    var idle = false

    @Flag(name: .long, help: "Shut it down even though it looks in use.")
    var force = false

    func validate() throws {
      if idle == (simulator != nil) { throw ValidationError("Give a simulator's UDID or name, or --idle.") }
      if idle && force { throw ValidationError("--force applies to one named simulator, not --idle.") }
    }

    struct Failure: Encodable {
      var error: String
      var target: String
    }

    func run() async throws {
      defer { _ = Log.recent(limit: 1) }
      if idle {
        let results = await SimulatorControl.shutdownIdle()
        emit(results, json: output.json) {
          if results.isEmpty { print("Nothing was shut down: no simulator is idle for certain. `\(Brand.cli) simulators` shows why.") }
          for result in results { print(result.message) }
        }
        if results.contains(where: { !$0.succeeded }) { throw ExitCode(1) }
        return
      }
      let target = simulator ?? ""
      let result: SimulatorActionResult
      do {
        let booted = await SystemSampler().simulators()
        let match = try SimulatorControl.resolve(target, in: booted)
        if match.inUse && !force {
          fail("\(match.name) looks in use (\(match.inUseReasons.joined(separator: "; "))). Add --force to shut it down anyway.", target: target)
          throw ExitCode(2)
        }
        result = try await SimulatorControl.shutdown(match)
      } catch let error as SimulatorControlError {
        fail(error.errorDescription ?? "\(error)", target: target)
        throw ExitCode(2)
      }
      emit(result, json: output.json) { print(result.message) }
      if !result.succeeded { throw ExitCode(1) }
    }

    private func fail(_ message: String, target: String) {
      if output.json {
        print(JSONFiles.string(Failure(error: message, target: target)))
      } else {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
      }
    }
  }
}

struct Quit: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Ask an app to quit, as its Quit menu item would. The app may ask about unsaved work.",
    discussion: "System apps and \(Brand.name) itself are refused. --force ends the app without asking and loses unsaved work."
  )

  @OptionGroup var output: OutputOptions

  @Argument(help: "The app's name, bundle identifier, id from `apps`, or pid.")
  var app: String

  @Flag(name: .long, help: "End the app immediately. Unsaved work is lost.")
  var force = false

  @Flag(name: .long, help: "Reopen the app after it quits.")
  var relaunch = false

  @Option(name: .long, help: "Seconds to wait for the app to exit.")
  var timeout: Double = 10

  func validate() throws {
    if force && relaunch { throw ValidationError("--force and --relaunch can't be combined; relaunch always quits gracefully.") }
  }

  func run() async throws {
    // The log file is written on a background queue; reading it back waits for pending
    // writes, so the action's log line survives the process exiting straight after.
    defer { _ = Log.recent(limit: 1) }
    let result: AppActionResult
    do {
      if relaunch {
        result = try await AppControl.relaunch(app, timeout: timeout)
      } else if force {
        result = try await AppControl.forceQuit(app, timeout: timeout)
      } else {
        result = try await AppControl.quit(app, timeout: timeout)
      }
    } catch let error as AppControlError {
      if output.json {
        struct Failure: Encodable {
          var error: String
          var target: String
        }
        print(JSONFiles.string(Failure(error: error.errorDescription ?? "\(error)", target: app)))
      } else {
        FileHandle.standardError.write(Data("\(error.errorDescription ?? "\(error)")\n".utf8))
      }
      throw ExitCode(2)
    }
    emit(result, json: output.json) { print(result.message) }
    if !result.exited { throw ExitCode(1) }
  }
}

private func pct(_ value: Double) -> String { "\(Int(value.rounded()))%" }

private enum Elapsed {
  /// "45s", "12m", "3h", "2d".
  static func short(_ seconds: Double) -> String {
    let s = Int(max(0, seconds))
    if s < 90 { return "\(s)s" }
    if s < 5400 { return "\(s / 60)m" }
    if s < 172_800 { return "\(s / 3600)h" }
    return "\(s / 86_400)d"
  }
}
