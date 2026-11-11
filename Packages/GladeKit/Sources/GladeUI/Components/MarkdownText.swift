import SwiftUI

/// An AI’s answer, rendered from its Markdown: paragraphs, bold, italic, inline code
/// and links, modest headings, lists with hanging indents on the answer’s text edge,
/// quiet code blocks with Copy, quotes and simple tables. Everything is selectable;
/// copying the whole answer elsewhere copies the original Markdown.
struct MarkdownText: View {
  var source: String
  /// The space between blocks.
  var spacing: CGFloat

  init(_ source: String, spacing: CGFloat = Metrics.s) {
    self.source = source
    self.spacing = spacing
  }

  var body: some View {
    let blocks = MarkdownBlock.parse(source)
    VStack(alignment: .leading, spacing: spacing) {
      ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
        view(for: block, after: index > 0 ? blocks[index - 1] : nil)
      }
    }
    .textSelection(.enabled)
  }

  @ViewBuilder
  private func view(for block: MarkdownBlock, after previous: MarkdownBlock?) -> some View {
    switch block {
    case .paragraph(let text):
      Text(Self.inline(text))
        .fixedSize(horizontal: false, vertical: true)
    case .heading(let level, let text):
      // An answer is not a document: headings stay close to body size.
      Text(Self.inline(text))
        .font(level <= 2 ? .title3.weight(.semibold) : .headline)
        .padding(.top, previous == nil ? 0 : Metrics.xs)
        .accessibilityAddTraits(.isHeader)
    case .item(let number, let depth, let text):
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(number.map { "\($0)." } ?? (depth == 0 ? "•" : "◦"))
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .frame(minWidth: 14, alignment: number == nil ? .center : .trailing)
          .accessibilityHidden(number == nil)
        Text(Self.inline(text))
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.leading, CGFloat(depth) * 20)
      // Items of one list sit closer together than paragraphs.
      .padding(.top, Self.isItem(previous) ? -spacing / 2 : 0)
    case .code(let code):
      CodeBlock(code: code)
    case .quote(let text):
      Text(Self.inline(text))
        .foregroundStyle(.secondary)
        .padding(.leading, Metrics.m)
        .overlay(alignment: .leading) {
          Capsule().fill(.quaternary).frame(width: 3)
        }
    case .rule:
      Divider()
    case .table(let header, let rows):
      MarkdownTable(header: header, rows: rows)
    }
  }

  private static func isItem(_ block: MarkdownBlock?) -> Bool {
    if case .item? = block { return true }
    return false
  }

  /// Bold, italic, inline code and links, with code in a monospaced face.
  static func inline(_ text: String) -> AttributedString {
    guard var attributed = try? AttributedString(
      markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
    ) else { return AttributedString(text) }
    for run in attributed.runs where run.inlinePresentationIntent?.contains(.code) == true {
      attributed[run.range].font = .system(.body, design: .monospaced)
      attributed[run.range].backgroundColor = Color.primary.opacity(0.06)
    }
    return attributed
  }
}

/// A fenced code block: monospaced, on a quiet fill, with its own Copy.
private struct CodeBlock: View {
  var code: String
  @State private var hovering = false

  var body: some View {
    ScrollView(.horizontal) {
      Text(verbatim: code)
        .font(.system(.callout, design: .monospaced))
        .fixedSize()
        .padding(Metrics.m)
    }
    .scrollIndicators(.hidden)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.fill.quaternary, in: .rect(cornerRadius: Metrics.innerRadius))
    .overlay(alignment: .topTrailing) {
      CopyButton { code }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .padding(Metrics.s)
        .opacity(hovering ? 1 : 0)
        .help("Copy")
    }
    .onHover { hovering = $0 }
  }
}

/// A Markdown table as a plain grid with a bold header and hairlines.
private struct MarkdownTable: View {
  var header: [String]
  var rows: [[String]]

  var body: some View {
    let columns = max(header.count, rows.map(\.count).max() ?? 0)
    Grid(alignment: .leading, horizontalSpacing: Metrics.l, verticalSpacing: 6) {
      GridRow {
        ForEach(0..<columns, id: \.self) { column in
          Text(MarkdownText.inline(column < header.count ? header[column] : ""))
            .fontWeight(.semibold)
        }
      }
      Divider()
      ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
        GridRow {
          ForEach(0..<columns, id: \.self) { column in
            Text(MarkdownText.inline(column < row.count ? row[column] : ""))
          }
        }
      }
    }
    .font(.callout)
  }
}
