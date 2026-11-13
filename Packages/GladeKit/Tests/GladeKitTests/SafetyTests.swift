import Foundation
import Testing
@testable import GladeKit

/// The one automated test in the project, because this is the code that can lose
/// data: the safety policy and the cleaner, run against a fake home folder full of
/// things that must survive.
@Suite(.serialized)
struct SafetyTests {
  let home: String
  let outside: String
  let protection: Protection

  init() throws {
    let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path + "/glade-safety-\(UUID().uuidString.prefix(8))"
    home = base + "/home"
    // Receipts and logs from these tests belong with the fixture, not in the real History.
    GladePaths.supportOverride = URL(fileURLWithPath: base + "/support", isDirectory: true)
    outside = base + "/outside"
    let files = [
      "Library/Caches/com.example.app/data.bin",
      "Library/Caches/com.example.withlibrary/Old.photoslibrary/originals/a.jpg",
      "Library/Developer/Xcode/DerivedData/App-abcdefghijklmnopqrstuvwxyzab/Build/x.o",
      ".ssh/id_ed25519",
      ".claude/projects/-Users-me-App/memory/MEMORY.md",
      ".claude/projects/-Users-me-App/session.jsonl",
      "Documents/report.txt",
      "Downloads/old-installer.dmg",
      "Library/Mobile Documents/com~apple~CloudDocs/thesis.pages",
      "proj/.git/HEAD",
      "proj/.env",
      "proj/node_modules/pkg/index.js",
      "proj/src/main.swift",
    ]
    for file in files {
      let path = home + "/" + file
      try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
      try Data(repeating: 7, count: 4096).write(to: URL(fileURLWithPath: path))
    }
    try FileManager.default.createDirectory(atPath: outside + "/victim", withIntermediateDirectories: true)
    try Data("keep".utf8).write(to: URL(fileURLWithPath: outside + "/victim/file.txt"))
    // A cache entry that is really a link to Documents, and a cache folder that is a link out of home.
    try FileManager.default.createSymbolicLink(atPath: home + "/Library/Caches/link-to-documents", withDestinationPath: home + "/Documents")
    try FileManager.default.createSymbolicLink(atPath: home + "/Library/Caches/escape", withDestinationPath: outside)
    protection = Protection(config: GladeConfig(), home: home, extraScopes: [])
  }

  private func exists(_ relative: String) -> Bool {
    FileManager.default.fileExists(atPath: home + "/" + relative)
  }

  private func finding(_ id: String, _ path: String, method: RemovalMethod = .delete, risk: Risk = .safe, contentsOnly: Bool = false) -> Finding {
    Finding(
      id: id, ruleID: "test", category: .appCaches, title: id, detail: "", paths: [path], contentsOnly: contentsOnly,
      bytes: 4096, recovery: .automatic, risk: risk, method: method, autoLevel: .careful
    )
  }

  private func scan(_ findings: [Finding]) -> ScanResult {
    ScanResult(started: Date(), finished: Date(), volume: .current(), findings: findings, skipped: [], timings: [:], hasFullDiskAccess: false)
  }

  @Test func verdictsRefuseEverythingThatMustSurvive() {
    let refused = [
      "", ".ssh", ".ssh/id_ed25519", "Documents", "Downloads", "Library", "Library/Caches",
      "Library/Application Support", ".claude/projects/-Users-me-App", ".claude/projects/-Users-me-App/memory",
      ".claude/projects/-Users-me-App/memory/MEMORY.md", "Library/Mobile Documents/com~apple~CloudDocs/thesis.pages",
      "proj", "proj/.git", "proj/.git/HEAD", "proj/.env", "Library/Caches/escape/victim",
      "Library/Caches/com.example.withlibrary/Old.photoslibrary", "Library/Caches/com.example.withlibrary/Old.photoslibrary/originals/a.jpg",
      "Library/Keychains/login.keychain-db", "Library/Messages/chat.db", "Pictures/Photos Library.photoslibrary",
      // Security agents: touching their files sets off tamper alarms.
      "Library/Caches/com.crowdstrike.falcon", "Library/Group Containers/X9E956P446.com.crowdstrike.falcon/data",
      "Library/Application Support/com.jamf.connect/state", "Library/Caches/com.cisco.secureclient.gui",
    ]
    for relative in refused {
      let path = relative.isEmpty ? home : home + "/" + relative
      #expect(!protection.verdict(forRemoving: path).isAllowed, "must refuse \(relative)")
    }
    for path in ["/", "/etc/hosts", "/Applications/Safari.app", "/Users", outside + "/victim", home + "/../outside/victim", "relative/path", "/System/Library"] {
      #expect(!protection.verdict(forRemoving: path).isAllowed, "must refuse \(path)")
    }
    let allowed = [
      "Library/Caches/com.example.app", "Library/Developer/Xcode/DerivedData/App-abcdefghijklmnopqrstuvwxyzab",
      "proj/node_modules", "Downloads/old-installer.dmg", ".claude/projects/-Users-me-App/session.jsonl",
      "Library/Caches/link-to-documents",
    ]
    for relative in allowed {
      #expect(protection.verdict(forRemoving: home + "/" + relative).isAllowed, "should allow \(relative)")
    }
    for hidden in [".ssh", "proj/.git", "proj/.env", "Library/Mobile Documents", ".claude/projects/-Users-me-App/memory", "Library/Caches/com.sentinelone.agent"] {
      #expect(!protection.canScan(home + "/" + hidden), "scans must not see \(hidden)")
    }
  }

