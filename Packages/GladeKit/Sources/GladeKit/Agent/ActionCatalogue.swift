import Foundation

/// The actions Glade offers the Assistant for one question, built from the readings it
/// just took. Each wraps something Glade already does (Free Up Memory, a clean level,
/// Put Back, the speed test) and takes that feature’s own rules as its say on what may
/// run without the person. Nothing the model writes adds to this list or changes an
/// action: it can only pick ids from it.
public enum ActionCatalogue {
  public struct Readings: Sendable {
    public var question: String
    public var apps: [AppUsage]
    public var relief: ReliefPlan?
    public var scan: ScanResult?
    public var config: GladeConfig
    /// The newest clean with something in the Trash to put back.
    public var lastReceipt: Receipt?
    /// The connection is metered or in Low Data Mode, or unknown.
    public var limitedConnection: Bool
    /// A speed test already ran in this conversation.
    public var speedTestRan: Bool
    /// Roughly the data a speed test would use.
    public var speedTestBytes: Int64?

    public init(
      question: String, apps: [AppUsage], relief: ReliefPlan?, scan: ScanResult?, config: GladeConfig,
      lastReceipt: Receipt?, limitedConnection: Bool, speedTestRan: Bool, speedTestBytes: Int64?
    ) {
      self.question = question
      self.apps = apps
      self.relief = relief
      self.scan = scan
      self.config = config
      self.lastReceipt = lastReceipt
      self.limitedConnection = limitedConnection
      self.speedTestRan = speedTestRan
      self.speedTestBytes = speedTestBytes
    }
  }

  /// The most single quits and shutdowns offered.
  static let reliefLimit = 6

