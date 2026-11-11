import Foundation

/// How boldly a plan selects things.
public enum CleanLevel: String, Codable, Sendable, CaseIterable, Identifiable, Comparable {
  /// Only what rebuilds itself and hasn't been touched lately.
  case careful
  /// Adds things that download or reinstall, when they've sat idle.
  case balanced
  /// Everything that can come back, however recently it was used.
  case aggressive

  public var id: String { rawValue }
  public var title: String { rawValue.capitalized }

  private var rank: Int {
    switch self {
    case .careful: 0
    case .balanced: 1
    case .aggressive: 2
    }
  }

  public static func < (lhs: CleanLevel, rhs: CleanLevel) -> Bool { lhs.rank < rhs.rank }
}

public enum Effort: String, Codable, Sendable, CaseIterable, Identifiable {
  case automatic, low, medium, high, max

  public var id: String { rawValue }
  public var title: String { self == .automatic ? "Default" : rawValue.capitalized }
}

public struct AssistantSettings: Codable, Sendable, Equatable {
  /// Providers in the order to try them. The first one that's ready is used.
  public var order: [String]
  /// The everyday model for each provider. A provider that isn't listed uses its default.
  public var models: [String: String]
  /// The stronger model to call in when the everyday one asks for a closer look.
  public var deepModels: [String: String]
  /// The provider to call in for a closer look, or `nil` to stay with the same one.
  public var deepProvider: String?
  public var effort: Effort
  /// Let assistants that run in the cloud see short excerpts of file contents.
  /// Off by default: they get names, sizes and dates only.
  public var shareExcerpts: Bool
  /// Let the assistant look at the Mac by itself when a threshold trips.
  public var proactive: Bool
  /// The most assistant runs Glade starts by itself in a day. `nil` means no limit.
  public var runsPerDay: Int?
  /// Seconds before a run is abandoned.
  public var timeout: Double

  public init() {
    order = ["claude", "codex", "apple"]
    models = [:]
    deepModels = [:]
    deepProvider = nil
    effort = .automatic
    shareExcerpts = false
    proactive = false
    runsPerDay = 6
    timeout = 180
  }

  public init(from decoder: Decoder) throws {
    self.init()
    let c = try decoder.container(keyedBy: CodingKeys.self)
    order = try c.decodeIfPresent([String].self, forKey: .order) ?? order
    models = try c.decodeIfPresent([String: String].self, forKey: .models) ?? models
    deepModels = try c.decodeIfPresent([String: String].self, forKey: .deepModels) ?? deepModels
    deepProvider = try c.decodeIfPresent(String.self, forKey: .deepProvider)
    effort = try c.decodeIfPresent(Effort.self, forKey: .effort) ?? effort
    shareExcerpts = try c.decodeIfPresent(Bool.self, forKey: .shareExcerpts) ?? shareExcerpts
    proactive = try c.decodeIfPresent(Bool.self, forKey: .proactive) ?? proactive
    if c.contains(.runsPerDay) { runsPerDay = try c.decodeIfPresent(Int.self, forKey: .runsPerDay) }
    timeout = try c.decodeIfPresent(Double.self, forKey: .timeout) ?? timeout
  }
}

public struct AutomationSettings: Codable, Sendable, Equatable {
  public var enabled: Bool
  /// Notify when free space drops below this many gigabytes.
  public var storageFreeGB: Double
  public var storageAlerts: Bool
  /// Run the Careful clean without asking when storage is low.
  public var autoCleanOnLowStorage: Bool
  public var memoryAlerts: Bool
  /// Notify when total processor use stays above this percentage…
  public var cpuPercent: Double
  /// …for this many minutes.
  public var cpuMinutes: Double
  public var cpuAlerts: Bool
  public var gpuPercent: Double
  public var gpuMinutes: Double
  public var gpuAlerts: Bool
  /// Minutes before the same alert can fire again.
  public var quietMinutes: Double

