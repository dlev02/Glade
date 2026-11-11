import Foundation

/// What an assistant said about a plan, after Glade has checked it.
public struct StorageAdvice: Codable, Sendable {
  public struct Note: Codable, Sendable, Identifiable {
    public var id: String
    public var why: String
  }

  /// Two or three sentences for the person.
  public var summary: String
  /// Findings to add to the selection.
  public var select: [Note]
  /// Findings the rules selected that should be left alone.
  public var deselect: [Note]
  /// Personal items worth the person's attention. Never selected.
  public var review: [Note]
  /// Suggestions Glade threw out because they broke a safety rule, with the reason.
  public var rejected: [Note]
  public var provider: String
  public var model: String?
  /// True when a stronger model was called in.
  public var escalated: Bool
  public var runID: String
}

/// The record of one assistant run, kept so a person can see exactly what was asked
/// and answered. Stored locally; nothing here is sent anywhere.
public struct AssistantRun: Codable, Sendable, Identifiable {
  public var id: String
  public var date: Date
  public var purpose: String
  public var provider: String
  public var model: String?
  public var system: String
  public var prompt: String
  public var reply: String?
  public var error: String?
  public var duration: TimeInterval
  public var inputTokens: Int?
  public var outputTokens: Int?
  public var costUSD: Double?
  public var rejected: [String]
  /// Started by Glade itself (a threshold tripped) and not by a person.
  public var proactive: Bool
}

public enum AssistantError: Error, LocalizedError {
  case noProvider([ProviderStatus])
  case dailyLimitReached(Int)

  public var errorDescription: String? {
    switch self {
    case .noProvider(let statuses):
      let installed = statuses.filter { $0.state != .notInstalled }.map(\.name)
      return installed.isEmpty
        ? "No AI is connected. Install Claude Code or Codex, or turn on Apple Intelligence."
        : "None of your AIs is ready (\(installed.joined(separator: ", "))). Check that they’re signed in."
    case .dailyLimitReached(let limit):
      return "Glade has already checked in \(limit) times today, which is the limit you set."
    }
  }
}

/// Asks a model for advice and keeps it inside the safety rules.
///
/// The model sees a description of what Glade found: names, sizes, dates and how each
/// thing comes back. It answers with finding identifiers only. It can't name a path,
/// run a command, or select anything the rules forbid; anything it tries is dropped
/// and recorded.
public enum Assistant {
  // MARK: Storage

