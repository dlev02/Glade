import Foundation
import IOKit
import IOKit.ps

/// The battery and charger right now, from IOPowerSources and the AppleSmartBattery
/// registry entry. A Mac without a battery gets a reading with `hasBattery` false and
/// whatever is known about its power.
public struct BatteryReading: Codable, Sendable, Hashable {
  public enum State: String, Codable, Sendable {
    case charging
    case onBattery
    /// Plugged in, below full, and not charging: a limit, Optimised Battery Charging,
    /// heat, or a charger that can’t keep up. `notChargingReason` says which.
    case notCharging
    /// Plugged in and full.
    case charged
    /// This Mac has no battery.
    case noBattery
  }

  public struct Adapter: Codable, Sendable, Hashable {
    /// What the charger is rated for.
    public var watts: Int?
    /// "USB-C charger", "MagSafe charger", or the charger’s own name.
    public var name: String
    /// What macOS calls it, such as "pd charger", for the technical view.
    public var rawDescription: String?
    public var isWireless: Bool
  }

  public var date: Date
  public var hasBattery: Bool
  public var state: State
  /// Charge, 0–100.
  public var percent: Int?
  /// Why it’s plugged in but not charging, in a few words: "Holding at 80%, your limit".
  public var notChargingReason: String?
  /// macOS’s own estimates. `nil` while it’s still working them out.
  public var minutesToFull: Int?
  public var minutesToEmpty: Int?
  public var adapter: Adapter?
  /// Watts flowing into the battery (positive) or out of it (negative).
  public var batteryWatts: Double?
  /// What the whole Mac is using right now.
  public var systemWatts: Double?
  /// What the charger is delivering right now.
  public var adapterWatts: Double?
  public var temperatureCelsius: Double?
  public var voltage: Double?
  /// Milliamps into (positive) or out of (negative) the battery.
  public var amperage: Int?
  public var cycleCount: Int?
  /// The cycles the battery is designed for (1000 on recent Mac laptops).
  public var designCycleCount: Int?
  /// What it holds when full now, as macOS counts it for Battery Health.
  public var capacitymAh: Int?
  /// What it held when new.
  public var designCapacitymAh: Int?
  /// The gauge’s own figure for a full charge, before macOS’s smoothing.
  public var rawMaxCapacitymAh: Int?
  /// What’s in it now.
  public var currentCapacitymAh: Int?
  /// `capacitymAh` against `designCapacitymAh`: System Settings’ "Maximum Capacity".
  public var healthPercent: Int?
  /// "Normal", or what macOS says when it isn’t: "Service Recommended".
  public var condition: String?
  public var lowPowerMode: Bool

  public var isPluggedIn: Bool { state == .charging || state == .notCharging || state == .charged || (state == .noBattery && adapter != nil) }

  /// The health in a word or two, for a panel’s corner.
  public var healthTitle: String {
    if let condition, condition.lowercased() != "normal" { return condition }
    guard let healthPercent else { return "Unknown" }
    return healthPercent >= 80 ? "Normal" : "Worn"
  }
}

