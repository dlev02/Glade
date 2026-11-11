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