  @Test func cleanerRemovesOnlyWhatIsAllowed() async throws {
    let good = [
      finding("cache", home + "/Library/Caches/com.example.app"),
      finding("derived", home + "/Library/Developer/Xcode/DerivedData/App-abcdefghijklmnopqrstuvwxyzab"),
      finding("modules", home + "/proj/node_modules"),
      finding("link", home + "/Library/Caches/link-to-documents"),
      finding("session", home + "/.claude/projects/-Users-me-App/session.jsonl"),
    ]
    // Findings a buggy scanner or a tampered scan file might contain.
    let hostile = [
      finding("ssh", home + "/.ssh"),
      finding("documents", home + "/Documents"),
      finding("repo", home + "/proj"),
      finding("git", home + "/proj/.git"),
      finding("env", home + "/proj/.env"),
      finding("memory", home + "/.claude/projects/-Users-me-App"),
      finding("cloud", home + "/Library/Mobile Documents/com~apple~CloudDocs"),
      finding("escape", home + "/Library/Caches/escape/victim"),
      finding("outside", outside + "/victim"),
      finding("system", "/etc/hosts"),
      finding("dotdot", home + "/Library/Caches/../../../outside/victim"),
      finding("library", home + "/Library/Caches/com.example.withlibrary/Old.photoslibrary"),
      finding("home-contents", home, contentsOnly: true),
      finding("library-contents", home + "/Library", contentsOnly: true),
    ]
    let result = scan(good + hostile)
    let receipt = try await Cleaner.clean(
      ids: result.findings.map(\.id) + ["not-a-real-id"], from: result, config: GladeConfig(),
      options: CleanOptions(dryRun: false, initiator: .commandLine), protection: protection, running: RunningApps()
    )

    for entry in receipt.entries where good.contains(where: { $0.id == entry.id }) {
      #expect(entry.outcome == .deleted, "\(entry.id) should be deleted, got \(entry.outcome)")
    }
    for entry in receipt.entries where hostile.contains(where: { $0.id == entry.id }) || entry.id == "not-a-real-id" {
      if case .skipped = entry.outcome { continue }
      Issue.record("\(entry.id) must be refused, got \(entry.outcome)")
    }
    #expect(!exists("Library/Caches/com.example.app"))
    #expect(!exists("proj/node_modules"))
    #expect(!exists(".claude/projects/-Users-me-App/session.jsonl"))
    // Removing the link removed only the link.
    #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: home + "/Library/Caches/link-to-documents")) == nil)
    for survivor in [
      ".ssh/id_ed25519", "Documents/report.txt", "proj/.git/HEAD", "proj/.env", "proj/src/main.swift",
      ".claude/projects/-Users-me-App/memory/MEMORY.md", "Library/Mobile Documents/com~apple~CloudDocs/thesis.pages",
      "Library/Caches/com.example.withlibrary/Old.photoslibrary/originals/a.jpg", "Downloads/old-installer.dmg",
    ] {
      #expect(exists(survivor), "\(survivor) must survive")
    }
    #expect(FileManager.default.fileExists(atPath: outside + "/victim/file.txt"))
    #expect(FileManager.default.fileExists(atPath: "/etc/hosts"))
  }

  @Test func dryRunChangesNothingAndPersonalFilesGoToTrash() async throws {
    let installer = finding("installer", home + "/Downloads/old-installer.dmg", method: .delete, risk: .personal)
    let result = scan([installer])
    let dry = try await Cleaner.clean(ids: ["installer"], from: result, config: GladeConfig(), options: CleanOptions(dryRun: true), protection: protection, running: RunningApps())
    #expect(dry.entries.first?.outcome == .wouldRemove)
    #expect(exists("Downloads/old-installer.dmg"))

    // Even though the finding says "delete", a personal file must go to the Trash.
    let real = try await Cleaner.clean(ids: ["installer"], from: result, config: GladeConfig(), options: CleanOptions(dryRun: false), protection: protection, running: RunningApps())
    guard case .trashed(let locations) = real.entries.first?.outcome else {
      Issue.record("personal file should be trashed, got \(String(describing: real.entries.first?.outcome))")
      return
    }
    #expect(!exists("Downloads/old-installer.dmg"))
    let restored = Cleaner.restore(real)
    #expect(restored.restored.count == 1)
    #expect(exists("Downloads/old-installer.dmg"))
    for trashed in locations.values { try? FileManager.default.removeItem(atPath: trashed) }
  }

  @Test func cleanerKeepsWhatIsInUse() async throws {
    let support = home + "/Library/Application Support"
    for folder in ["LiveApp/Cache", "StaleApp/Cache", "MovedApp/Cache"] {
      try FileManager.default.createDirectory(atPath: support + "/" + folder, withIntermediateDirectories: true)
      try Data(repeating: 1, count: 4096).write(to: URL(fileURLWithPath: support + "/" + folder + "/data_0"))
    }
    // An open Chromium-style app, one that has quit, and one whose lock came from another Mac.
    try FileManager.default.createSymbolicLink(atPath: support + "/LiveApp/SingletonLock", withDestinationPath: "\(InUse.hostName)-\(getpid())")
    try FileManager.default.createSymbolicLink(atPath: support + "/StaleApp/SingletonLock", withDestinationPath: "\(InUse.hostName)-0")
    try FileManager.default.createSymbolicLink(atPath: support + "/MovedApp/SingletonLock", withDestinationPath: "Another-Mac.local-\(getpid())")
    // A toolkit version a program is running from.
    let toolkit = home + "/.toolkit/versions/1.0"
    try FileManager.default.createDirectory(atPath: toolkit + "/bin", withIntermediateDirectories: true)
    try Data(repeating: 2, count: 4096).write(to: URL(fileURLWithPath: toolkit + "/bin/tool"))

    let findings = [
      finding("live", support + "/LiveApp/Cache"), finding("stale", support + "/StaleApp/Cache"),
      finding("moved", support + "/MovedApp/Cache"), finding("toolkit", toolkit),
    ]
    let running = RunningApps(executablePaths: [toolkit + "/bin/tool"])
    let receipt = try await Cleaner.clean(
      ids: findings.map(\.id), from: scan(findings), config: GladeConfig(),
      options: CleanOptions(dryRun: false), protection: protection, running: running
    )
    let outcomes = Dictionary(uniqueKeysWithValues: receipt.entries.map { ($0.id, $0.outcome) })
    for kept in ["live", "toolkit"] {
      guard case .skipped = outcomes[kept] else {
        Issue.record("\(kept) is in use and must be kept, got \(String(describing: outcomes[kept]))")
        continue
      }
    }
    #expect(outcomes["stale"] == .deleted)
    #expect(outcomes["moved"] == .deleted)
    #expect(FileManager.default.fileExists(atPath: support + "/LiveApp/Cache/data_0"))
    #expect(FileManager.default.fileExists(atPath: toolkit + "/bin/tool"))
  }

