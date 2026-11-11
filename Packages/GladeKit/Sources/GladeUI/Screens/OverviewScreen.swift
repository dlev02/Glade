import GladeKit
import SwiftUI

/// The first thing you see: how full the disk is, what can be freed, and how the Mac
/// is doing right now.
struct OverviewScreen: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Metrics.l) {
        if !model.hasFullDiskAccess { AccessBanner() }
        StorageSummary()
        HStack(alignment: .top, spacing: Metrics.l) {
          memoryTile
          processorTile
          graphicsTile
        }
        if !model.suggestions.isEmpty { SuggestionList() }
      }
      .padding(Metrics.xl)
      .frame(maxWidth: Metrics.contentWidth)
      .frame(maxWidth: .infinity)
    }
    .navigationTitle("Overview")
    .toolbar {
      ToolbarItem {
        ScanButton()
      }
    }
    .onAppear { model.surfaceAppeared(detail: true) }
    .onDisappear { model.surfaceDisappeared(detail: true) }
  }

  private var memoryTile: some View {
    let memory = model.snapshot?.memory
    let fraction = memory.map { Double($0.usedBytes) / Double(max($0.totalBytes, 1)) } ?? 0
    let pressure = memory?.pressure ?? .normal
    let top = model.apps.max { $0.memoryBytes < $1.memoryBytes }
    return MetricTile(
      title: "Memory", symbol: "memorychip",
      figure: memory.map { Format.bytes($0.usedBytes) } ?? "—",
      caption: memory.map { "of \(Format.bytes($0.totalBytes)) · \(pressure.title)" } ?? "Measuring…",
      footnote: top.map { "\($0.name) \(Format.bytes($0.memoryBytes))" },
      history: model.history.map { Double($0.memory.usedBytes) / Double(max($0.memory.totalBytes, 1)) * 100 },
      color: pressure == .normal ? Palette.load(fraction * 0.85) : pressure == .warning ? Palette.warning : Palette.critical
    )
  }

  private var processorTile: some View {
    let cpu = model.snapshot?.cpu
    let top = model.apps.max { $0.cpuPercent < $1.cpuPercent }
    return MetricTile(
      title: "Processor", symbol: "cpu",
      figure: cpu.map { "\(Int($0.totalPercent.rounded()))%" } ?? "—",
      caption: cpu.map { "\($0.logicalCores) cores" } ?? "Measuring…",
      // Per-app figures are a share of one core; show them as a share of the whole Mac.
      footnote: top.flatMap { app in
        let share = app.cpuPercent / Double(max(cpu?.logicalCores ?? 1, 1))
        return share >= 1 ? "\(app.name) \(Int(share.rounded()))%" : nil
      },
      history: model.history.map(\.cpu.totalPercent),
      color: Palette.load((cpu?.totalPercent ?? 0) / 100)
    )
  }

  private var graphicsTile: some View {
    let gpu = model.snapshot?.gpu
    let top = model.apps.max { ($0.gpuPercent ?? 0) < ($1.gpuPercent ?? 0) }
    return MetricTile(
      title: "Graphics", symbol: "cube.transparent",
      figure: gpu?.utilizationPercent.map { "\(Int($0.rounded()))%" } ?? "—",
      caption: gpu?.name ?? "No reading",
      footnote: top.flatMap { app in (app.gpuPercent ?? 0) >= 1 ? "\(app.name) \(Int(app.gpuPercent ?? 0))%" : nil },
      history: model.history.map { $0.gpu?.utilizationPercent ?? 0 },
      color: Palette.load((gpu?.utilizationPercent ?? 0) / 100)
    )
  }
}

