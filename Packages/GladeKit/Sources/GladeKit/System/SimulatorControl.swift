import Foundation

public enum SimulatorControlError: Error, LocalizedError, Equatable {
  case invalidUDID(String)
  case notFound(String)
  case ambiguous(String, matches: [String])
  case simctlUnavailable

  public var errorDescription: String? {
    switch self {
    case .invalidUDID(let value): "“\(value)” isn’t a simulator UDID."
    case .notFound(let target): "No booted simulator matches “\(target)”."
    case .ambiguous(let target, let matches): "“\(target)” matches more than one booted simulator: \(matches.joined(separator: ", "))."
    case .simctlUnavailable: "xcrun simctl isn’t available, so simulators can’t be shut down."
    }
  }
}

/// What happened when a simulator was asked to shut down.
public struct SimulatorActionResult: Codable, Sendable {
  public var udid: String
  public var name: String?
  public var setPath: String?
  public var succeeded: Bool
  public var memoryFreedBytes: Int64?
  public var seconds: Double
  /// One plain sentence describing the outcome.
  public var message: String
}

/// Shuts simulators down, like turning a phone off: apps in it stop, its apps and data
/// stay. Nothing here erases or deletes a simulator.
public enum SimulatorControl {
  public static let timeout: TimeInterval = 60

  /// Runs `xcrun simctl [--set <set>] shutdown <udid>`.
  /// - Parameter set: The device set’s folder; `nil` for the standard set.
  public static func shutdown(udid: String, set: String? = nil, name: String? = nil) async throws -> SimulatorActionResult {
    guard UUID(uuidString: udid) != nil else {
      Log.info(.system, "Refused to shut down simulator “\(udid)”: not a UDID")
      throw SimulatorControlError.invalidUDID(udid)
    }
    let label = name.map { "\($0) (\(udid))" } ?? udid
    let standard = set.map { SimulatorDeviceSet.of(path: $0) == .standard } ?? true
    let arguments = ["simctl"] + (standard ? [] : ["--set", set ?? ""]) + ["shutdown", udid]
    let started = Date()
    let result: ShellResult
    do {
      result = try await Shell.run("xcrun", arguments, timeout: timeout)
    } catch {
      Log.warning(.system, "Shut down simulator \(label): simctl couldn’t run: \(error.localizedDescription)")
      throw SimulatorControlError.simctlUnavailable
    }
    let seconds = Date().timeIntervalSince(started)
    let alreadyOff = result.stderr.contains("current state: Shutdown")
    let succeeded = result.succeeded || alreadyOff
    let message: String
    if result.timedOut {
      message = "\(name ?? udid) didn’t shut down within \(Int(timeout)) seconds."
    } else if alreadyOff {
      message = "\(name ?? udid) was already shut down."
    } else if succeeded {
      message = "\(name ?? udid) was shut down. Its apps and data are kept."
    } else {
      let detail = result.stderr.split(separator: "\n").first.map(String.init) ?? "exit \(result.status)"
      message = "\(name ?? udid) couldn’t be shut down: \(detail)"
    }
    if succeeded {
      Log.info(.system, "Shut down simulator \(label)\(standard ? "" : " in \(set ?? "")"): \(alreadyOff ? "already off" : "done") in \(String(format: "%.1f", seconds))s")
    } else {
      Log.warning(.system, "Shut down simulator \(label) failed after \(String(format: "%.1f", seconds))s: \(message)")
    }
    return SimulatorActionResult(udid: udid, name: name, setPath: set, succeeded: succeeded, memoryFreedBytes: nil, seconds: seconds, message: message)
  }

  public static func shutdown(_ simulator: SimulatorUsage) async throws -> SimulatorActionResult {
    var result = try await shutdown(udid: simulator.udid, set: simulator.setPath, name: simulator.name)
    if result.succeeded { result.memoryFreedBytes = simulator.memoryBytes }
    return result
  }

  /// Shuts down every booted simulator judged idle. Skips ones named in `keepRunning` and
  /// ones whose judgement carries a caveat (an IDE that may be showing it), which a
  /// person has to name one by one.
  public static func shutdownIdle(
    sampler: SystemSampler = SystemSampler(), config: GladeConfig = ConfigStore.load()
  ) async -> [SimulatorActionResult] {
    let keep = Set(config.keepRunning.map { $0.lowercased() })
    let all = await sampler.simulators()
    let idle = all.filter { $0.isIdle && $0.note == nil && !keep.contains($0.udid.lowercased()) && !keep.contains($0.name.lowercased()) }
    let uncertain = all.filter { $0.isIdle && $0.note != nil }
    Log.info(.system, "Shut down idle simulators: \(idle.count) idle\(idle.isEmpty ? "" : " (\(idle.map(\.name).joined(separator: ", ")))"), \(uncertain.count) left because an IDE may be showing them")
    var results: [SimulatorActionResult] = []
    for simulator in idle {
      do {
        results.append(try await shutdown(simulator))
      } catch {
        let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        results.append(SimulatorActionResult(
          udid: simulator.udid, name: simulator.name, setPath: simulator.setPath, succeeded: false,
          memoryFreedBytes: nil, seconds: 0, message: message
        ))
      }
    }
    return results
  }

  /// Finds the booted simulator a person or agent means, by UDID or name. A name shared
  /// by devices in different sets is ambiguous.
  public static func resolve(_ target: String, in simulators: [SimulatorUsage]) throws -> SimulatorUsage {
    let wanted = target.trimmingCharacters(in: .whitespaces)
    let lower = wanted.lowercased()
    if UUID(uuidString: wanted) != nil {
      guard let match = simulators.first(where: { $0.udid.lowercased() == lower }) else { throw SimulatorControlError.notFound(wanted) }
      return match
    }
    var matches = simulators.filter { $0.name.lowercased() == lower }
    if matches.isEmpty { matches = simulators.filter { $0.name.lowercased().hasPrefix(lower) } }
    guard let first = matches.first else { throw SimulatorControlError.notFound(wanted) }
    if matches.count > 1 {
      throw SimulatorControlError.ambiguous(wanted, matches: matches.map { "\($0.name) (\($0.deviceSet.title), \($0.udid))" })
    }
    return first
  }
}
