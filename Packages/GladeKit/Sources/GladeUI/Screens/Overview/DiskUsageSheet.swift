import AppKit
import GladeKit
import SwiftUI

/// What everything on the disk is, folder by folder, biggest first: the answer to
/// the storage bar’s “Other”. Folders open to show the biggest things inside.
struct DiskUsageSheet: View {
  @Environment(AppModel.self) private var model
  var close: () -> Void
  @State private var now = Date()

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

      List {
        OutlineGroup(areas, children: \.listedChildren) { node in
          DiskUsageRow(node: node, listed: listed[node.path ?? ""] ?? 0, scale: scale)
        }
        if !measuring, let usage = model.usage, usage.unmeasuredBytes > 0 {
          DiskUsageRow(
            node: UsageNode(id: "unmeasured", title: "Not Measured", bytes: usage.unmeasuredBytes),
            listed: 0, scale: scale,
            detail: model.hasFullDiskAccess
              ? "Protected folders and what macOS keeps to itself"
              : "Full Disk Access is off, so some folders couldn’t be measured"
          )
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
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(30))
        now = .now
      }
    }
  }

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

/// One place on the disk: its name, its share of the space in use, and its size.
struct DiskUsageRow: View {
  var node: UsageNode
  /// How much of it Storage already lists.
  var listed: Int64
  var scale: Int64
  var detail: String?

  var body: some View {
    HStack(spacing: Metrics.m) {
      VStack(alignment: .leading, spacing: 1) {
        Text(node.title)
          .lineLimit(1)
          .truncationMode(.middle)
        if let second = detail ?? listedText {
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
    }
    .padding(.vertical, 2)
    .help(node.path.map(Redactor.tilde) ?? "")
    .accessibilityElement(children: .combine)
    .contextMenu {
      if let path = node.path {
        Button("Show in Finder", systemImage: Symbols.showInFinder) {
          NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
        Button("Copy Path", systemImage: "document.on.document") { Copying.copy(path) }
      }
    }
  }

  private var listedText: String? {
    guard listed >= 50_000_000 else { return nil }
    return "\(Format.bytes(min(listed, node.bytes))) of this is listed in Storage"
  }
}
