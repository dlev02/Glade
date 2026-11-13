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
    request.httpMethod = "HEAD"
    request.httpShouldHandleCookies = false
    let delegate = MetricsDelegate()
    let started = Date()
    do {
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

  /// The site, then the comparison site, side by side.
  public static func compare(_ host: String) async -> [SiteCheck] {
    async let site = run(host)
    async let control = run(control)
    return await [site, control]
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
    if siteTotal > controlTotal * 3, siteTotal - controlTotal > 300 {
      return "\(site.host) is slow to answer (\(Int(siteTotal)) ms against \(Int(controlTotal)) ms for \(control.host)), so the delay is at its end or on the way to it, not your connection."
    }
    return "\(site.host) answered about as quickly as \(control.host) (\(Int(siteTotal)) ms against \(Int(controlTotal)) ms), so the way there looks fine."
  }

  static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.urlCache = nil
    return URLSession(configuration: configuration)
  }()

  final class MetricsDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    var metrics: URLSessionTaskMetrics?
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
      self.metrics = metrics
    }
  }
}
