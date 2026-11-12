import Foundation
import GladeKit
import SwiftUI

/// Installed apps, drawn with `glade snapshot <name>`. Panels are 300 wide; sheets
/// take `--width 440`.
enum AppSnapshots {
  static var all: [String: (AppModel) -> AnyView] {
    StorageScreen.drawsOffscreen = true
    return screens
  }

  private static let screens: [String: (AppModel) -> AnyView] = [
    // Review lists every app; the other groups fold away so the apps show.
    "storage-apps": { model in
      let state = StorageViewState(scope: .review, showsInspector: false)
      state.collapsed = Set(StorageCategory.allCases).subtracting([.installedApps])
      return AnyView(NavigationStack { StorageScreen(state: state) })
    },
    "storage-app-inspector": { model in panel(app(model, "Final Cut Pro")) },
    "storage-app-uninstaller": { model in panel(app(model, "Adobe Photoshop 2025")) },
    "storage-app-finder": { model in panel(app(model, "Xcode")) },
    "storage-uninstall-confirm": { model in
      if let id = app(model, "Final Cut Pro")?.id { model.focusClean(on: [id]) }
      return sheet(CleanConfirmation(cancel: {}, confirm: {}))
    },
    "storage-uninstall-confirm-several": { model in
      model.focusClean(on: ["Final Cut Pro", "iMovie", "Minecraft"].compactMap { app(model, $0)?.id })
      return sheet(CleanConfirmation(cancel: {}, confirm: {}))
    },
  ]

  private static func app(_ model: AppModel, _ name: String) -> Finding? {
    model.scan?.findings.first { $0.isApp && $0.title == name }
  }

  private static func panel(_ finding: Finding?) -> AnyView {
    AnyView(
      FindingInspector(finding: finding).frame(width: 300).frame(maxHeight: .infinity, alignment: .top)
    )
  }

  private static func sheet(_ content: some View) -> AnyView {
    AnyView(
      content
        .frame(width: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    )
  }
}
