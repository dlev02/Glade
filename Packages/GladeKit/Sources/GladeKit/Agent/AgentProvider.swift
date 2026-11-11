import Foundation

/// One question for a model: a system prompt, the prompt itself, and how to run it.
/// Providers run with their tools switched off; the reply is text only.
public struct AgentRequest: Sendable {
  public var system: String
  public var prompt: String
  /// A model name to pass through, or `nil` for the provider's default.
  public var model: String?
  public var effort: Effort
  /// Seconds before the run is abandoned.
  public var timeout: TimeInterval
  /// A JSON Schema the reply must satisfy, used by providers that can enforce one.
  public var jsonSchema: String?

  public init(system: String, prompt: String, model: String? = nil, effort: Effort = .automatic, timeout: TimeInterval = 180, jsonSchema: String? = nil) {
    self.system = system
    self.prompt = prompt
    self.model = model
    self.effort = effort
    self.timeout = timeout
    self.jsonSchema = jsonSchema
  }
}

public struct AgentReply: Sendable, Codable {
  public var text: String
  public var provider: String
  public var model: String?
  public var inputTokens: Int?
  public var outputTokens: Int?
  public var costUSD: Double?
  public var duration: TimeInterval

  public init(text: String, provider: String, model: String? = nil, inputTokens: Int? = nil, outputTokens: Int? = nil, costUSD: Double? = nil, duration: TimeInterval = 0) {
    self.text = text
    self.provider = provider
    self.model = model
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens
    self.costUSD = costUSD
    self.duration = duration
  }
}

public enum AgentError: Error, LocalizedError, Sendable {
  case notInstalled(provider: String)
  /// `hint` is the command or step that signs in.
  case notSignedIn(provider: String, hint: String)
  case unavailable(provider: String, reason: String)
  case rateLimited(provider: String, detail: String)
  case timedOut(provider: String, seconds: Int)
  case failed(provider: String, detail: String)
  /// The reply didn't contain what was asked for.
  case badReply(provider: String, detail: String)

  public var errorDescription: String? {
    switch self {
    case .notInstalled(let provider): "\(provider) isn’t installed."
    case .notSignedIn(let provider, let hint): "\(provider) isn’t signed in. \(hint)"
    case .unavailable(let provider, let reason): "\(provider) isn’t available: \(reason)"
    case .rateLimited(let provider, let detail): "\(provider) has reached its usage limit. \(detail)"
    case .timedOut(let provider, let seconds): "\(provider) didn’t answer within \(seconds) seconds."
    case .failed(let provider, let detail): "\(provider) failed: \(detail)"
    case .badReply(let provider, let detail): "\(provider) gave an answer Glade couldn’t use: \(detail)"
    }
  }
}

public struct ProviderStatus: Sendable, Codable, Identifiable {
  public enum State: Sendable, Codable, Equatable {
    case ready
    case notInstalled
    case needsSignIn(hint: String)
    case unavailable(reason: String)
  }

  public var id: String
  public var name: String
  public var state: State
  /// Where the command-line tool was found, if it is one.
  public var path: String?
  public var version: String?
  /// Runs entirely on this Mac, so it may be shown file contents.
  public var isLocal: Bool
  public var supportsEffort: Bool
  /// Model names worth offering. Empty when the provider has no way to list them.
  public var models: [String]
  /// Whether this integration has been run for real, or follows the tool's documentation only.
  public var verified: Bool

  public init(id: String, name: String, state: State, path: String? = nil, version: String? = nil, isLocal: Bool = false, supportsEffort: Bool = false, models: [String] = [], verified: Bool = true) {
    self.id = id
    self.name = name
    self.state = state
    self.path = path
    self.version = version
    self.isLocal = isLocal
    self.supportsEffort = supportsEffort
    self.models = models
    self.verified = verified
  }

  public var isReady: Bool { state == .ready }
}

/// A model Glade can ask for advice: an installed agent command-line tool, or Apple's
/// on-device model.
public protocol AgentProvider: Sendable {
  var id: String { get }
  var name: String { get }
  /// Runs entirely on this Mac.
  var isLocal: Bool { get }
  /// Whether it's installed and signed in. Must be quick and must never start a sign-in flow.
  func status() async -> ProviderStatus
  /// Sends one request and returns the model's final text.
  func complete(_ request: AgentRequest) async throws -> AgentReply
}
