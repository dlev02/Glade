import Foundation
import GladeKit

/// Made-up storage findings and real system readings, for rendering screens without
/// scanning, and for screenshots that don't show anyone's own files.
public struct SampleData: Sendable {
  public var snapshot: SystemSnapshot
  public var history: [SystemSnapshot]
  public var apps: [AppUsage]
  public var context: ActivityContext?
  public var suggestions: [PerformanceSuggestion]
  public var scan: ScanResult
  public var receipts: [Receipt]
  public var providers: [ProviderStatus]
  public var messages: [AppModel.Message]

  /// Reads the Mac's live figures and pairs them with invented storage findings.
  public static func capture() async -> SampleData {
    let sampler = SystemSampler()
    _ = await sampler.snapshot()
    var history: [SystemSnapshot] = []
    for _ in 0..<3 {
      try? await Task.sleep(for: .milliseconds(250))
      history.append(await sampler.snapshot())
    }
    let latest = history[history.count - 1]
    // Stretch the few real readings into a believable two minutes of history.
    var series: [SystemSnapshot] = []
    for step in 0..<60 {
      var reading = latest
      let wave = sin(Double(step) / 6) * 14 + sin(Double(step) / 2.3) * 6
      reading.cpu.totalPercent = max(3, min(100, latest.cpu.totalPercent + wave))
      reading.gpu?.utilizationPercent = max(1, min(100, (latest.gpu?.utilizationPercent ?? 20) + wave * 0.8))
      reading.memory.usedBytes = latest.memory.usedBytes + Int64(wave * 30_000_000)
      reading.date = latest.date.addingTimeInterval(Double(step - 59) * 2)
      series.append(reading)
    }
    let apps = await sampler.apps()
    let context = ActivityContext.current(apps: apps, power: latest.power)
    let config = GladeConfig()
    return SampleData(
      snapshot: latest, history: series, apps: apps, context: context,
      suggestions: PerformanceAdvisor.suggestions(snapshot: latest, apps: apps, context: context, config: config),
      scan: sampleScan(volume: latest.disk), receipts: sampleReceipts(), providers: sampleProviders(),
      messages: [
        AppModel.Message(role: .person, text: "Why is my Mac slow?"),
        AppModel.Message(role: .assistant, text: formattedAnswer(snapshot: latest, apps: apps), provider: "claude"),
      ]
    )
  }

  /// An idle simulator with a doubt worth seeing, and an idle app: the two kinds of
  /// suggestion people meet most. The app is the largest real one running, so its icon
  /// draws; acting on either in demo mode changes nothing.
  public static func sampleSuggestions(apps: [AppUsage]) -> [PerformanceSuggestion] {
    var entries: [[String: Any]] = [[
      "id": "shutDownIdleSimulator:simulator:sample", "kind": "shutDownIdleSimulator", "appID": "simulator:sample",
      "appName": "iPad Pro 13-inch (M5)", "title": "Shut down iPad Pro 13-inch (M5)",
      "reason": "iPad Pro 13-inch (M5) · iOS 27.2 has been idle since it started 31 hours ago and is using 10.3 GB. Bitrig is open and may be showing it; Glade can’t tell which simulator Bitrig shows.",
      "frees": ["memoryBytes": 10_300_000_000, "cpuPercent": 0.2], "confidence": "low", "actionable": true,
      "simulatorUDID": "sample", "facts": "Idle 31 h · 10.3 GB", "caveat": "May be in use by Bitrig",
    ]]
    let candidates = apps.filter { $0.kind == .app && !$0.isSystem && !$0.isGlade && !$0.isFrontmost }
    if let app = candidates.max(by: { $0.memoryBytes < $1.memoryBytes }) {
      let bytes = max(app.memoryBytes, 1_200_000_000)
      entries.append([
        "id": "quitIdleApp:\(app.id)", "kind": "quitIdleApp", "appID": app.id, "appName": app.name,
        "title": "Quit \(app.name)",
        "reason": "\(app.name) is using \(Format.bytes(bytes)) and hasn’t been used for 3 hours.",
        "frees": ["memoryBytes": bytes, "cpuPercent": 0.4], "confidence": "high", "actionable": true,
        "facts": "Idle 3 h · \(Format.bytes(bytes))",
      ])
    }
    // The engine's initialiser isn't public, so build them the way they arrive from disk.
    guard let data = try? JSONSerialization.data(withJSONObject: entries) else { return [] }
    return (try? JSONDecoder().decode([PerformanceSuggestion].self, from: data)) ?? []
  }

