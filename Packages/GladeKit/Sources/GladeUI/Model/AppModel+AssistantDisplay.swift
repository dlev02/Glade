import Foundation
import GladeKit

/// What the Assistant screen shows about who answered and which advice still counts,
/// worked out in one place so every caption, menu and card names things the same way.
extension AppModel {
  /// The provider a message, run or advice refers to. Records hold the identifier,
  /// older ones the name, sometimes in a different case; any of them matches.
  func responder(_ reference: String?) -> ProviderStatus? {
    guard let reference else { return nil }
    return providerStatus(reference) ?? providers.first {
      $0.id.caseInsensitiveCompare(reference) == .orderedSame
        || $0.name.caseInsensitiveCompare(reference) == .orderedSame
    }
  }

  /// The name shown for whoever answered: the same words as the composer's menu.
  func responderName(_ reference: String?) -> String {
    responder(reference)?.name ?? reference ?? "Assistant"
  }

  /// Whether an answer came from someone other than the provider chosen now, so its
  /// caption is worth showing.
  func answeredByOther(_ reference: String?, chosen: ProviderStatus?) -> Bool {
    guard let reference, let chosen else { return false }
    return responder(reference)?.id != chosen.id
  }

  /// Advice still describes the selection only while nothing has changed it since:
  /// no hand-made choice, no new level, no rescan.
  func isLive(_ advice: StorageAdvice) -> Bool {
    self.advice?.runID == advice.runID && !hasManualChoices
  }
}

extension ProviderStatus {
  /// Apple's models have no choice of model; every other provider takes a name.
  var takesModel: Bool {
    !id.hasPrefix("apple")
  }
}

extension Notification.Name {
  /// Asks the Settings window to show the Assistant pane.
  public static let gladeShowAssistantSettings = Notification.Name("gladeShowAssistantSettings")
}
