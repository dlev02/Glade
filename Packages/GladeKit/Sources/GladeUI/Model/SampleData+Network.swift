import Foundation
import GladeKit

extension SampleData {
  /// The Network section on made-up readings, for screenshots and demo mode.
  static func sampleNetwork(_ scene: NetworkSample.Scene, now: Date = Date()) -> NetworkState {
    let readings = NetworkSample.readings(scene, now: now)
    var state = NetworkState()
    state.status = readings.status
    state.live = readings.live
    state.traffic = readings.traffic
    state.wifi = readings.status.wifi
    state.verdicts = readings.status.verdicts
    state.tests = readings.tests
    state.history = readings.history
    state.signal = readings.signal.enumerated().map { index, rssi in
      HistoryChart.Point(date: now.addingTimeInterval(Double(index - readings.signal.count) * 2), value: Double(rssi + 90) / 60 * 100)
    }
    state.littleSnitch = try? LittleSnitchRules.parse(Data(sampleRules.utf8), now: now.addingTimeInterval(-3 * 86_400))
    return state
  }

  /// A real reading of this Mac’s network, for `glade snapshot network --live`: one
  /// burst of pings stands in for the live chart.
  static func liveNetwork() async -> NetworkState {
    let status = await NetworkStatus.current(devices: true)
    var state = NetworkState()
    state.status = status
    state.wifi = status.wifi
    state.traffic = status.apps
    state.verdicts = status.verdicts
    state.tests = SpeedTest.history()
    state.history = NetworkHistoryStore.load()
    state.littleSnitch = LittleSnitchRules.load()
    return state
  }

  /// Made-up Little Snitch rules with one of each thing Glade notices.
  static let sampleRules = """
    {"name":"Sample","rules":[
     {"action":"allow","process":"/Applications/Safari.app/Contents/MacOS/Safari","remote":"any"},
     {"action":"allow","process":"/System/Applications/Music.app/Contents/MacOS/Music","remote-domains":["apple.com"]},
     {"action":"allow","process":"/System/Applications/Music.app/Contents/MacOS/Music","remote-domains":["apple.com"]},
     {"action":"deny","process":"/Applications/Old Editor.app/Contents/MacOS/Old Editor","remote-domains":["updates.example"]},
     {"action":"allow","process":"any","remote":"any","disabled":false},
     {"action":"deny","process":"any","remote-domains":["tracker.example"]}
    ],"denied-remote-domains":["ads.example","beacon.example","pixel.example"]}
    """
}
