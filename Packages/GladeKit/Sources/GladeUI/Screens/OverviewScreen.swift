import GladeKit
import SwiftUI

/// The first thing you see: how full the disk is, what can be freed, and how the Mac
/// is doing right now.
struct OverviewScreen: View {
  @Environment(AppModel.self) private var model
  /// Ticks so "Scanned 9 minutes ago" stays true while the screen is open.
  @State private var now = Date()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Metrics.l) {
        FullDiskAccessBanner()
        StorageSummary()
        HStack(alignment: .top, spacing: Metrics.l) {
          memoryTile
          processorTile
          graphicsTile
        }
        SuggestionList()
      }
      .padding(Metrics.xl)
      // Lined up with the window title rather than centred, like the other sections.
      .frame(maxWidth: Metrics.contentWidth, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .navigationTitle("Overview")
    .navigationSubtitle(subtitle)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        ScanButton()
      }
    }
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(30))
        now = .now
      }
    }
    .onAppear { model.surfaceAppeared(detail: true) }
    .onDisappear { model.surfaceDisappeared(detail: true) }
  }

  private var subtitle: String {
    if model.isScanning { return "Scanning…" }
    guard let scan = model.scan else { return "" }
    if now.timeIntervalSince(scan.finished) < 60 { return "Scanned just now" }
    return "Scanned \(scan.finished.formatted(.relative(presentation: .named)))"
  }

  private var memoryTile: some View {
    let memory = model.snapshot?.memory
    let pressure = memory?.pressure ?? .normal
    let top = model.apps.max { $0.memoryBytes < $1.memoryBytes }
    return MetricTile(
      title: "Memory", symbol: "memorychip",
      figure: memory.map { Format.bytes($0.usedBytes) } ?? "—",
      caption: memory.map { "of \(Format.bytes($0.totalBytes)) · \(pressure.title)" } ?? "Measuring…",
      footnote: top.map { "Using the most: \($0.name), \(Format.bytes($0.memoryBytes))" },
      history: model.history.map { Double($0.memory.usedBytes) / Double(max($0.memory.totalBytes, 1)) * 100 },
      color: memory == nil ? .secondary : pressure.color
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
        return share >= 1 ? "Using the most: \(app.name), \(Int(share.rounded()))%" : nil
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
      footnote: top.flatMap { app in
        (app.gpuPercent ?? 0) >= 1 ? "Using the most: \(app.name), \(Int(app.gpuPercent ?? 0))%" : nil
      },
      history: model.history.map { $0.gpu?.utilizationPercent ?? 0 },
      color: Palette.load((gpu?.utilizationPercent ?? 0) / 100)
    )
  }
}

/// The disk at a glance, and the one decision that matters: how much to free.
private struct StorageSummary: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accentMark) private var accentMark
  /// The slice or legend entry under the pointer; `-demoHoverSegment <id>` sets one
  /// for screenshots.
  @State private var hovered: String?
  private let pinned = UserDefaults.standard.string(forKey: "demoHoverSegment")

  var body: some View {
    let segments = legendSegments
    let hover = Binding(get: { pinned ?? hovered }, set: { if pinned == nil { hovered = $0 } })
    Card(padding: Metrics.xl) {
      VStack(alignment: .leading, spacing: Metrics.l) {
        VStack(alignment: .leading, spacing: 2) {
          Text(volume.map { Format.bytes($0.availableBytes) } ?? "—")
            .font(.figure(40))
            .contentTransition(.numericText())
          Text(volume.map { "available of \(Format.bytes($0.totalBytes)) on \($0.name)" } ?? "Measuring…")
            .font(.title3)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        if let total = volume?.totalBytes {
          StorageBar(segments: segments, total: total, hovered: hover)
          Legend(segments: segments, hovered: hover)
        }

        Divider()

        if case .scanning(let done, let total) = model.scanState {
          HStack(spacing: Metrics.m) {
            ProgressView(value: Double(done), total: Double(max(total, 1)))
              .frame(maxWidth: 240)
            Text("Looking for what can be freed…")
              .foregroundStyle(.secondary)
            Spacer()
            Button("Stop") { model.cancelScan() }
              .secondaryAction()
          }
        } else if model.scan == nil {
          HStack(spacing: Metrics.m) {
            Text("Scan to see what can be freed safely.")
              .foregroundStyle(.secondary)
            Spacer()
            Button("Scan Storage", systemImage: Symbols.scan) { model.startScan() }
              .principalAction()
              .accessibilityIdentifier("overview.scanStorage")
              .controlSize(.large)
          }
        } else {
          HStack(alignment: .center, spacing: Metrics.l) {
            // The big figure is what a clean frees now; what goes to the Trash frees
            // nothing until it's emptied, so it's named on its own.
            let free = model.immediateBytes
            let trash = model.trashBytes
            VStack(alignment: .leading, spacing: 2) {
              HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                Text(Format.bytes(free > 0 ? free : trash))
                  .font(.figure(26))
                  .foregroundStyle(accentMark)
                  .contentTransition(.numericText())
                if free > 0, trash > 0 {
                  Text("+ \(Format.bytes(trash)) to the Trash")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
              }
              HStack(spacing: Metrics.s) {
                Text(free > 0 || trash == 0 ? "ready to free" : "to move to the Trash")
                  .foregroundStyle(.secondary)
                LevelMenu()
              }
              .font(.callout)
            }
            .accessibilityElement(children: .contain)
            Spacer()
            Button("Review", systemImage: Symbols.review) { model.section = .storage }
              .principalAction()
              .accessibilityIdentifier("overview.review")
              .controlSize(.large)
              .keyboardShortcut(.return, modifiers: .command)
          }
        }
      }
    }
  }

  private var volume: VolumeInfo? { model.snapshot?.disk ?? model.scan?.volume }

  /// The bar's slices, with the catch-all given a short name.
  private var legendSegments: [BarSegment] {
    model.storageSegments.map { segment in
      var segment = segment
      if segment.id == "other", model.scan != nil { segment.title = "Other" }
      return segment
    }
  }
}

