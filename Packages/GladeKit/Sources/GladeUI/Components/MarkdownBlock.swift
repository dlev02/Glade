import Foundation

/// One block of an AI’s Markdown answer. Inline styling (bold, italic, code, links)
/// is left to `AttributedString(markdown:)`; this splits out the block structure it
/// doesn’t handle: headings, lists, code blocks, quotes, rules and tables.
enum MarkdownBlock: Equatable {
  case paragraph(String)
  case heading(level: Int, text: String)
  /// A list item; `number` is set for ordered lists, `depth` counts nesting.
  case item(number: Int?, depth: Int, text: String)
  case code(String)
  case quote(String)
  case rule
  case table(header: [String], rows: [[String]])

  /// Splits Markdown into blocks. Anything it doesn’t recognise stays a paragraph, so
  /// nothing an AI wrote is ever dropped.
  static func parse(_ source: String) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    var paragraph: [String] = []
    let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    var index = 0

    func flush() {
      if !paragraph.isEmpty {
        blocks.append(.paragraph(paragraph.joined(separator: "\n")))
        paragraph = []
      }
    }

    while index < lines.count {
      let line = lines[index]
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      // Fenced code: everything up to the closing fence, verbatim.
      if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
        flush()
        let fence = String(trimmed.prefix(3))
        var code: [String] = []
        index += 1
        while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
          code.append(lines[index])
          index += 1
        }
        blocks.append(.code(code.joined(separator: "\n")))
        index += 1
        continue
      }

      if trimmed.isEmpty {
        flush()
        index += 1
        continue
      }

      // A table: a row of cells, then a separator row of dashes.
      if trimmed.hasPrefix("|"), index + 1 < lines.count, isTableSeparator(lines[index + 1]) {
        flush()
        let header = cells(trimmed)
        var rows: [[String]] = []
        index += 2
        while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
          rows.append(cells(lines[index].trimmingCharacters(in: .whitespaces)))
          index += 1
        }
        blocks.append(.table(header: header, rows: rows))
        continue
      }

      if let heading = heading(trimmed) {
        flush()
        blocks.append(heading)
      } else if ["---", "***", "___"].contains(trimmed.replacingOccurrences(of: " ", with: "")) {
        flush()
        blocks.append(.rule)
      } else if trimmed.hasPrefix(">") {
        flush()
        blocks.append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
      } else if let item = item(line) {
        flush()
        blocks.append(item)
      } else if case .item(let number, let depth, let text)? = blocks.last, paragraph.isEmpty, line.hasPrefix("  ") {
        // A wrapped continuation of the item above.
        blocks[blocks.count - 1] = .item(number: number, depth: depth, text: text + " " + trimmed)
      } else {
        paragraph.append(trimmed)
      }
      index += 1
    }
    flush()
    return blocks
  }

  private static func heading(_ line: String) -> MarkdownBlock? {
    let hashes = line.prefix { $0 == "#" }.count
    guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
    return .heading(level: hashes, text: String(line.dropFirst(hashes + 1)).trimmingCharacters(in: .whitespaces))
  }

  private static func item(_ line: String) -> MarkdownBlock? {
    let indent = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
    let rest = line.drop { $0 == " " || $0 == "\t" }
    let depth = min(indent / 2, 3)
    for marker in ["- ", "* ", "+ ", "• "] where rest.hasPrefix(marker) {
      return .item(number: nil, depth: depth, text: String(rest.dropFirst(marker.count)))
    }
    let digits = rest.prefix { $0.isNumber }
    if !digits.isEmpty, digits.count < 4, let number = Int(digits) {
      let after = rest.dropFirst(digits.count)
      if after.hasPrefix(". ") || after.hasPrefix(") ") {
        return .item(number: number, depth: depth, text: String(after.dropFirst(2)))
      }
    }
    return nil
  }

  private static func isTableSeparator(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("|"), trimmed.contains("-") else { return false }
    return trimmed.allSatisfy { "|-: ".contains($0) }
  }

  private static func cells(_ row: String) -> [String] {
    var inner = Substring(row)
    if inner.hasPrefix("|") { inner = inner.dropFirst() }
    if inner.hasSuffix("|") { inner = inner.dropLast() }
    return inner.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
  }
}
