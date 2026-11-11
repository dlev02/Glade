import Foundation

/// Pulls a JSON object out of a model's reply, which may wrap it in Markdown fences or
/// put a sentence before it.
public enum JSONExtractor {
  /// The first balanced `{…}` in the text, skipping braces inside strings, or `nil` when
  /// there isn't one. The result isn't checked further; parse it to be sure.
  public static func firstObject(in text: String) -> String? {
    let scalars = Array(text.unicodeScalars)
    var index = 0
    while index < scalars.count {
      if scalars[index] == "{", let end = matchingBrace(in: scalars, from: index) {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars[index...end])
        let candidate = String(view)
        if (try? JSONSerialization.jsonObject(with: Data(candidate.utf8))) != nil { return candidate }
      }
      index += 1
    }
    return nil
  }

  /// The text with a surrounding Markdown code fence (```json … ```) removed.
  public static func stripFences(_ text: String) -> String {
    var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("```") else { return trimmed }
    if let firstBreak = trimmed.firstIndex(of: "\n") {
      trimmed = String(trimmed[trimmed.index(after: firstBreak)...])
    } else {
      trimmed = String(trimmed.dropFirst(3))
    }
    if trimmed.hasSuffix("```") { trimmed = String(trimmed.dropLast(3)) }
    return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// What a provider returns when a schema was asked for: the JSON object alone, or
  /// `badReply` when the reply has none.
  static func objectReply(_ text: String, provider: String) throws -> String {
    let unfenced = stripFences(text)
    if let object = firstObject(in: unfenced) { return object }
    throw AgentError.badReply(provider: provider, detail: "The reply didn’t contain a JSON object.")
  }

  private static func matchingBrace(in scalars: [Unicode.Scalar], from start: Int) -> Int? {
    var depth = 0
    var inString = false
    var escaped = false
    var index = start
    while index < scalars.count {
      let scalar = scalars[index]
      if inString {
        if escaped {
          escaped = false
        } else if scalar == "\\" {
          escaped = true
        } else if scalar == "\"" {
          inString = false
        }
      } else if scalar == "\"" {
        inString = true
      } else if scalar == "{" {
        depth += 1
      } else if scalar == "}" {
        depth -= 1
        if depth == 0 { return index }
      }
      index += 1
    }
    return nil
  }
}
