import GladeKit
import SwiftUI

/// The standard surface for a group of related content.
public struct Card<Content: View>: View {
  @Environment(\.colorScheme) private var colorScheme
  var padding: CGFloat
  @ViewBuilder var content: Content

  public init(padding: CGFloat = Metrics.l, @ViewBuilder content: () -> Content) {
    self.padding = padding
    self.content = content()
  }

  public var body: some View {
    content
      .padding(padding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Palette.card, in: .rect(cornerRadius: Metrics.cardRadius))
      .overlay {
        // In dark the fill separates a card from the window; in light it needs a line.
        if colorScheme == .light {
          RoundedRectangle(cornerRadius: Metrics.cardRadius)
            .strokeBorder(Palette.hairline.opacity(0.6), lineWidth: Metrics.hairline)
        }
      }
  }
}

/// A small heading above a card or a group of rows.
public struct SectionTitle: View {
  var title: String

  public init(_ title: String) {
    self.title = title
  }

  public var body: some View {
    Text(title)
      .font(.headline)
      .accessibilityAddTraits(.isHeader)
  }
}

/// One slice of a storage bar.
public struct BarSegment: Identifiable, Hashable, Sendable {
  public var id: String
  public var title: String
  public var bytes: Int64
  public var color: Color

  /// The slice’s colour as a small dot in a key: the catch-all’s faint fill is
  /// strengthened so the dot doesn’t vanish.
  public var legendColor: Color {
    id == "other" ? Color.primary.opacity(0.38) : color
  }

  public init(id: String, title: String, bytes: Int64, color: Color) {
    self.id = id
    self.title = title
    self.bytes = bytes
    self.color = color
  }
}

/// The disk as one rounded bar: what’s reclaimable by family, everything else in
/// use, and what’s free. Pointing at a slice brightens it, dims the rest a little and
/// shows its name and size in a small bubble above it, in room the bar’s owner leaves
/// clear (`bubbleRoom`), so nothing moves or is covered; `hovered` is shared with the
/// legend so each lights the other. Every slice is its own accessibility element.
public struct StorageBar: View {
  var segments: [BarSegment]
  var total: Int64
  var height: CGFloat
  @Binding var hovered: String?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var bubbleSize = CGSize(width: 120, height: 28)
  /// The slice this bar last lit, so leaving the bar clears only that.
  @State private var pointed: String?

  /// How much room the bubble needs above the bar.
  public static var bubbleRoom: CGFloat { Metrics.xxl }

  public init(segments: [BarSegment], total: Int64, height: CGFloat = 22, hovered: Binding<String?> = .constant(nil)) {
    self.segments = segments
    self.total = total
    self.height = height
    _hovered = hovered
  }

