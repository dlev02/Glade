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
}
