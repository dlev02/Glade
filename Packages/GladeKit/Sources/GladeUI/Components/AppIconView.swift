import AppKit
import SwiftUI

/// An app's icon, looked up from where the app lives on disk.
public struct AppIconView: View {
  var path: String?
  var size: CGFloat

  public init(path: String?, size: CGFloat = 28) {
    self.path = path
    self.size = size
  }

  public var body: some View {
    Group {
      if let path, FileManager.default.fileExists(atPath: path) {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
          .resizable()
          .interpolation(.high)
      } else {
        Image(systemName: "gearshape.2")
          .font(.system(size: size * 0.5))
          .foregroundStyle(.secondary)
          .frame(width: size, height: size)
          .background(Palette.track, in: .rect(cornerRadius: size * 0.24))
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}
