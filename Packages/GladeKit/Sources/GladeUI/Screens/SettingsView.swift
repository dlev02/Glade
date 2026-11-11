import GladeKit
import SwiftUI

/// The Settings window: one tab per area, every change applied as it's made.
struct SettingsView: View {
  @State private var tab: SettingsTab
  @State private var showsReport = false

  /// - Parameter initialTab: The tab showing when the window opens. Only snapshots
  ///   choose anything other than General.
  init(initialTab: SettingsTab = .general) {
    _tab = State(initialValue: initialTab)
  }

  var body: some View {
    TabView(selection: $tab) {
      Tab(SettingsTab.general.title, systemImage: SettingsTab.general.symbol, value: .general) {
        GeneralPane().settingsPane(.general)
      }
      Tab(SettingsTab.protection.title, systemImage: SettingsTab.protection.symbol, value: .protection) {
        ProtectionPane().settingsPane(.protection)
      }
      Tab(SettingsTab.assistant.title, systemImage: SettingsTab.assistant.symbol, value: .assistant) {
        AssistantPane().settingsPane(.assistant)
      }
      Tab(SettingsTab.alerts.title, systemImage: SettingsTab.alerts.symbol, value: .alerts) {
        AlertsPane().settingsPane(.alerts)
      }
      Tab(SettingsTab.search.title, systemImage: SettingsTab.search.symbol, value: .search) {
        SearchPane().settingsPane(.search)
      }
      Tab(SettingsTab.advanced.title, systemImage: SettingsTab.advanced.symbol, value: .advanced) {
        AdvancedPane(showsReport: $showsReport).settingsPane(.advanced)
      }
    }
    .sheet(isPresented: $showsReport) {
      ReportSheet()
    }
    .onReceive(NotificationCenter.default.publisher(for: .gladeReportProblem)) { _ in
      tab = .advanced
      showsReport = true
    }
  }
}

private extension View {
  func settingsPane(_ tab: SettingsTab) -> some View {
    formStyle(.grouped)
      .frame(width: SettingsTab.width, height: tab.height)
  }
}
