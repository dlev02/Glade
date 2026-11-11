import Foundation

/// Launch arguments that put sample data into a particular state for screenshots,
/// such as `-demoClean result` or `-demoChoice "Clean level"`. They only count
/// alongside `-demo YES`, and nothing they do is saved.
enum DemoState {
  static func value(_ key: String) -> String? {
    let defaults = UserDefaults.standard
    guard defaults.bool(forKey: "demo") else { return nil }
    return defaults.string(forKey: key)
  }
}
