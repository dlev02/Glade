import CoreGraphics
import Foundation

/// What the person is doing right now, so suggestions and automations can stay out of
/// the way of real work, calls and games.
public struct ActivityContext: Codable, Sendable {
  public struct FrontApp: Codable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var bundleIdentifier: String?
    public var category: String?
    public var isFullScreen: Bool
  }

  /// One sign that an app is doing something the person cares about.
  public struct Signal: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
      case highCPU, preventingSleep, playingAudio, capturingAudio
    }

    public var kind: Kind
    public var appID: String
    public var appName: String
    /// "64% CPU", "Playing video", "microphone in use".
    public var detail: String
  }

  public var date: Date
  public var frontmostApp: FrontApp?
  /// Seconds since the last key press, click, scroll or mouse movement.
  public var secondsSinceInput: Double
  /// `nil` when the session state couldn't be read.
  public var isScreenLocked: Bool?
  public var isDisplayAsleep: Bool?
  public var onBattery: Bool
  public var lowPowerMode: Bool
  /// A game, or a game launcher, is in front.
  public var isGaming: Bool
  /// Why `isGaming` is set, in a few words.
  public var gamingReason: String?
  public var signals: [Signal]

  /// Processor share, as a share of one core, above which an app counts as busy.
  public static let busyCPUPercent = 20.0

  /// Builds the context from an apps listing, which already carries audio, sleep and
  /// window details. Costs well under a millisecond on top of that listing.
  public static func current(apps: [AppUsage], power: PowerStats? = nil, now: Date = Date()) -> ActivityContext {
    let power = power ?? HostReader.power()
    let front = apps.first { $0.isFrontmost && $0.kind == .app } ?? apps.first { $0.isFrontmost }

    var gamingReason: String?
    if let front, front.isGame {
      if let category = front.category, category.lowercased().contains("games") {
        gamingReason = "\(front.name) is a game (\(category))"
      } else if let bundleID = front.bundleIdentifier, GameDetection.launchers.contains(bundleID.lowercased()) {
        gamingReason = "\(front.name) is a game launcher"
      } else {
        gamingReason = "\(front.name) was installed by a game store"
      }
    }

    var signals: [Signal] = []
    for app in apps where !app.isGlade {
      if app.cpuPercent >= busyCPUPercent {
        signals.append(Signal(kind: .highCPU, appID: app.id, appName: app.name, detail: "\(Int(app.cpuPercent.rounded()))% CPU"))
      }
      if let reason = app.preventingSleep, !app.isSystem {
        signals.append(Signal(kind: .preventingSleep, appID: app.id, appName: app.name, detail: reason))
      }
      if app.isPlayingAudio && !app.isSystem {
        signals.append(Signal(kind: .playingAudio, appID: app.id, appName: app.name, detail: "playing sound"))
      }
      if app.isCapturingAudio && !app.isSystem {
        signals.append(Signal(kind: .capturingAudio, appID: app.id, appName: app.name, detail: "microphone in use"))
      }
    }

    return ActivityContext(
      date: now,
      frontmostApp: front.map {
        FrontApp(id: $0.id, name: $0.name, bundleIdentifier: $0.bundleIdentifier, category: $0.category, isFullScreen: $0.isFullScreen)
      },
      secondsSinceInput: secondsSinceInput(),
      isScreenLocked: screenLocked(),
      isDisplayAsleep: CGDisplayIsAsleep(CGMainDisplayID()) != 0,
      onBattery: power.onBattery,
      lowPowerMode: power.lowPowerMode,
      isGaming: gamingReason != nil,
      gamingReason: gamingReason,
      signals: signals
    )
  }

  static func secondsSinceInput() -> Double {
    // kCGAnyInputEventType is ~0; C enums accept any raw value.
    if let any = CGEventType(rawValue: ~0) {
      return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
    }
    let types: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDown, .scrollWheel]
    return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
  }

  static func screenLocked() -> Bool? {
    guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return nil }
    return (session["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue ?? false
  }
}