/// The key under the storage bar, in the bar's order: first what Glade can clear,
/// family by family, then everything else on the disk, set apart so the coloured part
/// never reads as the whole disk. Pointing at an entry lights its slice.
private struct Legend: View {
  var segments: [BarSegment]
  @Binding var hovered: String?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let columns = [GridItem(.adaptive(minimum: 188, maximum: 240), spacing: Metrics.xl, alignment: .leading)]

  var body: some View {
    let shown = segments.filter { $0.bytes > 0 }
    let clearable = shown.filter { $0.id != "other" }
    let other = shown.first { $0.id == "other" }
    VStack(alignment: .leading, spacing: Metrics.s) {
      if !clearable.isEmpty {
        HStack(spacing: Metrics.xs) {
          Text("Glade can clear")
          Text(Format.bytes(clearable.reduce(0) { $0 + $1.bytes }))
            .monospacedDigit()
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(.secondary)
        LazyVGrid(columns: Self.columns, alignment: .leading, spacing: Metrics.s) {
          ForEach(clearable) { entry($0) }
        }
      }
      if let other {
        LazyVGrid(columns: Self.columns, alignment: .leading, spacing: Metrics.s) {
          entry(other)
        }
      }
    }
    .animation(reduceMotion ? nil : .snappy(duration: 0.12), value: hovered)
  }

  private func entry(_ segment: BarSegment) -> some View {
    HStack(spacing: 6) {
      Circle()
        .fill(segment.color)
        .frame(width: 8, height: 8)
      Text(segment.title)
        .foregroundStyle(hovered == segment.id ? .primary : .secondary)
        .lineLimit(1)
      Spacer(minLength: Metrics.s)
      Text(Format.bytes(segment.bytes))
        .monospacedDigit()
        .frame(minWidth: 64, alignment: .trailing)
    }
    .font(.callout)
    .padding(.horizontal, 4)
    .padding(.vertical, 1)
    .background(Color.primary.opacity(hovered == segment.id ? 0.06 : 0), in: .rect(cornerRadius: 5))
    .padding(.horizontal, -4)
    .contentShape(.rect)
    .onHover { inside in
      if inside { hovered = segment.id } else if hovered == segment.id { hovered = nil }
    }
    .accessibilityElement(children: .combine)
  }
}

/// Things Glade's rules would quit or shut down to free memory.
private struct SuggestionList: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var outcome: String?

  var body: some View {
    let suggestions = Array(model.suggestions.prefix(4))
    VStack(alignment: .leading, spacing: Metrics.s) {
      if !suggestions.isEmpty {
        SectionTitle("Suggestions")
        Card(padding: 0) {
          VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
              VStack(spacing: 0) {
                // The same insets as Storage's row separators: from the text edge to
                // the content's trailing edge.
                if index > 0 { Divider().padding(.leading, 56).padding(.trailing, Metrics.l) }
                SuggestionRow(suggestion) { outcome = $0 }
                  .padding(.horizontal, Metrics.l)
                  .padding(.vertical, Metrics.m)
              }
              .suggestionTransition(reduceMotion: reduceMotion)
            }
          }
        }
      }
      if let outcome {
        Text(outcome)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
    .animation(.smooth(duration: 0.3), value: suggestions.map(\.id))
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

  /// Memory's colour follows pressure, not how full it is: macOS keeps memory full on
  /// purpose, so a full bar is no cause for alarm.
  var color: Color {
    switch self {
    case .normal: Palette.good
    case .warning: Palette.warning
    case .critical: Palette.critical
    }
  }
}
