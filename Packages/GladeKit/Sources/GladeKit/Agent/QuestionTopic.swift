import Foundation

/// What a question to the Assistant is about, decided from its whole words rather than
/// pieces of them, so "CleanShot" isn’t a request to clean and "recall" isn’t a call.
/// File paths pasted into a question are ignored: their folder and file names say
/// nothing about what the person wants.
public enum QuestionTopic {
  /// Words that make a request to free space.
  static let spaceWords: Set<String> = ["free", "clean", "cleanup", "clear", "space", "storage", "delete", "remove", "gb", "declutter"]

  /// Words that make a question about the network, so it’s measured (27 pings) before
  /// the AI is asked rather than for every question.
  static let networkWords: Set<String> = [
    "internet", "wifi", "network", "router", "gateway", "modem", "ping", "latency", "lag", "laggy", "buffer", "buffering",
    "bufferbloat", "stream", "streaming", "speed", "upload", "download", "vpn", "bandwidth", "connection", "call", "calls",
    "zoom", "facetime", "discord", "steam", "netflix", "youtube", "data", "hotspot", "hotel", "mesh", "deco", "dns", "slow",
    "qos", "sqm", "channel", "ethernet", "mbps", "jitter", "keychain", "online", "offline",
  ]

  /// Phrases of more than one word, matched in the lowercased text.
  static let networkPhrases = ["wi-fi", "little snitch", "smart queue", "access code", "speed test", "packet loss"]

  public static func wantsSpace(_ question: String) -> Bool {
    let text = withoutPaths(question)
    if text.range(of: #"\d+\s*gb\b"#, options: [.regularExpression, .caseInsensitive]) != nil { return true }
    return !Set(RemovalRequest.words(text)).isDisjoint(with: spaceWords)
  }

  /// Whether a question is about the network, or follows on from one that was: "use
  /// the code to check the settings" means the router when the last question did.
  public static func isAboutNetwork(_ question: String, earlier: [ConversationTurn] = []) -> Bool {
    if mentionsNetwork(question) { return true }
    // The two latest things the person said, so one aside doesn’t lose the thread.
    return earlier.filter { $0.role == .person }.suffix(2).contains { mentionsNetwork($0.text) }
  }

  static func mentionsNetwork(_ text: String) -> Bool {
    let text = withoutPaths(text)
    let lowered = text.lowercased()
    if networkPhrases.contains(where: lowered.contains) { return true }
    return !Set(RemovalRequest.words(text)).isDisjoint(with: networkWords)
  }

  /// The text with file paths taken out: `/Users/…/CleanShot 2026-11-20 at 3.34.52 AM@2x.png`
  /// and `~/Downloads/thing` alike. A path ending in a file name may contain spaces.
  public static func withoutPaths(_ text: String) -> String {
    var text = text
    let patterns = [
      #"(?:~|/)(?:[^\s/]+/)+[^/\n]*?\.[A-Za-z0-9]{2,5}\b"#,
      #"(?:~|(?<![\w.])/)[^\s]*/[^\s]*"#,
    ]
    for pattern in patterns {
      text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
    }
    return text
  }
}
