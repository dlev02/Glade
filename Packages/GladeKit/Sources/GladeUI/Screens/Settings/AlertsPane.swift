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
        Section("Low Storage") {
          Toggle("Alert when free space is low", isOn: $model.config.automation.storageAlerts)
          LabeledContent("Below") {
            HStack(spacing: Metrics.s) {
              Slider(value: Binding(
                get: { automation.storageFreeGB },
                set: { model.config.automation.storageFreeGB = ($0 / 5).rounded() * 5 }
              ), in: 5...200)
                .labelsHidden()
                .frame(width: 180)
                .accessibilityLabel("Free space threshold")
                .accessibilityValue("\(Int(automation.storageFreeGB)) gigabytes")
              Text("\(Int(automation.storageFreeGB)) GB")
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
            }
          }
          .disabled(!automation.storageAlerts)
          Toggle(isOn: Binding(
            get: { automation.autoCleanOnLowStorage },
            set: { on in
              if on { confirmsAutoClean = true } else { model.config.automation.autoCleanOnLowStorage = false }
            }
          )) {
            HStack(spacing: Metrics.s) {
              Text("Clear caches automatically")
              LevelTag(title: CleanLevel.careful.title)
            }
          }
          .disabled(!automation.storageAlerts)
        }

        Section("Memory") {
          Toggle("Alert when memory is under pressure", isOn: $model.config.automation.memoryAlerts)
        }

        Section("Processor") {
          Toggle("Alert when the processor stays busy", isOn: $model.config.automation.cpuAlerts)
          threshold(percent: $model.config.automation.cpuPercent, minutes: $model.config.automation.cpuMinutes)
            .disabled(!automation.cpuAlerts)
        }

        Section("Graphics") {
          Toggle("Alert when graphics stay busy", isOn: $model.config.automation.gpuAlerts)
          threshold(percent: $model.config.automation.gpuPercent, minutes: $model.config.automation.gpuMinutes)
            .disabled(!automation.gpuAlerts)
        }

        Section {
          Picker("Don’t repeat an alert for", selection: $model.config.automation.quietMinutes) {
            ForEach(Self.quietChoices, id: \.minutes) { choice in
              Text(choice.title).tag(choice.minutes)
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

  private func threshold(percent: Binding<Double>, minutes: Binding<Double>) -> some View {
    Group {
      LabeledContent("Above") {
        Stepper(value: percent, in: 50...100, step: 5) {
          Text("\(Int(percent.wrappedValue))%").monospacedDigit()
        }
      }
      LabeledContent("For") {
        Stepper(value: minutes, in: 1...60, step: 1) {
          Text("\(Int(minutes.wrappedValue)) min").monospacedDigit()
        }
      }
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
