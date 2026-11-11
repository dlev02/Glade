import AppKit
import GladeKit
import SwiftUI

/// Everything the scan found, what a clean would remove, and the clean itself.
/// People adjust the selection here, see why each thing is or isn't included, and
/// free the space.
struct StorageScreen: View {
  /// What the list is built from; when any of it changes the rows are worked out again.
  private struct ListInputs: Equatable {
    var scanID: String?
    var findingCount: Int
    var scope: StorageScope
    var query: String
  }

  private static let inspectorKey = "storageShowsInspector"

  @Environment(AppModel.self) private var model
  @State private var list = StorageListModel()
  @State private var scope: StorageScope
  @State private var query = ""
  @State private var highlighted: Set<String>
  @State private var collapsed: Set<StorageCategory> = []
  @State private var showsInspector: Bool
  @State private var showsCleanSheet = false
  @State private var protectedPath: String?
  /// The list is too narrow for full recovery badges.
  @State private var isCompact = false
  /// Advice to show instead of the model's, for drawing the screen in snapshots.
  private let adviceOverride: StorageAdvice?

  init(scope: StorageScope = .ready, highlighted: String? = nil, showsInspector: Bool? = nil, advice: StorageAdvice? = nil) {
    _scope = State(initialValue: scope)
    _highlighted = State(initialValue: highlighted.map { [$0] } ?? [])
    let saved = UserDefaults.standard.object(forKey: Self.inspectorKey) as? Bool
    _showsInspector = State(initialValue: showsInspector ?? saved ?? true)
    adviceOverride = advice
  }

  var body: some View {
    content
      .navigationTitle("Storage")
      .toolbar { toolbar }
      .searchable(text: $query, placement: .toolbar, prompt: "Titles, projects, paths")
      .inspector(isPresented: $showsInspector) {
        FindingInspector(finding: highlightedFinding, highlightedCount: highlighted.count)
          .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
      }
      .sheet(isPresented: $showsCleanSheet) {
        CleanSheet { showsCleanSheet = false }
      }
      .alert(
        "Folder protected",
        isPresented: Binding(get: { protectedPath != nil }, set: { if !$0 { protectedPath = nil } })
      ) {
        Button("OK") { protectedPath = nil }
      } message: {
        Text("\(Brand.name) will leave \(protectedPath.map(Redactor.tilde) ?? "it") alone from the next scan on.")
      }
      .onChange(of: inputs, initial: true) {
        list.update(scan: model.scan, scope: scope, query: query)
        let visible = Set(list.groups.flatMap { $0.entries.map(\.id) })
        if !highlighted.isSubset(of: visible) { highlighted.formIntersection(visible) }
      }
      .onChange(of: showsInspector) { UserDefaults.standard.set(showsInspector, forKey: Self.inspectorKey) }
  }

  private var inputs: ListInputs {
    ListInputs(scanID: model.scan?.id, findingCount: model.scan?.findings.count ?? 0, scope: scope, query: query)
  }

  private var highlightedFinding: Finding? {
    guard highlighted.count == 1, let id = highlighted.first else { return nil }
    return list.finding(id)
  }

  // MARK: Content

