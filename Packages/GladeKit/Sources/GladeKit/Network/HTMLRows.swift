import Foundation

/// Table rows from a router’s status page: a label and its value as text, plus the
/// value’s markup for the odd detail only an image carries (signal bars).
struct HTMLRow: Sendable {
  var label: String
  var value: String
  var valueMarkup: String

  /// Every `<tr>` with a heading or first cell and a value, in page order.
  static func rows(in html: String) -> [HTMLRow] {
    var rows: [HTMLRow] = []
    for row in matches(#"<tr[^>]*>(.*?)</tr>"#, in: html) {
      let cells = matches(#"<t[hd][^>]*>(.*?)</t[hd]>"#, in: row)
      guard cells.count >= 2 else { continue }
      let label = text(cells[0])
      guard !label.isEmpty else { continue }
      rows.append(HTMLRow(label: label, value: text(cells[1]), valueMarkup: cells[1]))
    }
    return rows
  }

  /// The first value for each label.
  static func firstValues(in html: String) -> [String: String] {
    var values: [String: String] = [:]
    for row in rows(in: html) where values[row.label] == nil { values[row.label] = row.value }
    return values
  }

  static func matches(_ pattern: String, in text: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
    let range = NSRange(text.startIndex..., in: text)
    return regex.matches(in: text, range: range).compactMap { match in
      Range(match.range(at: 1), in: text).map { String(text[$0]) }
    }
  }

  /// Markup to plain text: tags become spaces, entities are decoded, runs of space collapse.
  static func text(_ markup: String) -> String {
    var text = markup.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
    text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
    for (entity, character) in ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'"] {
      text = text.replacingOccurrences(of: entity, with: character)
    }
    return text.split(separator: "\n").map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
      .filter { !$0.isEmpty }.joined(separator: "\n")
  }
}
