import Foundation
import Synchronization

/// Reads sleeps from `pmset -g log`. The log can run to tens of megabytes, almost all
/// of it about sleep requests, so only the sleep and wake lines are kept (filtered by
/// `grep` before Glade sees them), only the last two weeks are parsed, and the result
/// is cached for half an hour.
public enum SleepLog {
  /// How far back sleeps are kept.
  public static let days = 14
  static let refresh: TimeInterval = 1800

  private struct Cache: Sendable {
    var date: Date
    var records: [SleepRecord]
  }

  private static let cache = Mutex<Cache?>(nil)

  /// Recent sleeps, newest first.
  public static func recent(force: Bool = false, now: Date = Date()) async -> [SleepRecord] {
    if !force, let cached = cache.withLock({ $0 }), now.timeIntervalSince(cached.date) < refresh { return cached.records }
    let started = Date()
    // The filter is fixed text; nothing from outside goes into it.
    let script = "/usr/bin/pmset -g log | /usr/bin/grep -E ' (Sleep|Wake|DarkWake|Start) +\t'"
    do {
      let result = try await Shell.run("/bin/sh", ["-c", script], timeout: 30, quiet: true)
      // grep exits 1 when nothing matched, which just means no sleeps.
      guard !result.timedOut, result.status == 0 || result.status == 1 else {
        Log.warning(.system, "pmset -g log failed (exit \(result.status)\(result.timedOut ? ", timed out" : "")); sleep history unavailable")
        return cache.withLock { $0?.records } ?? []
      }
      let records = parse(result.stdout, since: now.addingTimeInterval(-Double(days) * 86_400))
      cache.withLock { $0 = Cache(date: now, records: records) }
      Log.debug(.system, "Read \(records.count) sleeps from the power log in \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
      return records
    } catch {
      Log.warning(.system, "pmset -g log couldn’t run: \(error.localizedDescription)")
      return cache.withLock { $0?.records } ?? []
    }
  }

  // MARK: Parsing

  /// Turns the log’s Sleep, Wake, DarkWake and Start lines into sleeps, newest first.
  ///
  /// Each line is `<date> <domain>\t<message>\t<duration>\t<delay>`. A sleep starts at
  /// the first Sleep line, carries on through dark wakes and "back to sleep" lines,
  /// and ends at a full Wake (or a restart, which a Start line marks).
  public static func parse(_ text: String, since: Date = .distantPast) -> [SleepRecord] {
    var records: [SleepRecord] = []
    var open: SleepRecord?

    for line in text.split(whereSeparator: \.isNewline) {
      guard let entry = Entry(line) else { continue }
      switch entry.domain {
      case "Sleep":
        guard entry.message.contains("Sleep") else { continue }
        if open == nil {
          let raw = quoted(entry.message) ?? "Sleep"
          open = SleepRecord(
            start: entry.date, end: entry.date, reason: sleepReason(raw), rawReason: raw,
            chargeBefore: charge(entry.message), chargeAfter: nil,
            onBattery: entry.message.lowercased().contains("using batt"), wokeBy: nil, rawWokeBy: nil, wakes: []
          )
        }
      case "DarkWake":
        guard var sleep = open else { continue }
        let raw = cause(entry.message)
        if entry.message.contains("FullWake") {
          sleep.end = entry.date
          sleep.chargeAfter = charge(entry.message)
          sleep.wokeBy = wakeReason(raw)
          sleep.rawWokeBy = raw
          records.append(sleep)
          open = nil
        } else {
          sleep.wakes.append(.init(date: entry.date, reason: wakeReason(raw), raw: raw, seconds: entry.seconds))
          sleep.chargeAfter = charge(entry.message) ?? sleep.chargeAfter
          open = sleep
        }
      case "Wake":
        guard var sleep = open, entry.message.contains("Wake") else { continue }
        let raw = cause(entry.message)
        sleep.end = entry.date
        sleep.chargeAfter = charge(entry.message) ?? sleep.chargeAfter
        sleep.wokeBy = wakeReason(raw)
        sleep.rawWokeBy = raw
        records.append(sleep)
        open = nil
      case "Start":
        // powerd starting again means the Mac restarted or shut down while asleep.
        if var sleep = open {
          sleep.end = entry.date
          records.append(sleep)
          open = nil
        }
      default:
        continue
      }
    }
    return records.filter { $0.end >= since && $0.seconds >= 60 }.sorted { $0.start > $1.start }
  }

  /// One line of the log, split into its columns.
  struct Entry {
    var date: Date
    var domain: String
    var message: String
    var seconds: Double?

    private static let stamp: Date.ParseStrategy = .init(
      format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits) \(timeZone: .iso8601(.short))",
      locale: Locale(identifier: "en_US_POSIX"), timeZone: .gmt
    )

    init?(_ line: Substring) {
      let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
      guard columns.count >= 2, columns[0].count > 26 else { return nil }
      let head = columns[0]
      let stampText = String(head.prefix(25))
      guard let date = try? Date(stampText, strategy: Self.stamp) else { return nil }
      self.date = date
      domain = head.dropFirst(26).trimmingCharacters(in: .whitespaces)
      message = columns[1].trimmingCharacters(in: .whitespaces)
      if columns.count >= 3 {
        let duration = columns[2].trimmingCharacters(in: .whitespaces)
        seconds = duration.split(separator: " ").first.flatMap { Double($0) }
      }
    }
  }

