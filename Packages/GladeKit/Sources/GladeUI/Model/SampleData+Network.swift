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
    return state
  }
}
