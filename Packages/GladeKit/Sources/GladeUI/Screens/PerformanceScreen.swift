import GladeKit
import SwiftUI

/// Glade's answer to Activity Monitor: what's using memory, the processor and the
/// graphics chip right now, grouped by app, with what's worth quitting.
struct PerformanceScreen: View {
  @Environment(AppModel.self) private var model
  @Environment(\.colorScheme) private var colorScheme
  @State private var filter: AppFilter
  @State private var search = ""
  @State private var selection: AppUsage.ID?
  @State private var notice: String?
  @State private var noticeTask: Task<Void, Never>?
  @State private var size: CGSize = .zero
  @State private var tableSpace: CGFloat = 0

  /// For snapshots: picks a row to show selected.
  private let preselect: (@MainActor (AppModel) -> AppUsage.ID?)?
  /// For snapshots: replaces the model's live readings.
  private let readingsOverride: (@MainActor (AppModel) -> PerformanceReadings)?

  /// - Parameter filter: Which rows to list; by default, whatever was chosen last.
  init(
    filter: AppFilter? = nil,
    preselect: (@MainActor (AppModel) -> AppUsage.ID?)? = nil,
    readings: (@MainActor (AppModel) -> PerformanceReadings)? = nil
  ) {
    _filter = State(initialValue: filter ?? AppsTableMemory.filter)
    self.preselect = preselect
    readingsOverride = readings
  }

  var body: some View {
    let readings = readingsOverride?(model) ?? PerformanceReadings(model: model)
    VStack(alignment: .leading, spacing: Metrics.l) {
      LivePanels(readings: readings, columns: size.width > 0 && size.width < 642 ? 2 : 3)
      if !readings.suggestions.isEmpty {
        SuggestionsCard(suggestions: Array(readings.suggestions.prefix(suggestionLimit)), report: show)
      }
      // The table takes the room left, snapped to whole rows so the last one is never
      // cut in half.
      Color.clear
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tableSpace = $0 }
        .overlay(alignment: .top) { table(readings) }
    }
    // Centred once the window is wider than the page, like Overview.
    .frame(maxWidth: Metrics.contentWidth, alignment: .leading)
    .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
    .padding(.horizontal, Metrics.xl)
    .padding(.top, Metrics.l)
    .padding(.bottom, Metrics.l)
    .frame(maxWidth: .infinity)
    .onChange(of: filter) { AppsTableMemory.filter = filter }
    .navigationTitle("Performance")
    .navigationSubtitle(StatusLine.text(readings.snapshot))
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

  /// A table row's height and the header's, as AppKit draws them, for snapping.
  private static let rowHeight: CGFloat = 26
  private static let headerHeight: CGFloat = 30

  private func table(_ readings: PerformanceReadings) -> some View {
    let rows = max(3, Int((tableSpace - Self.headerHeight - 4) / Self.rowHeight))
    return AppsTable(
        apps: readings.apps, logicalCores: readings.logicalCores, filter: $filter, search: search,
        selection: $selection, report: show
      )
      .frame(height: Self.headerHeight + 4 + CGFloat(rows) * Self.rowHeight)
      .clipShape(.rect(cornerRadius: Metrics.cardRadius))
      .overlay {
        // Like a card: a hairline in light only.
        if colorScheme == .light {
          RoundedRectangle(cornerRadius: Metrics.cardRadius)
            .strokeBorder(Palette.hairline.opacity(0.6), lineWidth: Metrics.hairline)
        }
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
  }

  /// Fewer suggestions in a short window, so the table keeps room for several rows.
  private var suggestionLimit: Int {
    switch size.height {
    case 1..<608: 1
    case 608..<728: 2
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
