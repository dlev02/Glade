import AppKit
import GladeKit
import SwiftUI

/// What everything on the disk is, folder by folder, biggest first: the answer to
/// the storage bar’s “Other”. Folders open to show the biggest things inside, and a
/// row’s menu (on hover, when picked, or on right-click) moves it to the Trash,
/// uninstalls an app or shows it in Storage, through the usual clean sheet.
struct DiskUsageSheet: View {
  @Environment(AppModel.self) private var model
  var close: () -> Void
  @State private var now = Date()
  /// Rows shown open, by node identifier.
  @State private var expanded: Set<String>
  @State private var selection: String?
  /// The installed apps, for saying whose a folder is; loaded when the sheet opens.
  @State private var apps: InstalledApps?
  @State private var showsClean = false
  @State private var cleanOpened = Date()
  /// The path being measured before the clean sheet opens.
  @State private var preparing: String?
  @State private var refusal: String?

  init(close: @escaping () -> Void, expanded: Set<String> = [], picked: String? = nil, apps: InstalledApps? = nil) {
    self.close = close
    _expanded = State(initialValue: expanded)
    _selection = State(initialValue: picked)
    _apps = State(initialValue: apps)
  }

  var body: some View {
    let measuring = model.isMeasuringUsage
    let areas = measuring ? model.usagePartial : (model.usage?.areas ?? [])
    VStack(alignment: .leading, spacing: Metrics.l) {
      VStack(alignment: .leading, spacing: 2) {
        Text("What’s on \(volume?.name ?? "This Disk")")
          .font(.title2.weight(.semibold))
        Text(subtitle(measuring: measuring))
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      .accessibilityElement(children: .combine)

      List(selection: $selection) {
        ForEach(areas) { node in
          outline(node)
        }
        if !measuring, let usage = model.usage, usage.unmeasuredBytes > 0 {
          DiskUsageRow(
            node: UsageNode(id: "unmeasured", title: "Not Measured", bytes: usage.unmeasuredBytes),
            scale: scale,
            detail: model.hasFullDiskAccess
              ? "Protected folders and what macOS keeps to itself"
              : "Full Disk Access is off, so some folders couldn’t be measured"
          )
          .tag("unmeasured")
        }
      }
      .listStyle(.inset)
      .alternatingRowBackgrounds(.disabled)
      .scrollContentBackground(.hidden)
      .background(Palette.card, in: .rect(cornerRadius: Metrics.innerRadius))
      .overlay {
        RoundedRectangle(cornerRadius: Metrics.innerRadius)
          .strokeBorder(Palette.hairline.opacity(0.6), lineWidth: Metrics.hairline)
      }
      .overlay {
        if areas.isEmpty, measuring {
          ProgressView()
            .controlSize(.small)
        }
      }
      .onDeleteCommand { deleteSelection(areas) }

      HStack(spacing: Metrics.s) {
        if case .measuring(let done, let total) = model.usageState {
          ProgressView(value: Double(done), total: Double(max(total, 1)))
            .frame(maxWidth: 160)
            .accessibilityLabel("Measuring")
        }
        Spacer()
        if measuring {
          Button("Stop") { model.cancelUsage() }
            .secondaryAction()
            .controlSize(.large)
        } else {
          Button("Measure Again", systemImage: Symbols.scan) { model.measureUsage() }
            .secondaryAction()
            .controlSize(.large)
            .accessibilityIdentifier("usage.measure")
        }
        Button("Done", action: close)
          .principalAction()
          .controlSize(.large)
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("usage.done")
      }
    }
    .padding(Metrics.xl)
    .frame(width: 560, height: 620)
    .onAppear { model.openUsage() }
    .task { if apps == nil { apps = await model.installedAppsIndex() } }
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(30))
        now = .now
      }
    }
    .sheet(isPresented: $showsClean, onDismiss: cleanClosed) {
      CleanSheet { showsClean = false }
    }
    .alert(
      "Can’t move this to the Trash",
      isPresented: Binding(get: { refusal != nil }, set: { if !$0 { refusal = nil } })
    ) {
      Button("OK") { refusal = nil }
    } message: {
      Text(refusal ?? "")
    }
  }

  // MARK: Rows

  /// A row, open or closed, with its children beneath when open.
  private func outline(_ node: UsageNode) -> AnyView {
    let row = row(node)
    guard let children = node.listedChildren else { return AnyView(row) }
    return AnyView(
      DisclosureGroup(isExpanded: Binding(
        get: { expanded.contains(node.id) },
        set: { open in if open { expanded.insert(node.id) } else { expanded.remove(node.id) } }
      )) {
        ForEach(children) { child in outline(child) }
      } label: {
        row
      }
    )
  }

  private func row(_ node: UsageNode) -> some View {
    let actions = model.usageActions(for: node, apps: apps)
    return DiskUsageRow(
      node: node, listed: listed[node.path ?? ""] ?? 0, scale: scale, detail: detail(node, actions),
      isPicked: selection == node.id, isPreparing: preparing != nil && preparing == node.path,
      hasActions: node.path != nil
    ) {
      menu(node, actions)
    }
    .tag(node.id)
  }

  /// Whose it is, or when an app was last opened. When no app claims a folder but
  /// Storage lists part of it, that says more, so the row shows it instead.
  private func detail(_ node: UsageNode, _ actions: UsageRowActions) -> String? {
    if let app = actions.app { return app.openedText }
    guard let owner = actions.owner else { return nil }
    if !owner.hasPrefix("Used by"), (listed[node.path ?? ""] ?? 0) >= 50_000_000 { return nil }
    return owner
  }

  /// Everything a row can do. The same menu shows on right-click and from the row’s
  /// own button.
  @ViewBuilder
  private func menu(_ node: UsageNode, _ actions: UsageRowActions) -> some View {
    if let path = node.path {
      let busy = model.isCleaning || model.isScanning || preparing != nil
      if let app = actions.app {
        if app.hasOwnUninstaller {
          Button("Open Uninstaller", systemImage: Symbols.uninstaller) { model.openUninstaller(app) }
            .disabled(app.app?.uninstaller == nil)
          Text(app.blockers.first { $0.kind == .ownUninstaller }?.detail ?? "")
        } else if let blocker = app.blockers.first {
          Button("Uninstall…", systemImage: Symbols.trash) {}
            .disabled(true)
          Text(blocker.detail)
        } else {
          Button("Uninstall…", systemImage: Symbols.trash) { uninstall(app) }
            .disabled(busy)
        }
      } else if actions.unscannedApp {
        Button("Uninstall…", systemImage: Symbols.trash) {}
          .disabled(true)
        Text("Scan first to see what would go with it")
      } else if let removal = actions.removal {
        switch removal {
        case .allowed:
          Button("Move to Trash…", systemImage: Symbols.trash) { pick(node) }
            .disabled(busy)
        case .refused(let reason):
          Button("Move to Trash…", systemImage: Symbols.trash) {}
            .disabled(true)
          Text(reason)
        }
      }
      if let target = actions.listed ?? actions.app {
        Button("Show in Storage", systemImage: Symbols.showInStorage) { show(target) }
      }
      Divider()
      Button("Show in Finder", systemImage: Symbols.showInFinder) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
      }
      Button("Copy Path", systemImage: "document.on.document") { Copying.copy(path) }
    }
  }

  // MARK: Actions

  private func pick(_ node: UsageNode) {
    guard let path = node.path else { return }
    preparing = path
    Task {
      let refused = await model.pick(forRemoval: path, bytes: node.bytes)
      preparing = nil
      if let refused {
        refusal = refused
      } else {
        openClean()
      }
    }
  }

  private func uninstall(_ app: Finding) {
    model.focusClean(on: [app.id])
    openClean()
  }

  private func openClean() {
    guard !model.cleanItems.isEmpty else { return }
    cleanOpened = Date()
    showsClean = true
  }

  /// Delete asks about the picked row, as its menu would.
  private func deleteSelection(_ areas: [UsageNode]) {
    guard let id = selection, let node = find(id, in: areas) else { return }
    let actions = model.usageActions(for: node, apps: apps)
    if let app = actions.app, !app.isBlocked {
      uninstall(app)
    } else if actions.removal == .allowed {
      pick(node)
    }
  }

  private func find(_ id: String, in nodes: [UsageNode]) -> UsageNode? {
    for node in nodes {
      if node.id == id { return node }
      if let found = find(id, in: node.children) { return found }
    }
    return nil
  }

  private func show(_ finding: Finding) {
    close()
    model.revealInStorage(finding.id)
  }

  /// After the clean sheet: forget what wasn’t removed, and take out of the tree what was.
  private func cleanClosed() {
    model.endCleanFocus()
    if let receipt = model.receipts.first, receipt.date >= cleanOpened { model.pruneUsage(after: receipt) }
    model.discardPicked()
  }

  // MARK: Figures

  private var volume: VolumeInfo? { model.snapshot?.disk ?? model.usage?.volume ?? model.scan?.volume }

  private var listed: [String: Int64] { model.isMeasuringUsage ? [:] : model.usageListed }

  /// Every bar is a share of the space in use, so rows can be compared at a glance.
  private var scale: Int64 { max(volume?.usedBytes ?? model.usage?.volume.usedBytes ?? 1, 1) }

  private func subtitle(measuring: Bool) -> String {
    let used = volume.map { "\(Format.bytes($0.usedBytes)) used" }
    if measuring { return [used, "Measuring…"].compactMap { $0 }.joined(separator: " · ") }
    guard let usage = model.usage else { return used ?? "" }
    let when = now.timeIntervalSince(usage.measured) < 60
      ? "measured just now"
      : "measured \(usage.measured.formatted(.relative(presentation: .named)))"
    return [used, when].compactMap { $0 }.joined(separator: " · ")
  }

  /// Opened to Application Support, for the snapshot of the row actions.
  static var sampleExpanded: Set<String> {
    let home = Protection.clean(NSHomeDirectory())
    return [home, home + "/Library", home + "/Library/Application Support"]
  }

  static var samplePicked: String { Protection.clean(NSHomeDirectory()) + "/Library/Application Support/Dreamtime" }
}

