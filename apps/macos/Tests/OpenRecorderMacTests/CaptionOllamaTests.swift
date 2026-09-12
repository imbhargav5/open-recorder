import Foundation
import XCTest
@testable import OpenRecorderMac

final class CaptionOllamaTests: XCTestCase {
    func testDiscoveryRejectsEmbeddingAndCloudAliases() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CaptionURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let service = OllamaCaptionService(session: session)
        let models = try await service.models()
        XCTAssertEqual(models, ["local-text"])
    }

    func testMissingModelDoesNotIssueChatRequest() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CaptionURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let service = OllamaCaptionService(session: session)
        do {
            _ = try await service.clean([.init(start: 0, end: 1, text: "Hello")], model: "removed")
            XCTFail("A removed model must block inference")
        } catch { XCTAssertTrue(error.localizedDescription.contains("unavailable")) }
    }
}

private final class CaptionURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let json: String
        switch request.url!.path {
        case "/api/tags":
            json = "{\"models\":[{\"name\":\"local-text\"},{\"name\":\"embed\"},{\"name\":\"custom-alias\"}]}"
        case "/api/show":
            var body = request.httpBody
            if body == nil, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var data = Data(), buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let size = stream.read(&buffer, maxLength: buffer.count)
                    if size <= 0 { break }
                    data.append(contentsOf: buffer.prefix(size))
                }
                body = data
            }
            let model = ((try? JSONSerialization.jsonObject(with: body ?? Data())) as? [String: String])?["model"]
            switch model {
            case "local-text": json = "{\"capabilities\":[\"completion\"]}"
            case "embed": json = "{\"capabilities\":[\"embedding\"]}"
            default: json = "{\"capabilities\":[\"completion\"],\"remote_host\":\"https://ollama.com\",\"remote_model\":\"cloud-model\"}"
            }
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
