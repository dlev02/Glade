import GladeKit
import SwiftUI

/// The battery screens that can be drawn to an image with `glade snapshot <name>`, all
/// from made-up figures so they look the same on any Mac. Draw `battery` at
/// `--width 940 --height 600` (or `window --section battery`) to check the minimum window.
enum BatterySnapshots {
  static let all: [String: (AppModel) -> AnyView] = [
    "battery": { model in
      model.loadBatterySample(SampleData.sampleBattery(.charging))
      return AnyView(NavigationStack { BatteryScreen(period: .hour) })
    },
    // The whole window on Battery, for the README and release notes: --width 1212 --height 852.
    "window-battery": { model in
      model.loadBatterySample(SampleData.sampleBattery(.charging))
      model.section = .battery
      return AnyView(RootView())
    },
    "battery-on-battery": { model in
      model.loadBatterySample(SampleData.sampleBattery(.onBattery))
      return AnyView(NavigationStack { BatteryScreen(period: .unplugged) })
    },
    "battery-technical": { model in
      model.loadBatterySample(SampleData.sampleBattery(.onBattery))
      return AnyView(NavigationStack { BatteryScreen(period: .hour, detail: .technical) })
    },
    "battery-none": { model in
      model.loadBatterySample(SampleData.sampleBattery(.noBattery))
      return AnyView(NavigationStack { BatteryScreen(period: .hour) })
    },
    "battery-week": { model in
      model.loadBatterySample(SampleData.sampleBattery(.charging))
      return AnyView(NavigationStack { BatteryScreen(range: .week, period: .halfDay) })
    },
    // The battery tile beside memory, processor and graphics; draw at --width 860 for
    // the narrowest window.
    "overview-battery": { model in
      model.loadBatterySample(SampleData.sampleBattery(.onBattery))
      return AnyView(NavigationStack { OverviewScreen() })
    },
    "popover-battery": { model in
      model.loadBatterySample(SampleData.sampleBattery(.onBattery))
      return AnyView(MenuBarView().environment(\.screenOverrides, ScreenOverrides(suggestions: [])))
    },
  ]
}
