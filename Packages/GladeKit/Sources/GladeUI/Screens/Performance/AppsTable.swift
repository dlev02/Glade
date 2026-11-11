import AppKit
import GladeKit
import SwiftUI

/// Every running app (and, if asked, every process) with what it's using, sortable,
/// plus the actions a person can take on the selected one.
///
/// Rows are worked out once per refresh, sort or filter change rather than on every
/// body pass. While the pointer is over the table the order holds still, so a row
/// doesn't slide out from under a click; figures keep updating in place.
struct AppsTable: View {
  @Environment(AppModel.self) private var model
  var apps: [AppUsage]
  var logicalCores: Int
  @Binding var filter: AppFilter
  var search: String
  @Binding var selection: AppUsage.ID?
  /// Shows the sentence describing what an action did.
  var report: (String) -> Void

  @State private var rows: [UsageRow] = []
  @State private var sortOrder = [KeyPathComparator(\UsageRow.memory, order: .reverse)]
  @State private var isHovering = false
  @State private var forceQuitTarget: UsageRow?
  @State private var working: Set<String> = []

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
        figure(PerformanceFormat.percent(row.processor), row)
          .help(Self.processorHelp)
      }
      .width(min: 72, ideal: 86)
      .alignment(.numeric)

      TableColumn("Graphics", value: \.graphics) { row in
        figure(row.graphics < 0 ? "—" : PerformanceFormat.percent(row.graphics), row)
      }
      .width(min: 64, ideal: 78)
      .alignment(.numeric)

      TableColumn("Last Used", value: \.lastUsed) { row in
        Text(PerformanceFormat.lastUsed(row.app))
          .foregroundStyle(row.app.isFrontmost ? .primary : .secondary)
          .monospacedDigit()
      }
      .width(min: 76, ideal: 96)
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
    .onChange(of: sortOrder) { rebuild(resort: true) }
    .onChange(of: filter) { rebuild(resort: true) }
    .onChange(of: search) { rebuild(resort: true) }
    .toolbar {
      ToolbarItem(placement: .principal) {
        Picker("Show", selection: $filter) {
          ForEach(AppFilter.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("Which processes to list")
      }
      ToolbarItemGroup(placement: .primaryAction) {
        toolbarActions
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

  private func figure(_ text: String, _ row: UsageRow) -> some View {
    Text(text)
      .monospacedDigit()
      .foregroundStyle(row.app.isSystem ? .secondary : .primary)
  }

  // MARK: Actions

  private var selectedRow: UsageRow? {
    guard let selection else { return nil }
    return rows.first { $0.id == selection }
  }

  @ViewBuilder private var toolbarActions: some View {
    let row = selectedRow
    let canQuit = row.map { $0.canQuit && !working.contains($0.id) } ?? false
    Menu {
      Button("Force Quit…") { forceQuitTarget = row }
    } label: {
      Label("Quit", systemImage: "xmark.octagon")
    } primaryAction: {
      if let row { run(row) { await model.quit(row.app) } }
    }
    .disabled(!canQuit)
    .help(row?.quitRefusal ?? (row.map { "Quit \($0.name)" } ?? "Quit the selected app"))

    Button("Relaunch", systemImage: "arrow.clockwise") {
      if let row { run(row) { await model.relaunch(row.app) } }
    }
    .disabled(!(row.map { $0.canRelaunch && !working.contains($0.id) } ?? false))
    .help("Quit and reopen, which often frees memory an app has built up")

    Toggle("Keep Running", systemImage: "pin", isOn: keepBinding(row))
      .disabled(row.map { $0.app.isSystem || $0.app.isGlade } ?? true)
      .help("Never suggest quitting this app")
  }

  @ViewBuilder private func menu(for row: UsageRow) -> some View {
    let busy = working.contains(row.id)
    Button("Quit") { run(row) { await model.quit(row.app) } }
      .disabled(!row.canQuit || busy)
    Button("Force Quit…") { forceQuitTarget = row }
      .disabled(!row.canQuit || busy)
    Button("Relaunch") { run(row) { await model.relaunch(row.app) } }
      .disabled(!row.canRelaunch || busy)
    Divider()
    Toggle("Keep Running", isOn: keepBinding(row))
      .disabled(row.app.isSystem || row.app.isGlade)
    Divider()
    if let path = row.app.bundlePath {
      Button("Show in Finder") {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
      }
    }
    Button("Copy Name") {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(row.name, forType: .string)
    }
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
    if let selection, !rows.contains(where: { $0.id == selection }) {
      self.selection = nil
    }
  }
}