/// The disk at a glance, and the one decision that matters: how much to free.
private struct StorageSummary: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model
    Card(padding: Metrics.xl) {
      VStack(alignment: .leading, spacing: Metrics.l) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 2) {
            Text(volume.map { Format.bytes($0.availableBytes) } ?? "—")
              .font(.figure(40))
              .contentTransition(.numericText())
            Text(volume.map { "available of \(Format.bytes($0.totalBytes)) on \($0.name)" } ?? "Measuring…")
              .font(.title3)
              .foregroundStyle(.secondary)
          }
          Spacer()
          if let scan = model.scan, !model.isScanning {
            Text("Scanned \(scan.finished, format: .relative(presentation: .named))")
              .font(.callout)
              .foregroundStyle(.tertiary)
          }
        }
        if let total = volume?.totalBytes {
          StorageBar(segments: model.storageSegments, total: total)
          BarLegend(segments: model.storageSegments)
        }

        Divider()

        if case .scanning(let done, let total) = model.scanState {
          HStack(spacing: Metrics.m) {
            ProgressView(value: Double(done), total: Double(max(total, 1)))
              .frame(maxWidth: 240)
            Text("Looking for what can be freed…")
              .foregroundStyle(.secondary)
            Spacer()
            Button("Stop", role: .cancel) { model.cancelScan() }
          }
        } else if model.scan == nil {
          HStack(spacing: Metrics.m) {
            Text("Scan to see what can be freed safely.")
              .foregroundStyle(.secondary)
            Spacer()
            Button("Scan", systemImage: "magnifyingglass") { model.startScan() }
              .buttonStyle(.glassProminent)
              .controlSize(.large)
          }
        } else {
          HStack(alignment: .center, spacing: Metrics.l) {
            VStack(alignment: .leading, spacing: 2) {
              Text(Format.bytes(model.selectedBytes))
                .font(.figure(26))
                .foregroundStyle(.tint)
                .contentTransition(.numericText())
              Text("ready to free")
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Picker("Level", selection: $model.level) {
              ForEach(CleanLevel.allCases) { level in
                Text(level.title).tag(level)
              }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 300)
            Spacer()
            Button("Review", systemImage: "list.bullet") { model.section = .storage }
              .buttonStyle(.glassProminent)
              .controlSize(.large)
          }
        }
      }
    }
  }

  private var volume: VolumeInfo? { model.snapshot?.disk ?? model.scan?.volume }
}

/// Things Glade's rules would quit to free memory, with the reason.
private struct SuggestionList: View {
  @Environment(AppModel.self) private var model
  @State private var working: Set<String> = []
  @State private var outcome: String?

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.s) {
      SectionTitle("Suggestions")
      Card(padding: 0) {
        VStack(spacing: 0) {
          ForEach(Array(model.suggestions.prefix(4).enumerated()), id: \.element.id) { index, suggestion in
            if index > 0 { Divider().padding(.leading, 56) }
            row(suggestion)
          }
        }
      }
      if let outcome {
        Text(outcome)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func row(_ suggestion: PerformanceSuggestion) -> some View {
    let app = model.apps.first { $0.id == suggestion.appID }
    return HStack(spacing: Metrics.m) {
      if let symbol = model.symbol(for: suggestion) {
        Image(systemName: symbol)
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(.teal)
          .frame(width: 28, height: 28)
          .background(.teal.opacity(0.14), in: .rect(cornerRadius: 7))
          .accessibilityHidden(true)
      } else {
        AppIconView(path: app?.bundlePath)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(suggestion.title)
        Text(suggestion.reason)
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      Spacer(minLength: Metrics.m)
      if let title = model.actionTitle(for: suggestion) {
        Button(title) {
          working.insert(suggestion.id)
          Task {
            outcome = await model.perform(suggestion)
            working.remove(suggestion.id)
          }
        }
        .disabled(working.contains(suggestion.id))
        .accessibilityLabel("\(title) \(suggestion.appName)")
      }
    }
    .padding(.horizontal, Metrics.l)
    .padding(.vertical, Metrics.m)
  }
}

/// Shown until Full Disk Access is granted, because without it parts of the Mac
/// can't be measured.
private struct AccessBanner: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    HStack(spacing: Metrics.m) {
      Image(systemName: "lock.shield")
        .font(.title2)
        .foregroundStyle(.orange)
      VStack(alignment: .leading, spacing: 2) {
        Text("Some folders can’t be measured yet")
          .font(.headline)
        Text("Allow Full Disk Access so \(Brand.name) can see the Trash and app data.")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button("Open Settings") { model.openFullDiskAccessSettings() }
    }
    .padding(Metrics.l)
    .background(.orange.opacity(0.1), in: .rect(cornerRadius: Metrics.cardRadius))
    .task {
      // Notice by itself when access is granted.
      while !model.hasFullDiskAccess, !Task.isCancelled {
        try? await Task.sleep(for: .seconds(3))
        await model.refreshPermissions()
      }
    }
  }
}

extension MemoryPressure {
  var title: String {
    switch self {
    case .normal: "Normal"
    case .warning: "Under pressure"
    case .critical: "Critical"
    }
  }
}
