import GladeKit
import SwiftUI

/// The main window: a sidebar of sections and the selected one beside it.
public struct RootView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.openSettings) private var openSettings
  /// The storage list and how it's being viewed, kept here so switching back to
  /// Storage shows it straight away rather than building it again.
  @State private var storage: StorageViewState

  public init() {
    _storage = State(initialValue: StorageViewState())
  }

  /// For snapshots that show the window with Storage in a particular state.
  init(storage: StorageViewState) {
    _storage = State(initialValue: storage)
  }

  public var body: some View {
    @Bindable var model = model
    NavigationSplitView {
      SidebarList()
      .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
      .safeAreaInset(edge: .bottom) {
        SidebarFooter()
      }
    } detail: {
      switch model.section {
      case .overview: OverviewScreen()
      case .storage: StorageScreen(state: storage)
      case .performance: PerformanceScreen()
      case .assistant: AssistantScreen()
      case .history: HistoryScreen()
      }
    }
    // Wide enough that Storage's toolbar (scope, Scan, Ask, search, inspector) never
    // spills into an overflow menu, even with the inspector open.
    .frame(minWidth: 1000, minHeight: 600)
    .accent(model.tint)
    .preferredColorScheme(model.appearance.colorScheme)
    .task {
      // `-demoSettingsTab <tab>` opens Settings on that tab, for screenshots.
      if DemoState.value("demoSettingsTab") != nil {
        try? await Task.sleep(for: .seconds(1))
        openSettings()
      }
    }
    .sheet(isPresented: $model.showsSetup) {
      SetupView()
        .accent(model.tint)
    }
  }
}

/// Free space, always in view at the foot of the sidebar. Clicking it opens Storage.
/// The bar stays neutral until space runs low.
private struct SidebarFooter: View {
  @Environment(AppModel.self) private var model
  @State private var isHovering = false

  var body: some View {
    if let disk = model.snapshot?.disk ?? model.scan?.volume {
      let low = isLow(disk)
      Button {
        model.section = .storage
      } label: {
        VStack(alignment: .leading, spacing: 6) {
          LevelBar(fraction: 1 - disk.freeFraction, color: low ? Palette.critical : Color.secondary)
          Text("\(Format.bytes(disk.availableBytes)) available")
            .font(.callout)
            .foregroundStyle(low ? AnyShapeStyle(Palette.critical) : AnyShapeStyle(.secondary))
            .monospacedDigit()
        }
        .padding(.horizontal, Metrics.s)
        .padding(.vertical, Metrics.s)
        .background(Color.primary.opacity(isHovering ? 0.06 : 0), in: .rect(cornerRadius: Metrics.s))
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .onHover { hovering in
        withAnimation(.snappy(duration: 0.12)) { isHovering = hovering }
      }
      .padding(.horizontal, Metrics.s)
      .padding(.bottom, Metrics.s)
      .help("Show Storage")
      .accessibilityIdentifier("sidebar.freeSpace")
      .accessibilityElement(children: .combine)
      .accessibilityLabel("\(Format.bytes(disk.availableBytes)) available")
      .accessibilityHint("Shows Storage")
      .accessibilityAddTraits(.isButton)
    }
  }

  /// Below the free-space alert threshold, or under a tenth of the disk.
  private func isLow(_ disk: VolumeInfo) -> Bool {
    let threshold = Int64(model.config.automation.storageFreeGB * 1_000_000_000)
    return disk.availableBytes < threshold || disk.freeFraction < 0.1
  }
}