  public static func offer(_ readings: Readings, now: Date = Date()) -> [AgentAction] {
    var actions: [AgentAction] = []
    var ids = Set<String>()
    func add(_ make: (String) -> AgentAction) {
      var id: String
      repeat { id = newID() } while ids.contains(id)
      ids.insert(id)
      actions.append(make(id))
    }
    let words = Set(RemovalRequest.words(QuestionTopic.withoutPaths(readings.question)))
    let keep = Set(readings.config.keepRunning.map { $0.lowercased() })

    // Memory: what Free Up Memory would do, together and one by one.
    if let relief = readings.relief {
      let chosen = relief.actions(relief.defaultSelection)
      if chosen.count > 1 {
        let bytes = relief.memoryBytes(of: relief.defaultSelection)
        add { id in
          var action = AgentAction(
            id: id, kind: .freeUpMemory, title: "Free up \(Format.bytes(bytes)) of memory",
            detail: "Quits or shuts down \(Format.listed(chosen.map { name($0.name) })). Each one opens again when you need it.",
            tier: .undoable, eligible: true
          )
          action.relief = chosen
          action.bytes = bytes
          return action
        }
      }
      for item in relief.actions.prefix(reliefLimit) {
        let named = isNamed(item.name, in: words)
        add { id in
          let shown = name(item.name)
          var action: AgentAction
          switch item.kind {
          case .quit:
            action = AgentAction(
              id: id, kind: .quit, title: "Quit \(shown)",
              detail: "Frees about \(Format.bytes(item.memoryBytes)). It asks about unsaved work first; opening it again brings it back.",
              tier: .undoable, eligible: item.selectedByDefault || named,
              heldBecause: item.caveat ?? "Free Up Memory wouldn’t tick it by itself."
            )
          case .relaunch:
            action = AgentAction(
              id: id, kind: .relaunch, title: "Quit and reopen \(shown)",
              detail: "It has grown over a long session; reopening usually gives back most of its \(Format.bytes(item.memoryBytes)).",
              tier: .undoable, eligible: named, heldBecause: "Reopening an app interrupts what it’s doing."
            )
          case .shutDown:
            action = AgentAction(
              id: id, kind: .shutDownSimulator, title: "Shut down the \(shown) simulator",
              detail: "Frees about \(Format.bytes(item.memoryBytes)). Its apps and data stay.",
              tier: .undoable, eligible: item.selectedByDefault || named,
              heldBecause: item.caveat ?? "Free Up Memory wouldn’t tick it by itself."
            )
          }
          action.relief = [item]
          action.bytes = item.memoryBytes
          return action
        }
      }
    }

    // An app the person named that Free Up Memory leaves out.
    let offeredApps = Set(readings.relief?.actions.map(\.appID) ?? [])
    for app in readings.apps where app.kind == .app && app.activationPolicy == .regular && !offeredApps.contains(app.id) {
      guard isNamed(app.name, in: words), actions.count < 12 else { continue }
      let busy = ReliefResult.inUse(app, keep: keep)
      if app.isSystem || app.isGlade { continue }
      add { id in
        var action = AgentAction(
          id: id, kind: .quit, title: "Quit \(name(app.name))",
          detail: "Frees about \(Format.bytes(app.memoryBytes)). It asks about unsaved work first; opening it again brings it back.",
          tier: .undoable, eligible: busy == nil, heldBecause: busy.map { "\($0), so Glade asks you first." }
        )
        action.relief = [ReliefPlan.Action(
          id: "named:\(app.id)", kind: .quit, suggestionKind: .quitIdleApp, appID: app.id, name: app.name,
          bundlePath: app.bundlePath, memoryBytes: app.memoryBytes, facts: Format.bytes(app.memoryBytes),
          why: "You named it.", selectedByDefault: false
        )]
        action.bytes = app.memoryBytes
        return action
      }
    }

    // A macOS helper that is leaking.
    for app in readings.apps where ProcessGuide.isRestartable(app) {
      add { id in
        var action = AgentAction(
          id: id, kind: .restartHelper, title: "Restart \(name(app.name))",
          detail: "It’s using \(Format.bytes(app.memoryBytes)), far more than usual. macOS opens it again by itself within a few seconds.",
          tier: .undoable, eligible: true
        )
        action.helperBundleID = app.bundleIdentifier
        action.bytes = app.memoryBytes
        return action
      }
    }

    // Storage: the clean levels, as the person would choose them.
    if let scan = readings.scan {
      let careful = Planner.plan(scan: scan, level: .careful, config: readings.config, now: now)
      let carefulIDs = Planner.topLevel(careful.selectedIDs, in: scan).map(\.id)
      if !carefulIDs.isEmpty, careful.selectedBytes >= 100_000_000 {
        add { id in
          var action = AgentAction(
            id: id, kind: .cleanCareful, title: "Clean Careful: \(Format.bytes(careful.selectedBytes))",
            detail: "Removes \(carefulIDs.count) things that rebuild themselves and haven’t been used lately. Some go to the Trash; the rest come back on their own when needed.",
            tier: .undoable, eligible: true
          )
          action.findingIDs = carefulIDs
          action.scanID = scan.id
          action.bytes = careful.selectedBytes
          return action
        }
      }
      let balanced = Planner.plan(scan: scan, level: .balanced, config: readings.config, now: now)
      let added = Planner.topLevel(balanced.selectedIDs.filter { !Set(careful.selectedIDs).contains($0) }, in: scan)
      let addedBytes = added.reduce(Int64(0)) { $0 + $1.bytes }
      if !added.isEmpty, addedBytes >= 100_000_000 {
        add { id in
          var action = AgentAction(
            id: id, kind: .cleanBalanced, title: "Clean what Balanced adds: \(Format.bytes(addedBytes))",
            detail: "Removes \(added.count) package caches, idle simulators, models and old agent history. They download or reinstall when needed.",
            tier: .harder, eligible: true
          )
          action.findingIDs = added.map(\.id)
          action.scanID = scan.id
          action.bytes = addedBytes
          return action
        }
      }
    }

    // Put back the last clean.
    if let receipt = readings.lastReceipt, now.timeIntervalSince(receipt.date) < 7 * 86_400 {
      let trashed = receipt.entries.filter { if case .trashed = $0.outcome { true } else { false } }
      if !trashed.isEmpty {
        add { id in
          var action = AgentAction(
            id: id, kind: .putBack, title: "Put back the last clean’s \(trashed.count) items",
            detail: "Moves them from the Trash to where they were.", tier: .undoable, eligible: true
          )
          action.receiptID = receipt.id
          return action
        }
      }
    }

    // The network.
    let data = readings.speedTestBytes.map { "about \(Format.bytes($0)) of data" } ?? "some data"
    add { id in
      if readings.limitedConnection {
        return AgentAction(
          id: id, kind: .speedTest, title: "Run a speed test",
          detail: "Uses \(data) on a connection that’s metered or in Low Data Mode.", tier: .alwaysAsks, eligible: false,
          heldBecause: "This connection is metered, so Glade asks before using data."
        )
      }
      return AgentAction(
        id: id, kind: .speedTest, title: "Run a speed test", detail: "Takes about \(readings.config.network.testSeconds) seconds and uses \(data).",
        tier: .undoable, eligible: !readings.speedTestRan, heldBecause: "A speed test already ran in this conversation."
      )
    }
    for host in hosts(in: QuestionTopic.withoutPaths(readings.question)).prefix(2) {
      add { id in
        var action = AgentAction(
          id: id, kind: .siteCheck, title: "Check how quickly \(host) answers",
          detail: "Times a few requests to it and to a well-known site, to tell the site apart from your connection.",
          tier: .look, eligible: true
        )
        action.host = host
        return action
      }
    }
    return actions
  }

