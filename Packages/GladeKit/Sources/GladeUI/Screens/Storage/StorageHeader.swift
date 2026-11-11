import GladeKit
import SwiftUI

/// The controls above the storage list: how boldly to select, asking the assistant
/// to refine the selection, and undoing hand-made choices.
struct StorageHeader: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    HStack(spacing: Metrics.m) {
      Picker("Level", selection: $model.level) {
        ForEach(CleanLevel.allCases) { level in
          Text(level.title).tag(level)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .fixedSize()
      .disabled(model.isCleaning)
      Spacer(minLength: Metrics.s)
      if model.hasManualChoices {
        Button("Reset") {
          withAnimation(.snappy) { model.resetSelection() }
        }
        .buttonStyle(.borderless)
        .help("Go back to what \(model.level.title) selects")
      }
      askButton
    }
  }

  @ViewBuilder
  private var askButton: some View {
    if case .thinking(let activity) = model.assistantState {
      HStack(spacing: Metrics.s) {
        ProgressView()
          .controlSize(.small)
        Text(activity)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      .accessibilityElement(children: .combine)
    } else {
      let provider = model.activeProvider
      Button("Ask \(provider.map(Self.shortName) ?? "Assistant")", systemImage: "sparkles") {
        Task { await model.adviseStorage() }
      }
      .disabled(provider == nil || model.scan == nil || model.isScanning || model.isCleaning)
      .help(provider == nil ? "Set up an assistant in Settings to ask for advice" : "Ask \(provider?.name ?? "") to refine the selection")
    }
  }

  /// "Claude Code" reads as "Claude" on a button; other names stay as they are.
  static func shortName(_ provider: ProviderStatus) -> String {
    provider.name.hasSuffix(" Code") ? String(provider.name.dropLast(5)) : provider.name
  }
}
