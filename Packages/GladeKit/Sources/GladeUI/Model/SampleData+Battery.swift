import Foundation
import GladeKit

/// Made-up battery figures for snapshots and screenshots: a month of a typical laptop
/// day (charged in the morning to an 80% limit, used on battery, asleep overnight),
/// well-known apps only, and no one’s own readings.
extension SampleData {
  public enum BatteryScene: String, Sendable, CaseIterable {
    case charging, onBattery, noBattery
  }

  public static func sampleBattery(_ scene: BatteryScene, now: Date = Date()) -> BatteryState {
    var state = BatteryState()
    let limit = ChargeLimit.parse("Battery level limits:\n{\n    chargeSocLimitSoc = 80;\n}", now: now)
    // The sample day runs in real time; the last two hours bend towards the scene, so
    // the line ends charging or on battery whatever the hour.
    let current = scene == .onBattery ? 61 : 62

    if scene != .noBattery {
      var history = BatteryHistory()
      var time = now.addingTimeInterval(-30 * 86_400)
      while time <= now {
        var (percent, state) = level(at: time)
        let minutesAgo = now.timeIntervalSince(time) / 60
        if minutesAgo < 120 {
          let pull = 1 - minutesAgo / 120
          let tail = scene == .onBattery ? Double(current) + minutesAgo * 0.12 : Double(current) - minutesAgo * 0.35
          percent = Int((Double(percent) * (1 - pull) + tail * pull).rounded())
          if minutesAgo < 75 { state = scene == .onBattery ? .onBattery : .charging }
        }
        let watts: Double = state == .charging ? 24 : state == .onBattery ? -(7 + 3 * sin(time.timeIntervalSince1970 / 2000)) : 0
        history.samples.append(.init(
          date: time, percent: percent, state: state, batteryWatts: watts, systemWatts: state == .onBattery ? -watts : 12,
          temperature: 30 + (state == .charging ? 4 : 1) + sin(time.timeIntervalSince1970 / 5000)
        ))
        time = time.addingTimeInterval(now.timeIntervalSince(time) < 2 * 86_400 ? 300 : 1800)
      }
      for day in stride(from: 365, through: 0, by: -7) {
        let date = now.addingTimeInterval(-Double(day) * 86_400)
        history.health.append(.init(date: date, percent: 100 - (365 - day) / 40, capacitymAh: 6249 * (100 - (365 - day) / 40) / 100, designCapacitymAh: 6249, cycles: 412 - day))
      }
      state.history = history
      state.sleeps = (0..<5).compactMap { sampleSleep(night: $0, now: now) }
    }

    let reading: BatteryReading
    switch scene {
    case .charging:
      reading = sampleReading(now: now, percent: current, state: .charging, battery: true)
    case .onBattery:
      reading = sampleReading(now: now, percent: current, state: .onBattery, battery: true)
    case .noBattery:
      reading = sampleReading(now: now, percent: nil, state: .noBattery, battery: false)
    }
    state.status = BatteryStatus.make(reading: reading, limit: scene == .noBattery ? nil : limit, history: state.history, now: now)
    state.awake = sampleAwake(now: now, onBattery: scene == .onBattery)
    state.sleepsLoaded = true
    state.sampleEnergy = Dictionary(uniqueKeysWithValues: EnergyPeriod.allCases.map { ($0, sampleEnergy($0, now: now)) })
    state.suggestions = decodeList([PerformanceSuggestion].self, [[
      "id": "idleEnergyDrain:com.apple.mail", "kind": "idleEnergyDrain", "appID": "com.apple.mail", "appName": "Mail",
      "title": "Quit Mail", "reason": "Mail hasn’t been used for 2 days but is still using 0.6 W in the background.",
      "frees": ["memoryBytes": 412_000_000, "cpuPercent": 1.2], "confidence": "medium", "actionable": true,
      "facts": "Idle 2 days · 0.6 W", "idleSeconds": 172_800,
    ]]) ?? []
    return state
  }

