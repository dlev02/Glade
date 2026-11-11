import AppKit
import GladeKit
import SwiftUI

/// The menu bar popover: the Mac at a glance, and the one or two things worth doing,
/// without opening the window.
struct MenuBarView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.screenOverrides) private var overrides
  @Environment(\.openWindow) private var openWindow
  @State private var quitting = false
  @State private var outcome: String?

  var body: some View {
    let suggestion = (overrides.suggestions ?? model.suggestions).first
    VStack(alignment: .leading, spacing: Metrics.m) {
      freeSpace
      HStack(spacing: Metrics.s) {
        memory
        processor
        graphics
      }
      if let suggestion {
        suggestionRow(suggestion)
      } else if let outcome {
        Text(outcome)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      if model.scan != nil, model.selectedBytes > 0 {
        Button {
          showStorage()
        } label: {
          Text("Free Up \(Format.bytes(model.selectedBytes))…")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
      }
      Divider()
      footer
    }
    .padding(Metrics.l)
    .frame(width: 340)
    .onAppear { model.surfaceAppeared(detail: true) }
    .onDisappear { model.surfaceDisappeared(detail: true) }
  }

  // MARK: Free space

  @ViewBuilder private var freeSpace: some View {
    let disk = model.snapshot?.disk ?? model.scan?.volume
    VStack(alignment: .leading, spacing: 6) {
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
    .accessibilityElement(children: .combine)
  }

  // MARK: Readings

  private var memory: some View {
    let memory = model.snapshot?.memory
    let pressure = memory?.pressure ?? .normal
    let fraction = memory.map { Double($0.usedBytes) / Double(max($0.totalBytes, 1)) } ?? 0
    return MenuReading(
      title: "Memory",
      figure: memory.map { Format.bytes($0.usedBytes) } ?? "—",
      caption: pressure.title,
      history: model.history.map { Double($0.memory.usedBytes) / Double(max($0.memory.totalBytes, 1)) * 100 },
      color: pressure == .normal ? Palette.load(fraction * 0.85) : pressure == .warning ? Palette.warning : Palette.critical
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

  // MARK: Suggestion

  private func suggestionRow(_ suggestion: PerformanceSuggestion) -> some View {
    let app = model.apps.first { $0.id == suggestion.appID }
    return HStack(spacing: Metrics.s) {
      AppIconView(path: app?.bundlePath, size: 24)
      VStack(alignment: .leading, spacing: 1) {
        Text(suggestion.title)
          .font(.callout.weight(.medium))
          .lineLimit(1)
        Text(suggestion.reason)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      Spacer(minLength: Metrics.s)
      if suggestion.actionable, let app {
        Button("Quit") {
          quitting = true
          Task {
            outcome = await model.quit(app)
            quitting = false
          }
        }
        .controlSize(.small)
        .disabled(quitting)
      }
    }
  }

  // MARK: Footer

  private var footer: some View {
    HStack(spacing: Metrics.m) {
      Button("Open \(Brand.name)") { showWindow() }
      Spacer()
      if model.isScanning {
        ProgressView()
          .controlSize(.small)
          .help("Scanning…")
      } else {
        Button("Scan", systemImage: "arrow.clockwise") { model.startScan() }
          .labelStyle(.iconOnly)
          .help("Scan")
      }
      SettingsLink {
        Label("Settings", systemImage: "gearshape")
      }
      .labelStyle(.iconOnly)
      .help("Settings")
      Button("Quit \(Brand.name)", systemImage: "power") { NSApp.terminate(nil) }
        .labelStyle(.iconOnly)
        .help("Quit \(Brand.name)")
    }
    .buttonStyle(.borderless)
    .foregroundStyle(.secondary)
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
