import GladeKit
import SwiftUI

/// The standard surface for a group of related content.
public struct Card<Content: View>: View {
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
        RoundedRectangle(cornerRadius: Metrics.cardRadius)
          .strokeBorder(Palette.hairline.opacity(0.6), lineWidth: Metrics.hairline)
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

  public init(id: String, title: String, bytes: Int64, color: Color) {
    self.id = id
    self.title = title
    self.bytes = bytes
    self.color = color
  }
}

/// The disk as one rounded bar: what's reclaimable by family, everything else in
/// use, and what's free.
public struct StorageBar: View {
  var segments: [BarSegment]
  var total: Int64
  var height: CGFloat

  public init(segments: [BarSegment], total: Int64, height: CGFloat = 22) {
    self.segments = segments
    self.total = total
    self.height = height
  }

  public var body: some View {
    GeometryReader { proxy in
      let visible = segments.filter { $0.bytes > 0 }
      let gap: CGFloat = 2
      let usable = max(0, proxy.size.width - gap * CGFloat(max(0, visible.count - 1)))
      HStack(spacing: gap) {
        ForEach(visible) { segment in
          Rectangle()
            .fill(segment.color.gradient)
            .frame(width: max(2, usable * CGFloat(segment.bytes) / CGFloat(max(total, 1))))
            .help("\(segment.title): \(Format.bytes(segment.bytes))")
        }
        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Palette.track)
      .clipShape(.capsule)
    }
    .frame(height: height)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Storage")
    .accessibilityValue(segments.filter { $0.bytes > 0 }.map { "\($0.title) \(Format.bytes($0.bytes))" }.joined(separator: ", "))
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
          Circle().fill(segment.color).frame(width: 8, height: 8)
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

/// A small pill saying how something comes back after removal.
public struct RecoveryBadge: View {
  var recovery: Recovery

  public init(_ recovery: Recovery) {
    self.recovery = recovery
  }

  public var body: some View {
    Label(recovery.title, systemImage: recovery.symbol)
      .font(.caption)
      .foregroundStyle(recovery.color)
      .padding(.horizontal, 7)
      .padding(.vertical, 2)
      .background(recovery.color.opacity(0.12), in: .capsule)
      .help(recovery.explanation)
  }
}

/// A category's symbol on a tinted tile.
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
      .foregroundStyle(category.family.color)
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