  /// The sample day: asleep on battery overnight, a morning charge to the limit, a
  /// working day on battery, a top-up before the evening.
  private static func level(at date: Date) -> (percent: Int, state: BatteryReading.State) {
    let calendar = Calendar.current
    let hour = Double(calendar.component(.hour, from: date)) + Double(calendar.component(.minute, from: date)) / 60
    let day = Double(calendar.ordinality(of: .day, in: .era, for: date) ?? 0)
    let wobble = sin(day * 1.7) * 4
    func clamp(_ value: Double) -> Int { Int(min(100, max(5, value)).rounded()) }
    switch hour {
    case ..<7.5: return (clamp(60 + wobble - (hour + 0.5) * 0.8), .onBattery)
    case ..<8.5: return (clamp(53 + wobble - (hour - 7.5) * 10), .onBattery)
    case ..<10.2: return (clamp(min(80, 43 + wobble + (hour - 8.5) * 24)), .charging)
    case ..<12.5: return (80, .notCharging)
    case ..<17.5: return (clamp(80 - (hour - 12.5) * (7 + wobble / 4)), .onBattery)
    case ..<19: return (clamp(min(80, 45 + (hour - 17.5) * 26)), .charging)
    case ..<23.5: return (clamp(80 - (hour - 19) * 4), .onBattery)
    default: return (clamp(62 + wobble), .onBattery)
    }
  }

  private static func sampleReading(now: Date, percent: Int?, state: BatteryReading.State, battery: Bool) -> BatteryReading {
    var fields: [String: Any] = [
      "date": now.timeIntervalSinceReferenceDate, "hasBattery": battery, "state": state.rawValue, "lowPowerMode": false,
    ]
    if battery {
      fields.merge([
        "percent": percent ?? 60, "temperatureCelsius": state == .charging ? 34.6 : 31.2, "voltage": 12.62,
        "amperage": state == .charging ? 1890 : -760, "batteryWatts": state == .charging ? 23.9 : -9.6,
        "systemWatts": state == .charging ? 14.2 : 9.6, "cycleCount": 412, "designCycleCount": 1000,
        "capacitymAh": 5687, "designCapacitymAh": 6249, "rawMaxCapacitymAh": 5602,
        "currentCapacitymAh": 5602 * (percent ?? 60) / 100, "healthPercent": 91, "condition": "Normal",
      ]) { _, new in new }
      if state == .charging {
        fields["minutesToFull"] = 74
        fields["adapter"] = ["watts": 96, "name": "USB-C charger", "rawDescription": "pd charger", "isWireless": false]
        fields["adapterWatts"] = 38.1
      } else {
        fields["minutesToEmpty"] = 290
      }
    } else {
      fields["adapter"] = ["watts": 150, "name": "Charger", "isWireless": false]
      fields["systemWatts"] = 18.0
    }
    return decodeList(BatteryReading.self, fields)!
  }

  private static func sampleSleep(night: Int, now: Date) -> SleepRecord? {
    let calendar = Calendar.current
    // 23:30 to 07:30.
    let today = calendar.startOfDay(for: now)
    let start = today.addingTimeInterval(-Double(night + 1) * 86_400 + 23.5 * 3600)
    // Last night’s sleep ends before "now", whatever time the sample is drawn.
    let end = min(start.addingTimeInterval(8 * 3600), now.addingTimeInterval(-1800))
    guard end.timeIntervalSince(start) >= 3600 else { return nil }
    let wakes: [(String, Int)] = night == 1 ? [("the network", 31), ("a check-in by macOS", 6), ("Power Nap", 3)] : [("the network", 9 + night), ("a check-in by macOS", 4)]
    var list: [[String: Any]] = []
    var offset = 900.0
    for (reason, count) in wakes {
      for _ in 0..<count {
        list.append(["date": start.addingTimeInterval(offset).timeIntervalSinceReferenceDate, "reason": reason, "raw": reason == "the network" ? "smc.sysState.Wake wifibt SMC.OutboxNotEmpty" : "rtc/Maintenance", "seconds": 6])
        offset += 400
      }
    }
    let before = 62 - night
    return decodeList(SleepRecord.self, [
      "start": start.timeIntervalSinceReferenceDate, "end": end.timeIntervalSinceReferenceDate,
      "reason": "Lid closed", "rawReason": "Clamshell Sleep", "chargeBefore": before, "chargeAfter": before - (night == 1 ? 14 : 5),
      "onBattery": true, "wokeBy": "the lid opening", "rawWokeBy": "smc.sysState.Wake lid SMC.OutboxNotEmpty RTP.multi-touch/HID Activity",
      "wakes": list,
    ])
  }

