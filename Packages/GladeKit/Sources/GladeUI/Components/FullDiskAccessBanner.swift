import GladeKit
import SwiftUI

/// Shown on Overview until Full Disk Access is granted, because without it parts of
/// the Mac can’t be measured. One line; it goes away by itself once access is on,
/// and the close button hides it for a week.
public struct FullDiskAccessBanner: View {
  @Environment(AppModel.self) private var model
  @AppStorage("fullDiskAccessBannerHiddenUntil") private var hiddenUntil: Double = 0

  public init() {}

  public var body: some View {
    if !model.hasFullDiskAccess, Date().timeIntervalSince1970 >= hiddenUntil {
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
          .accessibilityIdentifier("fullDiskAccess.allow")
        Button("Hide for a Week", systemImage: "xmark") {
          withAnimation(.snappy(duration: 0.2)) {
            hiddenUntil = Date().addingTimeInterval(7 * 86_400).timeIntervalSince1970
          }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help("Hide for a week")
        .accessibilityIdentifier("fullDiskAccess.hide")
      }
      .padding(.leading, Metrics.l)
      .padding(.trailing, Metrics.m)
      .padding(.vertical, Metrics.s)
      .background(.fill.quaternary, in: .rect(cornerRadius: Metrics.innerRadius))
      .transition(.opacity)
      .task {
        // Notice by itself when access is granted.
        while !model.hasFullDiskAccess, !Task.isCancelled {
          try? await Task.sleep(for: .seconds(3))
          await model.refreshPermissions()
        }
      }
    }
  }
}

/// Storage’s quiet reminder: an orange lock at the end of the clean bar that opens the
/// Full Disk Access settings.
struct FullDiskAccessGlyph: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    if !model.hasFullDiskAccess {
      Button("Some folders weren’t measured. Allow Full Disk Access…", systemImage: Symbols.fullDiskAccess) {
        model.openFullDiskAccessSettings()
      }
      .labelStyle(.iconOnly)
      .buttonStyle(.borderless)
      .foregroundStyle(.orange)
      .help("Some folders weren’t measured. Click to allow Full Disk Access.")
      .accessibilityIdentifier("storage.fullDiskAccess")
    }
  }
}
