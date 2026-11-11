import Foundation

/// Processor use across the whole Mac.
public struct CPUStats: Codable, Sendable, Hashable {
  /// Busy share of all cores together, 0–100.
  public var totalPercent: Double
  public var userPercent: Double
  public var systemPercent: Double
  /// Busy share of each core, 0–100, in the kernel’s core order.
  public var perCorePercent: [Double]
  public var logicalCores: Int
  public var performanceCores: Int?
  public var efficiencyCores: Int?
  /// The 1, 5 and 15 minute load averages.
  public var loadAverage: [Double]

  public init(
    totalPercent: Double, userPercent: Double, systemPercent: Double, perCorePercent: [Double],
    logicalCores: Int, performanceCores: Int?, efficiencyCores: Int?, loadAverage: [Double]
  ) {
    self.totalPercent = totalPercent
    self.userPercent = userPercent
    self.systemPercent = systemPercent
    self.perCorePercent = perCorePercent
    self.logicalCores = logicalCores
    self.performanceCores = performanceCores
    self.efficiencyCores = efficiencyCores
    self.loadAverage = loadAverage
  }
}

/// How hard macOS is working to find memory, as the kernel reports it.
public enum MemoryPressure: String, Codable, Sendable, Comparable {
  case normal, warning, critical

  private var rank: Int {
    switch self {
    case .normal: 0
    case .warning: 1
    case .critical: 2
    }
  }

  public static func < (lhs: MemoryPressure, rhs: MemoryPressure) -> Bool { lhs.rank < rhs.rank }
}

/// Memory, counted the way Activity Monitor counts it.
public struct MemoryStats: Codable, Sendable, Hashable {
  public var totalBytes: Int64
  /// App memory + wired + compressed: Activity Monitor’s "Memory Used".
  public var usedBytes: Int64
  public var appBytes: Int64
  public var wiredBytes: Int64
  public var compressedBytes: Int64
  /// File contents kept in memory, which macOS drops as soon as anything needs the room.
  public var cachedFilesBytes: Int64
  public var freeBytes: Int64
  public var swapUsedBytes: Int64
  public var swapTotalBytes: Int64
  public var pressure: MemoryPressure
  /// The kernel’s own estimate of how much memory is free, 0–100.
  public var freePercent: Int?

  public init(
    totalBytes: Int64, usedBytes: Int64, appBytes: Int64, wiredBytes: Int64, compressedBytes: Int64,
    cachedFilesBytes: Int64, freeBytes: Int64, swapUsedBytes: Int64, swapTotalBytes: Int64,
    pressure: MemoryPressure, freePercent: Int?
  ) {
    self.totalBytes = totalBytes
    self.usedBytes = usedBytes
    self.appBytes = appBytes
    self.wiredBytes = wiredBytes
    self.compressedBytes = compressedBytes
    self.cachedFilesBytes = cachedFilesBytes
    self.freeBytes = freeBytes
    self.swapUsedBytes = swapUsedBytes
    self.swapTotalBytes = swapTotalBytes
    self.pressure = pressure
    self.freePercent = freePercent
  }
}

/// The graphics processor, from the IORegistry.
public struct GPUStats: Codable, Sendable, Hashable {
  /// "Apple M3 Max", or several names joined when a Mac has more than one GPU.
  public var name: String?
  public var coreCount: Int?
  /// Busy share of the GPU, 0–100.
  public var utilizationPercent: Double?
  /// System memory the GPU driver is using right now.
  public var inUseMemoryBytes: Int64?
  /// System memory the GPU driver has set aside.
  public var allocatedMemoryBytes: Int64?

  public init(name: String?, coreCount: Int?, utilizationPercent: Double?, inUseMemoryBytes: Int64?, allocatedMemoryBytes: Int64?) {
    self.name = name
    self.coreCount = coreCount
    self.utilizationPercent = utilizationPercent
    self.inUseMemoryBytes = inUseMemoryBytes
    self.allocatedMemoryBytes = allocatedMemoryBytes
  }
}

public enum ThermalState: String, Codable, Sendable {
  case nominal, fair, serious, critical

  init(_ state: ProcessInfo.ThermalState) {
    switch state {
    case .nominal: self = .nominal
    case .fair: self = .fair
    case .serious: self = .serious
    case .critical: self = .critical
    @unknown default: self = .nominal
    }
  }
}

public struct PowerStats: Codable, Sendable, Hashable {
  public var onBattery: Bool
  public var hasBattery: Bool
  /// Charge, 0–100, when the Mac has a battery.
  public var batteryPercent: Int?
  public var isCharging: Bool?
  public var lowPowerMode: Bool

  public init(onBattery: Bool, hasBattery: Bool, batteryPercent: Int?, isCharging: Bool?, lowPowerMode: Bool) {
    self.onBattery = onBattery
    self.hasBattery = hasBattery
    self.batteryPercent = batteryPercent
    self.isCharging = isCharging
    self.lowPowerMode = lowPowerMode
  }
}

/// One cheap reading of the whole Mac. Safe to take every few seconds indefinitely.
public struct SystemSnapshot: Codable, Sendable {
  public var date: Date
  /// Seconds the processor figures are averaged over.
  public var intervalSeconds: Double
  public var cpu: CPUStats
  public var memory: MemoryStats
  /// `nil` when the GPU doesn’t publish statistics.
  public var gpu: GPUStats?
  public var disk: VolumeInfo
  public var thermal: ThermalState
  public var power: PowerStats
  public var bootDate: Date?
  public var uptimeSeconds: Double

  public init(
    date: Date, intervalSeconds: Double, cpu: CPUStats, memory: MemoryStats, gpu: GPUStats?,
    disk: VolumeInfo, thermal: ThermalState, power: PowerStats, bootDate: Date?, uptimeSeconds: Double
  ) {
    self.date = date
    self.intervalSeconds = intervalSeconds
    self.cpu = cpu
    self.memory = memory
    self.gpu = gpu
    self.disk = disk
    self.thermal = thermal
    self.power = power
    self.bootDate = bootDate
    self.uptimeSeconds = uptimeSeconds
  }
}
