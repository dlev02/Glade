import GladeKit
import SwiftUI

/// What Glade never touches: the built-in protected areas, which of them can be
/// lifted, and the person's own protected folders.
struct ProtectionPane: View {
  @Environment(AppModel.self) private var model
  @State private var zones: [ProtectedZone] = ProtectedZones.builtIn
  @State private var pendingUnlock: ProtectedZone?
  @State private var showsAlwaysProtected = DemoState.value("demoExpandProtection") != nil
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    @Bindable var model = model
    let locked = zones.filter(\.locked)
    let liftable = zones.filter { !$0.locked }
    Form {
      Section("Protected Unless You Turn It Off") {
        ForEach(liftable) { zone in
          Toggle(isOn: binding(for: zone)) {
            HStack(alignment: .top, spacing: Metrics.m) {
              ZoneIcon(zone: zone)
              zoneText(zone)
            }
          }
        }
      }

      Section("Your Protected Folders") {
        FolderRows(paths: $model.config.protectedPaths, prompt: "Protect", confirmsRemoval: true)
      }

      Section {
        DisclosureGroup(isExpanded: $showsAlwaysProtected) {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(locked.enumerated()), id: \.element.id) { index, zone in
              if index > 0 {
                Divider().padding(.leading, 28 + Metrics.m)
              }
              HStack(alignment: .top, spacing: Metrics.m) {
                ZoneIcon(zone: zone)
                zoneText(zone)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.vertical, Metrics.s)
              .accessibilityElement(children: .combine)
              .accessibilityValue("Always protected")
            }
          }
          .padding(.top, Metrics.xs)
        } label: {
          // The whole row opens the list, not only the small triangle.
          Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { showsAlwaysProtected.toggle() }
          } label: {
            LabeledContent("Always Protected") {
              Text(locked.count == 1 ? "1 area" : "\(locked.count) areas")
                .monospacedDigit()
            }
            .contentShape(.rect)
          }
          .buttonStyle(.plain)
          .accessibilityValue(showsAlwaysProtected ? "Expanded" : "Collapsed")
          .accessibilityIdentifier("protection.alwaysProtected")
        }
      } footer: {
        Text("Protected areas are never scanned, listed, or shown to an AI.")
          .foregroundStyle(.secondary)
      }
    }
    .onAppear { zones = Self.allZones(config: model.config) }
    .confirmationDialog(
      "Stop protecting \(pendingUnlock?.title ?? "")?",
      isPresented: Binding(get: { pendingUnlock != nil }, set: { if !$0 { pendingUnlock = nil } }),
      presenting: pendingUnlock
    ) { zone in
      Button("Stop Protecting", role: .destructive) {
        if !model.config.unlockedZones.contains(zone.id) { model.config.unlockedZones.append(zone.id) }
      }
    } message: { zone in
      Text("\(zone.reason) Glade will be able to scan, list and remove what’s there.")
    }
  }

  private func zoneText(_ zone: ProtectedZone) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(zone.title)
        .frame(maxWidth: .infinity, alignment: .leading)
      Text(zone.reason)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func binding(for zone: ProtectedZone) -> Binding<Bool> {
    Binding(
      get: { !model.config.unlockedZones.contains(zone.id) },
      set: { protected in
        if protected {
          model.config.unlockedZones.removeAll { $0 == zone.id }
        } else {
          pendingUnlock = zone
        }
      }
    )
  }

  /// The built-in zones, plus iCloud Desktop & Documents when this Mac syncs them.
  /// Asked with nothing unlocked, so a zone the person switched off still shows.
  private static func allZones(config: GladeConfig) -> [ProtectedZone] {
    var everything = config
    everything.unlockedZones = []
    everything.protectedPaths = []
    let extra = Protection(config: everything).zones.filter { zone in
      !ProtectedZones.builtIn.contains { $0.id == zone.id }
    }
    return ProtectedZones.builtIn + extra
  }
}
