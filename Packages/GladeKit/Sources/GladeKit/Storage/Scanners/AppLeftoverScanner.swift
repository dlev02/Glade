import Foundation

/// Data left behind by apps that are no longer on this Mac.
///
/// Only folders named like a bundle identifier are considered, and only when nothing
/// installed, running or scheduled claims that identifier, its developer or its group.
/// Plain names ("Slack", "Google") are skipped: command-line tools, drivers and plugins
/// write there too, and a name alone can’t say who owns it.
public struct AppLeftoverScanner: StorageScanner {
  public let id = "app-leftovers"
  public let title = "Leftovers from removed apps"

  static let minimumBytes: Int64 = 5_000_000
  /// Something wrote here this recently, so something still uses it.
  static let quietDays = 30

  /// Where apps keep per-user data, relative to home. `~/Library/Preferences` and
  /// `~/Library/Application Scripts` are protected zones and are left alone.
  static let locations: [(folder: String, label: String)] = [
    ("Library/Application Support", "Application Support"),
    ("Library/Caches", "Caches"),
    ("Library/Containers", "Containers"),
    ("Library/Group Containers", "Group Containers"),
    ("Library/Saved Application State", "Saved Application State"),
    ("Library/HTTPStorages", "HTTP Storages"),
    ("Library/WebKit", "WebKit"),
    ("Library/Logs", "Logs"),
  ]

  /// Identifiers never reported, even when no app claims them. Each is written by
  /// something that isn’t an app bundle, is shared between many apps, or belongs to
  /// macOS. A trailing `*` matches the identifier and anything below it.
  static let neverReport: [String] = [
    // macOS and Apple’s own components.
    "com.apple.*", "is.workflow.*", "systemgroup.*",
    // Developer tools without an app bundle.
    "org.swift.*", "org.llvm.*", "org.python.*", "org.nodejs.*", "org.rust-lang.*", "dev.deno.*",
    "sh.brew.*", "org.homebrew.*", "com.github.githubcli", "com.github.electron", "com.github.squirrel.*",
    "com.microsoft.vscode.shipit", "com.microsoft.dotnet.*", "com.jetbrains.toolbox.*",
    "com.google.keystone", "com.google.keystone.*", "com.google.softwareupdate", "com.google.googleupdater",
    "com.microsoft.autoupdate*", "com.microsoft.shared", "com.microsoft.office.licensing*",
    "com.anthropic.claude-code*", "com.openai.codex*",
    // Password managers: an encrypted vault is never offered, installed or not.
    "com.bitwarden.*", "com.1password.*", "com.agilebits.*", "com.lastpass.*", "com.dashlane.*",
    "org.keepassxc.*", "com.sinew.enpass*", "com.nordsec.nordpass*", "com.proton.pass*", "me.proton.pass*",
    // SDKs that many apps embed under the SDK’s own name.
    "io.sentry.*", "com.crashlytics.*", "io.fabric.*", "com.firebase.*", "com.google.firebase.*",
    "com.facebook.sdk*", "org.sparkle-project.*", "com.sparkle-project.*", "com.segment.*",
    "com.plausiblelabs.*", "com.hockeyapp.*", "com.bugsnag.*", "com.amplitude.*", "com.mixpanel.*",
    "com.appcenter.*", "com.microsoft.appcenter.*",
  ]

  /// Top-level parts that real bundle identifiers start with.
  static let domainRoots: Set<String> = [
    "com", "org", "net", "io", "app", "dev", "co", "me", "ai", "tv", "cc", "sh", "so", "xyz", "info", "biz",
    "edu", "gov", "us", "uk", "ca", "au", "nz", "de", "fr", "es", "it", "nl", "be", "ch", "at", "se", "no", "dk",
    "fi", "pl", "cz", "sk", "hu", "ro", "pt", "gr", "ie", "is", "ee", "lv", "lt", "ru", "ua", "by", "jp", "kr",
    "cn", "tw", "hk", "sg", "in", "id", "my", "th", "vn", "ph", "br", "ar", "mx", "cl", "za", "il", "tr",
    "eu", "studio", "tech", "software", "page", "design", "pro", "codes", "fm", "gg", "im", "ly", "to", "ws",
  ]

  public init() {}

  /// One location belonging to an identifier.
  struct Location: Sendable {
    var path: String
    var label: String
  }

  public func scan(_ context: ScanContext) async -> [Finding] {
    let grouped = await context.background { Self.candidates(context) }
    guard !grouped.isEmpty, !context.cancel.isCancelled else { return [] }
    let apps = await InstalledApps.shared(for: context)

    var findings: [Finding] = []
    for (identifier, entry) in grouped.sorted(by: { $0.key < $1.key }) {
      if context.cancel.isCancelled { break }
      if apps.claim(on: identifier, team: entry.team) != nil { continue }
      // A path that would fail the removal check isn’t offered at all.
      let locations = entry.locations.filter { context.protection.verdict(forRemoving: $0.path).isAllowed }
      guard !locations.isEmpty else { continue }
      let measure = await context.measure(locations.map(\.path))
      guard !measure.cancelled, measure.bytes >= Self.minimumBytes else { continue }
      // Reads (backups, Spotlight) bump access times; only a write shows an owner is alive.
      if let days = context.days(since: measure.newestModification), days < Self.quietDays { continue }
      findings.append(make(identifier, entry.display, locations, measure, context))
    }
    return findings
  }

  struct Entry: Sendable {
    var display: String
    var team: String?
    var locations: [Location]
  }

