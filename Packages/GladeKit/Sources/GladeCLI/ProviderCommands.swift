import ArgumentParser
import Foundation
import GladeKit

struct Providers: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "List the AI assistants Glade can ask, and whether each is ready."
  )

  @OptionGroup var output: OutputOptions

  func run() async throws {
    let started = Date()
    let statuses = await AgentProviders.statuses()
    let elapsed = Date().timeIntervalSince(started)
    emit(statuses, json: output.json) {
      for status in statuses {
        let version = status.version.map { " \($0)" } ?? ""
        let flags = [status.isLocal ? "on this Mac" : nil, status.verified ? nil : "unverified"].compactMap { $0 }
        print("\(status.id.padding(toLength: 12, withPad: " ", startingAt: 0)) \(Self.describe(status.state))  \(status.name)\(version)\(flags.isEmpty ? "" : " (\(flags.joined(separator: ", ")))")")
        if let path = status.path { print("\(String(repeating: " ", count: 13))\(Redactor.tilde(path))") }
        if !status.models.isEmpty {
          let shown = status.models.prefix(8).joined(separator: ", ")
          print("\(String(repeating: " ", count: 13))models: \(shown)\(status.models.count > 8 ? ", … \(status.models.count - 8) more" : "")")
        }
      }
      print("\nChecked in \(String(format: "%.1f", elapsed))s")
    }
  }

  static func describe(_ state: ProviderStatus.State) -> String {
    switch state {
    case .ready: "ready"
    case .notInstalled: "not installed"
    case .needsSignIn(let hint): "needs sign-in: \(hint)"
    case .unavailable(let reason): "unavailable: \(reason)"
    }
  }
}

struct Prompt: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Send one prompt straight to an assistant and print the reply. For checking connectors."
  )

  @Argument(help: "The prompt.")
  var prompt: String

  @Option(name: .long, help: "Provider id (see `providers`). Defaults to the first ready one in your settings' order.")
  var provider: String?

  @Option(name: .long, help: "Model name to pass through.")
  var model: String?

  @Option(name: .long, help: "automatic, low, medium, high or max.")
  var effort = "automatic"

  @Option(name: .long, help: "System prompt.")
  var system = "You are a concise assistant."

  @Option(name: .long, help: "A JSON Schema the reply must match; the reply is then a JSON object only.")
  var schema: String?

  @Option(name: .long, help: "Seconds before giving up.")
  var timeout: Double = 120

  @OptionGroup var output: OutputOptions

  struct Failure: Encodable {
    var provider: String
    var error: String
  }

  func run() async throws {
    let chosen: (any AgentProvider)?
    if let provider {
      guard let found = AgentProviders.provider(id: provider) else {
        throw ValidationError("No provider called \(provider). Run `\(Brand.cli) providers`.")
      }
      chosen = found
    } else {
      chosen = await AgentProviders.firstReady(order: AgentProviders.all.map(\.id))
    }
    guard let chosen else { throw ValidationError("No assistant is ready. Run `\(Brand.cli) providers`.") }

    guard let effort = Effort(rawValue: effort) else {
      throw ValidationError("Effort must be one of: \(Effort.allCases.map(\.rawValue).joined(separator: ", ")).")
    }
    let request = AgentRequest(system: system, prompt: prompt, model: model, effort: effort, timeout: timeout, jsonSchema: schema)
    do {
      let reply = try await chosen.complete(request)
      emit(reply, json: output.json) {
        print(reply.text)
        var facts = ["\(reply.provider)", reply.model ?? "default model", String(format: "%.1fs", reply.duration)]
        if let input = reply.inputTokens, let out = reply.outputTokens { facts.append("\(input) in / \(out) out tokens") }
        if let cost = reply.costUSD { facts.append(String(format: "$%.4f", cost)) }
        fflush(stdout)
        FileHandle.standardError.write(Data("\n— \(facts.joined(separator: " · "))\n".utf8))
      }
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      if output.json {
        print(JSONFiles.string(Failure(provider: chosen.id, error: message)))
      } else {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
      }
      throw ExitCode.failure
    }
  }
}
