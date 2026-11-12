import GladeKit

/// What the Battery section shows, refreshed by `AppModel.sampleBattery()`.
public struct BatteryState {
  public var status: BatteryStatus?
  public var history = BatteryHistory()
  public var awake: AwakeReport?
  /// Recent sleeps, newest first, once the power log has been read.
  public var sleeps: [SleepRecord] = []
  public var sleepsLoaded = false
  public var suggestions: [PerformanceSuggestion] = []
  /// The last hour’s energy per app, for suggestions.
  public var hourEnergy: EnergyReport?
  /// Fixed energy tables for snapshots and sample data, by period.
  var sampleEnergy: [EnergyPeriod: EnergyReport]?

  public init() {}
}