  /// One test simulator is deleted only when the finding names that clone’s own folder
  /// and Xcode’s current list says it exists, belongs to that set and is shut down.
  @Test func testSimulatorClonesAreRemovedOneAtATimeAndOnlyWhenIdle() async throws {
    let set = home + "/Library/Developer/XCTestDevices"
    let idle = "11111111-1111-4111-8111-111111111111", booted = "22222222-2222-4222-8222-222222222222"
    let foreign = "33333333-3333-4333-8333-333333333333", missing = "44444444-4444-4444-8444-444444444444"
    for udid in [idle, booted, foreign, missing] {
      try FileManager.default.createDirectory(atPath: "\(set)/\(udid)/data", withIntermediateDirectories: true)
    }
    let json = """
      {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-27-2": [
        {"udid": "\(idle)", "name": "Clone 1 of iPhone 17", "state": "Shutdown", "dataPath": "\(set)/\(idle)/data"},
        {"udid": "\(booted)", "name": "Clone 2 of iPhone 17", "state": "Booted", "dataPath": "\(set)/\(booted)/data"},
        {"udid": "\(foreign)", "name": "iPhone 17", "state": "Shutdown", "dataPath": "\(home)/Library/Developer/CoreSimulator/Devices/\(foreign)/data"}
      ]}}
      """
    let listing = try JSONDecoder().decode(SimulatorCloneScanner.DeviceList.self, from: Data(json.utf8))
    func clone(_ udid: String, path: String? = nil, set name: String = "testing") -> Finding {
      finding(udid, path ?? "\(set)/\(udid)", method: .simulatorSet(name: name, udid: udid))
    }
    func outcome(_ finding: Finding) async -> RemovalOutcome {
      guard case .simulatorSet(let name, let udid?) = finding.method else { return .failed(reason: "not a clone") }
      return await Cleaner.simulatorClone(
        finding, set: name, udid: udid, protection: protection, running: RunningApps(), dryRun: true, listing: listing
      )
    }

    let idleOutcome = await outcome(clone(idle))
    #expect(idleOutcome == .wouldRemove, "\(idleOutcome)")
    for (label, hostile) in [
      ("booted", clone(booted)), ("other set", clone(foreign)), ("not listed", clone(missing)),
      ("wrong folder", clone(idle, path: home + "/Documents")), ("another clone’s folder", clone(idle, path: "\(set)/\(booted)")),
    ] {
      guard case .skipped = await outcome(hostile) else {
        Issue.record("\(label) must be refused")
        continue
      }
    }
    // Through the cleaner itself, which turns these away before asking simctl anything.
    let unknownSet = clone(idle, set: "standard")
    let notUUID = finding("bad", "\(set)/../../..", method: .simulatorSet(name: "testing", udid: "../../.."))
    let receipt = try await Cleaner.clean(
      ids: [unknownSet.id, notUUID.id], from: scan([unknownSet, notUUID]), config: GladeConfig(),
      options: CleanOptions(dryRun: true), protection: protection, running: RunningApps()
    )
    for entry in receipt.entries {
      guard case .skipped = entry.outcome else {
        Issue.record("\(entry.id) must be refused, got \(entry.outcome)")
        continue
      }
    }
    #expect(receipt.entries.count == 2)
    #expect(SimulatorCloneScanner.deviceName("Clone 12 of iPad Air 11-inch (M4)") == "iPad Air 11-inch (M4)")
    #expect(SimulatorCloneScanner.deviceName("Cloned Phone") == "Cloned Phone")
  }

