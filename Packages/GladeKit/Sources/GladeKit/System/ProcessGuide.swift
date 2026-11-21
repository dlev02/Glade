import Foundation

/// What an unfamiliar row in the apps list is, in a few plain words, and whether it’s
/// using far more than it should. Shown beside the name and given to the Assistant, so
/// "swift-frontend" or "Wi-Fi" at the top of the list means something.
public enum ProcessGuide {
  public struct Note: Sendable, Equatable {
    /// What it is: "Swift compiler".
    public var what: String?
    /// The apps that started it, for a command-line tool: "T3 Code, Terminal".
    public var startedBy: String?
    /// Set when it’s using far more than usual, with what to do.
    public var unusual: String?

    /// One line for beside the name: "Swift compiler · from Xcode".
    public var caption: String? {
      let parts = [what, startedBy.map { "from \($0)" }].compactMap { $0 }
      return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
  }

  /// Plain names, by process name or bundle identifier, lowercased.
  static let known: [String: String] = [
    "simulator devices": "Xcode’s test devices",
    "swift-frontend": "Swift compiler",
    "swift-build": "Swift build",
    "xcodebuild": "Xcode build",
    "clang": "C compiler",
    "ld": "Linker",
    "node": "JavaScript",
    "bun": "JavaScript",
    "deno": "JavaScript",
    "python": "Python",
    "python3": "Python",
    "java": "Java",
            "ollama": "AI models on this Mac",
    "qemu-system-aarch64": "Virtual machine",
    "esbuild": "Web build",
    "tsc": "TypeScript checker",
    "vite": "Web dev server",
    "com.apple.wifi.wifiagent": "macOS’s Wi-Fi menu",
    "windowserver": "Draws everything on screen",
    "kernel_task": "macOS itself",
    "mds_stores": "Spotlight indexing",
    "mdworker_shared": "Spotlight indexing",
    "photoanalysisd": "Photos library analysis",
    "mediaanalysisd": "Photo and video analysis",
    "backupd": "Time Machine",
    "softwareupdated": "Software Update",
  ]

  /// Helpers of macOS that normally stay small, with the most they should use. Above
  /// it they’re leaking, and macOS starts them again if they’re quit.
  static let ceilings: [String: Int64] = [
    "com.apple.wifi.wifiagent": 400_000_000,
    "com.apple.controlcenter": 600_000_000,
    "com.apple.notificationcenterui": 800_000_000,
    "com.apple.dock": 600_000_000,
    "com.apple.systemuiserver": 400_000_000,
    "com.apple.textinputmenuagent": 300_000_000,
  ]

  /// A macOS helper over its usual ceiling, which Glade may restart (`AppControl.restartHelper`).
  public static func isRestartable(_ app: AppUsage) -> Bool {
    guard let id = app.bundleIdentifier?.lowercased(), let ceiling = ceilings[id] else { return false }
    return app.memoryBytes > ceiling
  }

  public static func note(for app: AppUsage) -> Note? {
    let keys = [app.bundleIdentifier?.lowercased(), app.name.lowercased()].compactMap { $0 }
    let what = keys.lazy.compactMap { known[$0] }.first
    var unusual: String?
    if let key = keys.first(where: { ceilings[$0] != nil }), let ceiling = ceilings[key], app.memoryBytes > ceiling {
      unusual = "Using far more memory than usual, which is a fault in macOS. Restarting it gives the memory back; macOS opens it again by itself."
    }
    let startedBy = app.startedBy.flatMap { $0.isEmpty ? nil : $0.prefix(3).joined(separator: ", ") }
    guard what != nil || startedBy != nil || unusual != nil else { return nil }
    return Note(what: what, startedBy: startedBy, unusual: unusual)
  }
}
