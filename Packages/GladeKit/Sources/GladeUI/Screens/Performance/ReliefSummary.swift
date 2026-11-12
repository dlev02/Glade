import GladeKit
import SwiftUI

/// What Free Up Memory did, told the way the clean result tells it: a headline of what
/// was done, memory in use before and after as measured, and a line for each action,
/// with the reason for anything that didn’t go as asked. Every line hangs its icon in
/// one 20-point column so the text shares one edge.
struct ReliefSummary: View {
  @Environment(\.accentMark) private var accentMark
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var result: ReliefResult
  var done: () -> Void
  /// Flips once on appear, so the tick bounces a single time.
  @State private var appeared = false

  private static let iconWidth: CGFloat = 20

  var body: some View {
    let warns = !result.problems.isEmpty
    VStack(alignment: .leading, spacing: Metrics.l) {
      line(symbol: warns ? "exclamationmark.triangle.fill" : "checkmark.circle.fill", tint: warns ? Palette.warning : accentMark, large: true) {
        Text(headline)
          .font(.title2.weight(.semibold))
          .fixedSize(horizontal: false, vertical: true)
        memory
      }

      ScrollView {
        VStack(alignment: .leading, spacing: Metrics.s) {
          ForEach(result.entries) { entry in
            let ok = entry.outcome.succeeded
            line(symbol: ok ? "checkmark" : "exclamationmark.triangle", tint: ok ? .secondary : Palette.warning) {
              Text(entry.name)
                .lineLimit(1)
                .truncationMode(.middle)
              Text(Self.outcome(entry))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("relief.result.\(entry.name)")
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxHeight: 260)
      .fixedSize(horizontal: false, vertical: true)

      HStack {
        Spacer()
        Button("Done", action: done)
          .principalAction()
          .controlSize(.large)
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("relief.done")
      }
    }
    .padding(Metrics.xl)
    .onAppear { if !reduceMotion { appeared = true } }
  }

  /// "Quit 2 apps and shut down 2 simulators", counting only what was done.
  private var headline: String {
    let done = result.entries.filter { $0.outcome == .quit || $0.outcome == .relaunched || $0.outcome == .shutDown }
    func count(_ outcome: ReliefResult.Outcome) -> Int { done.filter { $0.outcome == outcome }.count }
    var parts: [String] = []
    if count(.quit) > 0 { parts.append("quit \(count(.quit)) \(count(.quit) == 1 ? "app" : "apps")") }
    if count(.relaunched) > 0 { parts.append("relaunched \(count(.relaunched)) \(count(.relaunched) == 1 ? "app" : "apps")") }
    if count(.shutDown) > 0 { parts.append("shut down \(count(.shutDown)) \(count(.shutDown) == 1 ? "simulator" : "simulators")") }
    guard !parts.isEmpty else { return "Nothing was quit" }
    let sentence = Format.listed(parts)
    return sentence.prefix(1).uppercased() + sentence.dropFirst()
  }

  /// Memory in use before and after, as measured.
  private var memory: some View {
    HStack(spacing: Metrics.s) {
      Text("Memory in use")
      Text(Format.bytes(result.memoryBefore))
      Image(systemName: "arrow.right")
        .font(.caption)
        .accessibilityLabel("to")
      Text(Format.bytes(result.memoryAfter))
        .foregroundStyle(.primary)
        .fontWeight(.medium)
    }
    .foregroundStyle(.secondary)
    .monospacedDigit()
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("relief.memory")
  }

  static func outcome(_ entry: ReliefResult.Entry) -> String {
    switch entry.outcome {
    case .quit: "Quit · was using \(Format.bytes(entry.memoryBytes))"
    case .relaunched: "Relaunched · was using \(Format.bytes(entry.memoryBytes))"
    case .shutDown: "Shut down · its apps and data are kept"
    case .alreadyGone: "Already closed"
    case .stillOpen, .leftAlone, .failed: entry.detail ?? "Not done"
    }
  }

  /// One line of the sheet: an icon in the shared column, then its text.
  private func line(
    symbol: String, tint: Color, large: Bool = false, @ViewBuilder content: () -> some View
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
      Image(systemName: symbol)
        .font(large ? .title2 : .body)
        .foregroundStyle(tint)
        .symbolEffect(.bounce, options: .nonRepeating, value: large && appeared)
        .frame(width: Self.iconWidth)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        content()
      }
    }
    .accessibilityElement(children: .combine)
  }
}
