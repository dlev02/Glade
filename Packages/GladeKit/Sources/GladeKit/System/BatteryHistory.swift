import Foundation

/// A small record of the battery over time, kept on this Mac only: the charge every five
/// minutes (thinned to every half hour after two days, gone after thirty), the energy
/// each app used (five-minute totals for twelve hours, hourly for a week), and one
/// health reading a day for three years. It stays well under a megabyte.
public struct BatteryHistory: Codable, Sendable {
  /// The charge and power at one moment.
  public struct Sample: Codable, Sendable, Hashable {
    public var date: Date
    public var percent: Int
    public var state: BatteryReading.State
    /// Into the battery (positive) or out of it (negative).
    public var batteryWatts: Double?
    /// What the whole Mac was using.
    public var systemWatts: Double?
    public var temperature: Double?

    public var isPluggedIn: Bool { state == .charging || state == .notCharging || state == .charged }

    enum CodingKeys: String, CodingKey { case date = "t", percent = "p", state = "s", batteryWatts = "b", systemWatts = "w", temperature = "c" }

    public init(date: Date, percent: Int, state: BatteryReading.State, batteryWatts: Double?, systemWatts: Double?, temperature: Double?) {
      self.date = date
      self.percent = percent
      self.state = state
      self.batteryWatts = batteryWatts
      self.systemWatts = systemWatts
      self.temperature = temperature
    }

    public init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      date = Date(timeIntervalSince1970: try c.decode(Double.self, forKey: .date))
      percent = try c.decode(Int.self, forKey: .percent)
      state = try c.decode(BatteryReading.State.self, forKey: .state)
      batteryWatts = try c.decodeIfPresent(Double.self, forKey: .batteryWatts)
      systemWatts = try c.decodeIfPresent(Double.self, forKey: .systemWatts)
      temperature = try c.decodeIfPresent(Double.self, forKey: .temperature)
    }

    public func encode(to encoder: Encoder) throws {
      var c = encoder.container(keyedBy: CodingKeys.self)
      try c.encode(date.timeIntervalSince1970.rounded(), forKey: .date)
      try c.encode(percent, forKey: .percent)
      try c.encode(state, forKey: .state)
      try c.encodeIfPresent(batteryWatts.map(Self.round), forKey: .batteryWatts)
      try c.encodeIfPresent(systemWatts.map(Self.round), forKey: .systemWatts)
      try c.encodeIfPresent(temperature.map(Self.round), forKey: .temperature)
    }