  /// Advice as a storage run returns it, after Glade's checks: additions, things left
  /// alone, personal items to look at and suggestions refused.
  /// - Parameter short: A one-line answer instead of a four-line one.
  public static func sampleAdvice(scan: ScanResult, short: Bool = false) -> StorageAdvice? {
    func id(_ prefix: String) -> String { scan.findings.first { $0.title.hasPrefix(prefix) }?.id ?? prefix }
    func note(_ prefix: String, _ why: String) -> [String: String] { ["id": id(prefix), "why": why] }
    // `{total}` becomes what the clean bar shows once the advice is applied.
    let summary = short
      ? "I’d add the older speech model, which MacWhisper no longer loads, and leave Atlas alone, since you built it this morning."
      : "I’d clear about **{total}**: build data for projects you haven’t opened in over a month, an iOS 18 simulator system nothing uses, an older speech model, old package downloads and agent sessions from the summer. I left Harbor’s build data alone because you built it this week, and kept the npm cache because you installed packages yesterday. Your CleanShot history, a second copy of a holiday video and an old film are worth a look yourself if you want more space."
    // Only what the rules didn't already tick is added, and only what they ticked is
    // left alone, so every chip changes the selection.
    let added = note("Speech models", "MacWhisper now uses a newer model; this one hasn’t loaded in three weeks.")
    let object: [String: Any] = [
      "summary": summary,
      "select": short ? [added] : [
        added,
        note("Codex sessions", "Untouched since August."),
        note("Homebrew downloads", "Installers already unpacked."),
      ],
      "deselect": short ? [] : [note("Build data – Harbor", "Built two days ago."), note("npm cache", "Packages installed yesterday.")],
      "review": short ? [] : [note("CleanShot", "Mostly old recordings."), note("Sintel", "Not opened in ten months."), note("holiday-2025", "A second copy.")],
      "rejected": short ? [] : [note("Worktree – Harbor", "It has 3 uncommitted files, so only you can remove it.")],
      "provider": "claude",
      "model": "opus",
      "escalated": false,
      "runID": "sample",
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
    return try? JSONDecoder().decode(StorageAdvice.self, from: data)
  }

  /// A written answer with the formatting AIs use, for showing how answers render.
  /// Its figures come from the sample's own readings, so it agrees with Performance.
  public static func formattedAnswer(snapshot: SystemSnapshot?, apps: [AppUsage]) -> String {
    let hog = apps.first { $0.name == "Docker" }
      ?? apps.filter { $0.kind == .app && !$0.isSystem && !$0.isGlade && !$0.isFrontmost }.max { $0.memoryBytes < $1.memoryBytes }
    let first = hog.map { "**\($0.name)** is holding **\(Format.bytes($0.memoryBytes))** of memory\($0.name == "Docker" ? " with no containers running" : " and hasn’t been used for hours")." }
      ?? "**An idle app** is holding memory it doesn’t need."
    let advice = hog.map { "Quit \($0.name) until you need it; it starts again in a few seconds." }
      ?? "Quit apps you aren’t using; they start again in a few seconds."
    let memory = snapshot?.memory
    let used = memory.map { "Memory used   \(Format.bytes($0.usedBytes)) of \(Format.bytes($0.totalBytes))" } ?? "Memory used   —"
    let pressure = (memory?.pressure ?? .normal).title.lowercased()
    return """
      Your Mac is busy mostly because of **two things**:

      1. \(first)
      2. An **iPad Pro simulator** has been idle for 31 hours and uses *10.3 GB*.

      ### What I'd do
      - \(advice)
      - Shut down the simulator with `xcrun simctl shutdown all`, or from Performance.

      Memory pressure is **\(pressure)**, so nothing is urgent:

      ```
      \(used)
      ```
      """
  }

  static func sampleProviders() -> [ProviderStatus] {
    [
      ProviderStatus(id: "claude", name: "Claude Code", state: .ready, path: "/usr/local/bin/claude", version: "2.1", supportsEffort: true, models: ["haiku", "sonnet", "opus", "fable"]),
      ProviderStatus(id: "codex", name: "Codex", state: .ready, path: "/opt/homebrew/bin/codex", version: "0.167", supportsEffort: true, models: ["gpt-6.1-sol", "gpt-6-luna"]),
      ProviderStatus(id: "apple", name: "Apple Intelligence", state: .ready, isLocal: true),
      ProviderStatus(id: "apple-cloud", name: "Apple Private Cloud Compute", state: .unavailable(reason: "Only for apps from the App Store")),
      ProviderStatus(id: "gemini", name: "Gemini", state: .needsSignIn(hint: "Run `gemini` in Terminal and sign in."), verified: false),
      ProviderStatus(id: "cursor", name: "Cursor", state: .notInstalled, verified: false),
    ]
  }

  /// When the sample cleans are dated from: fixed for the whole run, so every place
  /// that shows a sample clean's time agrees.
  private static let receiptsAnchor = Date()

  static func sampleReceipts() -> [Receipt] {
    let day: TimeInterval = 86_400
    let now = receiptsAnchor
    func entry(_ title: String, _ category: StorageCategory, _ gigabytes: Double, _ outcome: RemovalOutcome) -> ReceiptEntry {
      ReceiptEntry(id: UUID().uuidString, title: title, category: category, paths: [], bytes: Int64(gigabytes * 1e9), outcome: outcome)
    }
    return [
      Receipt(
        id: "A1B2C3D4-0000-0000-0000-000000000001", date: now.addingTimeInterval(-3600 * 5), initiator: .user, dryRun: false,
        entries: [
          entry("Build data – Lantern", .xcode, 18.4, .deleted),
          entry("npm cache", .packageCaches, 4.2, .deleted),
          entry("Old installer – Figma.dmg", .downloads, 0.4, .trashed(locations: ["~/Downloads/Figma.dmg": "~/.Trash/Figma.dmg"])),
          entry("Simulator logs", .logs, 0.5, .deleted),
        ],
        freeBefore: 9_600_000_000, freeAfter: 32_700_000_000
      ),
      Receipt(
        id: "A1B2C3D4-0000-0000-0000-000000000002", date: now.addingTimeInterval(-day * 3), initiator: .assistant(provider: "Claude"), dryRun: false,
        entries: [
          entry("Simulator system · iOS 18.0", .simulators, 8.4, .deleted),
          entry("Claude Code sessions – Developer-Harbor", .agentHistory, 1.1, .deleted),
          entry("uv cache", .packageCaches, 9.8, .deleted),
        ],
        freeBefore: 4_100_000_000, freeAfter: 23_400_000_000
      ),
      Receipt(
        id: "A1B2C3D4-0000-0000-0000-000000000003", date: now.addingTimeInterval(-day * 9), initiator: .automation(rule: "low storage"), dryRun: false,
        entries: [entry("App caches", .appCaches, 2.3, .deleted), entry("Crash reports", .logs, 0.1, .deleted)],
        freeBefore: 18_900_000_000, freeAfter: 21_300_000_000
      ),
    ]
  }

  static func sampleScan(volume: VolumeInfo) -> ScanResult {
    let day: TimeInterval = 86_400
    let home = NSHomeDirectory()
    var findings: [Finding] = []
    func add(
      _ title: String, _ category: StorageCategory, _ gigabytes: Double, daysAgo: Double, _ recovery: Recovery, _ risk: Risk,
      _ auto: CleanLevel?, idle: Int = 0, path: String, detail: String, blocked: Blocker? = nil, method: RemovalMethod = .delete,
      evidence: [String] = [], project: String? = nil
    ) {
      findings.append(Finding(
        id: Finding.makeID(rule: "sample", path: path), ruleID: "sample", category: category, title: title, detail: detail,
        paths: [home + "/" + path], bytes: Int64(gigabytes * 1e9), fileCount: Int(gigabytes * 4200),
        lastUsed: Date().addingTimeInterval(-daysAgo * day), recovery: recovery, risk: risk,
        blockers: blocked.map { [$0] } ?? [], method: method,
        evidence: evidence.isEmpty ? ["Used \(Format.age(Date().addingTimeInterval(-daysAgo * day)))."] : evidence,
        project: project, autoLevel: auto, idleDaysRequired: idle
      ))
    }
    let build = "Xcode's build products and indexes for one project. Rebuilt the next time you build it."
    add("Build data – Lantern", .xcode, 31.2, daysAgo: 41, .automatic, .safe, .careful, idle: 3, path: "Library/Developer/Xcode/DerivedData/Lantern-a", detail: build)
    add("Build data – Atlas", .xcode, 12.6, daysAgo: 0.2, .automatic, .safe, .careful, idle: 3, path: "Library/Developer/Xcode/DerivedData/Atlas-b", detail: build)
    add("Build data – Harbor", .xcode, 6.8, daysAgo: 2, .automatic, .safe, .careful, idle: 3, path: "Library/Developer/Xcode/DerivedData/Harbor-c", detail: build)
    add("Build data – Pocket Notes", .xcode, 3.1, daysAgo: 96, .automatic, .safe, .careful, idle: 3, path: "Library/Developer/Xcode/DerivedData/PocketNotes-d", detail: build)
    add("Archive – Lantern 2.3", .xcode, 2.4, daysAgo: 120, .permanent, .caution, nil, path: "Library/Developer/Xcode/Archives/2026-07-12/Lantern.xcarchive", detail: "A build you archived for release. Needed to symbolicate crashes from that version; nothing recreates it.", method: .trash)
    add("Simulator system · iOS 18.0", .simulators, 8.4, daysAgo: 210, .redownload, .caution, .balanced, path: "sim/ios18", detail: "A downloaded simulator system version that none of your simulators use. Xcode offers to download it again if you ever add one.", method: .simulatorRuntime(identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-0"), evidence: ["No simulator uses this version.", "Never used since it was installed."])
    add("iPhone 17 Pro · iOS 27.2", .simulators, 8.8, daysAgo: 1, .reinstall, .caution, .balanced, idle: 14, path: "Library/Developer/CoreSimulator/Devices/A", detail: "Apps and data inside this simulator. Erasing it keeps the simulator and returns it to a fresh state.", method: .simulatorErase(udid: "A"))
    add("iPad Air 11-inch · iOS 27.2", .simulators, 6.5, daysAgo: 38, .reinstall, .caution, .balanced, idle: 14, path: "Library/Developer/CoreSimulator/Devices/B", detail: "Apps and data inside this simulator. Erasing it keeps the simulator and returns it to a fresh state.", method: .simulatorErase(udid: "B"))
    add("Test simulators", .simulators, 25.1, daysAgo: 6, .automatic, .safe, .careful, idle: 3, path: "Library/Developer/XCTestDevices", detail: "Copies of simulators Xcode makes to run tests in parallel. Xcode makes fresh ones the next time tests run.", method: .simulatorSet(name: "testing"))
    add("Worktree – Lantern / fix-sync-crash", .agentWorktrees, 4.6, daysAgo: 33, .reinstall, .caution, .balanced, idle: 14, path: "Developer/Lantern/.claude/worktrees/fix-sync", detail: "An extra working copy an agent made. Its branch and commits stay in the repository.", method: .gitWorktree(repository: home + "/Developer/Lantern"), evidence: ["Branch fix-sync-crash, merged into main.", "Nothing uncommitted."], project: "Lantern")
    add("Worktree – Harbor / onboarding-redesign", .agentWorktrees, 3.9, daysAgo: 4, .reinstall, .caution, nil, path: "Developer/Harbor/.claude/worktrees/onboarding", detail: "An extra working copy an agent made. Its branch and commits stay in the repository.", blocked: Blocker(.uncommittedWork, "3 uncommitted files"), method: .gitWorktree(repository: home + "/Developer/Harbor"), project: "Harbor")
    add("Worktree – Atlas / t3-9e10", .agentWorktrees, 1.8, daysAgo: 52, .reinstall, .caution, .balanced, idle: 14, path: ".t3/worktrees/atlas/t3-9e10", detail: "An extra working copy an agent made. Its branch and commits stay in the repository.", method: .gitWorktree(repository: home + "/Developer/Atlas"), project: "Atlas")
    add("Claude Code sessions – Developer-Lantern", .agentHistory, 2.2, daysAgo: 22, .permanent, .caution, .balanced, path: ".claude/projects/lantern", detail: "Conversation transcripts from Claude Code sessions in this folder. Removing them means those sessions can no longer be resumed; your memory and skills are untouched.", evidence: ["184 sessions untouched for 14 days or more.", "12 recent sessions are kept."])
    add("Codex sessions – 2026-08", .agentHistory, 0.9, daysAgo: 74, .permanent, .caution, .balanced, idle: 90, path: ".codex/sessions/2026/08", detail: "Conversation transcripts from Codex sessions. Removing them means those sessions can no longer be resumed.")
    add("node_modules – harbor-web", .projectDependencies, 1.4, daysAgo: 47, .reinstall, .safe, .balanced, idle: 14, path: "Developer/harbor-web/node_modules", detail: "Packages this project installed. `npm install` brings them back.", project: "harbor-web")
    add("build – Atlas", .buildOutputs, 2.9, daysAgo: 0.3, .automatic, .safe, .balanced, idle: 14, path: "Developer/Atlas/build", detail: "This project's build folder. Rebuilt the next time you build.", project: "Atlas")
    add("uv cache", .packageCaches, 9.8, daysAgo: 3, .redownload, .safe, .balanced, path: ".cache/uv", detail: "Python packages and builds uv has cached. It fetches them again when needed.")
    add("npm cache", .packageCaches, 4.2, daysAgo: 1, .redownload, .safe, .balanced, path: ".npm/_cacache", detail: "Packages npm has downloaded. It fetches them again on the next install.")
    add("Homebrew downloads", .packageCaches, 1.3, daysAgo: 18, .redownload, .safe, .balanced, idle: 30, path: "Library/Caches/Homebrew", detail: "Installers Homebrew already unpacked. It downloads them again if you reinstall.")
    add("Speech models – large-v3", .aiModels, 3.1, daysAgo: 21, .redownload, .caution, .balanced, idle: 30, path: ".whisper-models/large-v3.bin", detail: "Transcription models downloaded by MacWhisper and similar apps. The app downloads them again when you pick that model.")
    add("Ollama models", .aiModels, 14.7, daysAgo: 5, .redownload, .caution, .balanced, idle: 30, path: ".ollama/models", detail: "Language models pulled with Ollama. `ollama pull` downloads them again.")
    add("Slack cache", .appCaches, 0.9, daysAgo: 9, .automatic, .safe, .careful, path: "Library/Application Support/Slack/Cache", detail: "Files this app saved to load faster. It rebuilds them as you use it.")
    add("Spotify cache", .appCaches, 1.6, daysAgo: 0, .automatic, .safe, .careful, path: "Library/Caches/com.spotify.client", detail: "Files this app saved to load faster. It rebuilds them as you use it.", blocked: Blocker(.appRunning, "Spotify is open."))
    add("Node 22.4 – mise", .sdks, 0.2, daysAgo: 0, .redownload, .caution, .balanced, path: ".local/share/mise/installs/node/22.4.0", detail: "A version of Node that mise installed. `mise install` downloads it again.", blocked: Blocker(.inUse, "node is running from here."))
    add("Simulator logs", .logs, 0.5, daysAgo: 12, .automatic, .safe, .careful, path: "Library/Logs/CoreSimulator", detail: "Logs from iOS simulators. New ones are written when a simulator runs.")
    add("Superseded extensions – Visual Studio Code", .editorExtensions, 1.4, daysAgo: 30, .automatic, .safe, .careful, path: ".vscode/extensions", detail: "Older versions of extensions the editor no longer loads.")
    add("Sintel (2010).mkv", .largeFiles, 1.2, daysAgo: 300, .permanent, .personal, nil, path: "Movies/Samples/Sintel (2010).mkv", detail: "A large file you haven't opened in a long time.", method: .trash)
    add("CleanShot capture history", .largeFiles, 21.9, daysAgo: 45, .permanent, .personal, nil, path: "Library/Application Support/CleanShot/media", detail: "Screenshots and recordings CleanShot keeps in its history, older than 30 days. Captures you saved or exported elsewhere are separate files and stay.", method: .trash)
    add("Figma.dmg", .downloads, 0.4, daysAgo: 88, .redownload, .caution, .balanced, idle: 14, path: "Downloads/Figma.dmg", detail: "An installer for an app that's already installed.", method: .trash, evidence: ["Figma is installed (126.2); this installer was last opened 3 months ago."])
    add("Hades II", .games, 9.6, daysAgo: 140, .redownload, .caution, nil, path: "Library/Application Support/Steam/steamapps/common/Hades II", detail: "An installed Steam game. Steam downloads it again from your library; cloud saves depend on the game.", method: .trash)
    add("holiday-2025.mov – 2 copies", .duplicates, 2.3, daysAgo: 200, .permanent, .personal, nil, path: "Downloads/holiday-2025 copy.mov", detail: "An identical copy of a file kept elsewhere. The other copy stays.", method: .trash)

    findings.sort { $0.bytes > $1.bytes }
    return ScanResult(
      started: Date().addingTimeInterval(-600), finished: Date().addingTimeInterval(-560), volume: volume,
      findings: findings, skipped: [], timings: [:], hasFullDiskAccess: true
    )
  }
}
