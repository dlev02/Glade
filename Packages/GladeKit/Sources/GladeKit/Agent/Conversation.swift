import Foundation

/// One earlier message in a conversation with the Assistant.
public struct ConversationTurn: Codable, Sendable, Equatable {
  public enum Role: String, Codable, Sendable { case person, assistant }

  public var role: Role
  public var text: String

  public init(role: Role, text: String) {
    self.role = role
    self.text = text
  }
}

/// What came before a question, so a follow-up such as “and the other one?” makes sense.
/// Only the conversation on screen is sent; nothing carries over once it’s cleared.
public enum Conversation {
  /// The longest a single earlier message may be once shortened.
  static func turnLimit(local: Bool) -> Int { local ? 600 : 2_000 }

  /// The earlier messages as prompt text, newest kept when they don’t all fit.
  /// - Parameter budget: Characters the whole section may use.
  public static func render(_ turns: [ConversationTurn], budget: Int, local: Bool) -> String? {
    guard !turns.isEmpty, budget > 200 else { return nil }
    var kept: [String] = []
    var used = 0
    for turn in turns.reversed() {
      var text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
      if text.isEmpty { continue }
      let limit = turnLimit(local: local)
      if text.count > limit { text = String(text.prefix(limit)) + " …" }
      let line = "\(turn.role == .person ? "Owner" : "Glade’s assistant"): \(text)"
      guard used + line.count <= budget else { break }
      kept.append(line)
      used += line.count + 2
    }
    guard !kept.isEmpty else { return nil }
    let dropped = turns.count - kept.count
    var section = "EARLIER IN THIS CONVERSATION (oldest first; the readings below are newer than anything said here)\n"
    if dropped > 0 { section += "(\(dropped) earlier messages left out)\n" }
    section += kept.reversed().joined(separator: "\n\n")
    return section
  }

  /// The conversation a new question continues: the last question’s own earlier
  /// messages, then that question and its answer. `nil` when the last one is too old
  /// to be what the person means.
  public static func continuing(from runs: [AssistantRun], now: Date = Date(), within: TimeInterval = 6 * 3_600) -> [ConversationTurn]? {
    guard let last = runs.first(where: { $0.purpose == "question" && $0.reply != nil }),
          now.timeIntervalSince(last.date) <= within,
          let question = last.question, let reply = last.reply
    else { return nil }
    return (last.earlier ?? []) + [ConversationTurn(role: .person, text: question), ConversationTurn(role: .assistant, text: reply)]
  }
}
