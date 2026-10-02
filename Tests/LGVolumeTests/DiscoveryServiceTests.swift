import Foundation
import XCTest
@testable import LGVolume

final class DiscoveryServiceTests: XCTestCase {
    func testParsesFriendlyNameFromDeviceDescription() throws {
        let data = try XCTUnwrap("""
        <?xml version="1.0"?>
        <root><device><friendlyName>Living Room LG C2</friendlyName></device></root>
        """.data(using: .utf8))

        XCTAssertEqual(DiscoveryService.parseFriendlyName(data), "Living Room LG C2")
    }

    func testDeviceDescriptionLoaderRefusesRedirects() {
        let loader = DeviceDescriptionLoader(maximumBytes: 16) {}
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URL(string: "http://192.168.1.20:1234/desc.xml")!)
        let response = HTTPURLResponse(
            url: URL(string: "http://192.168.1.20:1234/desc.xml")!,
            statusCode: 302, httpVersion: nil, headerFields: ["Location": "http://example.com/"]
        )!
        var followed: URLRequest?? = .none
        loader.urlSession(
            session, task: task, willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: URL(string: "http://example.com/")!)
        ) { followed = .some($0) }
        XCTAssertEqual(followed, .some(nil))
        session.invalidateAndCancel()
    }

    func testDeviceDescriptionLoaderStopsAtSizeLimit() {
        let loader = DeviceDescriptionLoader(maximumBytes: 4) {}
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URL(string: "http://192.168.1.20:1234/desc.xml")!)
        loader.urlSession(session, dataTask: task, didReceive: Data(repeating: 0, count: 5))
        loader.urlSession(session, task: task, didCompleteWithError: nil)
        XCTAssertNil(loader.result)
        session.invalidateAndCancel()
    }
}
