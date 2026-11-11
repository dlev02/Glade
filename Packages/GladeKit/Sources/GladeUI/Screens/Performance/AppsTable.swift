import AppKit
import GladeKit
import SwiftUI

/// Every running app (and, if asked, every process) with what it’s using, sortable,
/// plus the actions a person can take on the selected one.
///
/// Rows are worked out once per refresh, sort or filter change rather than on every
/// body pass. While the pointer is over the table the order holds still, so a row
/// doesn’t slide out from under a click; figures keep updating in place.
struct AppsTable: View {
  @Environment(AppModel.self) private var model
  var apps: [AppUsage]
  var logicalCores: Int
  @Binding var filter: AppFilter
  @Binding var search: String
  /// Bumped by ⌘F to put the cursor in the search field.
  var searchFocus: Int
  @Binding var selection: AppUsage.ID?
  /// Shows the sentence describing what an action did.
  var report: (String) -> Void

  // Start from what was on screen last time, so the first frame isn’t empty.
  @State private var rows: [UsageRow] = AppsTableMemory.rows
  @State private var sortOrder = AppsTableMemory.sortOrder
  @State private var isHovering = false
  @State private var forceQuitTarget: UsageRow?
  @State private var working: Set<String> = []
  /// Graphics and Last Used only show when some row has something in them.
  @State private var columns = OptionalColumns.memory

  private static let processorHelp = "Share of the whole Mac’s processor, across all its cores."

