import Foundation

enum LocalNetworkAddress {
    static func isAllowedIPv4(_ address: String) -> Bool {
        let components = address.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 4 else {
            return false
        }

        var octets: [Int] = []
        for component in components {
            guard !component.isEmpty,
                  component.allSatisfy(\.isNumber),
                  (component == "0" || !component.hasPrefix("0")),
                  let value = Int(component),
                  (0...255).contains(value) else {
                return false
            }
            octets.append(value)
        }

        if octets[0] == 10 {
            return true
        }
        if octets[0] == 172 && (16...31).contains(octets[1]) {
            return true
        }
        if octets[0] == 192 && octets[1] == 168 {
            return true
        }
        return octets[0] == 169 && octets[1] == 254
    }
}
