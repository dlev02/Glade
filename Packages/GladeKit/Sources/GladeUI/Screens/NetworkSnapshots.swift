import GladeKit
import SwiftUI

/// The network screens that can be drawn to an image with `glade snapshot <name>`, all
/// from made-up readings so they look the same on any Mac.
enum NetworkSnapshots {
  static let all: [String: (AppModel) -> AnyView] = [
    // With --live, this Mac’s own reading (loaded by the snapshotter).
    "network": { model in
      model.networkSetupAsked = true
      return AnyView(NavigationStack { NetworkScreen() })
    },
    "network-uploading": { model in
      model.loadNetworkSample(SampleData.sampleNetwork(.uploading))
      model.networkSetupAsked = true
      return AnyView(NavigationStack { NetworkScreen() })
    },
    "network-weak": { model in
      model.loadNetworkSample(SampleData.sampleNetwork(.weakWiFi))
      model.networkSetupAsked = true
      return AnyView(NavigationStack { NetworkScreen() })
    },
    // The whole window on Network, for the README and release notes: --width 1212 --height 852.
    "window-network": { model in
      model.loadNetworkSample(SampleData.sampleNetwork(.healthy))
      model.networkSetupAsked = true
      model.section = .network
      return AnyView(RootView())
    },
  ]
}
