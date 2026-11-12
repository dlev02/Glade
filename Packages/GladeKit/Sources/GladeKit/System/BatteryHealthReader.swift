import Foundation
import Synchronization

/// Battery health as System Settings shows it. macOS smooths "Maximum Capacity" over
/// time, so the gauge’s own figures can differ from it by a point or two; reading it
/// from `system_profiler` (a fifth of a second) keeps Glade and System Settings agreeing.
public enum BatteryHealthReader {
  public struct Health: Sendable, Hashable {
    /// "Maximum Capacity", 0–100.
    public var maximumCapacity: Int?
    /// "Normal", or what macOS says otherwise.
    public var condition: String?
    var readAt: Date
  }

  private static let cache = Mutex<Health?>(nil)
  /// Health moves over weeks; a few hours is fresh enough.
  static let refresh: TimeInterval = 6 * 3600

  public static var cached: Health? { cache.withLock { $0 } }

  public static func current(now: Date = Date()) async -> Health? {
    guard BatteryReader.hasBattery else { return nil }
    if let cached, now.timeIntervalSince(cached.readAt) < refresh { return cached }
    do {
      let result = try await Shell.run("/usr/sbin/system_profiler", ["SPPowerDataType", "-json", "-detailLevel", "mini"], timeout: 10, quiet: true)
      guard result.succeeded, let health = parse(result.stdout, now: now) else {
        SystemIssues.warn("system_profiler.power", "system_profiler SPPowerDataType gave no battery health (exit \(result.status)); using the gauge’s figures")
        return cached
      }
      cache.withLock { $0 = health }
      return health
    } catch {
      SystemIssues.warn("system_profiler.power.run", "system_profiler couldn’t run: \(error.localizedDescription)")
      return cached
    }
  }

  static func parse(_ json: String, now: Date) -> Health? {
    guard let data = json.data(using: .utf8),
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let items = root["SPPowerDataType"] as? [[String: Any]]
    else { return nil }
    for item in items {
      guard let info = item["sppower_battery_health_info"] as? [String: Any] else { continue }
      let capacity = (info["sppower_battery_health_maximum_capacity"] as? String)
        .flatMap { Int($0.filter(\.isNumber)) }
      let raw = info["sppower_battery_health"] as? String
      // System Settings words "Good" as "Normal".
      let condition = raw.map { $0.lowercased() == "good" ? "Normal" : $0 }
      return Health(maximumCapacity: capacity, condition: condition, readAt: now)
    }
    return nil
  }
}
