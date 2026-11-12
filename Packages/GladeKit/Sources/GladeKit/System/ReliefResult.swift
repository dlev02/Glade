import Foundation

/// What carrying out a relief plan did, action by action, and the memory in use
/// before and after as measured.
public struct ReliefResult: Codable, Sendable, Equatable {
  public enum Outcome: String, Codable, Sendable {
    case quit, relaunched, shutDown
    /// Asked to quit but still open when the wait ran out, usually because it’s asking
    /// about unsaved work.
    case stillOpen
    /// Closed before Glade got to it.
    case alreadyGone
    /// Left alone at the last moment: it came to the front, started playing, or is
    /// one Glade never quits.
    case leftAlone
    case failed

    /// It did what was asked.
    public var succeeded: Bool { self == .quit || self == .relaunched || self == .shutDown || self == .alreadyGone }
  }

  public struct Entry: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var kind: ReliefPlan.Action.Kind
    public var outcome: Outcome
    /// The memory it held when the plan was made.
    public var memoryBytes: Int64
    /// One short phrase for anything that didn’t go as asked: "Still open: it may be
    /// asking about unsaved changes".
    public var detail: String?

    public init(id: String, name: String, kind: ReliefPlan.Action.Kind, outcome: Outcome, memoryBytes: Int64, detail: String? = nil) {
      self.id = id
      self.name = name
      self.kind = kind
      self.outcome = outcome
      self.memoryBytes = memoryBytes
      self.detail = detail
    }
  }

  public var date: Date
  public var entries: [Entry]
  /// Memory in use when it started, and a few seconds after the last action.
  public var memoryBefore: Int64
  public var memoryAfter: Int64

  public init(date: Date = Date(), entries: [Entry], memoryBefore: Int64, memoryAfter: Int64) {
    self.date = date
    self.entries = entries
    self.memoryBefore = memoryBefore
    self.memoryAfter = memoryAfter
  }

  /// How long a quit may take before it counts as still open.
  public static let quitTimeout: TimeInterval = 10
  /// How long to let memory settle before measuring it again.
  public static let settleSeconds: Double = 3

  public var problems: [Entry] { entries.filter { !$0.outcome.succeeded } }

  /// Memory in use went down by this much, as measured. Other apps keep working
  /// meanwhile, so it can be more or less than the apps held.
  public var measuredFreedBytes: Int64 { max(0, memoryBefore - memoryAfter) }

  // MARK: Carrying it out

  /// Carries out the chosen actions in order, through the polite quit and the
  /// simulator shutdown, never a force quit. Each app is checked once more just
  /// before it’s asked, so one that has come to the front, started playing or
  /// recording, or begun keeping the Mac awake since the plan was made is left alone.
  /// - Parameter progress: Called before each action with how many are done and the
  ///   name of the next.
  public static func perform(
    _ actions: [ReliefPlan.Action], sampler: SystemSampler = SystemSampler(), config: GladeConfig = ConfigStore.load(),
    progress: (@Sendable (Int, Int, String) -> Void)? = nil
  ) async -> ReliefResult {
    let started = Date()
    let before = await sampler.snapshot().memory.usedBytes
    let reading = await sampler.appsAndSimulators()
    let byID = Dictionary(reading.apps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let keep = Set(config.keepRunning.map { $0.lowercased() })
    Log.info(.system, "Free up memory: \(actions.count) action\(actions.count == 1 ? "" : "s") (\(actions.map(\.name).joined(separator: ", "))), \(Format.bytes(before)) in use")

    var entries: [Entry] = []
    for (index, action) in actions.enumerated() {
      progress?(index, actions.count, action.name)
      var entry = Entry(id: action.id, name: action.name, kind: action.kind, outcome: .failed, memoryBytes: action.memoryBytes)
      switch action.kind {
      case .shutDown:
        guard let udid = action.simulatorUDID else {
          entry.detail = "Not a simulator Glade knows"
          break
        }
        guard let live = reading.simulators.first(where: { $0.udid == udid }) else {
          entry.outcome = .alreadyGone
          break
        }
        if live.inUse {
          entry.outcome = .leftAlone
          entry.detail = "In use now"
          break
        }
        do {
          let result = try await SimulatorControl.shutdown(live)
          entry.outcome = result.succeeded ? .shutDown : .failed
          if !result.succeeded { entry.detail = result.message }
        } catch {
          entry.detail = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
      case .quit, .relaunch:
        guard let app = byID[action.appID] else {
          entry.outcome = .alreadyGone
          break
        }
        if let reason = inUse(app, keep: keep) {
          entry.outcome = .leftAlone
          entry.detail = reason
          Log.info(.system, "Free up memory: left \(app.name) alone: \(reason)")
          break
        }
        do {
          let result = action.kind == .relaunch
            ? try await AppControl.relaunch(app.id, timeout: quitTimeout)
            : try await AppControl.quit(app.id, timeout: quitTimeout)
          if result.exited {
            entry.outcome = action.kind == .relaunch ? .relaunched : .quit
          } else {
            entry.outcome = .stillOpen
            entry.detail = "Still open: it may be asking about unsaved changes"
          }
        } catch AppControlError.notFound {
          entry.outcome = .alreadyGone
        } catch let error as AppControlError {
          if case .systemApp = error { entry.outcome = .leftAlone } else if case .isGlade = error { entry.outcome = .leftAlone }
          entry.detail = error.errorDescription
        } catch {
          entry.detail = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
      }
      entries.append(entry)
    }
    progress?(actions.count, actions.count, "")

    // Quitting hands memory back over a second or two.
    try? await Task.sleep(for: .seconds(settleSeconds))
    let after = await sampler.snapshot().memory.usedBytes
    let result = ReliefResult(date: started, entries: entries, memoryBefore: before, memoryAfter: after)
    let done = entries.filter(\.outcome.succeeded).count
    Log.info(.system, "Free up memory: \(done) of \(entries.count) done in \(String(format: "%.1f", Date().timeIntervalSince(started)))s; in use \(Format.bytes(before)) → \(Format.bytes(after))\(result.problems.isEmpty ? "" : "; not done: " + result.problems.map { "\($0.name) (\($0.outcome.rawValue))" }.joined(separator: ", "))")
    return result
  }

  /// Why an app must be left alone right now, or `nil` when it may be asked to quit.
  public static func inUse(_ app: AppUsage, keep: Set<String>) -> String? {
    if app.isGlade { return "\(Brand.name) itself" }
    if app.isSystem { return "Part of macOS" }
    if app.isFrontmost { return "In use now" }
    if app.isCapturingAudio { return "On a call now" }
    if app.isPlayingAudio { return "Playing sound now" }
    if app.preventingSleep != nil { return "Keeping the Mac awake now" }
    if keep.contains(app.id.lowercased()) || keep.contains(app.name.lowercased())
      || app.bundleIdentifier.map({ keep.contains($0.lowercased()) }) == true
    {
      return "Kept running"
    }
    return nil
  }
}
