import GladeKit
import SwiftUI

/// What the host app provides for software updates, which live outside this package.
public struct UpdaterHooks {
  /// Opens the updater's "check now" flow. `nil` hides the menu item.
  public var checkForUpdates: (() -> Void)?
  public var automaticallyChecks: Binding<Bool>?

  public init(checkForUpdates: (() -> Void)? = nil, automaticallyChecks: Binding<Bool>? = nil) {
    self.checkForUpdates = checkForUpdates
    self.automaticallyChecks = automaticallyChecks
  }
}

extension EnvironmentValues {
  @Entry public var updater = UpdaterHooks()
}

/// Every scene the app has: the main window, the menu bar item and Settings.
public struct GladeScenes: Scene {
  private let model: AppModel
  private let updater: UpdaterHooks

  public init(model: AppModel, updater: UpdaterHooks = UpdaterHooks()) {
    self.model = model
    self.updater = updater
  }

  public var body: some Scene {
    Window(Brand.name, id: "main") {
      RootView()
        .environment(model)
        .environment(\.updater, updater)
    }
    .defaultSize(width: 1100, height: 740)
    .commands {
      GladeCommands(model: model, updater: updater)
    }

    MenuBarExtra {
      MenuBarView()
        .environment(model)
        .tint(model.tint)
        .preferredColorScheme(model.appearance.colorScheme)
    } label: {
      MenuBarLabel(model: model)
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView()
        .environment(model)
        .environment(\.updater, updater)
        .tint(model.tint)
        .preferredColorScheme(model.appearance.colorScheme)
    }
  }
}

/// The menu bar item itself: a small gauge, and free space when that's switched on.
struct MenuBarLabel: View {
  var model: AppModel

  var body: some View {
    let pressure = model.snapshot?.memory.pressure ?? .normal
    HStack(spacing: 4) {
      Image(systemName: pressure == .normal ? "leaf" : "leaf.fill")
      if model.menuBarShowsFreeSpace, let disk = model.snapshot?.disk {
        Text(Format.bytes(disk.availableBytes))
          .monospacedDigit()
      }
    }
    .accessibilityLabel(Brand.name)
  }
}

/// Menu bar commands, so everything is reachable from the keyboard.
struct GladeCommands: Commands {
  var model: AppModel
  var updater: UpdaterHooks
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandGroup(after: .appInfo) {
      if let check = updater.checkForUpdates {
        Button("Check for Updates…") { check() }
      }
    }
    CommandGroup(replacing: .newItem) {}
    CommandMenu("Scan") {
      Button("Scan Now") { model.startScan() }
        .keyboardShortcut("r")
        .disabled(model.isScanning)
      Button("Scan Including Duplicates") { model.startScan(deep: true) }
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .disabled(model.isScanning)
      Button("Stop Scanning") { model.cancelScan() }
        .keyboardShortcut(".")
        .disabled(!model.isScanning)
    }
    CommandGroup(after: .sidebar) {
      ForEach(Array(AppModel.Section.allCases.enumerated()), id: \.element) { index, section in
        Button(section.title) { model.section = section }
          .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
      }
      Divider()
    }
    CommandGroup(replacing: .help) {
      Button("Set Up \(Brand.name)…") { model.showsSetup = true }
      Button("Report a Problem…") {
        NotificationCenter.default.post(name: .gladeReportProblem, object: nil)
      }
      Link("\(Brand.name) on GitHub", destination: URL(string: Brand.repository)!)
    }
  }
}

extension Notification.Name {
  /// Posted by the Help menu; the settings window shows the report sheet.
  public static let gladeReportProblem = Notification.Name("gladeReportProblem")
}