  public var body: some View {
    GeometryReader { proxy in
      let frames = frames(width: proxy.size.width)
      ZStack(alignment: .topLeading) {
        HStack(spacing: 0) { Spacer(minLength: 0) }
          .frame(width: proxy.size.width, height: height)
          .background(Palette.track)
        ForEach(frames, id: \.segment.id) { item in
          Rectangle()
            .fill(item.segment.color.gradient)
            .brightness(hovered == item.segment.id ? 0.06 : 0)
            .opacity(hovered == nil || hovered == item.segment.id ? 1 : 0.55)
            .frame(width: item.width, height: height)
            .offset(x: item.x)
            .accessibilityElement()
            .accessibilityLabel(item.segment.title)
            .accessibilityValue(Format.bytes(item.segment.bytes))
        }
      }
      // One pointer handler for the whole bar, worked out from where the pointer is:
      // a slice moved into place with an offset keeps its hover area where it was
      // laid out, so slices tracking the pointer themselves all answered at the
      // bar's leading end and the last one drawn won.
      .contentShape(.rect)
      .onContinuousHover(coordinateSpace: .local) { phase in
        switch phase {
        case .active(let point):
          let id = Self.slice(at: point.x, in: frames)
          if id != nil || hovered == pointed { hovered = id }
          pointed = id
        case .ended:
          // Only clears its own slice, so a legend entry lit a moment earlier stays.
          if hovered == pointed { hovered = nil }
          pointed = nil
        }
      }
      .clipShape(.capsule)
      .overlay(alignment: .topLeading) {
        if let item = frames.first(where: { $0.segment.id == hovered }) {
          // Over the slice, its arrow just touching the bar’s top edge, and kept
          // within the bar’s ends however near one the slice is.
          let centre = item.x + item.width / 2
          let half = bubbleSize.width / 2
          let x = min(max(centre, half), max(half, proxy.size.width - half))
          let arrowLimit = max(0, half - 14)
          BarBubble(segment: item.segment, arrowOffset: min(max(centre - x, -arrowLimit), arrowLimit))
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { bubbleSize = $0 }
            .position(x: x, y: -bubbleSize.height / 2 - 1)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
      }
      .animation(reduceMotion ? nil : .snappy(duration: 0.12), value: hovered)
    }
    .frame(height: height)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Storage")
  }

  /// The slice under a point along the bar. The gaps between slices belong to a
  /// neighbour, and a sliver a few points wide answers a little either side of
  /// itself, so the pointer can find it; the narrowest slice in reach wins.
  static func slice(at x: CGFloat, in frames: [(segment: BarSegment, x: CGFloat, width: CGFloat)]) -> String? {
    frames
      .filter { frame in
        let reach = max(1, (10 - frame.width) / 2)
        return x >= frame.x - reach && x <= frame.x + frame.width + reach
      }
      .min { $0.width < $1.width }?
      .segment.id
  }

  /// Where each visible slice sits, with a 2-point gap between slices.
  private func frames(width: CGFloat) -> [(segment: BarSegment, x: CGFloat, width: CGFloat)] {
    let visible = segments.filter { $0.bytes > 0 }
    let gap: CGFloat = 2
    let usable = max(0, width - gap * CGFloat(max(0, visible.count - 1)))
    var x: CGFloat = 0
    return visible.map { segment in
      let w = max(2, usable * CGFloat(segment.bytes) / CGFloat(max(total, 1)))
      defer { x += w + gap }
      return (segment, x, w)
    }
  }
}

/// The small bubble above a pointed-at slice: its name and size, with an arrow that
/// points at the slice even when the bubble is pushed in from the bar’s end.
private struct BarBubble: View {
  var segment: BarSegment
  var arrowOffset: CGFloat

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 6) {
        Circle().fill(segment.legendColor).frame(width: 7, height: 7)
        Text(segment.title)
        Text(Format.bytes(segment.bytes))
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      .font(.subheadline)
      .padding(.horizontal, 9)
      .padding(.vertical, 4)
      .background(.thickMaterial, in: .capsule)
      Triangle()
        .fill(.thickMaterial)
        .frame(width: 12, height: 6)
        .offset(x: arrowOffset)
    }
    .compositingGroup()
    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    .accessibilityHidden(true)
  }
}

/// A small downward arrow.
private nonisolated struct Triangle: Shape {
  func path(in rect: CGRect) -> Path {
    Path { path in
      path.move(to: CGPoint(x: rect.minX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
      path.closeSubpath()
    }
  }
}

/// The key under a storage bar.
public struct BarLegend: View {
  var segments: [BarSegment]

  public init(segments: [BarSegment]) {
    self.segments = segments
  }

  public var body: some View {
    FlowLayout(spacing: Metrics.l, lineSpacing: Metrics.s) {
      ForEach(segments.filter { $0.bytes > 0 }) { segment in
        HStack(spacing: 6) {
          Circle().fill(segment.legendColor).frame(width: 8, height: 8)
          Text(segment.title).foregroundStyle(.secondary)
          Text(Format.bytes(segment.bytes)).monospacedDigit()
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
      }
    }
  }
}

/// Lays children out left to right, wrapping onto new lines.
public struct FlowLayout: Layout {
  var spacing: CGFloat
  var lineSpacing: CGFloat

  public init(spacing: CGFloat = 8, lineSpacing: CGFloat = 8) {
    self.spacing = spacing
    self.lineSpacing = lineSpacing
  }

  public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = arrange(subviews, width: proposal.width ?? .infinity)
    return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
  }

  public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for row in arrange(subviews, width: bounds.width) {
      var x = bounds.minX
      for index in row.indices {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
        x += size.width + spacing
      }
    }
  }

  private struct Row {
    var indices: [Int] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
    var y: CGFloat = 0
  }

  private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
    var rows: [Row] = []
    var current = Row()
    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.unspecified)
      if !current.indices.isEmpty, current.width + spacing + size.width > width {
        rows.append(current)
        current = Row(y: current.y + current.height + lineSpacing)
      }
      current.width += (current.indices.isEmpty ? 0 : spacing) + size.width
      current.height = max(current.height, size.height)
      current.indices.append(index)
    }
    if !current.indices.isEmpty { rows.append(current) }
    return rows
  }
}

