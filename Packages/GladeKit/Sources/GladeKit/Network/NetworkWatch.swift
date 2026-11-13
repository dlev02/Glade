import Foundation

/// Watches latency second by second to the router, the provider and the internet, with
/// which app was busiest at each moment, so a spike can be tied to its cause. One ping
/// a second to each, about 10 KB a minute in all.
public struct NetworkWatch: Codable, Sendable, Equatable {
  public struct Sample: Codable, Sendable, Equatable {
    public var date: Date
    /// Milliseconds; `nil` when that reply was lost or there was none.
    public var router: Double?
    public var provider: Double?
    public var internet: Double?
    public var busiest: String?
    /// Bytes a second this Mac was sending and receiving.
    public var sending: Double
    public var receiving: Double

    public func value(_ kind: NetworkTargets.Kind) -> Double? {
      switch kind {
      case .router: router
      case .provider: provider
      case .internet: internet
      }
    }
  }

  public struct Spike: Codable, Sendable, Equatable {
    public var date: Date
    public var kind: NetworkTargets.Kind
    public var milliseconds: Double?
    /// What was busiest then, and how much it was sending.
    public var busiest: String?
    public var sending: Double
  }

  public var started: Date
  public var samples: [Sample]
  public var summary: [NetworkStatus.Latency]
  public var spikes: [Spike]

  /// - Parameter onSample: Called once a second with the newest sample.
  public static func run(
    seconds: Int, path: NetworkPath, internetHost: String, onSample: @escaping @Sendable (Sample) -> Void = { _ in }
  ) async -> NetworkWatch {
    let started = Date()
    let targets = await NetworkTargets.current(path: path, internetHost: internetHost)
    let collector = Collector()
    let length = min(600, max(5, seconds))
    await withTaskGroup(of: Void.self) { group in
      for kind in NetworkTargets.Kind.allCases {
        guard let host = targets.host(kind) else { continue }
        group.addTask {
          for await reply in Pinger.stream(host) {
            await collector.add(kind, reply.milliseconds)
            if Task.isCancelled { break }
          }
        }
      }
      group.addTask {
        let sampler = SystemSampler()
        while !Task.isCancelled {
          let apps = await TrafficReader.now(seconds: 2, sampler: sampler)
          await collector.traffic(apps)
        }
      }
      group.addTask {
        for _ in 0..<length {
          try? await Task.sleep(for: .seconds(1))
          onSample(await collector.tick())
        }
      }
      // The clock decides when it’s over.
      await group.next()
      group.cancelAll()
    }
    let samples = await collector.samples
    return summarise(samples, started: started, targets: targets)
  }

  static func summarise(_ samples: [Sample], started: Date, targets: NetworkTargets) -> NetworkWatch {
    var summary: [NetworkStatus.Latency] = []
    var spikes: [Spike] = []
    for kind in NetworkTargets.Kind.allCases {
      guard let host = targets.host(kind) else { continue }
      let values = samples.map { $0.value(kind) }
      let stats = LatencyStats(values)
      summary.append(.init(kind: kind, host: host, stats: stats))
      guard let typical = stats.typical else { continue }
      let threshold = max(typical * 3, typical + 30)
      for sample in samples {
        let value = sample.value(kind)
        if value.map({ $0 > threshold }) ?? true {
          spikes.append(Spike(date: sample.date, kind: kind, milliseconds: value, busiest: sample.busiest, sending: sample.sending))
        }
      }
    }
    return NetworkWatch(started: started, samples: samples, summary: summary, spikes: spikes.sorted { $0.date < $1.date })
  }

  actor Collector {
    var pending: [NetworkTargets.Kind: [Double?]] = [:]
    var apps: [AppTraffic] = []
    var samples: [Sample] = []

    func add(_ kind: NetworkTargets.Kind, _ value: Double?) { pending[kind, default: []].append(value) }
    func traffic(_ apps: [AppTraffic]) { self.apps = apps }

    /// The second just gone: the slowest reply from each place, a loss counting as none.
    func tick() -> Sample {
      func take(_ kind: NetworkTargets.Kind) -> Double? {
        let values = pending[kind] ?? []
        pending[kind] = []
        return values.compactMap { $0 }.max()
      }
      let busiest = apps.first.flatMap { $0.total >= 50_000 ? $0.name : nil }
      let sample = Sample(
        date: Date(), router: take(.router), provider: take(.provider), internet: take(.internet), busiest: busiest,
        sending: apps.map(\.sent).reduce(0, +), receiving: apps.map(\.received).reduce(0, +)
      )
      samples.append(sample)
      return sample
    }
  }
}