  @ViewBuilder
  private var content: some View {
    if case .scanning(let done, let total) = model.scanState {
      StorageScanning(done: done, total: total)
    } else if model.scan == nil {
      StorageEmptyState()
    } else {
      VStack(spacing: 0) {
        header
        Divider()
        findings
          .safeAreaInset(edge: .bottom) {
            CleanBar { showsCleanSheet = true }
          }
      }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: Metrics.m) {
      if !model.hasFullDiskAccess { StorageAccessBanner() }
      StorageHeader()
      if let advice = adviceOverride ?? model.advice {
        AdviceBanner(advice: advice) { list.finding($0)?.title }
      } else if case .failed(let message) = model.assistantState {
        Label(message, systemImage: "exclamationmark.triangle")
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
    }
    .padding(.horizontal, Metrics.l)
    .padding(.vertical, Metrics.m)
  }

  @ViewBuilder
  private var findings: some View {
    if list.groups.isEmpty {
      emptyScope
    } else {
      List(selection: $highlighted) {
        ForEach(list.groups) { group in
          Section {
            if !collapsed.contains(group.category) {
              ForEach(group.entries) { entry in
                FindingRow(entry: entry, compact: isCompact)
                  .tag(entry.id)
              }
            }
          } header: {
            GroupHeader(group: group, isExpanded: expanded(group.category))
          }
        }
      }
      .listStyle(.inset)
      .onGeometryChange(for: Bool.self) { $0.size.width < 640 } action: { isCompact = $0 }
      .contextMenu(forSelectionType: String.self) { ids in
        menu(for: ids)
      } primaryAction: { _ in
        showsInspector = true
      }
      .onKeyPress(.space) {
        toggleChecks(highlighted)
        return .handled
      }
    }
  }

  @ViewBuilder
  private var emptyScope: some View {
    if !query.trimmingCharacters(in: .whitespaces).isEmpty {
      ContentUnavailableView.search(text: query)
    } else {
      switch scope {
      case .ready: EmptyState("Nothing to free right now", symbol: "checkmark.circle")
      case .review: EmptyState("Nothing to review", symbol: "checklist")
      case .everything: EmptyState("Nothing found", symbol: "internaldrive")
      }
    }
  }

  private func expanded(_ category: StorageCategory) -> Binding<Bool> {
    Binding(
      get: { !collapsed.contains(category) },
      set: { isExpanded in
        if isExpanded { collapsed.remove(category) } else { collapsed.insert(category) }
      }
    )
  }

  // MARK: Toolbar

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarItem(placement: .navigation) {
      ScanButton()
    }
    ToolbarItem(placement: .principal) {
      Picker("Show", selection: $scope) {
        ForEach(StorageScope.allCases) { scope in
          Text(scope.title).tag(scope)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .disabled(model.scan == nil)
    }
    ToolbarItem(placement: .primaryAction) {
      Toggle("Inspector", systemImage: "sidebar.trailing", isOn: $showsInspector)
        .help(showsInspector ? "Hide the inspector" : "Show the inspector")
    }
  }

  // MARK: Actions

  @ViewBuilder
  private func menu(for ids: Set<String>) -> some View {
    let chosen = ids.compactMap(list.finding)
    let selectable = chosen.filter { !$0.isBlocked }
    if selectable.contains(where: { !model.isSelected($0.id) }) {
      Button("Select", systemImage: "checkmark.circle") { model.setSelected(selectable.map(\.id), true) }
    }
    if selectable.contains(where: { model.isSelected($0.id) }) {
      Button("Deselect", systemImage: "circle") { model.setSelected(selectable.map(\.id), false) }
    }
    let paths = chosen.flatMap(\.paths)
    if !paths.isEmpty {
      Divider()
      Button("Show in Finder", systemImage: "folder") {
        NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) })
      }
      Button("Copy Path", systemImage: "document.on.document") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
      }
      if chosen.count == 1, let path = paths.first {
        Divider()
        Button("Protect This Folder", systemImage: "lock.shield") { protect(path) }
      }
    }
  }

  /// Space ticks the highlighted rows, or clears them when they're all ticked already.
  private func toggleChecks(_ ids: Set<String>) {
    let selectable = ids.compactMap(list.finding).filter { !$0.isBlocked }.map(\.id)
    guard !selectable.isEmpty else { return }
    let selectAll = selectable.contains { !model.isSelected($0) }
    model.setSelected(selectable, selectAll)
  }

  private func protect(_ path: String) {
    if !model.config.protectedPaths.contains(path) {
      model.config.protectedPaths.append(path)
    }
    protectedPath = path
  }
}