/// Reads the battery. Each call is a few IOKit property reads; safe every few seconds.
public enum BatteryReader {
  /// Whether this Mac has a battery at all. Read once; batteries don’t come and go.
  public static let hasBattery: Bool = {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return false }
    let sources = (IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as [AnyObject]?) ?? []
    return sources.contains { source in
      (IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any])?[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
    }
  }()

  /// - Parameter limit: The charge limit, so a battery held at it can say so.
  public static func read(limit: ChargeLimit? = nil, now: Date = Date()) -> BatteryReading {
    let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    var reading = BatteryReading(
      date: now, hasBattery: false, state: .noBattery, percent: nil, notChargingReason: nil,
      minutesToFull: nil, minutesToEmpty: nil, adapter: adapter(), batteryWatts: nil, systemWatts: nil,
      adapterWatts: nil, temperatureCelsius: nil, voltage: nil, amperage: nil, cycleCount: nil,
      designCycleCount: nil, capacitymAh: nil, designCapacitymAh: nil, rawMaxCapacitymAh: nil,
      currentCapacitymAh: nil, healthPercent: nil, condition: nil, lowPowerMode: lowPower
    )
    guard let description = internalBattery() else { return reading }
    reading.hasBattery = true

    if let current = description[kIOPSCurrentCapacityKey] as? Int, let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 {
      reading.percent = min(100, Int((Double(current) / Double(maximum) * 100).rounded()))
    }
    let onBattery = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue
    let charging = description[kIOPSIsChargingKey] as? Bool ?? false
    let charged = description[kIOPSIsChargedKey] as? Bool ?? false
    if let minutes = description[kIOPSTimeToFullChargeKey] as? Int, minutes > 0 { reading.minutesToFull = minutes }
    if let minutes = description[kIOPSTimeToEmptyKey] as? Int, minutes > 0 { reading.minutesToEmpty = minutes }
    if let condition = description["BatteryHealthCondition"] as? String, !condition.isEmpty { reading.condition = condition }

    let registry = SmartBatteryRegistry()
    reading.cycleCount = registry.int("CycleCount")
    reading.designCycleCount = registry.int("DesignCycleCount9C")
    reading.voltage = registry.int("Voltage").map { Double($0) / 1000 }
    reading.amperage = registry.int("Amperage")
    let data = registry.dictionary("BatteryData")
    reading.designCapacitymAh = number(data?["DesignCapacity"]) ?? registry.int("DesignCapacity")
    reading.capacitymAh = number(data?["NominalChargeCapacity"]) ?? registry.int("NominalChargeCapacity")
    reading.rawMaxCapacitymAh = number(data?["AppleRawMaxCapacity"]) ?? registry.int("AppleRawMaxCapacity")
    reading.currentCapacitymAh = number(data?["AppleRawCurrentCapacity"]) ?? registry.int("AppleRawCurrentCapacity")
    // System Settings’ own figure when it has been read; the gauge’s otherwise.
    if let health = BatteryHealthReader.cached {
      reading.healthPercent = health.maximumCapacity
      if reading.condition == nil { reading.condition = health.condition }
    }
    if reading.healthPercent == nil, let capacity = reading.capacitymAh ?? reading.rawMaxCapacitymAh, let design = reading.designCapacitymAh, design > 0 {
      reading.healthPercent = min(100, Int((Double(capacity) / Double(design) * 100).rounded()))
    }
    if reading.condition == nil, let failure = number(data?["PermanentFailureStatus"]), failure != 0 { reading.condition = "Service Recommended" }

    if let volts = reading.voltage, let amps = reading.amperage {
      reading.batteryWatts = volts * Double(amps) / 1000
    }
    let telemetry = registry.dictionary("PowerTelemetryData")
    if let load = number(telemetry?["SystemLoad"]), load > 0 { reading.systemWatts = Double(load) / 1000 }
    if let input = number(telemetry?["SystemPowerIn"]), input >= 0, !onBattery { reading.adapterWatts = Double(input) / 1000 }
    if reading.systemWatts == nil, onBattery, let watts = reading.batteryWatts { reading.systemWatts = -watts }
    reading.temperatureCelsius = registry.packTemperature()

    if onBattery {
      reading.state = .onBattery
      reading.adapter = nil
    } else if charging {
      reading.state = .charging
    } else if charged || (reading.percent ?? 0) >= 100 {
      reading.state = .charged
    } else {
      reading.state = .notCharging
      reading.notChargingReason = notChargingReason(reading, registry: registry, limit: limit)
    }
    return reading
  }

  /// Why a plugged-in battery below full isn’t charging, as best the readings tell.
  static func notChargingReason(_ reading: BatteryReading, registry: SmartBatteryRegistry, limit: ChargeLimit?) -> String {
    let percent = reading.percent ?? 0
    if let target = limit?.percent, percent >= target - 1 { return "Holding at \(percent)%, your limit" }
    let charger = registry.dictionary("ChargerData")
    let thermal = number(charger?["TimeChargingThermallyLimited"]) ?? 0
    if thermal > 0 || (reading.temperatureCelsius ?? 0) >= 40 { return "Paused while the battery cools down" }
    if let rated = reading.adapter?.watts, let using = reading.systemWatts, using >= Double(rated) * 0.9 {
      return "The charger can only just keep up with what the Mac is using"
    }
    if (75...85).contains(percent) { return "Paused at \(percent)% to protect the battery" }
    return "Plugged in, not charging"
  }

  private static func internalBattery() -> [String: Any]? {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
      SystemIssues.warn("IOPSCopyPowerSourcesInfo.battery", "IOPSCopyPowerSourcesInfo returned nothing; battery unavailable")
      return nil
    }
    let sources = (IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as [AnyObject]?) ?? []
    for source in sources {
      guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
        description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
      else { continue }
      return description
    }
    return nil
  }

  private static func adapter() -> BatteryReading.Adapter? {
    guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] else { return nil }
    let watts = number(details[kIOPSPowerAdapterWattsKey])
    let raw = details["Description"] as? String
    let given = (details["Name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    let wireless = (details["IsWireless"] as? Bool) ?? false
    let name: String
    if let given {
      name = given
    } else if raw?.lowercased().contains("pd") == true || raw?.lowercased().contains("usb") == true {
      name = "USB-C charger"
    } else if raw?.lowercased().contains("magsafe") == true {
      name = "MagSafe charger"
    } else {
      name = "Charger"
    }
    return .init(watts: watts.flatMap { $0 > 0 ? $0 : nil }, name: name, rawDescription: raw, isWireless: wireless)
  }

  /// A number from the registry as a signed integer. Negative currents arrive as huge
  /// unsigned values; `int64Value` turns them back.
  static func number(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber else { return nil }
    return Int(truncatingIfNeeded: number.int64Value)
  }
}

/// Property reads on the AppleSmartBattery entry, one key at a time: the whole entry
/// carries large blobs that aren’t needed.
final class SmartBatteryRegistry {
  private let service: io_service_t

  init() {
    service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    if service == 0 { SystemIssues.warn("AppleSmartBattery", "No AppleSmartBattery registry entry; battery detail unavailable") }
  }

  deinit {
    if service != 0 { IOObjectRelease(service) }
  }

  func value(_ key: String) -> Any? {
    guard service != 0 else { return nil }
    return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
  }

  func int(_ key: String) -> Int? { BatteryReader.number(value(key)) }
  func dictionary(_ key: String) -> [String: Any]? { value(key) as? [String: Any] }

  /// Hundredths of a degree on the battery pack beneath this entry (macOS 27 keeps it
  /// there), or on the entry itself on earlier versions.
  func packTemperature() -> Double? {
    if let direct = int("Temperature"), direct > 0 { return Double(direct) / 100 }
    let pack = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBatteryPack"))
    guard pack != 0 else { return nil }
    defer { IOObjectRelease(pack) }
    let data = IORegistryEntryCreateCFProperty(pack, "BatteryData" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any]
    guard let raw = BatteryReader.number(data?["Temperature"] ?? data?["VirtualTemperature"]), raw > 0 else { return nil }
    return Double(raw) / 100
  }
}
