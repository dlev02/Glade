import AppKit
import GladeKit
import SwiftUI

/// The apps using the most energy over a period: a bar for each one’s share, notes on
/// what it’s doing, and Quit from the row or the toolbar, as on Performance.
struct EnergyTable: View {
  @Environment(AppModel.self) private var model
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.isPageShowing) private var isShowing
  @Environment(\.accentMark) private var accentMark
  var report: EnergyReport
  var detail: BatterySettings.Detail
  /// Shows the sentence describing what an action did.
  var announce: (String) -> Void
  @State private var selection: EnergyUse.ID?
  @State private var forceQuitTarget: EnergyUse?
  @State private var working: Set<String> = []

  /// The most rows shown; the rest are a long tail of small figures.
  static let rowLimit = 8
  private static let rowHeight: CGFloat = 26
  private static let headerHeight: CGFloat = 30

  private var rows: [EnergyUse] { Array(report.apps.prefix(Self.rowLimit)) }

  var body: some View {
    let count = max(3, rows.count)
    Table(rows, selection: $selection) {
      TableColumn("Name") { use in
        HStack(spacing: Metrics.s) {
          AppIconView(path: use.bundlePath, size: 18)
          Text(use.name)
            .lineLimit(1)
            .truncationMode(.tail)
        }
        .foregroundStyle(use.isSystem ? .secondary : .primary)
      }
      .width(min: 150, ideal: 210)

      TableColumn("Share") { use in
        HStack(spacing: Metrics.s) {
          ShareBar(fraction: use.share, color: accentMark)
          Text(Format.percent(use.share))
            .monospacedDigit()
            .foregroundStyle(use.share < 0.01 ? .tertiary : use.isSystem ? .secondary : .primary)
            .frame(width: 36, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
      }
      .width(min: 120, ideal: 170)

      if detail == .technical {
        TableColumn("Power") { use in
          Text(BatteryFormat.watts(use.watts)).monospacedDigit().foregroundStyle(.secondary)
        }
        .width(min: 60, ideal: 70)
        .alignment(.numeric)
        if report.period != .now {
          TableColumn("Energy") { use in
            Text(BatteryFormat.energy(use.joules)).monospacedDigit().foregroundStyle(.secondary)
          }
          .width(min: 64, ideal: 76)
          .alignment(.numeric)
        }
      }

      TableColumn("Notes") { use in
        Text(use.isSystem ? (["Part of macOS"] + use.notes).joined(separator: " · ") : use.notes.joined(separator: " · "))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .help(use.notes.joined(separator: ", "))
      }
      .width(min: 140, ideal: 260)
    }
    .contextMenu(forSelectionType: EnergyUse.ID.self) { ids in
      if let id = ids.first, let use = rows.first(where: { $0.id == id }) { menu(for: use) }
    }
    .overlay {
      if rows.isEmpty {
        Text(report.note ?? "Nothing measured yet")
          .font(.callout)
          .foregroundStyle(.secondary)
          .padding(.top, Self.headerHeight)
      }
    }
    .scrollDisabled(true)
    .scrollContentBackground(.hidden)
    .background(Palette.card)
    .transaction { $0.animation = nil }
    .frame(height: Self.headerHeight + 4 + CGFloat(count) * Self.rowHeight)
    .clipShape(.rect(cornerRadius: Metrics.cardRadius))
    .overlay {
      if colorScheme == .light {
        RoundedRectangle(cornerRadius: Metrics.cardRadius)
          .strokeBorder(Palette.hairline.opacity(0.6), lineWidth: Metrics.hairline)
      }
    }
    .toolbar {
      if isShowing {
        ToolbarItem(placement: .primaryAction) { actionsMenu }
      }
    }
    .confirmationDialog(
      forceQuitTarget.map { "Force quit \($0.name)?" } ?? "",
      isPresented: Binding(get: { forceQuitTarget != nil }, set: { if !$0 { forceQuitTarget = nil } }),
      titleVisibility: .visible,
      presenting: forceQuitTarget
    ) { use in
      Button("Force Quit", role: .destructive) { run(use) { await model.forceQuit(energy: use) } }
      Button("Cancel", role: .cancel) {}
    } message: { use in
      Text("\(use.name) closes at once, without saving. Any unsaved changes are lost.")
    }
  }

  // MARK: Actions

  private func canQuit(_ use: EnergyUse) -> Bool {
    use.isRunning && use.kind == .app && !use.isSystem && !use.isGlade
  }

  private var actionsMenu: some View {
    let use = selection.flatMap { id in rows.first { $0.id == id } }
    let enabled = use.map { canQuit($0) && !working.contains($0.id) } ?? false
    return Menu {
      Button("Quit", systemImage: "xmark.octagon") { if let use { run(use) { await model.quit(energy: use) } } }
        .disabled(!enabled)
      Button("Force Quit…", systemImage: "xmark.octagon.fill") { forceQuitTarget = use }
        .disabled(!enabled)
    } label: {
      Label("Actions", systemImage: Symbols.more)
    }
    .menuIndicator(.hidden)
    .disabled(use == nil)
    .help(use.map { canQuit($0) ? "Quit \($0.name)" : "\($0.name) can’t be quit from here" } ?? "Select an app to act on it")
    .accessibilityLabel(use.map { "Actions for \($0.name)" } ?? "Actions")
  }

  @ViewBuilder private func menu(for use: EnergyUse) -> some View {
    let busy = working.contains(use.id)
    Button("Quit") { run(use) { await model.quit(energy: use) } }
      .disabled(!canQuit(use) || busy)
    Button("Force Quit…") { forceQuitTarget = use }
      .disabled(!canQuit(use) || busy)
    Divider()
    if let path = use.bundlePath {
      Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
    }
    Button("Copy Name") { Copying.copy(use.name) }
  }

  private func run(_ use: EnergyUse, _ action: @escaping () async -> String) {
    working.insert(use.id)
    Task {
      announce(await action())
      working.remove(use.id)
    }
  }
}

/// A thin bar for one app’s share of the energy.
private struct ShareBar: View {
  var fraction: Double
  var color: Color

  var body: some View {
    GeometryReader { proxy in
      Capsule()
        .fill(color)
        .frame(width: max(fraction > 0.001 ? 3 : 0, proxy.size.width * min(max(fraction, 0), 1)))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.track, in: .capsule)
    }
    .frame(height: 6)
    .accessibilityHidden(true)
  }
}
