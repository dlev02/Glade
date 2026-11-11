import Foundation
import FoundationModels

/// Helpers for Apple's on-device model that don't depend on a provider, so prompts can be
/// trimmed to fit its small context before a request is made.
public enum AppleModel {
  /// The on-device model's context window in tokens (8192 on macOS 27, 4096 before).
  public static var contextTokens: Int { SystemLanguageModel.default.contextSize }

  /// How many tokens the text takes for the on-device model. Counted by the model on
  /// macOS 26.4 and later; an estimate (about 3.5 characters per token) before that or
  /// when counting fails.
  public static func tokenCount(_ text: String) async -> Int {
    if #available(macOS 26.4, *), let count = try? await SystemLanguageModel.default.tokenCount(for: text) {
      return count
    }
    return Int((Double(text.utf8.count) / 3.5).rounded(.up))
  }

  /// Plain-English text for a system model that can't be used.
  static func reason(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
    switch reason {
    case .deviceNotEligible: "This Mac can’t run Apple Intelligence."
    case .appleIntelligenceNotEnabled: "Turn on Apple Intelligence in System Settings."
    case .modelNotReady: "The model is still downloading."
    @unknown default: "Apple Intelligence isn’t ready."
    }
  }

  /// Runs `body`, abandoning it after `seconds`.
  static func withTimeout<T: Sendable>(_ seconds: TimeInterval, provider: String, _ body: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask { try await body() }
      group.addTask {
        try await Task.sleep(for: .seconds(max(1, seconds)))
        throw AgentError.timedOut(provider: provider, seconds: Int(seconds.rounded()))
      }
      defer { group.cancelAll() }
      guard let first = try await group.next() else {
        throw AgentError.failed(provider: provider, detail: "No answer.")
      }
      return first
    }
  }

  /// Maps the framework's errors to `AgentError`.
  static func map(_ error: Error, provider: String, timeout: TimeInterval) -> AgentError {
    if let agentError = error as? AgentError { return agentError }
    if #available(macOS 27.0, *), let modelError = error as? LanguageModelError {
      switch modelError {
      case .contextSizeExceeded(let detail):
        return .failed(provider: provider, detail: "The request is too long for this model (\(detail.tokenCount) tokens; it holds \(detail.contextSize)).")
      case .rateLimited:
        return .rateLimited(provider: provider, detail: "Try again later.")
      case .guardrailViolation:
        return .failed(provider: provider, detail: "Apple’s safety checks stopped this request.")
      case .refusal:
        return .failed(provider: provider, detail: "The model declined to answer.")
      case .unsupportedLanguageOrLocale:
        return .unavailable(provider: provider, reason: "The model doesn’t support this language.")
      case .timeout:
        return .timedOut(provider: provider, seconds: Int(timeout.rounded()))
      default:
        return .failed(provider: provider, detail: ProviderRun.excerpt(modelError.localizedDescription))
      }
    }
    if let generationError = error as? LanguageModelSession.GenerationError {
      switch generationError {
      case .exceededContextWindowSize:
        return .failed(provider: provider, detail: "The request is too long for this model.")
      case .rateLimited, .concurrentRequests:
        return .rateLimited(provider: provider, detail: "Try again later.")
      case .guardrailViolation:
        return .failed(provider: provider, detail: "Apple’s safety checks stopped this request.")
      case .refusal:
        return .failed(provider: provider, detail: "The model declined to answer.")
      case .unsupportedLanguageOrLocale:
        return .unavailable(provider: provider, reason: "The model doesn’t support this language.")
      case .assetsUnavailable:
        return .unavailable(provider: provider, reason: "The model is still downloading.")
      default:
        return .failed(provider: provider, detail: ProviderRun.excerpt(generationError.localizedDescription))
      }
    }
    if error is CancellationError { return .failed(provider: provider, detail: "Cancelled.") }
    return .failed(provider: provider, detail: ProviderRun.excerpt(error.localizedDescription))
  }

  static let options = GenerationOptions(temperature: 0.2, maximumResponseTokens: 1500)
}

/// Apple Intelligence's on-device model. Runs entirely on this Mac, so nothing leaves it.
/// Its context is small (8192 tokens on macOS 27), so send it a trimmed prompt: see
/// `contextTokens` and `AppleModel.tokenCount(_:)`.
public struct AppleModelProvider: AgentProvider {
  public let id = "apple"
  public let name = "Apple Intelligence"
  public let isLocal = true

  public init() {}

  /// The model's context window in tokens, shared by the instructions, prompt and reply.
  public var contextTokens: Int { AppleModel.contextTokens }

  public func status() async -> ProviderStatus {
    let state: ProviderStatus.State
    switch SystemLanguageModel.default.availability {
    case .available: state = .ready
    case .unavailable(let reason): state = .unavailable(reason: AppleModel.reason(reason))
    }
    return ProviderStatus(id: id, name: name, state: state, version: ProcessInfo.processInfo.operatingSystemVersionString, isLocal: true, supportsEffort: false)
  }

