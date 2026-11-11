import GladeKit
import SwiftUI

/// A protected area’s symbol in a small neutral tile, the same size and shape as the
/// storage category tiles. One calm treatment for every area: these are all "hands
/// off", so none should shout louder than another.
struct ZoneIcon: View {
  var zone: ProtectedZone
  var size: CGFloat = 28

  var body: some View {
    Image(systemName: Self.symbol(for: zone.id))
      .font(.system(size: size * 0.5, weight: .medium))
      .foregroundStyle(.secondary)
      .frame(width: size, height: size)
      .background(.fill.tertiary, in: .rect(cornerRadius: 8))
      .accessibilityHidden(true)
  }

  /// Every name here is checked against the symbol catalog.
  static func symbol(for id: String) -> String {
    switch id {
    case "credentials": "key"
    case "keychains": "lock"
    case "agent-memory": "brain"
    case "photos": "photo.on.rectangle"
    case "messages-mail": "envelope"
    case "apple-personal": "note.text"
    case "cloud", "icloud-desktop": "icloud"
    case "browsers": "safari"
    case "security-software": "checkmark.shield"
    case "git": "arrow.trianglehead.branch"
    case "glade": "leaf"
    case "backups": "externaldrive.badge.timemachine"
    case "virtual-machines": "desktopcomputer"
    default: Symbols.protected
    }
  }
}
