import Foundation

/// Finds out which router this is and reads it. Only status pages that open without a
/// password are read, so nothing here needs or sends a password.
public enum RouterReader {
  /// The router, or `nil` when it isn’t one Glade knows. Kept for five minutes, since
  /// some routers take a few seconds to build their device page.
  /// - Parameter includeDevices: Also read the device list. A cached report without
  ///   one is read again.
  public static func read(router: String, includeDevices: Bool = false, maximumAge: TimeInterval = 300, now: Date = Date()) async -> RouterReport? {
    if let cached = JSONFiles.read(Cached.self, from: url), cached.router == router, now.timeIntervalSince(cached.report.read) < maximumAge,
      !includeDevices || cached.report.devices != nil
    {
      return cached.report
    }
    guard let report = await ATTGateway.read(host: router, includeDevices: includeDevices, now: now) else { return nil }
    do {
      try JSONFiles.write(Cached(router: router, report: report), to: url)
    } catch {
      Log.warning(.network, "Couldn’t keep the router’s report: \(error.localizedDescription)")
    }
    return report
  }

  struct Cached: Codable {
    var router: String
    var report: RouterReport
  }

  static var url: URL { GladePaths.support.appendingPathComponent("router.json") }

  /// Fetches one page from the router. Only plain addresses on the local network, and
  /// a redirect to anywhere else is refused.
  static func page(_ host: String, _ path: String, timeout: TimeInterval = 15) async -> String? {
    guard NetworkTargets.isPrivate(host), let url = URL(string: "http://\(host)\(path)") else { return nil }
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
    request.httpShouldHandleCookies = false
    do {
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url?.host == host else {
        Log.info(.network, "Router page \(path) answered \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        return nil
      }
      return String(decoding: data, as: UTF8.self)
    } catch {
      Log.info(.network, "Router page \(path) couldn’t be read: \(error.localizedDescription)")
      return nil
    }
  }

  static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.urlCache = nil
    configuration.connectionProxyDictionary = [:]
    return URLSession(configuration: configuration, delegate: SameHostRedirects(), delegateQueue: nil)
  }()
}

/// Follows a redirect only when it stays on the same router.
final class SameHostRedirects: NSObject, URLSessionTaskDelegate, Sendable {
  func urlSession(
    _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest
  ) async -> URLRequest? {
    request.url?.host == task.originalRequest?.url?.host ? request : nil
  }
}
