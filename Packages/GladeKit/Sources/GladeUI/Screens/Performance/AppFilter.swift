import GladeKit

/// Which rows the apps table shows.
enum AppFilter: String, CaseIterable, Identifiable {
  /// Apps the person opened.
  case apps
  /// Apps and standalone processes such as `node`, but not macOS’s own.
  case everything
  /// Everything, including macOS’s own processes.
  case all

  var id: String { rawValue }

  var title: String {
    switch self {
    case .apps: "Apps"
    case .everything: "Processes"
    case .all: "All"
    }
  }

  /// What the choice adds, for its tooltip.
  var help: String {
    switch self {
    case .apps: "Apps you opened"
    case .everything: "Plus background tools like node"
    case .all: "Including macOS"
    }
  }

  func includes(_ app: AppUsage) -> Bool {
    switch self {
    case .apps: app.kind == .app && !app.isSystem
    case .everything: !app.isSystem
    case .all: true
    }
  }
}
