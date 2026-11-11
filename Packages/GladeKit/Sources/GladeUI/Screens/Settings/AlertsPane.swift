import AppKit
import GladeKit
import SwiftUI

/// When Glade speaks up: low storage, memory pressure, a busy processor or graphics
/// chip, and how long it waits before repeating itself.
struct AlertsPane: View {
  @Environment(AppModel.self) private var model
  @State private var askedForNotifications = false
  @State private var confirmsAutoClean = false

  private static let quietChoices: [(minutes: Double, title: String)] = [
    (15, "15 minutes"), (60, "1 hour"), (360, "6 hours"), (1440, "1 day"),
  ]

  var body: some View {
    @Bindable var model = model
    let automation = model.config.automation
    Form {
      Section {
        Toggle("Alerts", isOn: $model.config.automation.enabled)
        LabeledContent("Notifications") {
          if model.notificationsAllowed {
            Label("Allowed", systemImage: "checkmark.circle.fill")
              .labelStyle(.titleAndIcon)
              .foregroundStyle(.secondary)
          } else if askedForNotifications {
            Button("Open Notification Settings") {
              if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                NSWorkspace.shared.open(url)
              }
            }
          } else {
            Button("Allow Notifications") {
              Task {
                await model.requestNotifications()
                askedForNotifications = true
              }
            }
          }
        }
      }

      Group {
        Section("Storage") {
          alertRow("Free space below", isOn: $model.config.automation.storageAlerts) {
            MenuPicker("Free space threshold", value: $model.config.automation.storageFreeGB,
                       options: [5, 10, 15, 20, 30, 50, 75, 100, 150, 200]) { "\(Int($0)) GB" }
          }
          LabeledContent {
            Toggle("Clear caches automatically", isOn: Binding(
              get: { automation.autoCleanOnLowStorage },
              set: { on in
                if on { confirmsAutoClean = true } else { model.config.automation.autoCleanOnLowStorage = false }
              }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
          } label: {
            HStack(spacing: Metrics.s) {
              Text("Clear caches automatically")
              LevelTag(title: CleanLevel.careful.title)
            }
          }
          .disabled(!automation.storageAlerts)
        }

        Section("Performance") {
          alertRow("Memory pressure", isOn: $model.config.automation.memoryAlerts) { EmptyView() }
          alertRow("Processor above", isOn: $model.config.automation.cpuAlerts) {
            threshold("Processor", percent: $model.config.automation.cpuPercent, minutes: $model.config.automation.cpuMinutes)
              .disabled(!automation.cpuAlerts)
          }
          alertRow("Graphics above", isOn: $model.config.automation.gpuAlerts) {
            threshold("Graphics", percent: $model.config.automation.gpuPercent, minutes: $model.config.automation.gpuMinutes)
              .disabled(!automation.gpuAlerts)
          }
        }

        Section {
          LabeledContent("Don’t repeat an alert for") {
            MenuPicker("Don’t repeat an alert for", value: $model.config.automation.quietMinutes,
                       options: Self.quietChoices.map(\.minutes)) { minutes in
              Self.quietChoices.first { $0.minutes == minutes }?.title ?? "\(Int(minutes)) minutes"
            }
          }
        }
      }
      .disabled(!automation.enabled)
    }
    .task { await model.refreshPermissions() }
    .confirmationDialog("Clear caches without asking?", isPresented: $confirmsAutoClean) {
      Button("Clear Automatically") { model.config.automation.autoCleanOnLowStorage = true }
    } message: {
      Text("When space runs low, Glade will run the Careful clean by itself. Only things that rebuild themselves are removed.")
    }
  }

  /// One alert: its name, then its threshold and its switch, aligned at the trailing edge.
  private func alertRow(_ title: String, isOn: Binding<Bool>, @ViewBuilder threshold: () -> some View) -> some View {
    LabeledContent(title) {
      HStack(spacing: Metrics.m) {
        threshold()
        Toggle(title, isOn: isOn)
          .toggleStyle(.switch)
          .labelsHidden()
      }
    }
  }

  /// "80% ⌄ for 5 min ⌄"
  private func threshold(_ title: String, percent: Binding<Double>, minutes: Binding<Double>) -> some View {
    HStack(spacing: Metrics.xs) {
      MenuPicker("\(title) threshold", value: percent, options: [50, 60, 70, 80, 90, 95, 100]) { "\(Int($0))%" }
      Text("for")
        .foregroundStyle(.secondary)
      MenuPicker("\(title) duration", value: minutes, options: [1, 2, 5, 10, 15, 30, 60]) { "\(Int($0)) min" }
    }
  }
}

/// A small grey tag naming a clean level, so a setting says how bold it is.
private struct LevelTag: View {
  var title: String

  var body: some View {
    Text(title)
      .font(.caption)
      .foregroundStyle(.secondary)
      .padding(.horizontal, 6)
      .padding(.vertical, 1)
      .background(Palette.track, in: .capsule)
  }
}
