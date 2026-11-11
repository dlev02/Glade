import Foundation

/// The one place the product's name lives, so a rename is a single edit.
public enum Brand {
  public static let name = "Glade"
  public static let cli = "glade"
  public static let repository = "https://github.com/dlev02/Glade"
  public static let issuesURL = "https://github.com/dlev02/Glade/issues/new"

  public static var version: String {
    appBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
  }

  public static var build: String {
    appBundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
  }

  /// The app bundle, found even when Glade was started through the `glade` link, where
  /// the system's idea of the main bundle is the folder holding the link.
  public static let appBundle: Bundle = {
    if Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") != nil { return .main }
    guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return .main }
    let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return app.pathExtension == "app" ? Bundle(url: app) ?? .main : .main
  }()
}

/// Where Glade keeps its own files. Everything is local to this Mac.
public enum GladePaths {
  public static var home: String { NSHomeDirectory() }

  public static var support: URL {
    directory(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent(Brand.name, isDirectory: true))
  }

  public static var logs: URL {
    directory(FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Logs/\(Brand.name)", isDirectory: true))
  }

  public static var receipts: URL { directory(support.appendingPathComponent("Receipts", isDirectory: true)) }
  public static var agentRuns: URL { directory(support.appendingPathComponent("AgentRuns", isDirectory: true)) }
  public static var config: URL { support.appendingPathComponent("config.json") }
  public static var lastScan: URL { support.appendingPathComponent("last-scan.json") }
  public static var activity: URL { support.appendingPathComponent("activity.json") }
  public static var index: URL { support.appendingPathComponent("index.sqlite") }

  private static func directory(_ url: URL) -> URL {
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