/// A recent-history line, drawn as a single path so it costs almost nothing.
public struct Sparkline: View {
  var values: [Double]
  /// The value that fills the full height. `nil` scales to the largest value.
  var ceiling: Double?
  var color: Color

  public init(values: [Double], ceiling: Double? = 100, color: Color = .accentColor) {
    self.values = values
    self.ceiling = ceiling
    self.color = color
  }

  public var body: some View {
    Canvas { context, size in
      guard values.count > 1 else { return }
      let top = max(ceiling ?? values.max() ?? 1, 0.0001)
      let step = size.width / CGFloat(values.count - 1)
      var line = Path()
      for (index, value) in values.enumerated() {
        let point = CGPoint(x: CGFloat(index) * step, y: size.height - CGFloat(min(value, top) / top) * (size.height - 2) - 1)
        if index == 0 { line.move(to: point) } else { line.addLine(to: point) }
      }
      var area = line
      area.addLine(to: CGPoint(x: size.width, y: size.height))
      area.addLine(to: CGPoint(x: 0, y: size.height))
      area.closeSubpath()
      context.fill(area, with: .linearGradient(
        Gradient(colors: [color.opacity(0.28), color.opacity(0.02)]),
        startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)
      ))
      context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }
    .accessibilityHidden(true)
  }
}

/// A thin level bar with a rounded end.
public struct LevelBar: View {
  var fraction: Double
  var color: Color

  public init(fraction: Double, color: Color) {
    self.fraction = fraction
    self.color = color
  }

  public var body: some View {
    GeometryReader { proxy in
      Capsule()
        .fill(color.gradient)
        .frame(width: max(4, proxy.size.width * min(max(fraction, 0), 1)))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.track, in: .capsule)
    }
    .frame(height: 6)
    .accessibilityHidden(true)
  }
}

/// A small pill saying how something comes back after removal: the colour on the
/// glyph and the tint, the words in the primary colour so they stay readable.
public struct RecoveryBadge: View {
  var recovery: Recovery

  public init(_ recovery: Recovery) {
    self.recovery = recovery
  }

  public var body: some View {
    Label {
      Text(recovery.title)
    } icon: {
      Image(systemName: recovery.symbol)
        .foregroundStyle(recovery.color)
    }
    .font(.caption)
    .foregroundStyle(.primary)
    .padding(.horizontal, 7)
    .padding(.vertical, 2)
    .background(recovery.color.opacity(0.12), in: .capsule)
    .help(recovery.explanation)
  }
}

/// A category’s symbol on a tinted tile.
public struct CategoryIcon: View {
  var category: StorageCategory
  var size: CGFloat

  public init(_ category: StorageCategory, size: CGFloat = 28) {
    self.category = category
    self.size = size
  }

  public var body: some View {
    Image(systemName: category.symbol)
      .font(.system(size: size * 0.5, weight: .medium))
      .foregroundStyle(category.family.glyphColor)
      .frame(width: size, height: size)
      .background(category.family.color.opacity(0.14), in: .rect(cornerRadius: size * 0.28))
      .accessibilityHidden(true)
  }
}

/// A full-height message for a screen with nothing to show yet.
public struct EmptyState<Actions: View>: View {
  var title: String
  var symbol: String
  var message: String?
  @ViewBuilder var actions: Actions

  public init(_ title: String, symbol: String, message: String? = nil, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
    self.title = title
    self.symbol = symbol
    self.message = message
    self.actions = actions()
  }

  public var body: some View {
    ContentUnavailableView {
      Label(title, systemImage: symbol)
    } description: {
      if let message { Text(message) }
    } actions: {
      actions
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
