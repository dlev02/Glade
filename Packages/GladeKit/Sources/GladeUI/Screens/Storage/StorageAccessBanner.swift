import GladeKit
import SwiftUI

/// One line above the storage list while Full Disk Access is off, because some
/// folders can't be measured without it.
struct StorageAccessBanner: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    HStack(spacing: Metrics.s) {
      Image(systemName: "lock.shield")
        .foregroundStyle(.orange)
        .accessibilityHidden(true)
      Text("Some folders can’t be measured without Full Disk Access.")
        .lineLimit(1)
        .truncationMode(.tail)
      Spacer(minLength: Metrics.s)
      Button("Open Settings") { model.openFullDiskAccessSettings() }
        .controlSize(.small)
    }
    .font(.callout)
    .padding(.horizontal, Metrics.m)
    .padding(.vertical, Metrics.s)
    .background(.orange.opacity(0.1), in: .rect(cornerRadius: Metrics.innerRadius))
  }
}
