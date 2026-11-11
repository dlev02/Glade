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

  @Environment(AppModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// Kept by the window, so it outlives a visit to another section.
  @Bindable var state: StorageViewState
  @State private var showsCleanSheet = false
  @State private var protectedPath: String?
  @State private var searchFocus = 0
  /// The list is too narrow for words in the recovery column.
  @State private var isCompact = false
  /// Advice to show instead of the model's, for drawing the screen in snapshots.
  private let adviceOverride: StorageAdvice?

  /// Set by the snapshots. The offscreen renderer has nothing behind glass, so a
  /// scroll-edge effect under the clean bar paints over the whole list; snapshots
  /// use a plain inset instead.
  static var drawsOffscreen = false

  init(state: StorageViewState, advice: StorageAdvice? = nil) {
    self.state = state
    adviceOverride = advice
  }

  var body: some View {
    content
      .navigationTitle("Storage")
      .toolbar { toolbar }
      .background {
        // ⌘F puts the cursor in the toolbar's search field.
        Button("Find") { searchFocus += 1 }
          .keyboardShortcut("f")
          .hidden()
      }
      .inspector(isPresented: $state.showsInspector) {
        Group {
          if model.isScanning {
            // The last scan's totals would be out of date by the time it finishes.
            EmptyState("Scanning", symbol: Symbols.scan)
          } else {
            FindingInspector(finding: state.highlightedFinding, highlightedFindings: highlightedFindings)
          }
        }
        .inspectorBackground()
        .inspectorColumnWidth(min: 300, ideal: 320, max: 420)
      }
      .sheet(isPresented: $showsCleanSheet) {
        CleanSheet { showsCleanSheet = false }
      }
      .task {
        // `-demoClean confirm|result|putback` opens the clean sheet at that step.
        guard let step = DemoState.value("demoClean") else { return }
        // Sample findings arrive a moment after launch.
        for _ in 0..<20 where model.cleanItems.isEmpty { try? await Task.sleep(for: .milliseconds(500)) }
        showsCleanSheet = true
        if step != "confirm" { await model.clean() }
      }
      .task {
        // `-demoHighlight <title>` highlights a row, for the inspector.
        guard let title = DemoState.value("demoHighlight") else { return }
        for _ in 0..<20 {
          try? await Task.sleep(for: .milliseconds(500))
          let words = title.split(separator: " ").map(String.init)
          if let id = state.list.groups.flatMap(\.entries).first(where: { entry in
            words.allSatisfy { entry.finding.title.localizedCaseInsensitiveContains($0) }
          })?.id {
            state.highlighted = [id]
            return
          }
        }
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
        state.refresh(scan: model.scan)
      }
  }

  private var inputs: ListInputs {
    ListInputs(scanID: model.scan?.id, findingCount: model.scan?.findings.count ?? 0, scope: state.scope, query: state.query)
  }

  private var highlightedFindings: [Finding] {
    guard state.highlighted.count > 1 else { return [] }
    return state.highlighted.compactMap(state.list.finding)
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
        if Self.drawsOffscreen {
          findings
            .safeAreaInset(edge: .bottom) {
              CleanBar { showsCleanSheet = true }
            }
        } else {
          // The bar sits below the list rather than over it, and the rows fade out
          // just above it, so nothing shows through or under the glass. The bottom
          // margin lets the last row scroll clear of the fade.
          findings
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, Self.fadeHeight, for: .scrollContent)
            .mask {
              VStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                  .frame(height: Self.fadeHeight)
              }
            }
          CleanBar { showsCleanSheet = true }
        }
      }
      .background(Palette.card)
    }
  }

  /// How far above the clean bar the rows fade out.
  private static let fadeHeight: CGFloat = 24

  /// The Full Disk Access line and the assistant's advice, only when there's
  /// something to say.
  @ViewBuilder
  private var header: some View {
    let advice = adviceOverride ?? model.advice
    let failure: String? = if case .failed(let message) = model.assistantState { message } else { nil }
    if advice == nil, let failure {
      Label(failure, systemImage: "exclamationmark.triangle")
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .padding(.horizontal, Metrics.l)
        .padding(.vertical, Metrics.m)
      Divider()
    }
  }

  @ViewBuilder
  private var findings: some View {
    if state.list.groups.isEmpty {
      emptyScope
    } else {
      List(selection: $state.highlighted) {
        // The advice is the list's first row, so it sits on the same grid as the
        // rows: its sparkle in the checkbox column, its text on the titles' edge.
        if let advice = adviceOverride ?? model.advice {
          AdviceBanner(advice: advice) { state.list.finding($0)?.title }
            .selectionDisabled()
        }
        ForEach(state.list.groups) { group in
          Section {
            if !state.collapsed.contains(group.category) {
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
        // Double-click or Return.
        state.showsInspector = true
      }
      .onKeyPress(.space) {
        toggleChecks(state.highlighted)
        return .handled
      }
    }
  }

  @ViewBuilder
  private var emptyScope: some View {
    if !state.query.trimmingCharacters(in: .whitespaces).isEmpty {
      ContentUnavailableView.search(text: state.query)
    } else {
      switch state.scope {
      case .ready: EmptyState("Nothing to free right now", symbol: "checkmark.circle")
      case .review: EmptyState("Nothing to review", symbol: Symbols.review)
      case .everything: EmptyState("Nothing found", symbol: AppModel.Section.storage.symbol)
      }
    }
  }

  private func expanded(_ category: StorageCategory) -> Binding<Bool> {
    Binding(
      get: { !state.collapsed.contains(category) },
      set: { isExpanded in
        if isExpanded { state.collapsed.remove(category) } else { state.collapsed.insert(category) }
      }
    )
  }

  // MARK: Toolbar

  /// Title leading, scope in the middle, then Scan and Ask, search, and the
  /// inspector button at the far trailing edge.
  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarItem(placement: .principal) {
      Picker("Show", selection: $state.scope) {
        ForEach(StorageScope.allCases) { scope in
          Text(scope.title).tag(scope)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .disabled(model.scan == nil)
      .accessibilityIdentifier("storage.scope")
    }
    // Scan is a utility and Ask is an AI verb: two capsules, not one.
    ToolbarItem(placement: .primaryAction) { ScanButton() }
    ToolbarSpacer(.fixed, placement: .primaryAction)
    ToolbarItem(placement: .primaryAction) { AskButton() }
    ToolbarSpacer(.fixed, placement: .primaryAction)
    ToolbarItem(placement: .primaryAction) {
      ToolbarSearchField(text: $state.query, prompt: "Search", focusRequest: searchFocus)
    }
    // After search, so it is always the last item at the trailing edge.
    ToolbarSpacer(.fixed, placement: .primaryAction)
    ToolbarItem(placement: .primaryAction) { inspectorButton }
  }

  /// A plain button rather than a toggle, so it never shows a tinted "on" state.
  private var inspectorButton: some View {
    Button("Inspector", systemImage: Symbols.inspector) {
      withAnimation(reduceMotion ? nil : .default) { state.showsInspector.toggle() }
    }
    .keyboardShortcut("i", modifiers: [.command, .option])
    .help(state.showsInspector ? "Hide the inspector (⌥⌘I)" : "Show the inspector (⌥⌘I)")
    .accessibilityValue(state.showsInspector ? "Shown" : "Hidden")
    .accessibilityIdentifier("toolbar.inspector")
  }

  // MARK: Actions

  @ViewBuilder
  private func menu(for ids: Set<String>) -> some View {
    let chosen = ids.compactMap(state.list.finding)
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
      Button("Show in Finder", systemImage: Symbols.showInFinder) {
        NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) })
      }
      Button("Copy Path", systemImage: "document.on.document") {
        Copying.copy(paths.joined(separator: "\n"))
      }
      if chosen.count == 1, let path = paths.first {
        Divider()
        Button("Protect This Folder", systemImage: "lock.shield") { protect(path) }
      }
    }
  }

  /// Space ticks the highlighted rows, or clears them when they're all ticked already.
  private func toggleChecks(_ ids: Set<String>) {
    let selectable = ids.compactMap(state.list.finding).filter { !$0.isBlocked }.map(\.id)
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
