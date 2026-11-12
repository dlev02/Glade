import Foundation

/// Turns the names processes give their requests to stay awake into a few plain words.
/// The raw names ("Electron", "com.apple.audio.…preventuseridlesleep") stay available
/// for the technical view.
public enum AwakeReasons {
  /// What a request is for, in a few words: "Playing sound", "Running caffeinate".
  public static func describe(_ assertion: SleepAssertion) -> String {
    let name = assertion.name.lowercased()
    let process = assertion.processName.lowercased()
    let resources = Set(assertion.resources.map { $0.lowercased() })

    if resources.contains("audio-in") { return "Using the microphone" }
    if resources.contains("audio-out") || process == "coreaudiod" || name.contains("com.apple.audio") { return "Playing sound" }
    if process == "caffeinate" || name.contains("caffeinate") { return "Running caffeinate" }
    if name.contains("video") || name.contains("playback") || name.contains("movie") { return "Playing video" }
    if name.contains("call") || name.contains("facetime") || name.contains("webrtc") || name.contains("meeting") { return "On a call" }
    if name.contains("download") || name.contains("nsurlsession") { return "Downloading" }
    if name.contains("upload") { return "Uploading" }
    if name.contains("backup") || process == "backupd" { return "Backing up" }
    if name.contains("export") || name.contains("render") || name.contains("encode") { return "Exporting" }
    if name.contains("airplay") || name.contains("screen sharing") || name.contains("screensharing") { return "Sharing the screen" }
    if name.contains("handoff") { return "Handing off to another device" }
    if name.contains("sync") { return "Syncing" }
    if name.contains("build") || name.contains("xcodebuild") || name.contains("compile") { return "Building" }
    if name.contains("install") || name.contains("update") { return "Installing an update" }
    if let detail = assertion.detail?.trimmingCharacters(in: .whitespaces), !detail.isEmpty, detail.count <= 40,
      !detail.contains("."), detail.first?.isUppercase == true
    {
      return detail
    }
    // A short, readable name an app chose ("Printing") says more than a generic phrase.
    let raw = assertion.name.trimmingCharacters(in: .whitespaces)
    if raw.count <= 32, raw.first?.isUppercase == true, raw.contains(" "), !raw.contains("."), !raw.contains("_") {
      return raw
    }
    return assertion.holdsDisplay ? "Keeping the screen on" : "Asked to stay awake"
  }

  static func isGeneric(_ reason: String) -> Bool {
    reason == "Asked to stay awake" || reason == "Keeping the screen on"
  }

  /// "Keeps the screen on" or "Keeps the Mac awake", to start a sentence.
  public static func scope(display: Bool) -> String {
    display ? "Keeps the screen on" : "Keeps the Mac awake"
  }
}
