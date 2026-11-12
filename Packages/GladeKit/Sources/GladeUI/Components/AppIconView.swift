import AppKit
import SwiftUI

/// An app’s icon, looked up from where the app lives on disk.
public struct AppIconView: View {
  var path: String?
  var size: CGFloat

  public init(path: String?, size: CGFloat = 28) {
    self.path = path
    self.size = size
  }

  public var body: some View {
    Group {
      if let path, let icon = AppIcons.icon(for: path) {
        Image(nsImage: icon)
          .resizable()
          .interpolation(.high)
      } else {
        Image(systemName: "gearshape.2")
          .font(.system(size: size * 0.5))
          .foregroundStyle(.secondary)
          .frame(width: size, height: size)
          .background(Palette.track, in: .rect(cornerRadius: size * 0.24))
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

/// Icons looked up once per app rather than on every redraw: asking Launch Services
/// for an icon takes about a millisecond, and the apps table redraws every reading.
enum AppIcons {
  private static let cache: NSCache<NSString, NSImage> = {
    let cache = NSCache<NSString, NSImage>()
    cache.countLimit = 400
    return cache
  }()
  /// Paths with nothing there, so a missing app isn’t looked for again on every redraw.
  private static var missing: Set<String> = []

  /// Where an app lives, from an `AppUsage.id`: a bundle identifier or `path:<path>`.
  /// For showing the icon of an app that isn’t running (sample data, or one that has
  /// just quit).
  static func path(forAppID id: String) -> String? {
    if id.hasPrefix("path:") { return String(id.dropFirst(5)) }
    guard id.contains("."), !id.contains(":") else { return nil }
    if let known = bundlePaths[id] { return known }
    let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.path
    bundlePaths[id] = path
    return path
  }

  private static var bundlePaths: [String: String?] = [:]

  static func icon(for path: String) -> NSImage? {
    if let icon = cache.object(forKey: path as NSString) { return icon }
    if missing.contains(path) { return nil }
    guard FileManager.default.fileExists(atPath: path) else {
      missing.insert(path)
      return nil
    }
    let icon = NSWorkspace.shared.icon(forFile: path)
    cache.setObject(icon, forKey: path as NSString)
    return icon
  }
}
