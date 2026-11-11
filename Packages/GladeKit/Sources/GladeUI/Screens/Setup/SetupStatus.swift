import GladeKit

/// Where each setup step stands. Setup reads it live from the model and the system;
/// snapshots pass a fixed one in.
struct SetupStatus {
  var fullDiskAccess: Bool
  var notifications: Bool
  var providers: [ProviderStatus]
  var opensAtLogin: Bool
  var commandLine: CommandLineTool.Status

  /// Every step done, for drawing the finished checklist.
  static func allDone(providers: [ProviderStatus]) -> SetupStatus {
    SetupStatus(
      fullDiskAccess: true, notifications: true, providers: providers, opensAtLogin: true,
      commandLine: .installed(path: "~/.local/bin/glade", onPath: true)
    )
  }

  /// Nothing done yet, as on a Mac that has just installed Glade.
  static let nothingDone = SetupStatus(
    fullDiskAccess: false, notifications: false,
    providers: [
      ProviderStatus(id: "claude", name: "Claude Code", state: .needsSignIn(hint: "Run `claude` in Terminal and sign in.")),
      ProviderStatus(id: "codex", name: "Codex", state: .notInstalled),
      ProviderStatus(id: "apple", name: "Apple Intelligence", state: .unavailable(reason: "Turn on Apple Intelligence in System Settings."), isLocal: true),
    ],
    opensAtLogin: false, commandLine: .notInstalled
  )
}