  public init() {
    enabled = true
    storageFreeGB = 20
    storageAlerts = true
    autoCleanOnLowStorage = false
    memoryAlerts = true
    cpuPercent = 90
    cpuMinutes = 5
    cpuAlerts = true
    gpuPercent = 95
    gpuMinutes = 10
    gpuAlerts = false
    quietMinutes = 60
  }

  public init(from decoder: Decoder) throws {
    self.init()
    let c = try decoder.container(keyedBy: CodingKeys.self)
    enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
    storageFreeGB = try c.decodeIfPresent(Double.self, forKey: .storageFreeGB) ?? storageFreeGB
    storageAlerts = try c.decodeIfPresent(Bool.self, forKey: .storageAlerts) ?? storageAlerts
    autoCleanOnLowStorage = try c.decodeIfPresent(Bool.self, forKey: .autoCleanOnLowStorage) ?? autoCleanOnLowStorage
    memoryAlerts = try c.decodeIfPresent(Bool.self, forKey: .memoryAlerts) ?? memoryAlerts
    cpuPercent = try c.decodeIfPresent(Double.self, forKey: .cpuPercent) ?? cpuPercent
    cpuMinutes = try c.decodeIfPresent(Double.self, forKey: .cpuMinutes) ?? cpuMinutes
    cpuAlerts = try c.decodeIfPresent(Bool.self, forKey: .cpuAlerts) ?? cpuAlerts
    gpuPercent = try c.decodeIfPresent(Double.self, forKey: .gpuPercent) ?? gpuPercent
    gpuMinutes = try c.decodeIfPresent(Double.self, forKey: .gpuMinutes) ?? gpuMinutes
    gpuAlerts = try c.decodeIfPresent(Bool.self, forKey: .gpuAlerts) ?? gpuAlerts
    quietMinutes = try c.decodeIfPresent(Double.self, forKey: .quietMinutes) ?? quietMinutes
  }
}

public struct IndexSettings: Codable, Sendable, Equatable {
  /// Build and keep a searchable understanding of what files contain. Everything
  /// stays on this Mac.
  public var enabled: Bool
  /// Folders to index.
  public var folders: [String]
  /// Read the text in images and scanned pages.
  public var readTextInImages: Bool

  public init() {
    enabled = false
    folders = ["~/Downloads", "~/Desktop", "~/Documents"]
    readTextInImages = true
  }

  public init(from decoder: Decoder) throws {
    self.init()
    let c = try decoder.container(keyedBy: CodingKeys.self)
    enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
    folders = try c.decodeIfPresent([String].self, forKey: .folders) ?? folders
    readTextInImages = try c.decodeIfPresent(Bool.self, forKey: .readTextInImages) ?? readTextInImages
  }
}

/// Settings the engine needs. Stored as one JSON file so the app and the command line
/// read the same thing.
public struct GladeConfig: Codable, Sendable, Equatable {
  /// Folders the person has put off limits, on top of the built-in ones.
  public var protectedPaths: [String]
  /// Built-in protections that can be lifted, by zone identifier.
  public var unlockedZones: [String]
  /// Where projects live. Empty means look in the usual places.
  public var projectRoots: [String]
  /// Categories left out of scans.
  public var ignoredCategories: [StorageCategory]
  /// Send everything the Trash can take to it, even things that rebuild themselves.
  /// Simulators and worktrees are always removed by their own tools.
  public var trashEverything: Bool
  public var level: CleanLevel
  /// Apps the assistant must never suggest quitting, by bundle identifier or name.
  public var keepRunning: [String]
  public var assistant: AssistantSettings
  public var automation: AutomationSettings
  public var index: IndexSettings

  public init() {
    protectedPaths = []
    unlockedZones = []
    projectRoots = []
    ignoredCategories = []
    trashEverything = false
    level = .balanced
    keepRunning = []
    assistant = AssistantSettings()
    automation = AutomationSettings()
    index = IndexSettings()
  }

