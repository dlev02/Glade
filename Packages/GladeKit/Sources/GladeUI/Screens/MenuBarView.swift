import AppKit
import GladeKit
import SwiftUI

/// The menu bar popover: the Mac at a glance, and the one or two things worth doing,
/// without opening the window. The popover itself is the only glass; everything in it
/// sits on plain fills.
struct MenuBarView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.screenOverrides) private var overrides
  @Environment(\.openWindow) private var openWindow
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var outcome: String?

  var body: some View {
    let suggestion = (overrides.suggestions ?? model.suggestions).first
    VStack(alignment: .leading, spacing: Metrics.m) {
      freeSpace
      readings
      if let suggestion {
        SuggestionRow(suggestion, iconSize: 24, onGlass: true) { outcome = $0 }
          .padding(.horizontal, Metrics.xs)
          .suggestionTransition(reduceMotion: reduceMotion)
      } else if let outcome {
        Text(outcome)
          .font(.callout)
          .foregroundStyle(.secondary)
          .padding(.horizontal, Metrics.xs)
      }
      if model.scan != nil, model.selectedBytes > 0 {
        Button {
          showStorage()
        } label: {
          Text("Review \(Format.bytes(model.selectedBytes))…")
            .frame(maxWidth: .infinity)
        }
        .filledAction()
        .accessibilityIdentifier("popover.review")
        .keyboardShortcut(.defaultAction)
      }
      footer
    }
    .padding(Metrics.l)
    .frame(width: 320)
    .fixedSize(horizontal: false, vertical: true)
    .animation(.smooth(duration: 0.3), value: suggestion?.id)
    .onAppear { model.surfaceAppeared(detail: true) }
    .onDisappear { model.surfaceDisappeared(detail: true) }
  }

  // MARK: Free space

  @ViewBuilder private var freeSpace: some View {
    let disk = model.snapshot?.disk ?? model.scan?.volume
    VStack(alignment: .leading, spacing: Metrics.s) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(disk.map { Format.bytes($0.availableBytes) } ?? "—")
          .font(.figure(28))
          .contentTransition(.numericText())
        Text(disk.map { "available of \(Format.bytes($0.totalBytes))" } ?? "Measuring…")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      if let disk {
        LevelBar(fraction: 1 - disk.freeFraction, color: Palette.load(1 - disk.freeFraction))
      }
    }
    .padding(.horizontal, Metrics.xs)
    .accessibilityElement(children: .combine)
  }

  // MARK: Readings

  /// Memory, processor and graphics in one tile, divided by hairlines.
  private var readings: some View {
    HStack(spacing: 0) {
      memory
      Divider().padding(.vertical, Metrics.m)
      processor
      Divider().padding(.vertical, Metrics.m)
      graphics
    }
    .fixedSize(horizontal: false, vertical: true)
    .background(.fill.quaternary, in: .rect(cornerRadius: Metrics.innerRadius))
  }

  private var memory: some View {
    let memory = model.snapshot?.memory
    let pressure = memory?.pressure ?? .normal
    return MenuReading(
      title: "Memory",
      figure: memory.map { Format.bytes($0.usedBytes) } ?? "—",
      caption: memory == nil ? "Measuring…" : pressure.title,
      history: model.history.map { Double($0.memory.usedBytes) / Double(max($0.memory.totalBytes, 1)) * 100 },
      color: memory == nil ? .secondary : pressure.color
    )
  }

  private var processor: some View {
    let cpu = model.snapshot?.cpu
    return MenuReading(
      title: "Processor",
      figure: cpu.map { "\(Int($0.totalPercent.rounded()))%" } ?? "—",
      caption: cpu.map { "\($0.logicalCores) cores" } ?? "Measuring…",
      history: model.history.map(\.cpu.totalPercent),
      color: Palette.load((cpu?.totalPercent ?? 0) / 100)
    )
  }

  private var graphics: some View {
    let gpu = model.snapshot?.gpu
    return MenuReading(
      title: "Graphics",
      figure: gpu?.utilizationPercent.map { "\(Int($0.rounded()))%" } ?? "—",
      caption: gpu?.coreCount.map { "\($0) cores" } ?? "No reading",
      history: model.history.map { $0.gpu?.utilizationPercent ?? 0 },
      color: Palette.load((gpu?.utilizationPercent ?? 0) / 100)
    )
  }

  // MARK: Footer

  private var footer: some View {
    HStack(spacing: Metrics.xs) {
      Button("Open \(Brand.name)") { showWindow() }
        .accessibilityIdentifier("popover.open")
      Spacer()
      SettingsLink {
        Label("Settings", systemImage: Symbols.settings)
          .labelStyle(.iconOnly)
      }
      .help("Settings")
      .accessibilityIdentifier("popover.settings")
      Button("Quit") { NSApp.terminate(nil) }
        .accessibilityLabel("Quit \(Brand.name)")
        .accessibilityIdentifier("popover.quit")
        .help("Quit \(Brand.name)")
    }
    .buttonStyle(PopoverFooterButtonStyle())
  }

  private func showWindow() {
    openWindow(id: "main")
    NSApp.activate()
  }

  private func showStorage() {
    model.section = .storage
    showWindow()
  }
}
