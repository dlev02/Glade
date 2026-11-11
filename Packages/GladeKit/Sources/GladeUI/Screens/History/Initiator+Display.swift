import GladeKit

/// Who started a clean, as a symbol and a name. The symbol says what kind of starter
/// it was, so the name can be short: "You", "Claude", "Scheduled".
extension Initiator {
  var symbol: String {
    switch self {
    case .user: Symbols.byPerson
    case .commandLine: Symbols.byCommandLine
    case .assistant: Symbols.byAssistant
    case .automation: Symbols.byAutomation
    }
  }

  /// - Parameter providerName: Turns an AI’s identifier into the name people know.
  func name(providerName: (String) -> String) -> String {
    switch self {
    case .user: "You"
    case .commandLine: "Command line"
    case .assistant(let provider): providerName(provider)
    case .automation: "Scheduled"
    }
  }
}