  /// Refines a plan. The assistant may add findings up to the plan's level, take
  /// findings out, and flag personal items for review.
  /// - Parameter goal: What the person asked for, in their words, if anything.
  public static func advise(
    scan: ScanResult,
    plan: CleanPlan,
    goal: String? = nil,
    activity: String? = nil,
    config: GladeConfig = ConfigStore.load(),
    proactive: Bool = false,
    providers: [any AgentProvider]
  ) async throws -> (plan: CleanPlan, advice: StorageAdvice) {
    let provider = try await pick(config: config, providers: providers, proactive: proactive)
    let budget = provider.isLocal ? 9_000 : 60_000
    let prompt = StoragePrompt.build(scan: scan, plan: plan, goal: goal, activity: activity, characterBudget: budget)
    let known = Set(prompt.includedIDs)

    var (reply, runID) = try await run(
      provider: provider, purpose: "storage plan", system: StoragePrompt.system, prompt: prompt.text,
      model: config.assistant.models[provider.id], config: config, proactive: proactive
    )
    var raw = try decode(RawAdvice.self, from: reply.text, provider: provider.name)
    var escalated = false

    // The everyday model may ask for a closer look by a stronger one.
    if raw.escalate?.needed == true, let (deepProvider, deepModel) = deepChoice(config: config, current: provider, providers: providers) {
      Log.info(.agent, "\(provider.name) asked for a closer look (\(raw.escalate?.why ?? "no reason given")); calling in \(deepProvider.name) \(deepModel ?? "default")")
      do {
        let deepPrompt = prompt.text + "\n\nA faster model looked at this first and asked for your judgement because: \(raw.escalate?.why ?? "it was unsure"). Do not escalate further."
        let (deepReply, deepRunID) = try await run(
          provider: deepProvider, purpose: "storage plan (closer look)", system: StoragePrompt.system, prompt: deepPrompt,
          model: deepModel, config: config, proactive: proactive
        )
        raw = try decode(RawAdvice.self, from: deepReply.text, provider: deepProvider.name)
        reply = deepReply
        runID = deepRunID
        escalated = true
      } catch {
        Log.warning(.agent, "The closer look failed, keeping the first answer: \(error.localizedDescription)")
      }
    }

    // Validate every suggestion against the rules.
    var updated = plan
    var advice = StorageAdvice(
      summary: String((raw.summary ?? "").prefix(600)), select: [], deselect: [], review: [], rejected: [],
      provider: reply.provider, model: reply.model, escalated: escalated, runID: runID
    )
    func reject(_ id: String, _ why: String) {
      advice.rejected.append(.init(id: id, why: why))
      Log.warning(.safety, "Dropped assistant suggestion for \(id): \(why)")
    }
    for note in raw.select ?? [] {
      guard known.contains(note.id), let finding = scan.finding(note.id) else {
        reject(note.id, "Not one of the findings it was shown.")
        continue
      }
      guard Planner.mayAutoSelect(finding), let autoLevel = finding.autoLevel, autoLevel <= plan.level else {
        reject(note.id, finding.risk == .personal ? "Personal files are never selected by an assistant." : "Outside what the \(plan.level.title) level allows.")
        continue
      }
      if let index = updated.items.firstIndex(where: { $0.id == note.id }), !updated.items[index].selected {
        updated.items[index] = PlanItem(id: note.id, selected: true, reason: clip(note.why), source: .assistant)
        advice.select.append(.init(id: note.id, why: clip(note.why)))
      }
    }
    for note in raw.deselect ?? [] {
      guard let index = updated.items.firstIndex(where: { $0.id == note.id }) else {
        reject(note.id, "Not one of the findings it was shown.")
        continue
      }
      if updated.items[index].selected {
        updated.items[index] = PlanItem(id: note.id, selected: false, reason: clip(note.why), source: .assistant)
        advice.deselect.append(.init(id: note.id, why: clip(note.why)))
      }
    }
    for note in raw.review ?? [] where known.contains(note.id) && scan.finding(note.id) != nil {
      advice.review.append(.init(id: note.id, why: clip(note.why)))
    }
    updated.review = advice.review.map(\.id) + plan.review.filter { id in !advice.review.contains { $0.id == id } }
    updated.summary = advice.summary
    updated.provider = reply.provider
    Planner.total(&updated, scan: scan, config: config)
    amend(runID: runID) { $0.rejected = advice.rejected.map { "\($0.id): \($0.why)" } }
    Log.info(.agent, "Advice from \(reply.provider): +\(advice.select.count) −\(advice.deselect.count), \(advice.review.count) to review, \(advice.rejected.count) rejected; plan now \(Format.bytes(updated.selectedBytes))")
    return (updated, advice)
  }

  // MARK: Free-form questions

  /// Answers a question about this Mac using a snapshot Glade prepared. The answer is
  /// text for the person; it can't cause any action.
  public static func ask(
    _ question: String,
    snapshot: String,
    config: GladeConfig = ConfigStore.load(),
    proactive: Bool = false,
    providers: [any AgentProvider]
  ) async throws -> (answer: String, provider: String, model: String?, runID: String) {
    let provider = try await pick(config: config, providers: providers, proactive: proactive)
    let budget = provider.isLocal ? 9_000 : 60_000
    let prompt = "QUESTION\n\(question)\n\nWHAT GLADE SEES\n\(snapshot.prefix(budget))"
    let (reply, runID) = try await run(
      provider: provider, purpose: "question", system: StoragePrompt.questionSystem, prompt: prompt,
      model: config.assistant.models[provider.id], config: config, proactive: proactive, schema: nil
    )
    return (reply.text.trimmingCharacters(in: .whitespacesAndNewlines), reply.provider, reply.model ?? config.assistant.models[provider.id], runID)
  }

  // MARK: Running

  /// The first provider in the person's preferred order that's ready.
  public static func pick(config: GladeConfig, providers: [any AgentProvider], proactive: Bool) async throws -> any AgentProvider {
    if proactive, let limit = config.assistant.runsPerDay {
      let today = proactiveRunsToday()
      guard today < limit else { throw AssistantError.dailyLimitReached(limit) }
    }
    var statuses: [ProviderStatus] = []
    let ordered = config.assistant.order.compactMap { id in providers.first { $0.id == id } }
      + providers.filter { !config.assistant.order.contains($0.id) }
    for provider in ordered {
      let status = await provider.status()
      statuses.append(status)
      if status.isReady { return provider }
    }
    throw AssistantError.noProvider(statuses)
  }

  private static func deepChoice(config: GladeConfig, current: any AgentProvider, providers: [any AgentProvider]) -> (any AgentProvider, String?)? {
    let deepProvider = config.assistant.deepProvider.flatMap { id in providers.first { $0.id == id } } ?? current
    let deepModel = config.assistant.deepModels[deepProvider.id]
    // Calling the same provider with the same model again would learn nothing.
    if deepProvider.id == current.id, deepModel == nil || deepModel == config.assistant.models[current.id] { return nil }
    return (deepProvider, deepModel)
  }

