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
}
