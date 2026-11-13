import Foundation

/// How much data this Mac moved while Glade was open: hour by hour for each network it
/// was on, and day by day for each app, for 90 days. macOS keeps no record an app can
/// read, so anything before Glade started recording is unknown, and so is any time it
/// wasn’t running; `observed` says how much of each hour was seen.
public struct NetworkHistory: Codable, Sendable, Equatable {
  public struct Hour: Codable, Sendable, Equatable {
    public var start: Date
    /// The Wi-Fi network’s name when Location access allows it, else “Wi-Fi” or “Ethernet”.
    public var network: String
    public var received: UInt64
    public var sent: UInt64
    /// Seconds of the hour Glade was recording.
    public var observed: Double
  }

  public struct AppDay: Codable, Sendable, Equatable {
    public var day: Date
    public var id: String
    public var name: String
    public var received: UInt64
    public var sent: UInt64
  }

  public struct Total: Codable, Sendable, Equatable {
    public var name: String
    public var received: UInt64
    public var sent: UInt64
    public var total: UInt64 { received + sent }
  }

  public var hours: [Hour] = []
  public var appDays: [AppDay] = []
  /// When recording began.
  public var since: Date?

  public static let keptDays = 90
  /// Apps kept per day; the rest are added into “Other apps”.
  static let appsPerDay = 30

  public init() {}

  public mutating func add(received: UInt64, sent: UInt64, network: String, seconds: Double, now: Date = Date()) {
    if since == nil { since = now }
    let start = Calendar.current.dateInterval(of: .hour, for: now)?.start ?? now
    if let index = hours.lastIndex(where: { $0.start == start && $0.network == network }) {
      hours[index].received += received
      hours[index].sent += sent
      hours[index].observed = min(3_600, hours[index].observed + seconds)
    } else {
      hours.append(Hour(start: start, network: network, received: received, sent: sent, observed: min(3_600, seconds)))
    }
  }

  public mutating func add(apps: [AppTraffic], now: Date = Date()) {
    if since == nil { since = now }
    let day = Calendar.current.startOfDay(for: now)
    for app in apps where app.total >= 1 {
      if let index = appDays.lastIndex(where: { $0.day == day && $0.id == app.id }) {
        appDays[index].received += UInt64(app.received)
        appDays[index].sent += UInt64(app.sent)
      } else {
        appDays.append(AppDay(day: day, id: app.id, name: app.name, received: UInt64(app.received), sent: UInt64(app.sent)))
      }
    }
  }

  /// Drops what’s older than 90 days and folds small apps into one row per day.
  public mutating func compact(now: Date = Date()) {
    let cutoff = now.addingTimeInterval(-Double(Self.keptDays) * 86_400)
    hours.removeAll { $0.start < cutoff }
    appDays.removeAll { $0.day < cutoff }
    let today = Calendar.current.startOfDay(for: now)
    var compacted: [AppDay] = []
    for (day, list) in Dictionary(grouping: appDays, by: \.day) {
      let sorted = list.sorted { $0.received + $0.sent > $1.received + $1.sent }
      guard day < today, sorted.count > Self.appsPerDay else {
        compacted += sorted
        continue
      }
      compacted += sorted.prefix(Self.appsPerDay - 1)
      let rest = sorted.dropFirst(Self.appsPerDay - 1)
      compacted.append(AppDay(day: day, id: "other", name: "Other apps", received: rest.map(\.received).reduce(0, +), sent: rest.map(\.sent).reduce(0, +)))
    }
    appDays = compacted.sorted { $0.day < $1.day }
  }

  // MARK: Questions

  public func total(since date: Date) -> Total {
    let list = hours.filter { $0.start >= Self.hourStart(date) }
    return Total(name: "All", received: list.map(\.received).reduce(0, +), sent: list.map(\.sent).reduce(0, +))
  }

  public func byNetwork(since date: Date) -> [Total] {
    let list = hours.filter { $0.start >= Self.hourStart(date) }
    return Dictionary(grouping: list, by: \.network).map { name, hours in
      Total(name: name, received: hours.map(\.received).reduce(0, +), sent: hours.map(\.sent).reduce(0, +))
    }.sorted { $0.total > $1.total }
  }

  public func byApp(since date: Date) -> [Total] {
    let day = Calendar.current.startOfDay(for: date)
    let list = appDays.filter { $0.day >= day }
    return Dictionary(grouping: list, by: \.id).compactMap { _, days in
      days.last.map { Total(name: $0.name, received: days.map(\.received).reduce(0, +), sent: days.map(\.sent).reduce(0, +)) }
    }.sorted { $0.total > $1.total }
  }

  public func byDay(since date: Date) -> [(day: Date, total: Total)] {
    let list = hours.filter { $0.start >= Self.hourStart(date) }
    return Dictionary(grouping: list) { Calendar.current.startOfDay(for: $0.start) }.map { day, hours in
      (day, Total(name: day.formatted(.iso8601.year().month().day()), received: hours.map(\.received).reduce(0, +), sent: hours.map(\.sent).reduce(0, +)))
    }.sorted { $0.day < $1.day }
  }

  /// Hours since `date` that Glade saw, as a share of the time that passed.
  public func coverage(since date: Date, now: Date = Date()) -> Double {
    let start = max(date, since ?? now)
    let span = now.timeIntervalSince(start)
    guard span > 60 else { return since == nil ? 0 : 1 }
    // Several networks in one hour each count their own seconds; cap per hour.
    let perHour = Dictionary(grouping: hours.filter { $0.start >= Self.hourStart(start) }, by: \.start).mapValues { min(3_600, $0.map(\.observed).reduce(0, +)) }
    return min(1, perHour.values.reduce(0, +) / span)
  }

  static func hourStart(_ date: Date) -> Date { Calendar.current.dateInterval(of: .hour, for: date)?.start ?? date }
}

/// Where the record lives: Application Support, next to the settings.
public enum NetworkHistoryStore {
  public static var url: URL { GladePaths.support.appendingPathComponent("network-history.json") }

  public static func load(from url: URL = url) -> NetworkHistory {
    guard let data = try? Data(contentsOf: url) else { return NetworkHistory() }
    do {
      return try JSONFiles.decoder().decode(NetworkHistory.self, from: data)
    } catch {
      Log.warning(.network, "Network history couldn’t be read, starting again: \(error)")
      return NetworkHistory()
    }
  }

  public static func save(_ history: NetworkHistory, to url: URL = url) {
    do {
      try JSONFiles.encoder(pretty: false).encode(history).write(to: url, options: .atomic)
    } catch {
      Log.warning(.network, "Network history couldn’t be saved: \(error)")
    }
  }
}
