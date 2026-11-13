import Foundation

/// Reviews the person’s Little Snitch rules. The model reads a stripped-down list and
/// answers in JSON; Glade keeps only suggestions that pass its own checks.
extension Assistant {
  static let littleSnitchPurpose = "Little Snitch review"

  public static func reviewLittleSnitch(
    _ rules: LittleSnitchRules, request: String?, config: GladeConfig = ConfigStore.load(), providers: [any AgentProvider]
  ) async throws -> LittleSnitchReview {
    let provider = try await pick(config: config, providers: providers, proactive: false)
    let model = config.assistant.models[provider.id]
    let prompt = StoragePrompt.littleSnitchPrompt(rules, request: request, characterBudget: provider.isLocal ? 9_000 : 60_000)
    let (reply, runID) = try await run(
      provider: provider, purpose: littleSnitchPurpose, system: StoragePrompt.littleSnitchSystem, prompt: prompt,
      model: model, config: config, proactive: false, schema: StoragePrompt.littleSnitchSchema
    )
    let raw = try decode(RawSnitchReview.self, from: reply.text, provider: provider.name)
    var review = LittleSnitchReview(
      summary: String((raw.summary ?? "").prefix(800)), points: [], remove: [], add: [], rejected: [],
      provider: reply.provider, model: reply.model ?? model, runID: runID
    )
    validate(raw, rules: rules, into: &review)
    amend(runID: runID) { record in record.rejected = review.rejected }
    Log.info(.agent, "Little Snitch review from \(provider.name): \(review.points.count) points, \(review.remove.count) to delete, \(review.add.count) to add, \(review.rejected.count) refused")
    return review
  }

  /// Keeps what passes Glade’s own checks, whatever the model said.
  static func validate(_ raw: RawSnitchReview, rules: LittleSnitchRules, into review: inout LittleSnitchReview) {
    let byID = Dictionary(rules.rules.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let duplicates = Set(rules.findings().filter { $0.kind == .duplicate }.flatMap { $0.ruleIDs.dropFirst() })
    let processes = Set(rules.rules.map(\.process))
    for point in (raw.points ?? []).prefix(8) {
      review.points.append(.init(title: String(point.title.prefix(120)), detail: String(point.detail.prefix(400)), ruleIDs: point.rules.filter { byID[$0] != nil }))
    }
    for id in raw.remove ?? [] {
      guard let rule = byID[id] else {
        review.rejected.append("\(id): no such rule")
        continue
      }
      if rule.managed || rule.builtIn {
        review.rejected.append("\(id): managed by \(rule.group ?? "Little Snitch"), not deleted on its own")
        continue
      }
      if rule.action == "deny", !duplicates.contains(id) {
        review.rejected.append("\(id): a deny rule that isn’t a duplicate stays")
        continue
      }
      if !review.remove.contains(where: { $0.id == id }) { review.remove.append(rule) }
    }
    for item in (raw.add ?? []).prefix(20) {
      let action = item.action.lowercased()
      let direction = item.direction.lowercased() == "incoming" ? "incoming" : "outgoing"
      let domains = item.domains.map { $0.lowercased() }.filter(isHostName)
      let hosts = item.hosts.map { $0.lowercased() }.filter(isHostName)
      guard action == "allow" || action == "deny" else {
        review.rejected.append("add \(item.process): action \(item.action) isn’t allow or deny")
        continue
      }
      guard item.process == "any" || processes.contains(item.process) else {
        review.rejected.append("add \(item.process): not a process in these rules")
        continue
      }
      guard !domains.isEmpty || !hosts.isEmpty else {
        review.rejected.append("add \(item.process): names no server, which would match everything")
        continue
      }
      if action == "allow", item.process == "any" {
        review.rejected.append("add any process: allowing every process is too broad")
        continue
      }
      // An allow must never open what an existing block closes.
      if action == "allow", let blocked = (domains + hosts).first(where: { underDeny($0, process: item.process, rules: rules) }) {
        review.rejected.append("add \(item.process): allowing \(blocked) would undo a block")
        continue
      }
      let path = item.process.hasPrefix("~/") ? NSHomeDirectory() + item.process.dropFirst() : item.process
      review.add.append(.init(action: action, process: path, domains: domains, hosts: hosts, direction: direction, notes: String(item.notes.prefix(200))))
    }
  }

  /// A plain host or domain: two labels at least, no wildcards.
  static func isHostName(_ text: String) -> Bool {
    let labels = text.split(separator: ".", omittingEmptySubsequences: false)
    return text.count < 254 && labels.count >= 2 && labels.allSatisfy { !$0.isEmpty && !$0.hasPrefix("-") }
      && labels.last?.allSatisfy(\.isLetter) == true
      && text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
  }

  /// Whether an active deny rule for this process (or any process) covers the host.
  static func underDeny(_ host: String, process: String, rules: LittleSnitchRules) -> Bool {
    rules.rules.contains { rule in
      guard rule.action == "deny", !rule.disabled, rule.process == "any" || rule.process == process else { return false }
      if rule.remoteKind == "any" { return true }
      let names = rule.remote.components(separatedBy: CharacterSet(charactersIn: ",; ")).map { $0.lowercased() }.filter { $0.contains(".") }
      return names.contains { $0 == host || host.hasSuffix("." + $0) }
    }
  }

  struct RawSnitchReview: Decodable {
    struct Point: Decodable {
      var title: String
      var detail: String
      var rules: [String]
    }

    struct Add: Decodable {
      var action: String
      var process: String
      var domains: [String]
      var hosts: [String]
      var direction: String
      var notes: String

      init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        action = try c.decode(String.self, forKey: .action)
        process = try c.decode(String.self, forKey: .process)
        domains = (try? c.decodeIfPresent([String].self, forKey: .domains)) ?? []
        hosts = (try? c.decodeIfPresent([String].self, forKey: .hosts)) ?? []
        direction = (try? c.decodeIfPresent(String.self, forKey: .direction)) ?? "outgoing"
        notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? ""
      }

      enum CodingKeys: String, CodingKey { case action, process, domains, hosts, direction, notes }
    }

    var summary: String?
    var points: [Point]?
    var remove: [String]?
    var add: [Add]?
  }
}