  /// Agents keep live state in folders named like scratch space. Even long untouched,
  /// the catalog must not offer it.
  @Test func agentStateNamedLikeScratchIsNotOffered() async throws {
    let old = Date().addingTimeInterval(-90 * 86_400)
    let live = [
      ".codex/.tmp/plugins/plugins/tool/manifest.json", ".codex/.tmp/bundled-marketplaces/openai-bundled/index.json",
      ".codex/.tmp/plugins-backup-abc123/manifest.json", ".gemini/antigravity/brain/conv/notes.md",
      ".gemini/antigravity/knowledge/item/overview.md", ".gemini/antigravity/skills/review/SKILL.md",
    ]
    let scratch = [".codex/.tmp/git-Ab12Cd/objects/pack.bin"]
    for file in live + scratch {
      let path = home + "/" + file
      try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
      try Data(repeating: 3, count: 2_000_000).write(to: URL(fileURLWithPath: path))
      try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: path)
    }
    let context = ScanContext(config: GladeConfig(), protection: protection, home: home, running: RunningApps())
    let findings = await CatalogScanner(rules: Catalog.rules.filter { $0.category == .agentHistory }).scan(context)
    let paths = findings.flatMap(\.paths)
    #expect(paths.contains { $0.hasSuffix("/.codex/.tmp/git-Ab12Cd") }, "stale scratch clones should still be found")
    for forbidden in ["/.codex/.tmp/plugins", "/bundled-marketplaces/openai-bundled", "/plugins-backup-", "/.gemini/antigravity"] {
      #expect(!paths.contains { $0.contains(forbidden) }, "offered live agent state \(forbidden)")
    }
    for kept in [".gemini/antigravity/knowledge", ".gemini/antigravity/skills", ".gemini/skills", ".gemini/commands"] {
      #expect(!protection.canScan(home + "/" + kept), "\(kept) is agent memory")
    }
  }

  /// Things that live in cache folders but aren't caches: removing them breaks projects
  /// or loses downloads a person chose. The catalog must never offer them as a cache.
  @Test func catalogDoesNotMistakeLiveDataForCaches() async throws {
    let files = [
      "Library/Caches/pypoetry/virtualenvs/app-x1y2-py3.12/bin/python", "Library/Caches/pypoetry/cache/repositories/pypi/a.json",
      "Library/Caches/deno/location_data/abc/local_storage", "Library/Caches/deno/npm/registry.npmjs.org/pkg/a.tgz",
      "Library/Caches/org.R-project.R/R/renv/cache/v5/pkg/DESCRIPTION", "Library/Caches/llama.cpp/model-Q4_K_M.gguf",
      "Library/Caches/Buzz/models/whisper/ggml-base.bin", ".yarn/berry/cache/left-pad-npm-1.3.0.zip",
      "Library/Bitrig/Simulators/F079E336-669D-43AA-B657-D8CD2E05CDC3/data/a.bin",
    ]
    for file in files {
      let path = home + "/" + file
      try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
      try Data(repeating: 4, count: 6_000_000).write(to: URL(fileURLWithPath: path))
    }
    let context = ScanContext(config: GladeConfig(), protection: protection, home: home, running: RunningApps())
    let findings = await CatalogScanner().scan(context)
    func covering(_ relative: String) -> [Finding] {
      let path = home + "/" + relative
      return findings.filter { $0.paths.contains { path == $0 || path.hasPrefix($0 + "/") } }
    }
    for kept in ["Library/Caches/pypoetry/virtualenvs", "Library/Caches/deno/location_data", "Library/Caches/org.R-project.R"] {
      #expect(covering(kept).isEmpty, "\(kept) must not be offered")
    }
    #expect(!covering("Library/Caches/pypoetry/cache").isEmpty, "Poetry's download cache should still be found")
    #expect(!covering("Library/Caches/deno/npm").isEmpty, "Deno's download cache should still be found")
    for model in ["Library/Caches/llama.cpp", "Library/Caches/Buzz/models/whisper"] {
      for finding in covering(model) {
        #expect(finding.risk != .safe && finding.recovery == .redownload, "\(model) is a downloaded model, offered as \(finding.ruleID)")
      }
    }
    for finding in covering(".yarn/berry/cache") {
      #expect(finding.risk == .caution && finding.recovery == .reinstall, "Yarn's Plug'n'Play packages offered as \(finding.ruleID)")
    }
    // Bitrig manages its own simulators: listed with their size, never selected or removed.
    let bitrig = covering("Library/Bitrig/Simulators")
    #expect(!bitrig.isEmpty, "Bitrig's simulators should be listed")
    for finding in bitrig {
      #expect(finding.isBlocked && finding.autoLevel == nil, "Bitrig's simulators offered as \(finding.ruleID)")
      let plan = Planner.plan(scan: scan([finding]), level: .aggressive, config: GladeConfig())
      #expect(plan.selectedIDs.isEmpty, "Bitrig's simulators selected at Aggressive")
    }
  }

  /// Free Up Memory ticks only confident, undoubted, idle actions, and never shows an
  /// app that is in front, playing, recording, keeping the Mac awake or kept running.
  @Test func freeUpMemoryTicksOnlyWhatIsSafelyIdle() throws {
    let now = Date()
    func app(_ id: String, _ extra: [String: Any] = [:]) throws -> AppUsage {
      var fields: [String: Any] = [
        "id": id, "kind": "app", "name": id, "bundleIdentifier": id, "pids": [1], "cpuPercent": 0.5,
        "memoryBytes": 2_000_000_000, "threadCount": 10, "busiestCPUPercent": 0.5, "isFrontmost": false, "isHidden": false,
        "activationPolicy": "regular", "isPlayingAudio": false, "isCapturingAudio": false, "windowCount": 1,
        "isFullScreen": false, "isGame": false, "isSystem": false, "isGlade": false, "hasRestrictedMembers": false,
      ]
      fields.merge(extra) { $1 }
      return try JSONDecoder().decode(AppUsage.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    func idle(_ id: String, confidence: PerformanceSuggestion.Confidence = .high, caveat: String? = nil, idleFor: Double = 3 * 3600) -> PerformanceSuggestion {
      PerformanceSuggestion(
        id: "quitIdleApp:\(id)", kind: .quitIdleApp, appID: id, appName: id, pid: nil, title: "Quit \(id)", reason: "",
        frees: .init(memoryBytes: 2_000_000_000, cpuPercent: 0.5, gpuPercent: nil), confidence: confidence, actionable: true,
        facts: "Idle", caveat: caveat, idleSeconds: idleFor
      )
    }
    let apps = [
      try app("com.example.idle"), try app("com.example.unsure"), try app("com.example.doubt"),
      try app("com.example.recent", ["lastActive": now.addingTimeInterval(-60).timeIntervalSinceReferenceDate]),
      try app("com.example.front", ["isFrontmost": true]), try app("com.example.music", ["isPlayingAudio": true]),
      try app("com.example.call", ["isCapturingAudio": true]), try app("com.example.export", ["preventingSleep": "Exporting"]),
      try app("com.example.kept"), try app("com.game.studio"), try app("com.game.launcher"),
    ]
    let suggestions = [
      idle("com.example.idle"), idle("com.example.unsure", confidence: .medium), idle("com.example.doubt", caveat: "May be in use"),
      idle("com.example.recent"), idle("com.example.front"), idle("com.example.music"), idle("com.example.call"),
      idle("com.example.export"), idle("com.example.kept"), idle("com.game.launcher"),
      PerformanceSuggestion(
        id: "relaunchHeavyApp:com.example.idle", kind: .relaunchHeavyApp, appID: "com.example.idle", appName: "idle", pid: nil,
        title: "", reason: "", frees: .init(memoryBytes: 1, cpuPercent: 0, gpuPercent: nil), confidence: .high, actionable: true
      ),
      PerformanceSuggestion(
        id: "runawayProcess:com.example.unsure", kind: .runawayProcess, appID: "com.example.unsure", appName: "unsure", pid: nil,
        title: "", reason: "", frees: .init(memoryBytes: 1, cpuPercent: 100, gpuPercent: nil), confidence: .high, actionable: false
      ),
    ]
    var config = GladeConfig()
    config.keepRunning = ["com.example.kept"]
    let plan = ReliefPlan.make(suggestions: suggestions, apps: apps, context: nil, config: config, now: now)
    let shown = Set(plan.actions.map(\.appID))
    for never in ["com.example.front", "com.example.music", "com.example.call", "com.example.export", "com.example.kept"] {
      #expect(!shown.contains(never), "\(never) must not appear")
    }
    #expect(!plan.actions.contains { $0.suggestionKind == .runawayProcess }, "a runaway is only for looking at")
    #expect(plan.defaultSelection == ["quitIdleApp:com.example.idle", "quitIdleApp:com.game.launcher"], "ticked: \(plan.defaultSelection)")

    // During a game, nothing from its maker is ticked.
    let context = try JSONDecoder().decode(ActivityContext.self, from: JSONSerialization.data(withJSONObject: [
      "date": now.timeIntervalSinceReferenceDate, "secondsSinceInput": 1, "onBattery": false, "lowPowerMode": false,
      "isGaming": true, "signals": [],
      "frontmostApp": ["id": "com.game.play", "name": "Game", "bundleIdentifier": "com.game.play", "isFullScreen": true],
    ] as [String: Any]))
    let gaming = ReliefPlan.make(suggestions: suggestions, apps: apps, context: context, config: config, now: now)
    #expect(!gaming.defaultSelection.contains("quitIdleApp:com.game.launcher"), "the game’s launcher was ticked")
    #expect(gaming.defaultSelection.contains("quitIdleApp:com.example.idle"))
  }

  /// Old agent versions: the one the command runs, any newer download and the one
  /// before it must stay, and nothing is offered when the live one is unknown.
  @Test func oldAgentVersionsKeepTheLiveOnes() throws {
    let root = home + "/.local/share/claude/versions"
    let bin = home + "/.local/bin"
    try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(atPath: bin, withIntermediateDirectories: true)
    let now = Date()
    for (index, version) in ["1.0.1", "1.0.2", "1.0.3", "1.0.4", "1.0.5"].enumerated() {
      let path = root + "/" + version
      try Data(repeating: 5, count: 1024).write(to: URL(fileURLWithPath: path))
      try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(Double(index - 5) * 86_400)], ofItemAtPath: path)
    }
    let command = bin + "/claude"
    #expect(AgentVersionScanner.plan(root: root, command: command) == nil, "no command link: keep everything")
    // The command runs 1.0.4; 1.0.5 is an update waiting to switch over.
    try FileManager.default.createSymbolicLink(atPath: command, withDestinationPath: root + "/1.0.4")
    let plan = try #require(AgentVersionScanner.plan(root: root, command: command))
    #expect(Set(plan.keep) == Set(["1.0.3", "1.0.4", "1.0.5"].map { root + "/" + $0 }))
    #expect(plan.remove == ["1.0.1", "1.0.2"].map { root + "/" + $0 })
    // A link that points somewhere else says nothing about which version is live.
    try FileManager.default.removeItem(atPath: command)
    try FileManager.default.createSymbolicLink(atPath: command, withDestinationPath: home + "/elsewhere/claude")
    #expect(AgentVersionScanner.plan(root: root, command: command) == nil)
  }

  @Test func scannerNeverReportsProtectedPlaces() async {
    let rules = [
      LocationRule(id: "t.caches", category: .appCaches, title: "cache", detail: "", paths: ["~/Library/Caches/*"], split: .each, minimumBytes: 0),
      LocationRule(id: "t.everything", category: .appCaches, title: "all", detail: "", paths: ["~/*", "~/.*", "~/proj/*", "~/proj/.*", "~/.claude/projects/*/*", "~/Library/*/*"], split: .each, minimumBytes: 0),
    ]
    let context = ScanContext(config: GladeConfig(), protection: protection, home: home, running: RunningApps())
    let findings = await CatalogScanner(rules: rules).scan(context)
    #expect(!findings.isEmpty)
    for finding in findings {
      for path in finding.paths {
        #expect(protection.canScan(path), "scanner reported protected path \(path)")
        for forbidden in ["/.ssh", "/.git", "/.env", "/memory", "Mobile Documents"] {
          #expect(!path.contains(forbidden), "scanner reported \(path)")
        }
      }
    }
    // A folder holding a photo library is found but can't be removed.
    let withLibrary = findings.first { $0.paths.contains { $0.hasSuffix("com.example.withlibrary") } }
    #expect(withLibrary?.isBlocked == true)
  }

  // MARK: Uninstalling apps

  /// A minimal app bundle: a folder with an Info.plist naming its identifier.
  @discardableResult
  private func makeApp(_ path: String, id: String?) throws -> String {
    try FileManager.default.createDirectory(atPath: path + "/Contents/MacOS", withIntermediateDirectories: true)
    var info: [String: Any] = ["CFBundleName": ((path as NSString).lastPathComponent as NSString).deletingPathExtension, "CFBundleExecutable": "app"]
    if let id { info["CFBundleIdentifier"] = id }
    let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try data.write(to: URL(fileURLWithPath: path + "/Contents/Info.plist"))
    try Data(repeating: 1, count: 4096).write(to: URL(fileURLWithPath: path + "/Contents/MacOS/app"))
    return path
  }

  private func appFinding(_ id: String, _ paths: [String], bundleID: String, blockers: [Blocker] = []) -> Finding {
    Finding(
      id: id, ruleID: "apps.installed", category: .installedApps, title: id, detail: "", paths: paths,
      bytes: 8192, recovery: .reinstall, risk: .personal, owner: Owner(id, bundleIDs: [bundleID]),
      blockers: blockers, method: .uninstallApp(bundleID: bundleID), autoLevel: nil, needsOwnerClosed: true
    )
  }

  @Test func uninstallVerdictAllowsOnlyRealAppsInApplicationsFolders() throws {
    let apps = home + "/Applications"
    try makeApp(apps + "/Good.app", id: "com.example.good")
    try makeApp(apps + "/Vendor/Inner.app", id: "com.example.inner")
    try makeApp(apps + "/Vendor/Deeper/Deep.app", id: "com.example.deep")
    try makeApp(apps + "/Good.app/Contents/Nested.app", id: "com.example.nested")
    try makeApp(apps + "/Bundle.folder/Inside.app", id: "com.example.inside")
    try makeApp(apps + "/Glade.app", id: "io.github.dlev02.glade")
    try makeApp(apps + "/Glade Dev.app", id: "io.github.dlev02.glade.dev")
    try makeApp(apps + "/Safari Copy.app", id: "com.apple.Safari")
    try makeApp(apps + "/NoIdentity.app", id: nil)
    try makeApp(home + "/Other/Out.app", id: "com.example.out")
    try makeApp(outside + "/Elsewhere/Far.app", id: "com.example.far")
    try FileManager.default.createSymbolicLink(atPath: apps + "/Link.app", withDestinationPath: apps + "/Good.app")
    try FileManager.default.createSymbolicLink(atPath: apps + "/Escape.app", withDestinationPath: outside + "/Elsewhere/Far.app")
    try FileManager.default.createSymbolicLink(atPath: apps + "/LinkedFolder", withDestinationPath: outside + "/Elsewhere")
    try Data("not an app".utf8).write(to: URL(fileURLWithPath: apps + "/File.app"))

    #expect(protection.verdict(forUninstalling: apps + "/Good.app") == .allowed)
    #expect(protection.verdict(forUninstalling: apps + "/Vendor/Inner.app") == .allowed)
    let refused = [
      apps + "/Link.app", apps + "/Escape.app", apps + "/LinkedFolder/Far.app", apps + "/Vendor/Deeper/Deep.app",
      apps + "/Good.app/Contents/Nested.app", apps + "/Bundle.folder/Inside.app", apps + "/Glade.app", apps + "/Glade Dev.app",
      apps + "/Safari Copy.app", apps + "/NoIdentity.app", apps + "/File.app", apps + "/Vendor", apps + "/Missing.app",
      home + "/Other/Out.app", outside + "/Elsewhere/Far.app", apps, home,
      // Written with `..` or `.`, even where it would land on an allowed app.
      apps + "/Vendor/../Good.app", home + "/Other/../Applications/Good.app", apps + "/./Good.app",
      "Applications/Good.app", "/System/Applications/Calculator.app", "/System/Applications/Utilities/Terminal.app",
      "/Applications/Safari.app", "/System/Library/CoreServices/Finder.app",
    ]
    for path in refused {
      #expect(!protection.verdict(forUninstalling: path).isAllowed, "must refuse \(path)")
    }
    // The general rule still refuses every app: only the uninstall rule allows one.
    #expect(!protection.verdict(forRemoving: "/Applications/Safari.app").isAllowed)
  }

  @Test func uninstallVerdictRefusesAnotherDisk() throws {
    // A small disk image mounted inside ~/Applications/Disk, holding an app.
    let image = outside + "/disk.dmg", mount = home + "/Applications/Disk"
    try FileManager.default.createDirectory(atPath: mount, withIntermediateDirectories: true)
    func hdiutil(_ arguments: [String]) -> Bool {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
      process.arguments = arguments
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      guard (try? process.run()) != nil else { return false }
      process.waitUntilExit()
      return process.terminationStatus == 0
    }
    guard hdiutil(["create", "-size", "4m", "-fs", "HFS+", "-volname", "GladeTest", image]),
          hdiutil(["attach", "-nobrowse", "-noverify", "-mountpoint", mount, image]) else {
      Issue.record("Couldn’t mount a disk image to test with")
      return
    }
    defer { _ = hdiutil(["detach", mount, "-force"]) }
    try makeApp(mount + "/Mounted.app", id: "com.example.mounted")
    #expect(protection.verdict(forUninstalling: mount + "/Mounted.app") == .otherVolume)
  }

  @Test func cleanerUninstallsOnlyWhatStillPassesAndLeavesTheRest() async throws {
    let apps = home + "/Applications"
    let bundle = try makeApp(apps + "/Good.app", id: "com.example.good")
    let data = home + "/Library/Application Support/com.example.good"
    try FileManager.default.createDirectory(atPath: data, withIntermediateDirectories: true)
    try Data(repeating: 2, count: 4096).write(to: URL(fileURLWithPath: data + "/state.db"))
    try makeApp(apps + "/Other.app", id: "com.example.other")
    try makeApp(apps + "/Glade.app", id: "io.github.dlev02.glade")
    try FileManager.default.createSymbolicLink(atPath: apps + "/Link.app", withDestinationPath: bundle)

    // Data paths that must stay where they are, whatever the finding says.
    let protectedData = [
      home + "/.ssh", home + "/Library/Application Support", home + "/Library",
      home + "/Library/Caches/../../.ssh", home + "/proj", outside + "/victim",
      home + "/Library/Caches/escape/victim", home + "/Library/Mobile Documents/com~apple~CloudDocs",
    ]
    let good = appFinding("good", [bundle, data] + protectedData, bundleID: "com.example.good")
    let hostile = [
      appFinding("running", [apps + "/Other.app"], bundleID: "com.example.other", blockers: [Blocker(.appRunning, "Other is open.")]),
      appFinding("swapped", [apps + "/Other.app"], bundleID: "com.example.not-other"),
      appFinding("glade", [apps + "/Glade.app"], bundleID: "io.github.dlev02.glade"),
      appFinding("link", [apps + "/Link.app"], bundleID: "com.example.good"),
      appFinding("outside", [outside + "/victim"], bundleID: "com.example.victim"),
      appFinding("system", ["/System/Applications/Calculator.app"], bundleID: "com.apple.calculator"),
      appFinding("vendor", [apps + "/Other.app"], bundleID: "com.example.other", blockers: [Blocker(.ownUninstaller, "Has its own uninstaller.")]),
      appFinding("ssh-as-app", [home + "/.ssh"], bundleID: "com.example.ssh"),
    ]
    // Neither a clean level nor an assistant may ever pick an app.
    #expect(!Planner.mayAutoSelect(good))
    for level in CleanLevel.allCases { #expect(Planner.decide(good, level: level).0 == false) }

    let result = scan([good] + hostile)
    let running = RunningApps(bundleIDs: ["com.example.other"])
    let dry = try await Cleaner.clean(ids: result.findings.map(\.id), from: result, config: GladeConfig(), options: CleanOptions(dryRun: true), protection: protection, running: running)
    #expect(dry.entries.first { $0.id == "good" }?.outcome == .wouldRemove)
    #expect(FileManager.default.fileExists(atPath: bundle))

    let receipt = try await Cleaner.clean(ids: result.findings.map(\.id), from: result, config: GladeConfig(), options: CleanOptions(dryRun: false), protection: protection, running: running)
    for entry in receipt.entries where entry.id != "good" {
      if case .skipped = entry.outcome { continue }
      Issue.record("\(entry.id) must be refused, got \(entry.outcome)")
    }
    let entry = try #require(receipt.entries.first { $0.id == "good" })
    guard case .trashed(let locations) = entry.outcome else {
      Issue.record("the app should go to the Trash, got \(entry.outcome)")
      return
    }
    #expect(Set(locations.keys.map(Protection.clean)) == Set([bundle, data].map(Protection.clean)))
    #expect(!FileManager.default.fileExists(atPath: bundle))
    #expect(!FileManager.default.fileExists(atPath: data))
    // Every protected data path is named in the receipt and is still there.
    for path in protectedData where FileManager.default.fileExists(atPath: path) {
      #expect(entry.leftInPlace?[path] != nil, "\(path) should be named as left in place")
    }
    for survivor in [".ssh/id_ed25519", "proj/.git/HEAD", "Library/Mobile Documents/com~apple~CloudDocs/thesis.pages"] {
      #expect(exists(survivor), "\(survivor) must survive")
    }
    for app in ["Other.app", "Glade.app"] { #expect(FileManager.default.fileExists(atPath: apps + "/" + app)) }
    #expect(FileManager.default.fileExists(atPath: outside + "/victim/file.txt"))

    // Put Back brings the app and its data home.
    let restored = Cleaner.restore(receipt)
    #expect(restored.restored.count == 2)
    #expect(FileManager.default.fileExists(atPath: bundle + "/Contents/Info.plist"))
    #expect(FileManager.default.fileExists(atPath: data + "/state.db"))
  }

  @Test func appDataStaysWhenItIsProtectedOrAnotherAppClaimsIt() throws {
    let library = home + "/Library"
    let folders = [
      "Containers/com.example.alpha", "Application Support/com.example.alpha.helper", "Caches/com.example.alpha",
      "Group Containers/ABCDE12345.com.example.shared", "Caches/com.example.beta", "Application Support/Alpha",
      "Application Support/Cursor", "Saved Application State/com.example.alpha.savedState",
    ]
    for folder in folders {
      try FileManager.default.createDirectory(atPath: library + "/" + folder, withIntermediateDirectories: true)
    }
    let alpha = InstalledApp(
      path: home + "/Applications/Alpha.app", bundleID: "com.example.alpha", name: "Alpha", isStandardLocation: true,
      identifiers: ["com.example.alpha", "com.example.alpha.helper", "abcde12345.com.example.shared"], teamID: "ABCDE12345"
    )
    let beta = InstalledApp(
      path: home + "/Applications/Beta.app", bundleID: "com.example.beta", name: "Beta", isStandardLocation: true,
      identifiers: ["com.example.beta", "abcde12345.com.example.shared"], teamID: "ABCDE12345"
    )
    let cursor = InstalledApp(
      path: home + "/Applications/Cursor.app", bundleID: "com.todesktop.cursor", name: "Cursor", isStandardLocation: true,
      identifiers: ["com.todesktop.cursor"], teamID: nil
    )
    let listing = AppData.listing(home: home, protection: protection)
    let result = AppData.folders(for: alpha, among: [alpha, beta, cursor], listing: listing, protection: protection)
    let goes = Set(result.goes.map { Protection.clean($0.path) })
    let stays = Set(result.stays.map { Protection.clean($0.path) })
    func full(_ folder: String) -> String { Protection.clean(library + "/" + folder) }
    for folder in ["Containers/com.example.alpha", "Application Support/com.example.alpha.helper", "Caches/com.example.alpha", "Application Support/Alpha", "Saved Application State/com.example.alpha.savedState"] {
      #expect(goes.contains(full(folder)), "\(folder) should go with Alpha")
    }
    // The same developer’s other app shares the group container, so it stays.
    #expect(stays.contains(full("Group Containers/ABCDE12345.com.example.shared")))
    #expect(!goes.contains(full("Caches/com.example.beta")))
    // A folder other things depend on stays, even for the app named after it.
    let forCursor = AppData.folders(for: cursor, among: [alpha, beta, cursor], listing: listing, protection: protection)
    #expect(!forCursor.goes.contains { Protection.clean($0.path) == full("Application Support/Cursor") })
    #expect(forCursor.stays.contains { Protection.clean($0.path) == full("Application Support/Cursor") })
  }

  // MARK: Folders picked in the window

  @Test func pickedFoldersAreOnlyWhatRemovalAllows() throws {
    guard case .success(let picked) = PickedFolder.finding(for: home + "/Library/Caches/com.example.app", protection: protection) else {
      Issue.record("an ordinary cache folder should be pickable")
      return
    }
    #expect(picked.ruleID == PickedFolder.ruleID && picked.risk == .personal && picked.method == .trash && picked.recovery == .permanent)
    #expect(picked.autoLevel == nil && !Planner.mayAutoSelect(picked))

    let refused = [
      home, home + "/.ssh", home + "/.ssh/id_ed25519", home + "/Library", home + "/Library/Application Support",
      home + "/Library/Caches", home + "/Documents", home + "/proj", home + "/proj/.git", outside + "/victim",
      home + "/Library/Caches/escape/victim", home + "/Library/Caches/../../.ssh", "/Applications", "/System/Library",
      home + "/Library/Mobile Documents/com~apple~CloudDocs", home + "/.claude/projects/-Users-me-App/memory",
      home + "/Library/Caches/com.example.withlibrary/Old.photoslibrary",
    ]
    for path in refused {
      if case .success = PickedFolder.finding(for: path, protection: protection) { Issue.record("must refuse picking \(path)") }
      #expect(PickedFolder.assess(path, protection: protection) != .allowed, "must refuse \(path)")
    }

    // A picked finding never reaches the saved scan, so nothing outside the window can
    // remove it by identifier.
    ScanEngine.save(scan([picked, finding("cache", home + "/Library/Caches/com.example.app")]))
    let saved = try #require(ScanEngine.loadLast())
    #expect(!saved.findings.contains { $0.ruleID == PickedFolder.ruleID })
    #expect(saved.findings.contains { $0.id == "cache" })
  }

  // MARK: Assistant proposals

  /// A model Glade can ask, answering from a script: one reply for the proposal, another
  /// for the second opinion.
  private struct StubProvider: AgentProvider {
    var id: String
    var name: String { id }
    var isLocal = false
    var reply: @Sendable (AgentRequest) -> String

    func status() async -> ProviderStatus { ProviderStatus(id: id, name: id, state: .ready) }

    func complete(_ request: AgentRequest) async throws -> AgentReply {
      AgentReply(text: reply(request), provider: id)
    }
  }

  @Test func assistantProposalsTickOnlyWhatThePersonNamedAndCanBeRemoved() async throws {
    let apps = home + "/Applications"
    let lantern = appFinding("lantern", [apps + "/Lantern.app"], bundleID: "com.lanternco.lantern")
    let beacon = appFinding("beacon", [apps + "/Beacon.app"], bundleID: "com.lanternco.beacon", blockers: [Blocker(.ownUninstaller, "Has its own uninstaller.")])
    let compass = appFinding("compass", [apps + "/Compass.app"], bundleID: "com.othermaker.compass")
    var installer = finding("installer", home + "/Downloads/old-installer.dmg", method: .trash, risk: .personal)
    installer.title = "Lantern Setup.dmg"
    installer.category = .downloads
    installer.autoLevel = nil
    let unrelated = finding("unrelated", home + "/Library/Caches/com.example.app")
    var lanternNamed = lantern, beaconNamed = beacon, compassNamed = compass
    lanternNamed.title = "Lantern"
    beaconNamed.title = "Beacon"
    compassNamed.title = "Compass"
    let result = scan([lanternNamed, beaconNamed, compassNamed, installer, unrelated])
    let request = "Uninstall Lantern and Beacon, and the Lantern installer"

    // Only what matches the request is shown to the model.
    let shown = RemovalRequest.candidates(for: request, scan: result, limit: 40).map(\.id)
    #expect(Set(shown) == ["lantern", "beacon", "installer"])
    #expect(RemovalRequest.wantsProposal(request, scan: result))
    #expect(!RemovalRequest.wantsProposal("Free up 30 GB", scan: result))

    let proposer = StubProvider(id: "stub-proposer") { _ in
      #"{"answer": "Here they are.", "propose": [{"id": "lantern", "why": "Named."}, {"id": "beacon", "why": "Named."}, {"id": "installer", "why": "Named."}, {"id": "compass", "why": "Added."}, {"id": "unrelated", "why": "Big."}, {"id": "~/Documents", "why": "Made up."}]}"#
    }
    let reviewer = StubProvider(id: "stub-reviewer") { _ in
      #"{"items": [{"id": "lantern", "verdict": "caution", "note": "You opened it yesterday."}, {"id": "unrelated", "verdict": "ok", "note": ""}, {"id": "invented", "verdict": "ok", "note": "Remove this too."}]}"#
    }
    let proposal = try await Assistant.propose(request, scan: result, snapshot: "", config: GladeConfig(), providers: [proposer, reviewer])

    // Anything it wasn’t shown is dropped and recorded; Compass was never shown either.
    #expect(proposal.items.map(\.id) == ["lantern", "beacon", "installer"])
    #expect(Set(proposal.rejected.map(\.id)) == ["compass", "unrelated", "~/Documents"])
    func item(_ id: String) -> RemovalProposal.Item? { proposal.items.first { $0.id == id } }
    // A named app that can be removed starts ticked, and a caution leaves it ticked.
    #expect(item("lantern")?.startsTicked == true && item("lantern")?.review?.verdict == .caution)
    // An app with its own uninstaller is never ticked; a personal finding never is.
    #expect(item("beacon")?.startsTicked == false && item("beacon")?.action == .openUninstaller)
    #expect(item("installer")?.named == true && item("installer")?.startsTicked == false)
    // The second opinion came from the other provider and couldn’t add anything.
    #expect(proposal.reviewer == "stub-reviewer")
    #expect(proposal.items.count == 3 && !proposal.items.contains { $0.id == "unrelated" || $0.id == "invented" })

    // Something the model adds on its own is never ticked, even when it could be removed.
    let added = RemovalProposal.item(for: compassNamed, why: "Added.", named: RemovalRequest.isNamed(compassNamed, in: request))
    #expect(!added.named && !added.startsTicked && added.action == .remove)
    // A named safe cache can start ticked; the same thing open or personal can’t.
    #expect(RemovalProposal.item(for: unrelated, why: "", named: true).startsTicked)
    var open = unrelated
    open.blockers = [Blocker(.appRunning, "Open.")]
    #expect(!RemovalProposal.item(for: open, why: "", named: true).startsTicked)
    #expect(!RemovalProposal.item(for: installer, why: "", named: true).startsTicked)

    // A review that fails, or no other AI at all, leaves the proposal without one.
    let alone = try await Assistant.propose(request, scan: result, snapshot: "", config: GladeConfig(), providers: [proposer])
    #expect(alone.reviewer == nil && alone.items.count == 3)
  }

  /// What an AI is shown about the network names no network, access point, address or
  /// device, however the reading was taken.
  @Test func networkReadingsShownToAnAINameNothingOnTheNetwork() {
    let secrets = ["Maple Street", "aa:bb:cc:dd:ee:ff", "192.168.1.254", "203.0.113.1", "Sam’s iPhone", "Kitchen Speaker"]
    let path = NetworkPath(
      connected: true, medium: .wifi, interface: "en0", isExpensive: false, isConstrained: false, router: "192.168.1.254",
      defaultInterface: "en0", vpns: [], proxy: false
    )
    let wifi = WiFiLink(
      interface: "en0", rssi: -58, noise: -94, band: "5 GHz", channel: 136, widthMHz: 80, generation: "Wi-Fi 6", linkRateMbps: 864,
      security: "WPA2", networkName: "Maple Street", accessPoint: "aa:bb:cc:dd:ee:ff"
    )
    let router = RouterReport(
      kind: "AT&T gateway", maker: "Nokia", model: "BGW320-505", firmware: "6.40.4",
      line: .init(connected: true, source: "Fibre", portMbps: 1000, received: 1, sent: 1, errors: 0, drops: 0),
      devices: [
        .init(name: "Sam’s iPhone", online: true, connection: "Wi-Fi 5 GHz", signalBars: 2, throughMesh: false, lastActive: "now"),
        .init(name: "Kitchen Speaker", online: true, connection: "Wi-Fi 2.4 GHz", signalBars: 1, throughMesh: nil, lastActive: nil),
      ],
      read: Date()
    )
    let status = NetworkStatus(
      date: Date(), path: path, wifi: wifi,
      latency: [
        .init(kind: .router, host: "192.168.1.254", stats: LatencyStats([3, 4, 5])),
        .init(kind: .provider, host: "203.0.113.1", stats: LatencyStats([5, 6, 7])),
      ],
      apps: [], router: router, lastTest: nil, verdicts: []
    )
    var history = NetworkHistory()
    history.add(received: 1_000, sent: 1_000, network: "Maple Street", seconds: 60)

    let described = MacDescription.describe(network: status, history: history).joined(separator: "\n")
    let encoded = JSONFiles.string(status.forAI())
    let usage = JSONFiles.string(NetworkHistory.anonymised(history.byNetwork(since: .distantPast), current: "Maple Street"))
    for text in [described, encoded, usage] {
      for secret in secrets { #expect(!text.contains(secret), "\(secret) reached the AI") }
    }
    // The counts are still there.
    #expect(described.contains("2 devices online") && described.contains("2 on a weak signal"))
  }
}