  static func run(
    provider: any AgentProvider, purpose: String, system: String, prompt: String, model: String?,
    config: GladeConfig, proactive: Bool, schema: String? = StoragePrompt.schema
  ) async throws -> (AgentReply, String) {
    var record = AssistantRun(
      id: UUID().uuidString, date: Date(), purpose: purpose, provider: provider.id, model: model,
      system: system, prompt: prompt, reply: nil, error: nil, duration: 0, inputTokens: nil,
      outputTokens: nil, costUSD: nil, rejected: [], proactive: proactive
    )
    let started = Date()
    Log.info(.agent, "Asking \(provider.name) (\(model ?? "default model"), effort \(config.assistant.effort.rawValue)) for: \(purpose); prompt \(prompt.count) characters")
    do {
      let reply = try await provider.complete(AgentRequest(
        system: system, prompt: prompt, model: model, effort: config.assistant.effort,
        timeout: config.assistant.timeout, jsonSchema: schema
      ))
      record.reply = reply.text
      record.model = reply.model ?? model
      record.duration = Date().timeIntervalSince(started)
      record.inputTokens = reply.inputTokens
      record.outputTokens = reply.outputTokens
      record.costUSD = reply.costUSD
      save(record)
      return (reply, record.id)
    } catch {
      record.error = error.localizedDescription
      record.duration = Date().timeIntervalSince(started)
      save(record)
      Log.error(.agent, "\(provider.name) failed after \(String(format: "%.1f", record.duration))s: \(error.localizedDescription)")
      throw error
    }
  }

  // MARK: Run records

  public static func runs(limit: Int = 50) -> [AssistantRun] {
    let files = (try? FileManager.default.contentsOfDirectory(at: GladePaths.agentRuns, includingPropertiesForKeys: nil)) ?? []
    return files.filter { $0.pathExtension == "json" }
      .sorted { $0.lastPathComponent > $1.lastPathComponent }
      .prefix(limit)
      .compactMap { JSONFiles.read(AssistantRun.self, from: $0) }
  }

  /// How many runs Glade started by itself since midnight.
  public static func proactiveRunsToday() -> Int {
    let midnight = Calendar.current.startOfDay(for: Date())
    return runs(limit: 200).filter { $0.proactive && $0.date >= midnight }.count
  }

  private static func file(for record: AssistantRun) -> URL {
    GladePaths.agentRuns.appendingPathComponent("\(Int(record.date.timeIntervalSince1970))-\(record.id.prefix(8)).json")
  }

  private static func save(_ record: AssistantRun) {
    do {
      try JSONFiles.write(record, to: file(for: record))
    } catch {
      Log.warning(.agent, "Couldn’t save the run record: \(error)")
    }
    // Keep the newest 100 records.
    let files = ((try? FileManager.default.contentsOfDirectory(at: GladePaths.agentRuns, includingPropertiesForKeys: nil)) ?? [])
      .sorted { $0.lastPathComponent > $1.lastPathComponent }
    for old in files.dropFirst(100) { try? FileManager.default.removeItem(at: old) }
  }

  private static func amend(runID: String, _ change: (inout AssistantRun) -> Void) {
    guard var record = runs(limit: 20).first(where: { $0.id == runID }) else { return }
    change(&record)
    try? JSONFiles.write(record, to: file(for: record))
  }

  // MARK: Parsing

  private struct RawAdvice: Decodable {
    struct Note: Decodable {
      var id: String
      var why: String

      init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        why = (try? c.decodeIfPresent(String.self, forKey: .why)) ?? ""
      }

      enum CodingKeys: String, CodingKey { case id, why }
    }

    struct Escalate: Decodable {
      var needed: Bool?
      var why: String?
    }

    var summary: String?
    var select: [Note]?
    var deselect: [Note]?
    var review: [Note]?
    var escalate: Escalate?
  }

  static func decode<T: Decodable>(_ type: T.Type, from text: String, provider: String) throws -> T {
    guard let json = JSONExtractor.firstObject(in: text) else {
      throw AgentError.badReply(provider: provider, detail: "There was no JSON in the answer.")
    }
    do {
      return try JSONDecoder().decode(type, from: Data(json.utf8))
    } catch {
      throw AgentError.badReply(provider: provider, detail: "The JSON didn’t have the expected shape (\(error.localizedDescription)).")
    }
  }

  private static func clip(_ text: String) -> String {
    String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(220))
  }
}
