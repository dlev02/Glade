import Foundation

/// One app, simulator or process keeping the Mac (or just its screen) awake, with every
/// request it holds folded together.
public struct AwakeHolder: Codable, Sendable, Identifiable, Hashable {
  public enum Kind: String, Codable, Sendable {
    /// An app Glade can ask to quit.
    case app
    /// A simulated device; shutting it down keeps its data.
    case simulator
    /// A command-line tool such as `caffeinate`. Glade doesn’t stop these; the app that
    /// started it can.
    case process
    /// Part of macOS.
    case system
  }

  /// The app id, `simulator:<UDID>`, or `process:<name>`.
  public var id: String
  public var kind: Kind
  /// As a person knows it: "Safari", "iPhone 17 Pro", "caffeinate".
  public var name: String
  public var appID: String?
  public var bundlePath: String?
  public var simulatorUDID: String?
  public var pid: Int32
  /// Keeps the screen on rather than only the Mac.
  public var holdsDisplay: Bool
  /// When the oldest of its requests began.
  public var since: Date?
  /// What it’s doing, in a few words: "Playing sound", "Running caffeinate".
  public var reason: String
  /// The app or terminal that started a command-line tool, when it can be told.
  public var startedBy: String?
  /// The process that holds the request for it, such as coreaudiod for sound.
  public var heldBy: String?
  /// The names and kinds macOS reports, for the technical view.
  public var rawNames: [String]
  public var rawTypes: [String]
  /// How many requests were folded into this row.
  public var count: Int
  /// Seconds until macOS lets the request go by itself, when there’s a timeout.
  public var timeoutSeconds: Double?

  /// "Playing sound", "Keeps the screen on", "Running caffeinate, started by Terminal".
  public var sentence: String {
    var text = AwakeReasons.isGeneric(reason) ? AwakeReasons.scope(display: holdsDisplay) : reason
    if holdsDisplay, !AwakeReasons.isGeneric(reason) { text += " and keeping the screen on" }
    if let startedBy { text += ", started by \(startedBy)" }
    return text
  }

  public func seconds(now: Date = Date()) -> Double? { since.map { max(0, now.timeIntervalSince($0)) } }
}
