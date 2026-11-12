import AppKit
import GladeKit
import SwiftUI

/// Draws a screen into a PNG without showing a window, so layouts can be checked from
/// the command line. Glass and blur don’t draw offscreen; everything else does.
public enum Snapshotter {
  /// Every screen that can be drawn, by name. Each area of the app adds its own
  /// (including variants such as a sheet or an empty state) in its `…Snapshots` file.
  static var registry: [String: (AppModel) -> AnyView] {
    var all: [String: (AppModel) -> AnyView] = [
      "window": { _ in AnyView(RootView()) },
      "overview": { _ in AnyView(NavigationStack { OverviewScreen() }) },
      "overview-usage": { model in
        model.usage = AppModel.sampleUsage(volume: model.snapshot?.disk ?? .current())
        return AnyView(DiskUsageSheet(close: {}).background(Color(nsColor: .windowBackgroundColor)))
      },
    ]
    for group in [StorageSnapshots.all, AppSnapshots.all, PerformanceSnapshots.all, BatterySnapshots.all, AssistantSnapshots.all, SettingsSnapshots.all, HistorySnapshots.all] {
      all.merge(group) { _, new in new }
    }
    return all
  }

  public static var screens: [String] { registry.keys.sorted() }

  public enum SnapshotError: Error, LocalizedError {
    case unknownScreen(String)
    case couldNotDraw

    public var errorDescription: String? {
      switch self {
      case .unknownScreen(let name): "Unknown screen “\(name)”. Run `snapshot list` for the names."
      case .couldNotDraw: "The screen couldn’t be drawn."
      }
    }
  }

  /// - Parameters:
  ///   - screen: One of `screens`. `window` is the whole main window showing `section`.
  ///   - live: Use this Mac’s real last scan instead of made-up findings.
  public static func render(
    screen: String, section: AppModel.Section = .overview, size: CGSize, dark: Bool, live: Bool, to url: URL
  ) async throws {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    application.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)

    let model = AppModel(live: false)
    var sample = await SampleData.capture()
    if live, let scan = ScanEngine.loadLast() { sample.scan = scan }
    model.loadSample(sample)
    model.appearance = dark ? .dark : .light
    model.section = section

    guard let build = registry[screen] else { throw SnapshotError.unknownScreen(screen) }
    let content = build(model)

    let root = content
      .environment(model)
      .accent(model.tint)
      // Drawn as the frontmost window would be; the render’s own window never is.
      .environment(\.appearsActive, true)
      .frame(width: size.width, height: size.height)
      .background(Color(nsColor: .windowBackgroundColor))
    let host = NSHostingView(rootView: root)
    host.frame = CGRect(origin: .zero, size: size)
    let window = NSWindow(
      contentRect: CGRect(origin: CGPoint(x: 80, y: 80), size: size),
      styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false
    )
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.contentView = host
    // On screen but fully transparent, so lists and tables lay out as they would for
    // real without anything flashing up.
    window.alphaValue = 0
    window.ignoresMouseEvents = true
    window.orderBack(nil)

    // Let onAppear, tasks and layout settle.
    for _ in 0..<6 {
      try? await Task.sleep(for: .milliseconds(150))
      host.layoutSubtreeIfNeeded()
    }
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw SnapshotError.couldNotDraw }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else { throw SnapshotError.couldNotDraw }
    try data.write(to: url)
    window.orderOut(nil)
  }
}
