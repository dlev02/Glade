import GladeKit
import SwiftUI

/// The Network section: whether it’s on, what it reads, where latency is measured and
/// how long a speed test runs.
struct NetworkPane: View {
  @Environment(AppModel.self) private var model
  @State private var host = ""

  var body: some View {
    @Bindable var model = model
    Form {
      Section {
        Toggle("Show Network and count data used", isOn: $model.config.network.enabled)
        Toggle("Read the router’s status", isOn: $model.config.network.readRouter)
          .disabled(!model.config.network.enabled)
      }

      Section {
        LabeledContent("Internet latency host") {
          TextField("Host", text: $host, prompt: Text(NetworkSettings().internetHost))
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .frame(width: 180)
            .onSubmit(saveHost)
        }
        Picker("Speed test length", selection: $model.config.network.testSeconds) {
          ForEach([10, 15, 20, 30], id: \.self) { seconds in Text("\(seconds) seconds").tag(seconds) }
        }
      } footer: {
        Text("A speed test uses hundreds of megabytes, or gigabytes on a fast line.")
          .foregroundStyle(.secondary)
      }
      .disabled(!model.config.network.enabled)

      Section {
        Toggle("Let agents test speed on a hotspot", isOn: $model.config.network.agentTestsWhenLimited)
      }
      .disabled(!model.config.network.enabled)
    }
    .onAppear { host = model.config.network.internetHost }
    .onDisappear(perform: saveHost)
  }

  /// Only a plain host name or address; anything else keeps the old one.
  private func saveHost() {
    let trimmed = host.trimmingCharacters(in: .whitespaces)
    let valid = !trimmed.isEmpty && !trimmed.hasPrefix("-") && trimmed.count < 254
      && trimmed.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == ":" }
    if valid { model.config.network.internetHost = trimmed } else { host = model.config.network.internetHost }
  }
}