  private static func sampleAwake(now: Date, onBattery: Bool) -> AwakeReport? {
    func holder(_ id: String, _ kind: String, _ name: String, _ reason: String, minutes: Double, startedBy: String? = nil, display: Bool = false, raw: String, type: String) -> [String: Any] {
      var entry: [String: Any] = [
        "id": id, "kind": kind, "name": name, "pid": 400, "holdsDisplay": display,
        "since": now.addingTimeInterval(-minutes * 60).timeIntervalSinceReferenceDate, "reason": reason,
        "rawNames": [raw], "rawTypes": [type], "count": 1,
      ]
      if kind == "app" {
        entry["appID"] = id
        entry["bundlePath"] = AppIcons.path(forAppID: id)
      }
      if kind == "simulator" { entry["simulatorUDID"] = "sample-phone" }
      if let startedBy { entry["startedBy"] = startedBy }
      return entry
    }
    return decodeList(AwakeReport.self, [
      "date": now.timeIntervalSinceReferenceDate, "sleepDisabled": false, "neverSleepsOnThisPower": false, "onBattery": onBattery,
      "holders": [
        holder("process:caffeinate-912", "process", "caffeinate", "Running caffeinate", minutes: 185, startedBy: "Terminal", raw: "caffeinate command-line tool", type: "PreventUserIdleSystemSleep"),
        holder("simulator:sample-phone", "simulator", "iPhone 17 Pro", "Playing sound", minutes: 74, raw: "com.apple.audio.context.preventuseridlesleep", type: "PreventUserIdleSystemSleep"),
        holder("com.apple.Music", "app", "Music", "Playing sound", minutes: 42, raw: "com.apple.audio.context.preventuseridlesleep", type: "PreventUserIdleSystemSleep"),
      ],
    ])
  }

  private static func sampleEnergy(_ period: EnergyPeriod, now: Date) -> EnergyReport {
    let rows: [(String, String, Double, [String])] = [
      ("com.apple.Safari", "Safari", 3.1, ["In use"]),
      ("com.apple.dt.Xcode", "Xcode", 2.4, []),
      ("process:Simulator devices", "Simulator devices", 1.6, ["Keeping your Mac awake", "Playing sound"]),
      ("com.apple.Music", "Music", 0.7, ["Keeping your Mac awake", "Playing sound"]),
      ("com.apple.mail", "Mail", 0.6, ["Not used for 2 days"]),
      ("com.apple.Photos", "Photos", 0.4, ["In the background"]),
      ("com.apple.MobileSMS", "Messages", 0.2, ["In the background"]),
      ("process:mds_stores", "mds_stores", 0.15, []),
    ]
    let scale: Double = period == .now ? 1.3 : period == .hour ? 1 : 0.8
    let seconds: Double = period == .now ? 1 : period == .hour ? 3600 : period == .halfDay ? 43_200 : 9_000
    let total = rows.reduce(0) { $0 + $1.2 * scale }
    let apps: [[String: Any]] = rows.map { id, name, watts, notes in
      var entry: [String: Any] = [
        "id": id, "name": name, "kind": id.hasPrefix("process:") ? "process" : "app", "joules": watts * scale * seconds,
        "watts": watts * scale, "share": watts * scale / total, "notes": notes, "isSystem": name == "mds_stores",
        "isGlade": false, "isRunning": true,
      ]
      if let path = AppIcons.path(forAppID: id) { entry["bundlePath"] = path }
      return entry
    }
    return decodeList(EnergyReport.self, [
      "period": period.rawValue, "seconds": seconds, "totalWatts": total, "apps": apps,
      "measures": "Processor energy macOS billed each process.",
    ]) ?? EnergyReport.build(period: period, apps: [], history: nil, unpluggedAt: nil, now: now)
  }

  /// The engine’s types have no public initialisers, so samples are built the way they
  /// arrive from disk.
  private static func decodeList<T: Decodable>(_ type: T.Type, _ object: Any) -> T? {
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
    do {
      return try JSONDecoder().decode(type, from: data)
    } catch {
      Log.warning(.app, "Sample battery data didn’t decode as \(T.self): \(error)")
      return nil
    }
  }
}
