import Foundation

/// Something that crossed a limit the person set.
public struct ThresholdAlert: Codable, Sendable, Identifiable, Hashable {
  public enum Kind: String, Codable, Sendable, CaseIterable {
    case lowStorage, memoryPressure, sustainedCPU, sustainedGPU
  }

  public var id: String
  public var kind: Kind
  public var date: Date
  /// A short headline, for a notification’s title.
  public var title: String
  /// One sentence with the numbers.
  public var body: String
}

/// Watches snapshots for limits being crossed. Pure bookkeeping: it’s handed
/// snapshots, costs nothing between them, and decides only whether to raise an alert.
/// What happens next (a notification, a clean, an assistant check-in) is the caller’s.
public actor ThresholdMonitor {
  private var settings: AutomationSettings
  private var cpuHighSince: Date?
  private var gpuHighSince: Date?
  private var pressureSince: Date?
  private var lastFired: [ThresholdAlert.Kind: Date]
  private let stateFile: URL?

  /// - Parameter stateFile: Where the "last alerted" times are kept, so restarting
  ///   the app doesn’t repeat an alert. Pass `nil` to keep them in memory only.
  public init(settings: AutomationSettings, stateFile: URL? = GladePaths.support.appendingPathComponent("alerts.json")) {
    self.settings = settings
    self.stateFile = stateFile
    lastFired = stateFile.flatMap { JSONFiles.read([String: Date].self, from: $0) }?
      .reduce(into: [:]) { result, pair in
        if let kind = ThresholdAlert.Kind(rawValue: pair.key) { result[kind] = pair.value }
      } ?? [:]
  }

  public func update(_ settings: AutomationSettings) {
    self.settings = settings
  }

  /// Takes a new snapshot and returns any alerts it sets off.
  public func ingest(_ snapshot: SystemSnapshot, now: Date = Date()) -> [ThresholdAlert] {
    guard settings.enabled else { return [] }
    var alerts: [ThresholdAlert] = []

    if settings.storageAlerts {
      let freeGB = Double(snapshot.disk.availableBytes) / 1_000_000_000
      if freeGB < settings.storageFreeGB, mayFire(.lowStorage, now: now) {
        alerts.append(make(.lowStorage, now, "Storage is running low", "\(Format.bytes(snapshot.disk.availableBytes)) is left on \(snapshot.disk.name)."))
      }
    }

    if settings.memoryAlerts {
      if snapshot.memory.pressure >= .warning {
        let since = pressureSince ?? now
        pressureSince = since
        // Pressure that lasts a minute is real; a blip isn’t.
        if now.timeIntervalSince(since) >= 60, mayFire(.memoryPressure, now: now) {
          let level = snapshot.memory.pressure == .critical ? "critically low" : "under pressure"
          alerts.append(make(.memoryPressure, now, "Memory is \(level)", "\(Format.bytes(snapshot.memory.usedBytes)) of \(Format.bytes(snapshot.memory.totalBytes)) is in use, with \(Format.bytes(snapshot.memory.swapUsedBytes)) swapped to disk."))
        }
      } else {
        pressureSince = nil
      }
    }

    if settings.cpuAlerts {
      if snapshot.cpu.totalPercent >= settings.cpuPercent {
        let since = cpuHighSince ?? now
        cpuHighSince = since
        if now.timeIntervalSince(since) >= settings.cpuMinutes * 60, mayFire(.sustainedCPU, now: now) {
          alerts.append(make(.sustainedCPU, now, "The processor has been busy for a while", "It’s been above \(Int(settings.cpuPercent))% for \(Int(settings.cpuMinutes)) minutes."))
        }
      } else {
        cpuHighSince = nil
      }
    }

    if settings.gpuAlerts, let gpu = snapshot.gpu?.utilizationPercent {
      if gpu >= settings.gpuPercent {
        let since = gpuHighSince ?? now
        gpuHighSince = since
        if now.timeIntervalSince(since) >= settings.gpuMinutes * 60, mayFire(.sustainedGPU, now: now) {
          alerts.append(make(.sustainedGPU, now, "Graphics have been busy for a while", "The GPU has been above \(Int(settings.gpuPercent))% for \(Int(settings.gpuMinutes)) minutes."))
        }
      } else {
        gpuHighSince = nil
      }
    }

    if !alerts.isEmpty {
      for alert in alerts {
        lastFired[alert.kind] = now
        Log.info(.automation, "Alert: \(alert.kind.rawValue): \(alert.body)")
      }
      save()
    }
    return alerts
  }

  private func mayFire(_ kind: ThresholdAlert.Kind, now: Date) -> Bool {
    guard let last = lastFired[kind] else { return true }
    return now.timeIntervalSince(last) >= settings.quietMinutes * 60
  }

  private func make(_ kind: ThresholdAlert.Kind, _ date: Date, _ title: String, _ body: String) -> ThresholdAlert {
    ThresholdAlert(id: "\(kind.rawValue)-\(Int(date.timeIntervalSince1970))", kind: kind, date: date, title: title, body: body)
  }

  private func save() {
    guard let stateFile else { return }
    let table = Dictionary(uniqueKeysWithValues: lastFired.map { ($0.key.rawValue, $0.value) })
    try? JSONFiles.write(table, to: stateFile)
  }
}