  public init(from decoder: Decoder) throws {
    self.init()
    let c = try decoder.container(keyedBy: CodingKeys.self)
    protectedPaths = try c.decodeIfPresent([String].self, forKey: .protectedPaths) ?? protectedPaths
    unlockedZones = try c.decodeIfPresent([String].self, forKey: .unlockedZones) ?? unlockedZones
    projectRoots = try c.decodeIfPresent([String].self, forKey: .projectRoots) ?? projectRoots
    ignoredCategories = try c.decodeIfPresent([StorageCategory].self, forKey: .ignoredCategories) ?? ignoredCategories
    trashEverything = try c.decodeIfPresent(Bool.self, forKey: .trashEverything) ?? trashEverything
    level = try c.decodeIfPresent(CleanLevel.self, forKey: .level) ?? level
    keepRunning = try c.decodeIfPresent([String].self, forKey: .keepRunning) ?? keepRunning
    assistant = try c.decodeIfPresent(AssistantSettings.self, forKey: .assistant) ?? assistant
    automation = try c.decodeIfPresent(AutomationSettings.self, forKey: .automation) ?? automation
    index = try c.decodeIfPresent(IndexSettings.self, forKey: .index) ?? index
  }
}

/// Reads and writes the settings file.
public enum ConfigStore {
  public static func load(from url: URL = GladePaths.config) -> GladeConfig {
    guard let data = try? Data(contentsOf: url) else { return GladeConfig() }
    do {
      return try JSONDecoder().decode(GladeConfig.self, from: data)
    } catch {
      Log.error(.app, "Settings file couldn’t be read, using defaults: \(error)")
      return GladeConfig()
    }
  }

  public static func save(_ config: GladeConfig, to url: URL = GladePaths.config) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
      try encoder.encode(config).write(to: url, options: .atomic)
    } catch {
      Log.error(.app, "Settings couldn’t be saved to \(url.path): \(error)")
    }
  }
}

/// Small shared JSON helpers so every file Glade writes looks the same.
public enum JSONFiles {
  public static func encoder(pretty: Bool = true) -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }

  public static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }

  public static func write<T: Encodable>(_ value: T, to url: URL) throws {
    try encoder().encode(value).write(to: url, options: .atomic)
  }

  public static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? decoder().decode(type, from: data)
  }

  public static func string<T: Encodable>(_ value: T, pretty: Bool = true) -> String {
    (try? encoder(pretty: pretty).encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
  }
}

public enum Format {
  /// "12.4 GB", in the decimal units Finder uses, with only as many digits as help:
  /// "995 GB", "20.6 GB", "4.42 GB", "0 KB".
  public static func bytes(_ value: Int64) -> String {
    let units = ["KB", "MB", "GB", "TB"]
    var amount = Double(max(value, 0)) / 1000
    var unit = 0
    while amount >= 999.5, unit < units.count - 1 {
      amount /= 1000
      unit += 1
    }
    let digits = unit < 2 || amount >= 99.95 ? 0 : amount >= 9.995 ? 1 : 2
    return "\(amount.formatted(.number.precision(.fractionLength(0...digits)))) \(units[unit])"
  }

  /// "3 days ago", "5 months ago", or "today".
  public static func age(_ date: Date?, now: Date = Date()) -> String {
    guard let date else { return "unknown" }
    let days = Int(now.timeIntervalSince(date) / 86_400)
    switch days {
    case ..<1: return "today"
    case 1: return "yesterday"
    case ..<14: return "\(days) days ago"
    case ..<60: return "\(days / 7) weeks ago"
    case ..<730: return "\(days / 30) months ago"
    default: return "\(days / 365) years ago"
    }
  }

  public static func percent(_ fraction: Double) -> String {
    "\(Int((fraction * 100).rounded()))%"
  }
}
