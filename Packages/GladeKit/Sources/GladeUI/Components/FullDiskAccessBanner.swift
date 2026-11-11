import GladeKit
import SwiftUI

/// Shown until Full Disk Access is granted, because without it parts of the Mac
/// can't be measured. One line, and it goes away by itself once access is on.
public struct FullDiskAccessBanner: View {
  @Environment(AppModel.self) private var model

  public init() {}

  public var body: some View {
    HStack(spacing: Metrics.m) {
      Image(systemName: Symbols.fullDiskAccess)
        .foregroundStyle(.orange)
        .accessibilityHidden(true)
      Text("Allow Full Disk Access to measure everything")
        .lineLimit(2)
      Spacer(minLength: Metrics.m)
      Button("Allow…") { model.openFullDiskAccessSettings() }
        .secondaryAction()
        .controlSize(.small)
    }
    .padding(.horizontal, Metrics.l)
    .padding(.vertical, Metrics.s)
    .background(.fill.quaternary, in: .rect(cornerRadius: Metrics.innerRadius))
    .task {
      // Notice by itself when access is granted.
      while !model.hasFullDiskAccess, !Task.isCancelled {
        try? await Task.sleep(for: .seconds(3))
        await model.refreshPermissions()
      }
    }
  }
}