  /// Bundle-identifier-shaped children of each location, grouped by identifier.
  static func candidates(_ context: ScanContext) -> [String: Entry] {
    var grouped: [String: Entry] = [:]
    for (folder, label) in locations {
      let root = "\(context.home)/\(folder)"
      guard context.protection.canScan(root) else { continue }
      // Containers and some group containers need Full Disk Access; without it the
      // listing is empty or partial, and the engine reports the missing permission.
      for path in DiskWalk.children(of: root) {
        let name = (path as NSString).lastPathComponent
        guard let parsed = identifier(from: name, in: folder), context.protection.canScan(path) else { continue }
        let key = parsed.id.lowercased()
        if isNeverReported(key) { continue }
        var entry = grouped[key] ?? Entry(display: parsed.id, team: parsed.team, locations: [])
        if entry.team == nil { entry.team = parsed.team }
        entry.locations.append(Location(path: path, label: label))
        grouped[key] = entry
      }
    }
    return grouped
  }

  /// The identifier a folder is named after, or `nil` when the name isn’t shaped like
  /// one. Group containers may carry a team prefix (`ABCDE12345.com.vendor.app`) or a
  /// `group.` prefix; saved state and cookie files carry a suffix.
  static func identifier(from name: String, in folder: String) -> (id: String, team: String?)? {
    var base = name
    for suffix in [".savedState", ".binarycookies"] where base.hasSuffix(suffix) {
      base = String(base.dropLast(suffix.count))
    }
    var team: String?
    var parts = base.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    if folder.hasSuffix("Group Containers") || folder.hasSuffix("Containers") {
      if let first = parts.first, isTeamID(first), parts.count > 1 {
        team = first
        parts.removeFirst()
      }
      if parts.first?.lowercased() == "group", parts.count > 1 { parts.removeFirst() }
    }
    guard parts.count >= 3, let root = parts.first, domainRoots.contains(root.lowercased()) else { return nil }
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    for part in parts {
      guard !part.isEmpty, part.unicodeScalars.allSatisfy({ allowed.contains($0) && $0.isASCII }) else { return nil }
    }
    // Apple’s components sit under other roots too (group.com.apple…, *.apple.*).
    if parts.dropFirst().contains(where: { $0.lowercased() == "apple" }) { return nil }
    return (parts.joined(separator: "."), team)
  }

  /// Ten uppercase letters and digits, as Apple assigns developer teams.
  static func isTeamID(_ text: String) -> Bool {
    text.count == 10 && text.unicodeScalars.allSatisfy { ("A"..."Z").contains($0) || ("0"..."9").contains($0) }
  }

  static func isNeverReported(_ identifier: String) -> Bool {
    neverReport.contains { pattern in
      if pattern.hasSuffix(".*") {
        let prefix = String(pattern.dropLast(2))
        return identifier == prefix || identifier.hasPrefix(prefix + ".")
      }
      if pattern.hasSuffix("*") { return identifier.hasPrefix(String(pattern.dropLast())) }
      return identifier == pattern
    }
  }

  /// Last parts that say nothing about which app it was.
  static let genericParts: Set<String> = [
    "app", "mac", "macos", "osx", "desktop", "desktopclient", "client", "ios", "main", "application", "helper",
  ]

  /// "Slackmacgap" from "com.tinyspeck.slackmacgap"; "Foo Bar" from "com.vendor.foo-bar";
  /// "Nordvpn" from "com.nordvpn.macos".
  static func nameGuess(_ identifier: String) -> String {
    var parts = identifier.split(separator: ".").map(String.init)
    for (index, part) in parts.enumerated() {
      for suffix in ["-setapp", "_setapp"] where part.lowercased().hasSuffix(suffix) {
        parts[index] = String(part.dropLast(suffix.count))
      }
    }
    while parts.count > 2, let last = parts.last, genericParts.contains(last.lowercased()) { parts.removeLast() }
    let last = parts.last ?? identifier
    let words = last.split(whereSeparator: { $0 == "-" || $0 == "_" }).map { word in
      word.prefix(1).uppercased() + word.dropFirst()
    }
    return words.isEmpty ? last : words.joined(separator: " ")
  }

  private func make(_ identifier: String, _ display: String, _ locations: [Location], _ measure: Measure, _ context: ScanContext) -> Finding {
    let name = Self.nameGuess(display)
    var places: [String] = []
    for location in locations where !places.contains(location.label) { places.append(location.label) }
    var evidence = [
      "Found in \(places.joined(separator: ", ")) under the identifier \(display).",
      "No installed app, helper or background item uses this identifier.",
    ]
    if let days = context.days(since: measure.newestModification) {
      evidence.append("Nothing inside has changed in \(days) days.")
    }
    if measure.unreadable > 0 {
      evidence.append("\(measure.unreadable) items couldn’t be read, so the real size may be larger.")
    }
    evidence.append("If the app lives on another disk, or you plan to reinstall it, keep this.")
    var blockers: [Blocker] = []
    if measure.containsStrict {
      blockers.append(Blocker(.inUse, "Contains a library or backup that must stay whole."))
    }
    return Finding(
      id: Finding.makeID(rule: "leftovers.app", path: identifier),
      ruleID: "leftovers.app", category: .appLeftovers, title: "\(name) leftovers",
      detail: "Settings, caches and data from an app that’s no longer installed. Reinstalling the app starts fresh; this can’t be brought back once the Trash is emptied.",
      paths: locations.map(\.path), bytes: measure.bytes, fileCount: measure.files, lastUsed: measure.lastUsed,
      recovery: .permanent, risk: .caution, owner: Owner(name, bundleIDs: [display]),
      blockers: blockers, method: .trash, evidence: evidence, autoLevel: nil, idleDaysRequired: 0
    )
  }
}
