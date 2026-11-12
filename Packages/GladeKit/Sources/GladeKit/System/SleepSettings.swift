import Foundation

/// The sleep settings that decide whether the Mac can sleep at all. Read from the
/// power-management preferences file, which every user can read.
public struct SleepSettings: Codable, Sendable, Hashable {
  /// `pmset disablesleep 1`: nothing sleeps until it’s turned back on.
  public var sleepDisabled: Bool
  /// Minutes of idle before sleep on the charger and on battery; 0 means never.
  public var chargerSleepMinutes: Int?
  public var batterySleepMinutes: Int?

  public static let file = URL(fileURLWithPath: "/Library/Preferences/com.apple.PowerManagement.plist")

  public static func read(from url: URL = file) -> SleepSettings {
    guard let data = try? Data(contentsOf: url),
      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    else {
      SystemIssues.warn("PowerManagement.plist", "Power settings file couldn’t be read; sleep settings unknown")
      return SleepSettings(sleepDisabled: false, chargerSleepMinutes: nil, batterySleepMinutes: nil)
    }
    let system = plist["SystemPowerSettings"] as? [String: Any]
    let charger = plist["AC Power"] as? [String: Any]
    let battery = plist["Battery Power"] as? [String: Any]
    return SleepSettings(
      sleepDisabled: (system?["SleepDisabled"] as? Bool) ?? false,
      chargerSleepMinutes: charger?["System Sleep Timer"] as? Int,
      batterySleepMinutes: battery?["System Sleep Timer"] as? Int
    )
  }
}
