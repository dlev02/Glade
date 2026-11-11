import GladeKit

/// Wording for who started a clean, using the names of the AIs Glade has found.
extension AppModel {
  func initiatorTitle(_ initiator: Initiator) -> String {
    switch initiator {
    case .user: "You"
    case .commandLine: "Command line"
    case .assistant(let provider): "Assistant (\(providerName(provider)))"
    case .automation: "Automation"
    }
  }
}
