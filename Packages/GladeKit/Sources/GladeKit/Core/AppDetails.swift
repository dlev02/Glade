import Foundation

/// Where an installed app came from, when the Mac can tell.
public enum AppSource: String, Codable, Sendable, Hashable {
  case appStore, setapp, homebrew, other

  public var title: String {
    switch self {
    case .appStore: "App Store"
    case .setapp: "Setapp"
    case .homebrew: "Homebrew"
    case .other: "Downloaded"
    }
  }
}

/// What an installed app finding is made of: the app, the data that goes with it, and
/// what is left where it is and why. The finding’s `paths` are the app followed by the
/// data folders in `parts`.
public struct AppDetails: Codable, Sendable, Hashable {
  /// One thing that goes to the Trash with the app.
  public struct Part: Codable, Sendable, Hashable {
    public var path: String
    /// Where it sits, in words: "Application Support", "Caches".
    public var label: String
    public var bytes: Int64

    public init(path: String, label: String, bytes: Int64) {
      self.path = path
      self.label = label
      self.bytes = bytes
    }
  }

  /// Something that looks like the app’s but stays, and why.
  public struct Kept: Codable, Sendable, Hashable {
    public var path: String
    public var label: String
    public var reason: String

    public init(path: String, label: String, reason: String) {
      self.path = path
      self.label = label
      self.reason = reason
    }
  }

  public var bundleID: String
  public var name: String
  public var version: String?
  public var source: AppSource
  public var bundlePath: String
  public var bundleBytes: Int64
  public var parts: [Part]
  public var kept: [Kept]
  /// When it was last opened, from Spotlight, Glade’s own record of apps coming to the
  /// front, or the time its program was last read, whichever is latest.
  public var lastOpened: Date?
  /// The vendor’s own uninstaller, when the app has one. Glade opens it rather than
  /// removing the app itself.
  public var uninstaller: String?
  /// The app belongs to the system account, so only Finder (with the person’s
  /// password) can move it to the Trash.
  public var needsAdministrator: Bool

  public init(
    bundleID: String, name: String, version: String?, source: AppSource, bundlePath: String, bundleBytes: Int64,
    parts: [Part], kept: [Kept], lastOpened: Date?, uninstaller: String?, needsAdministrator: Bool
  ) {
    self.bundleID = bundleID
    self.name = name
    self.version = version
    self.source = source
    self.bundlePath = bundlePath
    self.bundleBytes = bundleBytes
    self.parts = parts
    self.kept = kept
    self.lastOpened = lastOpened
    self.uninstaller = uninstaller
    self.needsAdministrator = needsAdministrator
  }

  /// Space the app’s data takes, apart from the app itself.
  public var dataBytes: Int64 { parts.reduce(0) { $0 + $1.bytes } }
}