extension UsageNode {
  /// `nil` when there is nothing inside to show, so the row has no disclosure arrow.
  fileprivate var listedChildren: [UsageNode]? {
    guard !children.isEmpty else { return nil }
    var rows = children
    if unlistedBytes >= 50_000_000 {
      rows.append(UsageNode(id: id + "#rest", title: "Smaller Items", bytes: unlistedBytes))
    }
    return rows
  }
}

/// One place on the disk: its name, whose it is, its share of the space in use, its
/// size, and a menu of what can be done with it, shown on hover or when picked.
struct DiskUsageRow<Actions: View>: View {
  var node: UsageNode
  /// How much of it Storage already lists.
  var listed: Int64 = 0
  var scale: Int64
  var detail: String?
  var isPicked = false
  var isPreparing = false
  var hasActions = false
  @ViewBuilder var actions: () -> Actions
  @State private var isHovering = false

  /// Wide enough for the row’s menu button, kept even when it’s hidden so sizes line up.
  static var actionWidth: CGFloat { 22 }

  var body: some View {
    HStack(spacing: Metrics.m) {
      VStack(alignment: .leading, spacing: 1) {
        Text(node.title)
          .lineLimit(1)
          .truncationMode(.middle)
        if let second = secondLine {
          Text(second)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      Spacer(minLength: Metrics.s)
      Capsule()
        .fill(Palette.track)
        .frame(width: 72, height: 5)
        .overlay(alignment: .leading) {
          Capsule()
            .fill(.tint)
            .frame(width: max(2, 72 * CGFloat(node.bytes) / CGFloat(scale)), height: 5)
        }
        .accessibilityHidden(true)
      Text(Format.bytes(node.bytes))
        .monospacedDigit()
        .frame(width: FindingRow.sizeWidth, alignment: .trailing)
      ZStack { actionButton }
        .frame(width: Self.actionWidth, height: 16)
    }
    .padding(.vertical, 2)
    .contentShape(.rect)
    .onHover { isHovering = $0 }
    .help(node.path.map(Redactor.tilde) ?? "")
    .accessibilityElement(children: .combine)
    .contextMenu { actions() }
  }

  @ViewBuilder
  private var actionButton: some View {
    if isPreparing {
      ProgressView()
        .controlSize(.small)
        .accessibilityLabel("Measuring")
    } else if hasActions, isHovering || isPicked {
      Menu {
        actions()
      } label: {
        Image(systemName: "ellipsis.circle")
          .foregroundStyle(.secondary)
      }
      .menuStyle(.button)
      .buttonStyle(.borderless)
      .menuIndicator(.hidden)
      .fixedSize()
      .help("Actions for \(node.title)")
      .accessibilityLabel("Actions for \(node.title)")
    }
  }

  private var secondLine: String? {
    let listedText = listed >= 50_000_000 ? "\(Format.bytes(min(listed, node.bytes))) of this is listed in Storage" : nil
    return detail ?? listedText
  }
}

extension DiskUsageRow where Actions == EmptyView {
  init(node: UsageNode, scale: Int64, detail: String?) {
    self.init(node: node, scale: scale, detail: detail) { EmptyView() }
  }
}
