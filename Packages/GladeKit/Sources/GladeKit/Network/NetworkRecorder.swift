import Foundation

/// Keeps the record of data used while the app runs. Once a minute it reads the
/// interfaces’ counters (no traffic, almost no work) and `nettop`’s totals per process
/// (a few hundredths of a second). Like the battery recorder it has no timer: the
/// app’s sampling loop hands it the time and it decides whether anything is due.
public actor NetworkRecorder {
  public static let interval: TimeInterval = 60

  private var history: NetworkHistory
  private let url: URL?
  private let sampler = SystemSampler()
  private var lastCounters: [String: InterfaceCounters.Totals]?
  private var lastProcessTotals: [Int32: TrafficReader.Bytes]?
  private var lastSample: Date?
  private var lastSave: Date?

  public init(url: URL? = NetworkHistoryStore.url) {
    self.url = url
    history = url.map { NetworkHistoryStore.load(from: $0) } ?? NetworkHistory()
  }

  public var current: NetworkHistory { history }

  /// Returns the history when something was added.
  @discardableResult
  public func record(now: Date = Date()) async -> NetworkHistory? {
    guard lastSample.map({ now.timeIntervalSince($0) >= Self.interval }) ?? true else { return nil }
    let elapsed = lastSample.map { now.timeIntervalSince($0) } ?? 0
    lastSample = now

    // The interfaces: what moved since the last minute. A counter that went down was
    // reset (the interface restarted), so its new value is all new traffic.
    let counters = InterfaceCounters.physical()
    let network = Self.networkName()
    var changed = false
    if let last = lastCounters, elapsed < Self.interval * 10 {
      var received: UInt64 = 0, sent: UInt64 = 0
      for (name, now) in counters {
        let before = last[name]
        received += before.map { now.received >= $0.received ? now.received - $0.received : now.received } ?? 0
        sent += before.map { now.sent >= $0.sent ? now.sent - $0.sent : now.sent } ?? 0
      }
      history.add(received: received, sent: sent, network: network, seconds: elapsed, now: now)
      changed = true
    }
    lastCounters = counters

    // The apps: a process seen for the first time started since the last minute, so
    // all of its traffic is new; one whose total went down is a reused process number.
    let totals = await TrafficReader.totals()
    if let last = lastProcessTotals, elapsed < Self.interval * 10, !totals.isEmpty {
      var moved: [Int32: TrafficReader.Bytes] = [:]
      for (pid, now) in totals {
        if let before = last[pid], now.received >= before.received, now.sent >= before.sent {
          moved[pid] = .init(name: now.name, received: now.received - before.received, sent: now.sent - before.sent)
        } else {
          moved[pid] = now
        }
      }
      let processes = await sampler.processes()
      let names = Dictionary(processes.map { ($0.pid, $0.name) }, uniquingKeysWith: { first, _ in first })
      history.add(apps: TrafficReader.attribute(moved, apps: AppGrouper.group(processes), names: names), now: now)
      changed = true
    }
    if !totals.isEmpty { lastProcessTotals = totals }

    guard changed else { return nil }
    if let url, lastSave.map({ now.timeIntervalSince($0) >= 300 }) ?? true {
      history.compact(now: now)
      NetworkHistoryStore.save(history, to: url)
      lastSave = now
    }
    return history
  }

  /// Saves what’s been recorded, for when the app quits.
  public func flush() {
    guard let url else { return }
    history.compact()
    NetworkHistoryStore.save(history, to: url)
  }

  /// The Wi-Fi network’s name when Location access allows it, else the medium.
  static func networkName() -> String {
    if let link = WiFiLink.current() { return link.networkName ?? "Wi-Fi" }
    return InterfaceCounters.physical().isEmpty ? "Other" : "Ethernet"
  }
}
