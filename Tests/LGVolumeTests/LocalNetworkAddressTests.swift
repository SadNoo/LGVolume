import XCTest
@testable import LGVolume

final class LocalNetworkAddressTests: XCTestCase {
    func testAcceptsPrivateAndLinkLocalAddresses() {
        let addresses = [
            "10.0.0.1",
            "172.16.0.1",
            "172.31.255.254",
            "192.168.1.20",
            "169.254.12.34"
        ]

        for address in addresses {
            XCTAssertTrue(LocalNetworkAddress.isAllowedIPv4(address), address)
        }
    }

    func testRejectsPublicAndMalformedAddresses() {
        let addresses = [
            "8.8.8.8",
            "172.15.0.1",
            "172.32.0.1",
            "192.169.1.1",
            "192.168.01.2",
            "192.168.1",
            "192.168.1.256",
            "example.com"
        ]

        for address in addresses {
            XCTAssertFalse(LocalNetworkAddress.isAllowedIPv4(address), address)
        }
    }
}
