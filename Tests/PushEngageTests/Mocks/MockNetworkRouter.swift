import Foundation
@testable import PushEngage

/// Records every call and lets a test inject the response per call.
/// Default behavior: returns `.failure(.networkNotReachable)` so an
/// un-stubbed test fails loudly rather than silently hanging.
final class MockNetworkRouter: NetworkRouterType {

    private(set) var requestCallCount = 0
    private(set) var requestedRoutes: [PERouter] = []

    private(set) var downloadCallCount = 0
    private(set) var downloadedRoutes: [PERouter] = []

    private(set) var cancelCallCount = 0

    /// FIFO queue of stub results. If empty, `defaultResult` is used.
    var stubbedResults: [Result<Data, PEError>] = []
    var defaultResult: Result<Data, PEError> = .failure(.networkNotReachable)

    /// FIFO queue for downloads.
    var stubbedDownloadResults: [Result<(URL, URLResponse), PEError>] = []
    var defaultDownloadResult: Result<(URL, URLResponse), PEError> = .failure(.networkNotReachable)

    func request(_ route: PERouter, completion: @escaping NetworkRouterCompletion) {
        requestCallCount += 1
        requestedRoutes.append(route)
        let result = stubbedResults.isEmpty ? defaultResult : stubbedResults.removeFirst()
        completion(result)
    }

    func requestDownload(_ route: PERouter, completion: @escaping NetworkRouterDownloadCompletion) {
        downloadCallCount += 1
        downloadedRoutes.append(route)
        let result = stubbedDownloadResults.isEmpty ? defaultDownloadResult : stubbedDownloadResults.removeFirst()
        completion(result)
    }

    func cancel() {
        cancelCallCount += 1
    }

    // Convenience for tests
    func enqueueSuccess(_ json: String) {
        stubbedResults.append(.success(Data(json.utf8)))
    }

    func enqueueFailure(_ error: PEError) {
        stubbedResults.append(.failure(error))
    }
}
