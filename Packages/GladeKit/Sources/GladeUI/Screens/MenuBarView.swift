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
      if let line = model.batteryLine {
        Button { showBattery() } label: {
          Label(line.text, systemImage: line.symbol)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Metrics.m)
        .help("Show \(model.batteryTitle)")
        .accessibilityIdentifier("popover.battery")
      }
      if let suggestion {
        SuggestionRow(suggestion, iconSize: 24, onGlass: true) { outcome = $0 }
          .padding(.horizontal, Metrics.m)
          .suggestionTransition(reduceMotion: reduceMotion)
        // More than one thing to do: the whole plan is a click away.
        let plan = model.reliefPlan
        if plan.actions.count > 1 {
          Button(model.reliefButtonTitle(plan)) { showRelief() }
            .buttonStyle(PopoverFooterButtonStyle())
            .monospacedDigit()
            .accessibilityIdentifier("popover.freeUpMemory")
            // The words sit on the row’s text edge, under the name.
            .padding(.leading, Metrics.m + 24 + Metrics.m - Metrics.s)
            .padding(.top, -Metrics.s)
        }
      } else if let outcome {
        Text(outcome)
          .font(.callout)
          .foregroundStyle(.secondary)
          .padding(.horizontal, Metrics.m)
      }
      if model.scan != nil, model.selectedBytes > 0 {
        let free = model.immediateBytes
        let count = model.cleanItems.count
        Button {
          showStorage()
        } label: {
          // The figure is what a clean frees now, as on Overview; Trash-only
          // selections are counted in items, since they free nothing yet.
          Text(free > 0 ? "Review \(Format.bytes(free))…" : count == 1 ? "Review 1 Item…" : "Review \(count) Items…")
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
    .padding(.horizontal, Metrics.m)
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
        Text("Settings")
      }
      .accessibilityIdentifier("popover.settings")
      Button("Quit \(Brand.name)") { NSApp.terminate(nil) }
        .accessibilityIdentifier("popover.quit")
    }
    .buttonStyle(PopoverFooterButtonStyle())
    // The buttons' words sit on the same edge as the readings above them.
    .padding(.horizontal, Metrics.m - Metrics.s)
  }

  private func showWindow() {
    openWindow(id: "main")
    NSApp.activate()
  }

  private func showRelief() {
    model.section = .performance
    showWindow()
    model.openRelief()
  }

  private func showBattery() {
    model.section = .battery
    showWindow()
  }

  private func showStorage() {
    model.section = .storage
    showWindow()
  }
}
