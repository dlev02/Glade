import GladeKit
import SwiftUI

/// Says exactly what a clean will do before it starts. The title and button follow
/// the outcome: space is only freed by what is removed now; whatever goes to the Trash
/// still takes up space until the Trash is emptied, and the sheet says so.
struct CleanConfirmation: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var cancel: () -> Void
  var confirm: () -> Void
  /// Whether more of the list sits below the visible part, for the fade.
  @State private var moreBelow = false
  /// The list opens at its first row.
  @State private var position = ScrollPosition(edge: .top)

  /// Rows are one line each, so the list can show whole rows only.
  static let rowHeight: CGFloat = 32
  static let visibleRows = 7
  /// The list's inner leading inset: icons in the list and in the outcome lines above
  /// it share this edge.
  private static let inset = Metrics.m

  var body: some View {
    let items = model.cleanItems
    let immediate = model.immediateBytes
    let trash = model.trashBytes
    let permanent = items.filter { $0.recovery == .permanent }.count
    VStack(alignment: .leading, spacing: Metrics.l) {
      Text(title(items: items.count, immediate: immediate, trash: trash))
        .font(.title2.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)

      VStack(alignment: .leading, spacing: Metrics.s) {
        if immediate > 0 {
          outcome(
            "\(Format.bytes(immediate)) removed now", symbol: "bolt",
            detail: removedDetail(items)
          )
        }
        if trash > 0 {
          outcome(
            "\(Format.bytes(trash)) to the Trash",
            symbol: "trash", detail: "Space is freed when the Trash is emptied."
          )
        }
      }
      .padding(.leading, Self.inset)

      if !items.isEmpty {
        VStack(alignment: .leading, spacing: Metrics.s) {
          HStack(spacing: Metrics.s) {
            Text(items.count == 1 ? "1 item" : "\(items.count) items")
              .foregroundStyle(.secondary)
            Spacer(minLength: Metrics.s)
            if permanent > 0 {
              Label(
                permanent == 1 ? "1 item can’t be recreated" : "\(permanent) items can’t be recreated",
                systemImage: Recovery.permanent.symbol
              )
              .foregroundStyle(Recovery.permanent.color)
            }
          }
          .font(.callout)
          .padding(.horizontal, Self.inset)
          list(items)
        }
      }

      HStack(spacing: Metrics.s) {
        Spacer()
        Button("Cancel", action: cancel)
          .secondaryAction()
          .controlSize(.large)
          .keyboardShortcut(.cancelAction)
          .accessibilityIdentifier("confirm.cancel")
        Button(buttonTitle(immediate: immediate, trash: trash), action: confirm)
          .principalAction()
          .controlSize(.large)
          .monospacedDigit()
          .keyboardShortcut(.defaultAction)
          .disabled(items.isEmpty)
          .accessibilityIdentifier("confirm.clean")
      }
    }
    .padding(Metrics.xl)
  }

  private func title(items: Int, immediate: Int64, trash: Int64) -> String {
    if immediate == 0 {
      return items == 1 ? "Move 1 item to the Trash?" : "Move \(items) items to the Trash?"
    }
    return "Free up \(Format.bytes(immediate))?"
  }

  private func buttonTitle(immediate: Int64, trash: Int64) -> String {
    immediate == 0 ? "Move to Trash" : "Free Up \(Format.bytes(immediate))"
  }

  /// What removing outright means for the items it applies to. When only some of
  /// them can't be recreated, the red count above the list names the exception.
  private func removedDetail(_ items: [Finding]) -> String {
    let removed = items.filter { !$0.goesToTrash(model.config) }
    return !removed.isEmpty && removed.allSatisfy { $0.recovery == .permanent }
      ? "Can’t be put back"
      : "Rebuilds or downloads again when needed"
  }

  private func list(_ items: [Finding]) -> some View {
    let visible = min(items.count, Self.visibleRows)
    return ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, finding in
          row(finding)
            .overlay(alignment: .top) {
              if index > 0 {
                Divider().padding(.leading, Self.inset + 20 + Metrics.s)
              }
            }
        }
      }
      // Scrolling settles on whole rows.
      .scrollTargetLayout()
      .padding(.vertical, Metrics.xs)
    }
    .scrollPosition($position)
    .scrollTargetBehavior(.viewAligned)
    .defaultScrollAnchor(.top)
    .onAppear { position.scrollTo(edge: .top) }
    .scrollIndicators(items.count > Self.visibleRows ? .visible : .hidden)
    .scrollIndicatorsFlash(onAppear: true)
    .frame(height: CGFloat(visible) * Self.rowHeight + Metrics.xs * 2)
    .onScrollGeometryChange(for: Bool.self) { geometry in
      geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 2
    } action: { _, more in
      withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { moreBelow = more }
    }
    // A soft fade over the last row says there's more below.
    .mask {
      VStack(spacing: 0) {
        Color.black
        LinearGradient(colors: [.black, .black.opacity(moreBelow ? 0.15 : 1)], startPoint: .top, endPoint: .bottom)
          .frame(height: Self.rowHeight * 0.75)
      }
    }
    .background(Palette.card, in: .rect(cornerRadius: Metrics.innerRadius))
    .overlay {
      RoundedRectangle(cornerRadius: Metrics.innerRadius)
        .strokeBorder(Palette.hairline.opacity(0.6), lineWidth: Metrics.hairline)
    }
  }

  private func row(_ finding: Finding) -> some View {
    HStack(spacing: Metrics.s) {
      CategoryIcon(finding.category, size: 20)
      Text(finding.title)
        .lineLimit(1)
        .truncationMode(.middle)
      Spacer(minLength: Metrics.s)
      if finding.recovery == .permanent {
        Image(systemName: Recovery.permanent.symbol)
          .foregroundStyle(Recovery.permanent.color)
          .help(Recovery.permanent.explanation)
          .accessibilityLabel(Recovery.permanent.title)
      }
      Text(Format.bytes(finding.bytes))
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, Self.inset)
    .frame(height: Self.rowHeight)
    .accessibilityElement(children: .combine)
  }

  private func outcome(_ title: String, symbol: String, detail: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
      Image(systemName: symbol)
        .foregroundStyle(.secondary)
        .frame(width: 20)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .fontWeight(.medium)
          .monospacedDigit()
        Text(detail)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .accessibilityElement(children: .combine)
  }
}