  // MARK: The prompt

  /// The section the model reads. Titles and details are Glade’s own; app names in
  /// them were cleaned of line breaks, so no name can pose as an instruction line.
  public static func section(_ actions: [AgentAction]) -> String? {
    guard !actions.isEmpty else { return nil }
    let lines = actions.map { "\($0.id) | \($0.title) | \($0.detail)" }
    return "ACTIONS GLADE CAN TAKE (id | what | what happens)\n" + lines.joined(separator: "\n")
  }

  /// Takes the `Do: <id>` lines off the end of an answer. Ids Glade didn’t offer for
  /// this question are dropped; each counts once; at most `ActionPolicy.perAnswer`.
  public static func proposals(in answer: String, offered: [AgentAction]) -> (answer: String, actions: [AgentAction], dropped: [String]) {
    var kept: [String] = []
    var chosen: [AgentAction] = []
    var dropped: [String] = []
    let byID = Dictionary(offered.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    for line in answer.components(separatedBy: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "`*-• "))
      guard trimmed.lowercased().hasPrefix("do:") else {
        kept.append(line)
        continue
      }
      let id = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces).prefix { $0.isLetter || $0.isNumber }.lowercased()
      guard let action = byID[id] else {
        dropped.append(id)
        continue
      }
      if chosen.contains(where: { $0.id == id }) { continue }
      if chosen.count >= ActionPolicy.perAnswer {
        dropped.append(id)
        continue
      }
      chosen.append(action)
    }
    if !dropped.isEmpty { Log.warning(.safety, "Dropped \(dropped.count) proposed action ids that weren’t offered or went over the limit") }
    let text = kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    return (text, chosen, dropped)
  }

  // MARK: Helpers

  /// Four lowercase letters and digits.
  static func newID() -> String {
    let characters = Array("abcdefghjkmnpqrstuvwxyz23456789")
    return String((0..<4).map { _ in characters.randomElement()! })
  }

  /// A name as it may appear in a prompt or on a card: one line, at most 40 characters.
  static func name(_ text: String) -> String {
    let flat = text.components(separatedBy: .newlines).joined(separator: " ")
      .unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
    let line = String(String.UnicodeScalarView(flat)).trimmingCharacters(in: .whitespaces)
    return line.count > 40 ? String(line.prefix(39)) + "…" : line
  }

  /// The person named this app: every distinctive word of its name is in their words.
  static func isNamed(_ appName: String, in words: Set<String>) -> Bool {
    let nameWords = RemovalRequest.words(appName).filter { $0.count >= 3 && !RemovalRequest.commonNameWords.contains($0) }
    return !nameWords.isEmpty && nameWords.allSatisfy(words.contains)
  }

  /// Host names in the person’s own words ("is github.com slow?"). Never from a model.
  public static func hosts(in text: String) -> [String] {
    let pattern = #"(?i)\b(?:https?://)?((?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,24})\b"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(text.startIndex..., in: text)
    var found: [String] = []
    for match in regex.matches(in: text, range: range) {
      guard let hostRange = Range(match.range(at: 1), in: text) else { continue }
      let host = text[hostRange].lowercased()
      // A file name such as "notes.txt" isn't a site.
      let fileEndings: Set<String> = ["txt", "png", "jpg", "jpeg", "pdf", "swift", "json", "md", "app", "dmg", "zip", "log", "html", "plist", "heic", "mov"]
      if let last = host.split(separator: ".").last, fileEndings.contains(String(last)) { continue }
      if !found.contains(host) { found.append(host) }
    }
    return found
  }
}