  public func complete(_ request: AgentRequest) async throws -> AgentReply {
    let model = SystemLanguageModel.default
    if case .unavailable(let reason) = model.availability {
      throw AgentError.unavailable(provider: name, reason: AppleModel.reason(reason))
    }
    let started = Date()
    let name = name, id = id
    do {
      let reply = try await AppleModel.withTimeout(request.timeout, provider: name) {
        let session = LanguageModelSession(model: model, instructions: request.system)
        let response = try await session.respond(to: request.prompt, options: AppleModel.options)
        var input: Int?, output: Int?
        if #available(macOS 27.0, *) {
          input = response.usage.input.totalTokenCount
          output = response.usage.output.totalTokenCount
        }
        let text = request.jsonSchema != nil ? try JSONExtractor.objectReply(response.content, provider: name) : response.content
        return AgentReply(text: text, provider: id, model: "on-device", inputTokens: input, outputTokens: output, duration: Date().timeIntervalSince(started))
      }
      ProviderRun.logSuccess(reply)
      return reply
    } catch {
      let mapped = AppleModel.map(error, provider: name, timeout: request.timeout)
      ProviderRun.logFailure(provider: id, model: "on-device", status: -1, duration: Date().timeIntervalSince(started), reason: ProviderRun.excerpt(mapped.localizedDescription, limit: 120))
      throw mapped
    }
  }
}

/// Apple's Private Cloud Compute model (macOS 27 and later). Requests leave this Mac for
/// Apple's servers, so it isn't local, though Apple designed those servers so that it
/// can't read or keep what's sent. Apple only lets apps use it with an entitlement it
/// grants on request; until Glade has one, every call fails, so `status()` reports it
/// unavailable unless a call has already worked in this process.
public struct ApplePrivateCloudProvider: AgentProvider {
  public let id = "apple-cloud"
  public let name = "Apple Private Cloud Compute"
  public let isLocal = false
  static let noAccess = "Apple hasn’t granted this app access to Private Cloud Compute yet."

  public init() {}

  /// Whether a call has worked in this process: `nil` until one has been made.
  static var probeResult: Bool? {
    ProviderCache.shared.value("apple-cloud:probe").map { $0.first == "yes" }
  }

  static func record(_ worked: Bool) {
    ProviderCache.shared.set("apple-cloud:probe", [worked ? "yes" : "no"])
  }

  /// The context window in tokens, or `nil` before macOS 27 or when it can't be read.
  public func contextTokens() async -> Int? {
    guard #available(macOS 27.0, *) else { return nil }
    return try? await PrivateCloudComputeLanguageModel().contextSize
  }

  public func status() async -> ProviderStatus {
    guard #available(macOS 27.0, *) else {
      return ProviderStatus(id: id, name: name, state: .unavailable(reason: "Needs macOS 27 or later."))
    }
    let model = PrivateCloudComputeLanguageModel()
    let state: ProviderStatus.State
    switch model.availability {
    case .available:
      state = Self.probeResult == true ? .ready : .unavailable(reason: Self.noAccess)
    case .unavailable(let reason):
      switch reason {
      case .deviceNotEligible: state = .unavailable(reason: "This Mac can’t use Private Cloud Compute.")
      case .systemNotReady: state = .unavailable(reason: "Apple Intelligence isn’t ready yet.")
      @unknown default: state = .unavailable(reason: "Private Cloud Compute isn’t available.")
      }
    }
    return ProviderStatus(id: id, name: name, state: state, version: ProcessInfo.processInfo.operatingSystemVersionString)
  }

  /// Makes one tiny request to learn whether this app may use Private Cloud Compute.
  /// Runs at most once per process; later calls return the first answer.
  public func probe() async -> Bool {
    if let known = Self.probeResult { return known }
    let worked = (try? await complete(AgentRequest(system: "Reply with OK.", prompt: "OK", timeout: 20))) != nil
    Self.record(worked)
    return worked
  }

  public func complete(_ request: AgentRequest) async throws -> AgentReply {
    guard #available(macOS 27.0, *) else {
      throw AgentError.unavailable(provider: name, reason: "Needs macOS 27 or later.")
    }
    if Self.probeResult == false {
      throw AgentError.unavailable(provider: name, reason: Self.noAccess)
    }
    let model = PrivateCloudComputeLanguageModel()
    if case .unavailable = model.availability {
      throw AgentError.unavailable(provider: name, reason: "Private Cloud Compute isn’t available on this Mac right now.")
    }
    let started = Date()
    let name = name, id = id
    do {
      let reply = try await AppleModel.withTimeout(request.timeout, provider: name) {
        let session = LanguageModelSession(model: model, instructions: request.system)
        let response = try await session.respond(to: request.prompt, options: AppleModel.options)
        let text = request.jsonSchema != nil ? try JSONExtractor.objectReply(response.content, provider: name) : response.content
        return AgentReply(
          text: text, provider: id, model: "private-cloud-compute",
          inputTokens: response.usage.input.totalTokenCount,
          outputTokens: response.usage.output.totalTokenCount,
          duration: Date().timeIntervalSince(started)
        )
      }
      Self.record(true)
      ProviderRun.logSuccess(reply)
      return reply
    } catch {
      let described = "\(error) \(error.localizedDescription)"
      var mapped = AppleModel.map(error, provider: name, timeout: request.timeout)
      if described.contains("1046") || described.localizedCaseInsensitiveContains("entitlement") || described.contains("ModelManagerError") {
        Self.record(false)
        mapped = .unavailable(provider: name, reason: Self.noAccess)
      }
      ProviderRun.logFailure(provider: id, model: "private-cloud-compute", status: -1, duration: Date().timeIntervalSince(started), reason: ProviderRun.excerpt(described, limit: 160))
      throw mapped
    }
  }
}
