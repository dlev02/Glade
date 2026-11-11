import Foundation

/// A model’s name as its maker writes it: "opus" is shown as "Opus", "gpt-6.1-sol" as
/// "GPT-6.1-Sol". The stored identifier never changes; only what people read.
enum ModelName {
  static func display(_ identifier: String) -> String {
    let lowered = identifier.lowercased()
    if lowered.hasPrefix("gpt-") || lowered.hasPrefix("o") && lowered.dropFirst().first?.isNumber == true {
      return identifier.split(separator: "-").enumerated().map { index, part in
        index == 0 ? part.uppercased() : capitalised(part)
      }.joined(separator: "-")
    }
    // "claude-opus-4" and "gemini-2.5-pro" read as words.
    return identifier.split(separator: "-").map(capitalised).joined(separator: " ")
  }

  private static func capitalised(_ part: Substring) -> String {
    guard let first = part.first, first.isLetter else { return String(part) }
    return first.uppercased() + part.dropFirst()
  }
}
