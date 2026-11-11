import GladeKit
import SwiftUI

/// Names for the AIs Glade talks to, worked out from the providers it has found, so
/// the Assistant and History screens describe who answered the same way.
extension AppModel {
  /// The provider a message, run or receipt refers to. Records store the provider's
  /// identifier, older ones its name; either matches.
  func providerStatus(_ reference: String?) -> ProviderStatus? {
    guard let reference else { return nil }
    return providers.first { $0.id == reference || $0.name == reference }
  }

  /// A provider's name for display, falling back to whatever was recorded.
  func providerName(_ reference: String?) -> String {
    providerStatus(reference)?.name ?? reference ?? "Assistant"
  }

  /// Who answered, with a note when the model ran on this Mac.
  func providerCaption(_ reference: String?) -> String {
    let name = providerName(reference)
    return providerStatus(reference)?.isLocal == true ? "\(name) · on this Mac" : name
  }

  /// Moves a provider to the front of the preferred order, so it answers next.
  func preferProvider(_ id: String) {
    var order = config.assistant.order
    order.removeAll { $0 == id }
    order.insert(id, at: 0)
    config.assistant.order = order
  }
}
