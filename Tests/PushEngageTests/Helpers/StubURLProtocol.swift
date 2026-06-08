import Foundation

/// URLProtocol stub: lets a test install a per-request handler.
/// Configure responses by setting `StubURLProtocol.requestHandler`. Tests must
/// reset it in tearDown.
///
/// Usage:
/// ```
/// let config = URLSessionConfiguration.ephemeral
/// config.protocolClasses = [StubURLProtocol.self]
/// let session = URLSession(configuration: config)
/// let router = Router(session: session)
/// StubURLProtocol.requestHandler = { request in
///     return (HTTPURLResponse(...)!, Data("...".utf8))
/// }
/// ```
final class StubURLProtocol: URLProtocol {

    /// Called for every request that goes through a URLSession using this protocol.
    /// Return a (response, body) tuple, or throw to produce a URLError.
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = StubURLProtocol.requestHandler else {
            client?.urlProtocol(self,
                                didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data = data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension URLSession {
    /// Builds an ephemeral URLSession wired to StubURLProtocol.
    static func stubbedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}
