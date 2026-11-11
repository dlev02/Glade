import Foundation

/// Every model Glade knows how to ask, and quick ways to find one that's ready.
public enum AgentProviders {
  /// In the order they're listed to people: verified first, then documentation-only.
  public static let all: [any AgentProvider] = [
    ClaudeProvider(),
    CodexProvider(),
    OpenCodeProvider(),
    AppleModelProvider(),
    ApplePrivateCloudProvider(),
    GeminiProvider(),
    CursorProvider(),
    OllamaProvider(),
  ] + CLISpec.documented.map { DocumentedCLIProvider(spec: $0) }

  public static func provider(id: String) -> (any AgentProvider)? {
    all.first { $0.id == id }
  }

  /// Every provider's status, checked at once. A provider that takes longer than
  /// `limit` seconds is reported unavailable rather than holding up the rest.
  public static func statuses(limit: TimeInterval = 3) async -> [ProviderStatus] {
    await statuses(of: all, limit: limit)
  }

  /// The first provider in `order` that's ready, or `nil` when none is.
  public static func firstReady(order: [String]) async -> (any AgentProvider)? {
    let wanted = order.compactMap(provider(id:))
    let found = await statuses(of: wanted, limit: 3)
    guard let ready = found.first(where: \.isReady) else { return nil }
    return provider(id: ready.id)
  }

  static func statuses(of providers: [any AgentProvider], limit: TimeInterval) async -> [ProviderStatus] {
    await withTaskGroup(of: (Int, ProviderStatus).self) { group in
      for (index, provider) in providers.enumerated() {
        group.addTask { (index, await status(of: provider, limit: limit)) }
      }
      var results: [(Int, ProviderStatus)] = []
      for await result in group { results.append(result) }
      return results.sorted { $0.0 < $1.0 }.map(\.1)
    }
  }

  private static func status(of provider: any AgentProvider, limit: TimeInterval) async -> ProviderStatus {
    let late = ProviderStatus(id: provider.id, name: provider.name, state: .unavailable(reason: "It didn’t respond in time."), isLocal: provider.isLocal)
    return await withTaskGroup(of: ProviderStatus?.self) { group in
      group.addTask { await provider.status() }
      group.addTask {
        try? await Task.sleep(for: .seconds(limit))
        return nil
      }
      defer { group.cancelAll() }
      let first = await group.next() ?? nil
      if first == nil { Log.warning(.agent, "\(provider.id) status took longer than \(Int(limit))s") }
      return first ?? late
    }
  }
}
