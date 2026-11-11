import GladeKit
import SwiftUI

/// Fixed states for drawing Settings, Setup and the menu bar to images, so a snapshot
/// can show a state this Mac isn't in. Empty in the running app, where every value
/// is read live.
struct ScreenOverrides {
  var setup: SetupStatus?
  var suggestions: [PerformanceSuggestion]?
  var commandLine: CommandLineTool.Status?
  var agents: [AgentConnection.Agent: AgentConnection.State]?
  var opensAtLogin: Bool?
}

extension EnvironmentValues {
  @Entry var screenOverrides = ScreenOverrides()
}
