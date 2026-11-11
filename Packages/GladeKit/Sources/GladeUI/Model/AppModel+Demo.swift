import Foundation
import GladeKit

/// Demo mode's stand-in for restoring, which never touches the disk. The simulated
/// clean is in `AppModel` itself, because it sets the model's own state.
extension AppModel {
  /// Says every Trash item came back, without moving anything.
  static func pretendRestore(_ receipt: Receipt) -> Cleaner.RestoreResult {
    let titles = receipt.entries.compactMap { entry -> String? in
      if case .trashed = entry.outcome { return entry.title }
      return nil
    }
    let json = try? JSONSerialization.data(withJSONObject: ["restored": titles, "missing": [], "blocked": []])
    return json.flatMap { try? JSONDecoder().decode(Cleaner.RestoreResult.self, from: $0) }
      ?? (try! JSONDecoder().decode(Cleaner.RestoreResult.self, from: Data(#"{"restored":[],"missing":[],"blocked":[]}"#.utf8)))
  }
}
