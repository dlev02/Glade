import Foundation

/// Describes the state of this Mac in plain text for an assistant: what's using
/// memory and the processors, what the person is doing, and what the last scan
/// found. App and process names only; never file contents.
public enum MacDescription {
  public static func build(
    snapshot: SystemSnapshot?, apps: [AppUsage], context: ActivityContext?,
    suggestions: [PerformanceSuggestion], scan: ScanResult?, plan: CleanPlan?
  ) -> String {
    var lines: [String] = []
    if let snapshot {
      lines.append("SYSTEM")
      lines.append("Processor: \(Int(snapshot.cpu.totalPercent))% of \(snapshot.cpu.logicalCores) cores, load \(snapshot.cpu.loadAverage.map { String(format: "%.1f", $0) }.joined(separator: " "))")
      lines.append("Memory: \(Format.bytes(snapshot.memory.usedBytes)) used of \(Format.bytes(snapshot.memory.totalBytes)), pressure \(snapshot.memory.pressure.rawValue), swap \(Format.bytes(snapshot.memory.swapUsedBytes))")
      if let gpu = snapshot.gpu?.utilizationPercent { lines.append("Graphics: \(Int(gpu))%") }
      lines.append("Disk: \(Format.bytes(snapshot.disk.availableBytes)) free of \(Format.bytes(snapshot.disk.totalBytes))")
      lines.append("Power: \(snapshot.power.onBattery ? "on battery" : "plugged in")\(snapshot.power.lowPowerMode ? ", low power mode" : ""); thermal \(snapshot.thermal.rawValue)")
    }
    if let context {
      lines.append("")
      lines.append("WHAT THE PERSON IS DOING")
      if let front = context.frontmostApp { lines.append("In front: \(front.name)\(front.isFullScreen ? " (full screen)" : "")") }
      lines.append("Last input: \(Int(context.secondsSinceInput)) seconds ago")
      if context.isGaming { lines.append("Gaming: \(context.gamingReason ?? "yes")") }
      for signal in context.signals.prefix(8) { lines.append("Active: \(signal.appName) — \(signal.detail)") }
    }
    if !apps.isEmpty {
      lines.append("")
      lines.append("APPS BY MEMORY (name | memory | processor | graphics | notes)")
      for app in apps.sorted(by: { $0.memoryBytes > $1.memoryBytes }).prefix(25) {
        var notes: [String] = []
        if app.isFrontmost { notes.append("in front") }
        if app.isPlayingAudio { notes.append("playing audio") }
        if app.isCapturingAudio { notes.append("using the microphone") }
        if let reason = app.preventingSleep { notes.append("keeping the Mac awake: \(reason)") }
        if app.isSystem { notes.append("part of macOS") }
        if let last = app.lastActive, !app.isFrontmost { notes.append("last used \(Format.age(last))") }
        if app.windowCount == 0, app.kind == .app { notes.append("no windows") }
        lines.append("\(app.name) | \(Format.bytes(app.memoryBytes)) | \(Int(app.cpuPercent))% | \(app.gpuPercent.map { "\(Int($0))%" } ?? "-") | \(notes.joined(separator: ", "))")
      }
    }
    if !suggestions.isEmpty {
      lines.append("")
      lines.append("WHAT GLADE'S RULES SUGGEST")
      for suggestion in suggestions.prefix(8) { lines.append("\(suggestion.title): \(suggestion.reason)") }
    }
    if let scan {
      lines.append("")
      lines.append("STORAGE (scanned \(Format.age(scan.finished)))")
      lines.append("Reclaimable: \(Format.bytes(scan.totalBytes)) in \(scan.findings.count) findings")
      var totals: [StorageCategory: Int64] = [:]
      for finding in scan.findings where finding.within == nil { totals[finding.category, default: 0] += finding.bytes }
      for (category, bytes) in totals.sorted(by: { $0.value > $1.value }).prefix(12) {
        lines.append("\(category.title): \(Format.bytes(bytes))")
      }
      for level in CleanLevel.allCases {
        let plan = Planner.plan(scan: scan, level: level)
        let trash = plan.selectedBytes - plan.immediateBytes
        lines.append("A \(level.title) clean would free \(Format.bytes(plan.immediateBytes))" + (trash > 0 ? " and move \(Format.bytes(trash)) to the Trash (freed only when the Trash is emptied)" : ""))
      }
      if let plan { lines.append("Currently selected: \(Format.bytes(plan.selectedBytes)) at \(plan.level.title)") }
    }
    return lines.joined(separator: "\n")
  }

  /// A one-paragraph summary of recent activity, for the storage assistant.
  public static func activity(context: ActivityContext?, apps: [AppUsage]) -> String? {
    guard let context else { return nil }
    var parts: [String] = []
    if let front = context.frontmostApp { parts.append("\(front.name) is in front") }
    let busy = context.signals.filter { $0.kind == .highCPU }.map(\.appName)
    if !busy.isEmpty { parts.append("busy right now: \(Array(Set(busy)).sorted().joined(separator: ", "))") }
    let open = apps.filter { $0.kind == .app && !$0.isSystem }.map(\.name)
    if !open.isEmpty { parts.append("open apps: \(open.prefix(20).joined(separator: ", "))") }
    return parts.isEmpty ? nil : parts.joined(separator: "; ")
  }
}