  /// The charge in "(Charge:85%)".
  static func charge(_ message: String) -> Int? {
    guard let range = message.range(of: "Charge:") else { return nil }
    let digits = message[range.upperBound...].prefix { $0.isNumber || $0 == " " }.filter(\.isNumber)
    return Int(digits)
  }

  /// The text in the first pair of single quotes: "'Clamshell Sleep'".
  static func quoted(_ message: String) -> String? {
    guard let open = message.firstIndex(of: "'") else { return nil }
    let rest = message[message.index(after: open)...]
    guard let close = rest.firstIndex(of: "'") else { return nil }
    return String(rest[..<close])
  }

  /// What follows "due to", up to "Using".
  static func cause(_ message: String) -> String {
    guard let range = message.range(of: "due to ") else { return message }
    var rest = message[range.upperBound...]
    if let using = rest.range(of: " Using ") { rest = rest[..<using.lowerBound] }
    return rest.trimmingCharacters(in: .whitespaces)
  }

  static func sleepReason(_ raw: String) -> String {
    let text = raw.lowercased()
    if text.contains("clamshell") { return "Lid closed" }
    if text.contains("idle") { return "Left idle" }
    if text.contains("power button") { return "Power button" }
    if text.contains("low power") || text.contains("battery") { return "Battery low" }
    if text.contains("thermal") { return "Too hot" }
    if text.contains("software") { return "Put to sleep" }
    if text.contains("maintenance") || text.contains("sleep service") { return "Back to sleep" }
    return raw
  }

  /// What woke the Mac, in a few words that fit after "for" or "by".
  static func wakeReason(_ raw: String) -> String {
    let text = raw.lowercased()
    if text.contains("lid") { return "the lid opening" }
    if text.contains("hid activity") || text.contains("multi-touch") || text.contains("keyboard") || text.contains("mouse") {
      return "the keyboard or trackpad"
    }
    if text.contains("pwrbtn") || text.contains("power button") { return "the power button" }
    if text.contains("sleepservice") { return "Power Nap" }
    if text.contains("maintenance") { return "a check-in by macOS" }
    if text.contains("acattach") || text.contains("ac attach") || text.contains("adapter") || text.contains("usb-c power") { return "the charger" }
    if text.contains("wifibt") || text.contains("wlan") || text.contains("arpt") || text.contains("wifi") || text.contains("en0") || text.contains("network") {
      return "the network"
    }
    if text.contains("bluetooth") { return "Bluetooth" }
    if text.contains("rtc") || text.contains("alarm") { return "a timer" }
    if text.contains("usb") || text.contains("xhc") { return "a USB device" }
    if text.contains("notification") { return "a notification" }
    return "something else"
  }
}
