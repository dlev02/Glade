import Foundation

/// A model served by Ollama on this Mac, reached over its local HTTP API. Nothing is
/// launched; Glade only talks to a server the person is already running.
///
/// Written from the documentation (docs.ollama.com/api); not yet run here.
public struct OllamaProvider: AgentProvider {
  public let id = "ollama"
  public let name = "Ollama"
  public let isLocal = true
  static let base = URL(string: "http://127.0.0.1:11434")

  public init() {}

  public func status() async -> ProviderStatus {
    guard let path = Shell.which("ollama") else {
      return ProviderStatus(id: id, name: name, state: .notInstalled, isLocal: true, verified: false)
    }
    let version = await ProviderCache.shared.version(of: path)
    guard let models = await Self.installedModels() else {
      return ProviderStatus(id: id, name: name, state: .unavailable(reason: "Ollama isn’t running. Open Ollama or run `ollama serve`."), path: path, version: version, isLocal: true, verified: false)
    }
    let state: ProviderStatus.State = models.isEmpty ? .unavailable(reason: "No models are installed. Run `ollama pull` with a model name.") : .ready
    return ProviderStatus(id: id, name: name, state: state, path: path, version: version, isLocal: true, models: models, verified: false)
  }

  public func complete(_ request: AgentRequest) async throws -> AgentReply {
    guard let endpoint = Self.base?.appendingPathComponent("api/chat") else {
      throw AgentError.failed(provider: name, detail: "Bad server address.")
    }
    var model = request.model ?? ""
    if model.isEmpty {
      guard let first = await Self.installedModels()?.first else {
        throw AgentError.unavailable(provider: name, reason: "Ollama isn’t running or has no models.")
      }
      model = first
    }
    var body: [String: Any] = [
      "model": model,
      "stream": false,
      "messages": [["role": "system", "content": request.system], ["role": "user", "content": request.prompt]],
    ]
    if let schema = request.jsonSchema {
      body["format"] = LooseJSON.object(schema) ?? "json"
    }
    var urlRequest = URLRequest(url: endpoint)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = request.timeout
    configuration.timeoutIntervalForResource = request.timeout
    let session = URLSession(configuration: configuration)
    defer { session.finishTasksAndInvalidate() }

    let started = Date()
    let data: Data, response: URLResponse
    do {
      (data, response) = try await session.data(for: urlRequest)
    } catch let error as URLError where error.code == .timedOut {
      ProviderRun.logFailure(provider: id, model: model, status: -1, duration: Date().timeIntervalSince(started), reason: "timed out")
      throw AgentError.timedOut(provider: name, seconds: Int(request.timeout.rounded()))
    } catch let error as URLError where error.code == .cannotConnectToHost {
      throw AgentError.unavailable(provider: name, reason: "Ollama isn’t running. Open Ollama or run `ollama serve`.")
    } catch {
      throw AgentError.failed(provider: name, detail: ProviderRun.excerpt(error.localizedDescription))
    }
    let duration = Date().timeIntervalSince(started)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    let json = LooseJSON.object(String(decoding: data, as: UTF8.self)) ?? [:]
    guard status == 200, let text = (json["message"] as? [String: Any])?["content"] as? String else {
      ProviderRun.logFailure(provider: id, model: model, status: Int32(status), duration: duration, reason: "http \(status)")
      let message = LooseJSON.errorMessage(json["error"]) ?? "HTTP \(status)"
      throw ProviderRun.classify(provider: name, message: message, signInHint: "Ollama doesn’t need a sign-in.")
    }
    let replyText = request.jsonSchema != nil ? try JSONExtractor.objectReply(text, provider: name) : text
    let reply = AgentReply(
      text: replyText, provider: id, model: model,
      inputTokens: LooseJSON.int(json["prompt_eval_count"]),
      outputTokens: LooseJSON.int(json["eval_count"]),
      duration: duration
    )
    ProviderRun.logSuccess(reply, status: Int32(status))
    return reply
  }

  /// The installed model names, or `nil` when the server doesn’t answer within a second.
  static func installedModels() async -> [String]? {
    guard let url = base?.appendingPathComponent("api/tags") else { return nil }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 1
    configuration.timeoutIntervalForResource = 1
    let session = URLSession(configuration: configuration)
    defer { session.finishTasksAndInvalidate() }
    guard let (data, response) = try? await session.data(from: url),
          (response as? HTTPURLResponse)?.statusCode == 200,
          let list = LooseJSON.object(String(decoding: data, as: UTF8.self))?["models"] as? [[String: Any]]
    else { return nil }
    return list.compactMap { $0["name"] as? String }
  }
}
