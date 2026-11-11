import GladeKit
import SwiftUI

/// The main window: a sidebar of sections and the selected one beside it.
public struct RootView: View {
  @Environment(AppModel.self) private var model

  public init() {}

  public var body: some View {
    @Bindable var model = model
    NavigationSplitView {
      List(selection: Binding(get: { model.section }, set: { model.section = $0 ?? .overview })) {
        ForEach(AppModel.Section.allCases) { section in
          Label(section.title, systemImage: section.symbol)
            .tag(section)
        }
      }
      .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
      .safeAreaInset(edge: .bottom) {
        SidebarFooter()
      }
    } detail: {
      switch model.section {
      case .overview: OverviewScreen()
      case .storage: StorageScreen()
      case .performance: PerformanceScreen()
      case .assistant: AssistantScreen()
      case .history: HistoryScreen()
      }
    }
    .frame(minWidth: 940, minHeight: 600)
    .tint(model.tint)
    .preferredColorScheme(model.appearance.colorScheme)
    .sheet(isPresented: $model.showsSetup) {
      SetupView()
        .tint(model.tint)
    }
  }
}

/// Free space, always in view at the foot of the sidebar.
private struct SidebarFooter: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    if let disk = model.snapshot?.disk ?? model.scan?.volume {
      VStack(alignment: .leading, spacing: 6) {
        LevelBar(fraction: 1 - disk.freeFraction, color: Palette.load(1 - disk.freeFraction))
        Text("\(Format.bytes(disk.availableBytes)) available")
          .font(.caption)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      .padding(.horizontal, Metrics.l)
      .padding(.bottom, Metrics.m)
      .accessibilityElement(children: .combine)
    }
  }
}
