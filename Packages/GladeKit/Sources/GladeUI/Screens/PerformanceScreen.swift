import GladeKit
import SwiftUI

/// Glade's answer to Activity Monitor: what's using memory, the processor and the
/// graphics chip right now, grouped by app, with what's worth quitting.
struct PerformanceScreen: View {
  @Environment(AppModel.self) private var model
  @State private var filter: AppFilter
  @State private var search = ""
  @State private var selection: AppUsage.ID?
  @State private var notice: String?
  @State private var noticeTask: Task<Void, Never>?
  @State private var size: CGSize = .zero

  /// For snapshots: picks a row to show selected.
  private let preselect: (@MainActor (AppModel) -> AppUsage.ID?)?
  /// For snapshots: replaces the model's live readings.
  private let readingsOverride: (@MainActor (AppModel) -> PerformanceReadings)?

  init(
    filter: AppFilter = .apps,
    preselect: (@MainActor (AppModel) -> AppUsage.ID?)? = nil,
    readings: (@MainActor (AppModel) -> PerformanceReadings)? = nil
  ) {
    _filter = State(initialValue: filter)
    self.preselect = preselect
    readingsOverride = readings
  }

  var body: some View {
    let readings = readingsOverride?(model) ?? PerformanceReadings(model: model)
    VStack(alignment: .leading, spacing: Metrics.l) {
      LivePanels(readings: readings, columns: size.width > 0 && size.width < 690 ? 2 : 3)
      if !readings.suggestions.isEmpty {
        SuggestionsCard(
          suggestions: Array(readings.suggestions.prefix(suggestionLimit)),
          apps: readings.apps, report: show
        )
      }
      AppsTable(
        apps: readings.apps, logicalCores: readings.logicalCores, filter: $filter, search: search,
        selection: $selection, report: show
      )
      .clipShape(.rect(cornerRadius: Metrics.cardRadius))
      .overlay {
        RoundedRectangle(cornerRadius: Metrics.cardRadius)
          .strokeBorder(Palette.hairline.opacity(0.6), lineWidth: Metrics.hairline)
      }
      .overlay(alignment: .bottom) {
        if let notice {
          Text(notice)
            .font(.callout)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Metrics.l)
            .padding(.vertical, Metrics.s)
            .glassEffect(.regular, in: .capsule)
            .padding(Metrics.m)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .accessibilityAddTraits(.isStaticText)
        }
      }
      StatusFooter(snapshot: readings.snapshot)
    }
    .padding(.horizontal, Metrics.xl)
    .padding(.top, Metrics.l)
    .padding(.bottom, Metrics.m)
    .frame(maxWidth: Metrics.contentWidth)
    .frame(maxWidth: .infinity)
    .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
    .navigationTitle("Performance")
    .searchable(text: $search, placement: .toolbar, prompt: "Search")
    .onAppear {
      model.surfaceAppeared(detail: true)
      if let preselect { selection = preselect(model) }
    }
    .onDisappear {
      model.surfaceDisappeared(detail: true)
      noticeTask?.cancel()
    }
  }

  /// Fewer suggestions in a short window, so the table keeps room for several rows.
  private var suggestionLimit: Int {
    switch size.height {
    case 1..<640: 1
    case 640..<760: 2
    default: 3
    }
  }

  /// Shows what an action did for a few seconds, then lets it go.
  private func show(_ message: String) {
    noticeTask?.cancel()
    withAnimation(.smooth) { notice = message }
    AccessibilityNotification.Announcement(message).post()
    noticeTask = Task {
      try? await Task.sleep(for: .seconds(5))
      guard !Task.isCancelled else { return }
      withAnimation(.smooth) { notice = nil }
    }
  }
}
