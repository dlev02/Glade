import Foundation
import GladeKit

/// `glade://show/<section>` opens the window on a section. `glade show` and anything
/// else on the Mac can use it, whether or not the app is running.
extension AppModel.Section {
  /// The link’s scheme, registered in the app’s Info.plist.
  public static let linkScheme = Brand.cli

  /// The link that opens the window on this section.
  public var link: URL {
    URL(string: "\(Self.linkScheme)://show/\(rawValue)")!
  }

  /// The section a link asks for, or `nil` when it isn’t one of Glade’s.
  public init?(link: URL) {
    guard link.scheme?.lowercased() == Self.linkScheme, link.host()?.lowercased() == "show" else { return nil }
    let name = link.pathComponents.first { $0 != "/" }?.lowercased() ?? Self.overview.rawValue
    self.init(rawValue: name)
  }
}

extension AppModel {
  /// Follows a `glade://` link. Returns `false` for a link it doesn’t understand.
  @discardableResult
  public func open(_ link: URL) -> Bool {
    guard let wanted = Section(link: link) else {
      Log.warning(.app, "Ignored a link Glade doesn’t understand: \(link.scheme ?? "")://\(link.host() ?? "")")
      return false
    }
    Log.info(.app, "Opened on \(wanted.rawValue) from a link")
    section = wanted
    return true
  }
}
