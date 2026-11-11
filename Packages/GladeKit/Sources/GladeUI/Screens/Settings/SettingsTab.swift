import SwiftUI

/// The tabs of the Settings window, each with its own fixed size so the window fits
/// what it's showing, as Mac settings windows do.
enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
  case general, protection, assistant, alerts, search, advanced

  var id: String { rawValue }

  var title: String {
    switch self {
    case .general: "General"
    case .protection: "Protection"
    case .assistant: "Assistant"
    case .alerts: "Alerts"
    case .search: "Search"
    case .advanced: "Advanced"
    }
  }

  var symbol: String {
    switch self {
    case .general: "gearshape"
    case .protection: "lock.shield"
    case .assistant: "sparkles"
    case .alerts: "bell.badge"
    case .search: "text.magnifyingglass"
    case .advanced: "wrench.and.screwdriver"
    }
  }

  static let width: CGFloat = 600

  var height: CGFloat {
    switch self {
    case .general: 350
    case .protection: 640
    case .assistant: 660
    case .alerts: 640
    case .search: 360
    case .advanced: 600
    }
  }
}
