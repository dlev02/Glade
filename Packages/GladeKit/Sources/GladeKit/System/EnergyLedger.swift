import Foundation
import Synchronization

/// Works out how much energy each app used between two process listings, from the
/// energy the kernel bills each process. It keeps only the last counter per process.
public final class EnergyLedger: Sendable {
  private struct Mark: Sendable {
    var start: Date?
    var nanojoules: UInt64
  }

  private struct State: Sendable {
    var time: Date?
    var marks: [Int32: Mark] = [:]
  }

  private let state = Mutex(State())

  public init() {}

  /// Joules each app used since the last call, and the seconds that covers. The first
  /// call only sets the starting point and returns `nil`.
  public func measure(processes: [ProcessSample], apps: [AppUsage], now: Date = Date()) -> (apps: [BatteryHistory.AppEnergy], seconds: Double)? {
    var marks: [Int32: Mark] = [:]
    marks.reserveCapacity(processes.count)
    for process in processes {
      if let energy = process.energyNanojoules { marks[process.pid] = Mark(start: process.startTime, nanojoules: energy) }
    }
    let previous = state.withLock { state -> State in
      let old = state
      state = State(time: now, marks: marks)
      return old
    }
    guard let since = previous.time else { return nil }

    var used: [Int32: Double] = [:]
    for (pid, mark) in marks {
      if let old = previous.marks[pid], old.start == mark.start {
        used[pid] = Double(mark.nanojoules &- min(mark.nanojoules, old.nanojoules)) / 1e9
      } else if let start = mark.start, start >= since {
        // Started since the last listing: all of its energy is new.
        used[pid] = Double(mark.nanojoules) / 1e9
      }
    }
    var result: [BatteryHistory.AppEnergy] = []
    for app in apps {
      let joules = app.pids.reduce(0) { $0 + (used[$1] ?? 0) }
      if joules > 0 { result.append(.init(id: app.id, name: app.name, bundlePath: app.bundlePath, joules: joules)) }
    }
    return (result, now.timeIntervalSince(since))
  }
}
