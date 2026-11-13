import Foundation

/// How quickly one website or service answers, step by step: finding its address, connecting,
/// securing the connection and the first reply. Compared with a well-connected site, it
/// tells “this service is slow” apart from “my connection is slow”. One small request
/// to each, made only when someone asks.
public struct SiteCheck: Codable, Sendable, Equatable {
  public var host: String
  /// Milliseconds for each step; `nil` when the step was skipped (an address already known).
  public var lookup: Double?
  public var connect: Double?
  public var secure: Double?
  public var firstReply: Double?
  public var total: Double?
  public var status: Int?
  /// Went through a proxy or iCloud Private Relay.
  public var throughProxy: Bool
  public var error: String?

  /// The site used for comparison.
  public static let control = "www.apple.com"

  public static func run(_ host: String) async -> SiteCheck {
    var check = SiteCheck(host: host, throughProxy: false)
    guard let url = URL(string: "https://\(host)/"), url.host == host, Pinger.isPlainHost(host) else {
      check.error = "That isn’t a site name Glade can check."
      return check
    }
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15)
    // The first byte only: many sites refuse HEAD (405), and a byte is all a timing needs.
    request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
    request.httpShouldHandleCookies = false
    let delegate = MetricsDelegate()
    let started = Date()
    do {
      // A new session each time, so every try measures finding, connecting and securing.
      let session = Self.freshSession()
      defer { session.finishTasksAndInvalidate() }
      let (_, response) = try await session.data(for: request, delegate: delegate)
      check.status = (response as? HTTPURLResponse)?.statusCode
    } catch {
      check.error = error.localizedDescription
    }
    check.total = Date().timeIntervalSince(started) * 1_000
    if let metrics = delegate.metrics?.transactionMetrics.last {
      func span(_ from: Date?, _ to: Date?) -> Double? {
        guard let from, let to else { return nil }
        return to.timeIntervalSince(from) * 1_000
      }
      check.lookup = span(metrics.domainLookupStartDate, metrics.domainLookupEndDate)
      check.connect = span(metrics.connectStartDate, metrics.secureConnectionStartDate ?? metrics.connectEndDate)
      check.secure = span(metrics.secureConnectionStartDate, metrics.secureConnectionEndDate)
      check.firstReply = span(metrics.requestStartDate, metrics.responseStartDate)
      check.throughProxy = metrics.isProxyConnection
    }
    Log.info(.network, "Checked a site: \(check.status.map(String.init) ?? "no answer") in \(Int(check.total ?? 0)) ms")
    return check
  }

  /// The site, then the comparison site, side by side: the median of three tries each,
  /// since one try can land on a hiccup.
  public static func compare(_ host: String) async -> [SiteCheck] {
    async let site = median(host)
    async let control = median(Self.control)
    return await [site, control]
  }

  static func median(_ host: String) async -> SiteCheck {
    var tries: [SiteCheck] = []
    for _ in 0..<3 {
      let check = await run(host)
      if check.error != nil, tries.isEmpty { return check }
      tries.append(check)
    }
    let answered = tries.filter { $0.error == nil }.sorted { ($0.total ?? 0) < ($1.total ?? 0) }
    return answered.isEmpty ? tries[0] : answered[answered.count / 2]
  }

  /// One sentence comparing a site with the control.
  public static func sentence(_ site: SiteCheck, control: SiteCheck) -> String {
    if let error = site.error { return "\(site.host) didn’t answer: \(error)" }
    guard let siteTotal = site.total, let controlTotal = control.total, control.error == nil else {
      return "\(site.host) answered in \(Int(site.total ?? 0)) ms."
    }
    if let lookup = site.lookup, lookup > 300, lookup > (control.lookup ?? 0) * 3 {
      return "Finding \(site.host)’s address was slow (\(Int(lookup)) ms), which delays it starting. Your DNS may be the problem."
    }
    let figures = "(\(Int(siteTotal)) ms against \(Int(controlTotal)) ms for \(control.host))"
    if controlTotal > 1_000 {
      return "Even \(control.host) was slow \(figures), so the delay is your connection, not \(site.host)."
    }
    if siteTotal > controlTotal * 2.5, siteTotal - controlTotal > 250 {
      return "\(site.host) is slow to answer \(figures), so the delay is at its end or on the way to it, not your connection."
    }
    if siteTotal > controlTotal * 1.5, siteTotal - controlTotal > 100 {
      return "\(site.host) answered a little slower than \(control.host) \(figures), which is normal for a site further away."
    }
    return "\(site.host) answered about as quickly as \(control.host) \(figures), so the way there looks fine."
  }

  static func freshSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.urlCache = nil
    return URLSession(configuration: configuration)
  }

  final class MetricsDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    var metrics: URLSessionTaskMetrics?
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
      self.metrics = metrics
    }
  }
}
