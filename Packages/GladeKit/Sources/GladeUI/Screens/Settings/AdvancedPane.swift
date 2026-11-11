import AppKit
import GladeKit
import SwiftUI

/// Permissions, the command line, connections to coding agents, problem reports,
/// updates and the version.
struct AdvancedPane: View {
  @Binding var showsReport: Bool
  @Environment(AppModel.self) private var model
  @Environment(\.updater) private var updater

  var body: some View {
    Form {
      Section {
        LabeledContent {
          if !model.hasFullDiskAccess {
            Button("Open Settings") { model.openFullDiskAccessSettings() }
              .secondaryAction()
          }
        } label: {
          Text("Full Disk Access")
          Text(model.hasFullDiskAccess ? "Allowed" : "Not allowed. Some folders can’t be measured.")
        }
        CommandLineRows()
      }

      Section("Connect to Agents") {
        ForEach(AgentConnection.Agent.allCases) { agent in
          AgentConnectionRow(agent: agent)
        }
      }

      Section {
        LabeledContent("Troubleshooting") {
          HStack {
            Button("Show Log in Finder") { NSWorkspace.shared.activateFileViewerSelecting([GladePaths.logs]) }
              .secondaryAction()
            Button("Report a Problem…") { showsReport = true }
              .secondaryAction()
          }
        }
      }

      Section {
        LabeledContent("Version", value: "\(Brand.version) (\(Brand.build))")
          .monospacedDigit()
        if let check = updater.checkForUpdates {
          LabeledContent("Updates") {
            Button("Check for Updates…", action: check)
              .secondaryAction()
          }
        }
        if let automatic = updater.automaticallyChecks {
          Toggle("Check automatically", isOn: automatic)
        }
        if let url = URL(string: Brand.repository) {
          Link("\(Brand.name) on GitHub", destination: url)
        }
      } footer: {
        Text("Free and open source under GPL-3.0. © 2026 Drew Levinson")
          .foregroundStyle(.secondary)
      }
    }
    .task { await model.refreshPermissions() }
  }
}