    static func round(_ value: Double) -> Double { (value * 10).rounded() / 10 }
  }

  /// The energy one app used in a stretch of time.
  public struct AppEnergy: Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var bundlePath: String?
    public var joules: Double

    enum CodingKeys: String, CodingKey { case id = "i", name = "n", bundlePath = "a", joules = "j" }

    public init(id: String, name: String, bundlePath: String?, joules: Double) {
      self.id = id
      self.name = name
      self.bundlePath = bundlePath
      self.joules = joules
    }
  }

  public struct EnergyBucket: Codable, Sendable, Hashable {
    public var start: Date
    public var seconds: Double
    public var onBattery: Bool
    public var apps: [AppEnergy]

    enum CodingKeys: String, CodingKey { case start = "t", seconds = "d", onBattery = "b", apps = "a" }

    public init(start: Date, seconds: Double, onBattery: Bool, apps: [AppEnergy]) {
      self.start = start
      self.seconds = seconds
      self.onBattery = onBattery
      self.apps = apps
    }

    public init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      start = Date(timeIntervalSince1970: try c.decode(Double.self, forKey: .start))
      seconds = try c.decode(Double.self, forKey: .seconds)
      onBattery = try c.decodeIfPresent(Bool.self, forKey: .onBattery) ?? false
      apps = try c.decode([AppEnergy].self, forKey: .apps)
    }

    public func encode(to encoder: Encoder) throws {
      var c = encoder.container(keyedBy: CodingKeys.self)
      try c.encode(start.timeIntervalSince1970.rounded(), forKey: .start)
      try c.encode(seconds.rounded(), forKey: .seconds)
      if onBattery { try c.encode(true, forKey: .onBattery) }
      try c.encode(apps, forKey: .apps)
    }
  }

  /// What the battery holds, read once a day, to chart how it ages.
  public struct HealthPoint: Codable, Sendable, Hashable {
    public var date: Date
    public var percent: Int
    public var capacitymAh: Int?
    public var designCapacitymAh: Int?
    public var cycles: Int?

    enum CodingKeys: String, CodingKey { case date = "t", percent = "h", capacitymAh = "c", designCapacitymAh = "d", cycles = "n" }

    public init(date: Date, percent: Int, capacitymAh: Int?, designCapacitymAh: Int?, cycles: Int?) {
      self.date = date
      self.percent = percent
      self.capacitymAh = capacitymAh
      self.designCapacitymAh = designCapacitymAh
      self.cycles = cycles
    }

    public init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      date = Date(timeIntervalSince1970: try c.decode(Double.self, forKey: .date))
      percent = try c.decode(Int.self, forKey: .percent)
      capacitymAh = try c.decodeIfPresent(Int.self, forKey: .capacitymAh)
      designCapacitymAh = try c.decodeIfPresent(Int.self, forKey: .designCapacitymAh)
      cycles = try c.decodeIfPresent(Int.self, forKey: .cycles)
    }

    public func encode(to encoder: Encoder) throws {
      var c = encoder.container(keyedBy: CodingKeys.self)
      try c.encode(date.timeIntervalSince1970.rounded(), forKey: .date)
      try c.encode(percent, forKey: .percent)
      try c.encodeIfPresent(capacitymAh, forKey: .capacitymAh)
      try c.encodeIfPresent(designCapacitymAh, forKey: .designCapacitymAh)
      try c.encodeIfPresent(cycles, forKey: .cycles)
    }
  }

  public var samples: [Sample] = []
  public var energy: [EnergyBucket] = []
  public var health: [HealthPoint] = []
  /// When the charger was last connected and disconnected, as seen while Glade ran.
  public var pluggedInAt: Date?
  public var unpluggedAt: Date?

  public init() {}

  // MARK: Limits

  /// How often the charge is written down, and the most a stretch of energy covers.
  public static let sampleInterval: TimeInterval = 300
  static let fineSamples: TimeInterval = 2 * 86_400
  static let coarseStep: TimeInterval = 1800
  static let keepSamples: TimeInterval = 30 * 86_400
  static let fineEnergy: TimeInterval = 12 * 3600
  static let keepEnergy: TimeInterval = 7 * 86_400
  static let appsPerBucket = 12
  static let keepHealth: TimeInterval = 3 * 365 * 86_400
  static let otherID = "other"

  // MARK: Recording

  public mutating func add(_ reading: BatteryReading, now: Date = Date()) {
    guard let percent = reading.percent, reading.hasBattery else { return }
    let sample = Sample(
      date: now, percent: percent, state: reading.state, batteryWatts: reading.batteryWatts,
      systemWatts: reading.systemWatts, temperature: reading.temperatureCelsius
    )
    // The very first sample can’t tell when the charger came or went.
    if let last = samples.last, last.isPluggedIn != sample.isPluggedIn {
      if sample.isPluggedIn { pluggedInAt = now } else { unpluggedAt = now }
    }
    samples.append(sample)
    if let health = reading.healthPercent, Calendar.current.isDate(self.health.last?.date ?? .distantPast, inSameDayAs: now) == false {
      self.health.append(HealthPoint(
        date: now, percent: health, capacitymAh: reading.capacitymAh, designCapacitymAh: reading.designCapacitymAh,
        cycles: reading.cycleCount
      ))
    }
  }

  /// Adds what each app used over the last stretch, keeping the largest few by name and
  /// the rest as one "Other".
  public mutating func add(energy apps: [AppEnergy], seconds: Double, onBattery: Bool, now: Date = Date()) {
    guard seconds > 0 else { return }
    energy.append(EnergyBucket(start: now.addingTimeInterval(-seconds), seconds: seconds, onBattery: onBattery, apps: Self.trim(apps)))
  }

  /// Thins and trims everything to its limits.
  public mutating func compact(now: Date = Date()) {
    samples = Self.thin(samples.filter { now.timeIntervalSince($0.date) <= Self.keepSamples }, now: now)
    var fine: [EnergyBucket] = []
    var hourly: [Date: EnergyBucket] = [:]
    for bucket in energy where now.timeIntervalSince(bucket.start) <= Self.keepEnergy {
      if now.timeIntervalSince(bucket.start) <= Self.fineEnergy && bucket.seconds < 3600 {
        fine.append(bucket)
        continue
      }
      let hour = Calendar.current.dateInterval(of: .hour, for: bucket.start)?.start ?? bucket.start
      var merged = hourly[hour] ?? EnergyBucket(start: hour, seconds: 0, onBattery: true, apps: [])
      merged.seconds += bucket.seconds
      merged.onBattery = merged.onBattery && bucket.onBattery
      merged.apps = Self.trim(merged.apps + bucket.apps)
      hourly[hour] = merged
    }
    energy = (hourly.values.sorted { $0.start < $1.start }) + fine.sorted { $0.start < $1.start }
    health = Array(health.filter { now.timeIntervalSince($0.date) <= Self.keepHealth }.suffix(1200))
  }

  /// Every five minutes for two days, then one sample per half hour.
  static func thin(_ samples: [Sample], now: Date) -> [Sample] {
    var kept: [Sample] = []
    var slot: Int?
    for sample in samples {
      let age = now.timeIntervalSince(sample.date)
      if age <= fineSamples {
        kept.append(sample)
        continue
      }
      let current = Int(sample.date.timeIntervalSince1970 / coarseStep)
      // Plugging in or unplugging is always kept, so charging periods stay accurate.
      if current != slot || kept.last.map({ $0.isPluggedIn != sample.isPluggedIn }) == true {
        kept.append(sample)
        slot = current
      }
    }
    return Array(kept.suffix(4000))
  }

  static func trim(_ apps: [AppEnergy]) -> [AppEnergy] {
    var totals: [String: AppEnergy] = [:]
    for app in apps {
      if var existing = totals[app.id] {
        existing.joules += app.joules
        totals[app.id] = existing
      } else {
        totals[app.id] = app
      }
    }
    let sorted = totals.values.filter { $0.joules > 0 }.sorted { $0.joules > $1.joules }
    let other = sorted.dropFirst(appsPerBucket).reduce(0) { $0 + $1.joules }
    var kept = Array(sorted.prefix(appsPerBucket))
    if other > 0 {
      if let index = kept.firstIndex(where: { $0.id == otherID }) {
        kept[index].joules += other
      } else {
        kept.append(AppEnergy(id: otherID, name: "Everything else", bundlePath: nil, joules: other))
      }
    }
    return kept.map { var app = $0; app.joules = (app.joules * 10).rounded() / 10; return app }
  }

  // MARK: Reading

  public func samples(since: Date) -> [Sample] { samples.filter { $0.date >= since } }

  /// What each app used since a moment, largest first, and the seconds that covers.
  public func energy(since: Date) -> (apps: [AppEnergy], seconds: Double) {
    var totals: [String: AppEnergy] = [:]
    var seconds = 0.0
    for bucket in energy where bucket.start.addingTimeInterval(bucket.seconds) > since {
      // A bucket that straddles the start counts in proportion.
      let overlap = min(bucket.seconds, bucket.start.addingTimeInterval(bucket.seconds).timeIntervalSince(since))
      let share = bucket.seconds > 0 ? max(0, overlap) / bucket.seconds : 1
      seconds += bucket.seconds * share
      for app in bucket.apps {
        totals[app.id, default: AppEnergy(id: app.id, name: app.name, bundlePath: app.bundlePath, joules: 0)].joules += app.joules * share
      }
    }
    return (totals.values.sorted { $0.joules > $1.joules }, seconds)
  }

  /// When the current stretch on the charger began, from the samples if Glade wasn’t
  /// watching when it was plugged in.
  public func pluggedInSince(now: Date = Date()) -> Date? {
    guard let last = samples.last, last.isPluggedIn else { return nil }
    if let pluggedInAt, pluggedInAt <= last.date { return pluggedInAt }
    return samples.reversed().prefix { $0.isPluggedIn }.last?.date
  }

  /// When the current stretch on battery began.
  public func unpluggedSince(now: Date = Date()) -> Date? {
    guard let last = samples.last, !last.isPluggedIn else { return nil }
    if let unpluggedAt, unpluggedAt <= last.date { return unpluggedAt }
    return samples.reversed().prefix { !$0.isPluggedIn }.last?.date
  }

  /// Seconds at or above a charge while plugged in, since the charger was connected.
  public func secondsAtOrAbove(_ percent: Int, since: Date, now: Date = Date()) -> Double {
    let recent = samples.filter { $0.date >= since }
    var total = 0.0
    for (index, sample) in recent.enumerated() where sample.isPluggedIn && sample.percent >= percent {
      let next = index + 1 < recent.count ? recent[index + 1].date : now
      // A gap means Glade wasn’t running; it isn’t counted.
      total += min(next.timeIntervalSince(sample.date), Self.sampleInterval * 2)
    }
    return total
  }
}

/// Where the history lives: Application Support, next to the settings.
public enum BatteryHistoryStore {
  public static var url: URL { GladePaths.support.appendingPathComponent("battery-history.json") }
  /// Past this the oldest energy is dropped, whatever the time limits allow.
  static let maximumBytes = 1_500_000

  public static func load(from url: URL = url) -> BatteryHistory {
    guard let data = try? Data(contentsOf: url) else { return BatteryHistory() }
    do {
      return try JSONDecoder().decode(BatteryHistory.self, from: data)
    } catch {
      Log.warning(.system, "Battery history couldn’t be read, starting again: \(error)")
      return BatteryHistory()
    }
  }

  public static func save(_ history: BatteryHistory, to url: URL = url) {
    var history = history
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    do {
      var data = try encoder.encode(history)
      while data.count > maximumBytes, !history.energy.isEmpty {
        history.energy.removeFirst(max(1, history.energy.count / 4))
        data = try encoder.encode(history)
      }
      try data.write(to: url, options: .atomic)
    } catch {
      Log.error(.system, "Battery history couldn’t be saved to \(url.path): \(error)")
    }
  }
}
