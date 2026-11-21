import AppKit
import GladeKit

/// Opens Terminal running an AI tool’s own sign-in command, so a person needn’t
/// remember it. Glade writes a small `.command` file and opens it; Terminal runs it in a
/// new window. Nothing is typed for the person: the tool asks them to sign in itself.
enum SignInTerminal {
  /// Opens Terminal with the provider’s sign-in command. Returns false when there isn’t
  /// one or Terminal couldn’t be started.
  @discardableResult
  static func open(_ provider: ProviderStatus) -> Bool {
    guard let command = provider.signInCommand else { return false }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Glade sign-in", isDirectory: true)
    let file = folder.appendingPathComponent("Sign in to \(provider.name.replacingOccurrences(of: "/", with: "-")).command")
    let script = """
      #!/bin/zsh -l
      clear
      echo \(quoted("Signing in to \(provider.name). When it’s done, go back to \(Brand.name)."))
      echo
      \(runnable(command, path: provider.path))

      """
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try script.write(to: file, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
    } catch {
      Log.warning(.agent, "Couldn’t prepare the sign-in for \(provider.name): \(error.localizedDescription)")
      return false
    }
    guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return false }
    NSWorkspace.shared.open([file], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    Log.info(.agent, "Opened Terminal to sign in to \(provider.name)")
    return true
  }

  /// The command with its tool named by the path Glade found it at, so it runs even
  /// when Terminal’s shell doesn’t look in the same places.
  static func runnable(_ command: String, path: String?) -> String {
    var words = command.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    guard let path, !words.isEmpty, (path as NSString).lastPathComponent == words[0] else { return command }
    words[0] = quoted(path)
    return words.joined(separator: " ")
  }

  private static func quoted(_ text: String) -> String {
    "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }
}
