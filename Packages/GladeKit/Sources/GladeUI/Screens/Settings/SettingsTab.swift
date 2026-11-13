import GladeKit
import SwiftUI

/// The tabs of the Settings window, each with its own fixed size so the window fits
/// what it’s showing, as Mac settings windows do.
enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
  case general, protection, assistant, alerts, network, search, advanced

  var id: String { rawValue }

  var title: String {
    switch self {
    case .general: "General"
    case .protection: "Protection"
    case .assistant: "Assistant"
    case .alerts: "Alerts"
    case .network: "Network"
    case .search: "Search"
    case .advanced: "Advanced"
    }
  }

  var symbol: String {
    switch self {
    case .general: Symbols.settings
    case .protection: Symbols.protected
    case .assistant: Symbols.assistant
    case .alerts: "bell.badge"
    case .network: "wifi"
    case .search: "text.magnifyingglass"
    case .advanced: "wrench.and.screwdriver"
    }
  }

  static let width: CGFloat = 600

  var height: CGFloat {
    switch self {
    case .general: 452
    case .protection: 520
    case .assistant: 720
    case .alerts: BatteryReader.hasBattery ? 790 : 540
    case .network: 400
    case .search: 360
    case .advanced: 600
    }
  }
}
