import GladeKit
import SwiftUI

/// Everything keeping the Mac awake: who, what, for how long, and the fitting action.
/// Apps can be quit and simulators shut down; command-line tools name what started
/// them, since Glade doesn’t stop them; macOS’s own requests show only in Technical.
struct AwakeList: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accentMark) private var accentMark
  var report: AwakeReport?
  var detail: BatterySettings.Detail
  var now: Date
  var announce: (String) -> Void
  @State private var working: Set<String> = []

  private var holders: [AwakeHolder] {
    guard let report else { return [] }
    return detail == .technical ? report.holders : report.notable
  }

  var body: some View {
    Card(padding: 0) {
      VStack(spacing: 0) {
        if report == nil {
          ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            .padding(Metrics.l)
        } else {
          if report?.sleepDisabled == true {
            row(
              icon: AnyView(symbol("moon.zzz", color: Palette.warning)),
              title: "Sleep is off for this whole Mac",
              facts: "Turned off by an app or a command",
              help: "Sleep stays off until whatever turned it off turns it back on (`pmset disablesleep 0`, which needs an administrator)."
            ) { EmptyView() }
            if !holders.isEmpty { divider }
          }
          ForEach(Array(holders.enumerated()), id: \.element.id) { index, holder in
            if index > 0 { divider }
            holderRow(holder)
          }
          if holders.isEmpty && report?.sleepDisabled != true {
            Text(report?.neverSleepsOnThisPower == true ? "Nothing, but it’s set never to sleep on the charger." : "Nothing is keeping your Mac awake.")
              .font(.callout)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, Metrics.l)
              .padding(.vertical, Metrics.m)
          }
        }
      }
    }
  }

  private var divider: some View {
    Divider().padding(.leading, 52).padding(.trailing, Metrics.l)
  }

  private func holderRow(_ holder: AwakeHolder) -> some View {
    var facts = holder.sentence
    if let seconds = holder.seconds(now: now) { facts += " · \(PerformanceAdvisor.shortDuration(seconds))" }
    var help = "\(AwakeReasons.scope(display: holder.holdsDisplay))."
    if detail == .technical {
      help += " \(holder.rawTypes.joined(separator: ", ")): \(holder.rawNames.joined(separator: "; "))"
      if let heldBy = holder.heldBy { help += " (held by \(heldBy))" }
    }
    return row(icon: icon(holder), title: holder.name, facts: facts, help: help, dimmed: holder.kind == .system) {
      if let title = model.actionTitle(for: holder) {
        Button(title) {
          working.insert(holder.id)
          Task {
            announce(await model.perform(holder))
            working.remove(holder.id)
          }
        }
        .secondaryAction()
        .controlSize(.small)
        .disabled(working.contains(holder.id))
        .accessibilityLabel("\(title) \(holder.name)")
      }
    }
  }

  private func icon(_ holder: AwakeHolder) -> AnyView {
    switch holder.kind {
    case .app: AnyView(AppIconView(path: holder.bundlePath, size: 24))
    case .simulator: AnyView(symbol("iphone", color: accentMark))
    case .process: AnyView(symbol("terminal", color: accentMark))
    case .system: AnyView(symbol("gearshape", color: .secondary))
    }
  }

  private func symbol(_ name: String, color: Color) -> some View {
    Image(systemName: name)
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(color)
      .frame(width: 24, height: 24)
      .background(color.opacity(0.14), in: .rect(cornerRadius: 24 * 0.24))
      .accessibilityHidden(true)
  }

  private func row(
    icon: AnyView, title: String, facts: String, help: String, dimmed: Bool = false, @ViewBuilder action: () -> some View
  ) -> some View {
    HStack(spacing: Metrics.m) {
      icon
      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .foregroundStyle(dimmed ? .secondary : .primary)
          .lineLimit(1)
        Text(facts)
          .font(.callout)
          .foregroundStyle(.secondary)
          .monospacedDigit()
          .lineLimit(1)
      }
      .accessibilityElement(children: .combine)
      Spacer(minLength: Metrics.s)
      action()
    }
    .padding(.horizontal, Metrics.l)
    .padding(.vertical, Metrics.s)
    .contentShape(.rect)
    .help(help)
  }
}
