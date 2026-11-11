import Foundation
import GladeKit

/// Wording for a recorded run, shared by its row and its detail.
extension AssistantRun {
  /// "Storage plan", "Question": the purpose with a capital first letter.
  var purposeTitle: String {
    purpose.prefix(1).uppercased() + purpose.dropFirst()
  }

  /// Duration, tokens and cost, whichever are known.
  var figures: [String] {
    var parts = [duration.formatted(.number.precision(.fractionLength(1))) + " s"]
    switch (inputTokens, outputTokens) {
    case let (input?, output?): parts.append("\(input.formatted()) in · \(output.formatted()) out")
    case let (input?, nil): parts.append("\(input.formatted()) tokens in")
    case let (nil, output?): parts.append("\(output.formatted()) tokens out")
    case (nil, nil): break
    }
    if let costUSD {
      parts.append(costUSD.formatted(.currency(code: "USD").precision(.fractionLength(costUSD < 0.01 ? 4 : 2))))
    }
    return parts
  }
}