  var body: some View {
    Table(rows, selection: $selection, sortOrder: $sortOrder) {
      TableColumn("Name", value: \.name, comparator: .localizedStandard) { row in
        HStack(spacing: Metrics.s) {
          AppIconView(path: row.app.bundlePath, size: 18)
          Text(row.name)
            .lineLimit(1)
            .truncationMode(.tail)
          StatusMarks(app: row.app, keepsRunning: model.keepsRunning(row.app))
        }
        .foregroundStyle(row.app.isSystem ? .secondary : .primary)
      }
      .width(min: 160, ideal: 220)

      TableColumn("Memory", value: \.memory) { row in
        figure(Format.bytes(row.memory), row)
      }
      .width(min: 72, ideal: 90)
      .alignment(.numeric)

      TableColumn("Processor", value: \.processor) { row in
        figure(PerformanceFormat.percent(row.processor), row, quiet: row.processor < 0.05)
          .help(Self.processorHelp)
      }
      .width(min: 72, ideal: 86)
      .alignment(.numeric)

      if columns.graphics {
        TableColumn("Graphics", value: \.graphics) { row in
          figure(row.graphics < 0 ? "—" : PerformanceFormat.percent(row.graphics), row, quiet: row.graphics <= 0)
        }
        .width(min: 64, ideal: 78)
        .alignment(.numeric)
      }

      if columns.lastUsed {
        TableColumn("Last Used", value: \.lastUsed) { row in
          let text = PerformanceFormat.lastUsed(row.app)
          Text(text)
            // "—" means Glade can’t tell, so it recedes.
            .foregroundStyle(row.app.isFrontmost ? AnyShapeStyle(.primary) : text == "—" ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.secondary))
            .monospacedDigit()
        }
        .width(min: 76, ideal: 96)
      }
    }
    .contextMenu(forSelectionType: AppUsage.ID.self) { ids in
      if let id = ids.first, let row = rows.first(where: { $0.id == id }) {
        menu(for: row)
      }
    }
    .onHover { hovering in
      isHovering = hovering
      if !hovering { rebuild(resort: true) }
    }
    .overlay {
      if rows.isEmpty {
        if apps.isEmpty {
          ProgressView("Measuring…")
            .controlSize(.small)
            .foregroundStyle(.secondary)
        } else if !search.isEmpty {
          ContentUnavailableView.search(text: search)
        } else {
          ContentUnavailableView("Nothing Running", systemImage: "cpu")
        }
      }
    }
    .onChange(of: apps, initial: true) { rebuild(resort: false) }
    .onChange(of: logicalCores) { rebuild(resort: false) }
    .onChange(of: sortOrder) {
      AppsTableMemory.sortOrder = sortOrder
      rebuild(resort: true)
    }
    .onChange(of: filter) { rebuild(resort: true) }
    .onChange(of: search) { rebuild(resort: true) }
    // Live re-sorts jump straight to the new order; rows sliding every second is noise.
    .transaction { $0.animation = nil }
    // The table sits on the card colour, which softens the alternate-row stripes.
    .scrollContentBackground(.hidden)
    .background(Palette.card)
    .toolbar {
      ToolbarItem(placement: .principal) {
        Picker("Show", selection: $filter) {
          ForEach(AppFilter.allCases) { filter in
            Text(filter.title)
              .help(filter.help)
              .tag(filter)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier("performance.filter")
      }
      ToolbarItem(placement: .primaryAction) {
        actionsMenu
      }
      // A plain toolbar search field rather than `.searchable`, so it stays no wider
      // than app names need, at the far end after Actions.
      ToolbarSpacer(.fixed, placement: .primaryAction)
      ToolbarItem(placement: .primaryAction) {
        ToolbarSearchField(
          text: $search, prompt: "Search", focusRequest: searchFocus,
          identifier: "performance.search", help: "Search apps by name", minWidth: 160, maxWidth: 240
        )
      }
    }
    .confirmationDialog(
      forceQuitTarget.map { "Force quit \($0.name)?" } ?? "",
      isPresented: Binding(get: { forceQuitTarget != nil }, set: { if !$0 { forceQuitTarget = nil } }),
      titleVisibility: .visible,
      presenting: forceQuitTarget
    ) { row in
      Button("Force Quit", role: .destructive) { run(row) { await model.quit(row.app, force: true) } }
      Button("Cancel", role: .cancel) {}
    } message: { row in
      Text("\(row.name) closes at once, without saving. Any unsaved changes are lost.")
    }
  }

  // MARK: Cells

  /// - Parameter quiet: Nothing to see (0% or no reading), so it’s dimmed and the
  ///   rows that matter stand out.
  private func figure(_ text: String, _ row: UsageRow, quiet: Bool = false) -> some View {
    Text(text)
      .monospacedDigit()
      .foregroundStyle(quiet ? AnyShapeStyle(.tertiary) : row.app.isSystem ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
  }

  // MARK: Actions

  private var selectedRow: UsageRow? {
    guard let selection else { return nil }
    return rows.first { $0.id == selection }
  }

  /// One menu for the selected row, always in the same place, so the toolbar never
  /// reflows as the selection changes. Quitting comes first, apart from the gentler
  /// actions.
  private var actionsMenu: some View {
    let row = selectedRow
    let busy = row.map { working.contains($0.id) } ?? true
    let canQuit = !busy && (row?.canQuit ?? false)
    return Menu {
      Button("Quit", systemImage: "xmark.octagon") {
        if let row { run(row) { await model.quit(row.app) } }
      }
      .disabled(!canQuit)
      Button("Force Quit…", systemImage: "xmark.octagon.fill") { forceQuitTarget = row }
        .disabled(!canQuit)
      Divider()
      Button("Relaunch", systemImage: "arrow.clockwise") {
        if let row { run(row) { await model.relaunch(row.app) } }
      }
      .disabled(busy || !(row?.canRelaunch ?? false))
      Toggle("Keep Running", systemImage: "pin", isOn: keepBinding(row))
        .disabled(row.map { $0.app.isSystem || $0.app.isGlade } ?? true)
    } label: {
      Label("Actions", systemImage: Symbols.more)
    }
    .menuIndicator(.hidden)
    .disabled(row == nil)
    .help(row.map { $0.quitRefusal ?? "Quit, relaunch or keep \($0.name) running" } ?? "Select an app to act on it")
    .accessibilityLabel(row.map { "Actions for \($0.name)" } ?? "Actions")
    .accessibilityIdentifier("toolbar.actions")
  }

  @ViewBuilder private func menu(for row: UsageRow) -> some View {
    let busy = working.contains(row.id)
    Button("Quit") { run(row) { await model.quit(row.app) } }
      .disabled(!row.canQuit || busy)
    Button("Force Quit…") { forceQuitTarget = row }
      .disabled(!row.canQuit || busy)
    Divider()
    Button("Relaunch") { run(row) { await model.relaunch(row.app) } }
      .disabled(!row.canRelaunch || busy)
    Toggle("Keep Running", isOn: keepBinding(row))
      .disabled(row.app.isSystem || row.app.isGlade)
    Divider()
    if let path = row.app.bundlePath {
      Button("Show in Finder") {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
      }
    }
    Button("Copy Name") { Copying.copy(row.name) }
  }

  private func keepBinding(_ row: UsageRow?) -> Binding<Bool> {
    Binding(
      get: { row.map { model.keepsRunning($0.app) } ?? false },
      set: { keep in if let row { model.setKeepRunning(row.app, keep) } }
    )
  }

  private func run(_ row: UsageRow, _ action: @escaping () async -> String) {
    working.insert(row.id)
    Task {
      report(await action())
      working.remove(row.id)
    }
  }

  // MARK: Rows

  /// - Parameter resort: Apply the sort order even while the pointer is over the table.
  private func rebuild(resort: Bool) {
    let query = search.trimmingCharacters(in: .whitespaces)
    let fresh = apps
      .filter { filter.includes($0) && (query.isEmpty || $0.name.localizedStandardContains(query)) }
      .map { UsageRow($0, logicalCores: logicalCores) }

    if !resort, isHovering, !rows.isEmpty {
      // Keep the order on screen; anything new goes at the end.
      let position = Dictionary(rows.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
      rows = fresh.sorted { (position[$0.id] ?? .max, $0.id) < (position[$1.id] ?? .max, $1.id) }
    } else {
      rows = fresh.sorted(using: sortOrder + [KeyPathComparator(\UsageRow.id)])
    }
    AppsTableMemory.rows = rows
    columns.update(rows)
    AppsTableMemory.columns = columns
    if let selection, !rows.contains(where: { $0.id == selection }) {
      self.selection = nil
    }
  }
}
