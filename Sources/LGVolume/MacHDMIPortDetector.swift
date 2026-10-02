import Foundation
import IOKit

/// Finds which HDMI input of the LG TV this Mac is plugged into, using the TV's EDID.
///
/// A TV gives every HDMI input its own EDID whose HDMI vendor block carries a CEC physical
/// address: input N reports N.0.0.0, and a source behind a receiver or switch reports N.x.x.x.
/// The address only depends on the cable, so switching the TV to another source (for example a
/// Switch 2) and back never changes the answer. No CEC hardware or network access is involved.
enum MacHDMIPortDetector {
    /// IORegistry classes that publish the connected display's EDID on Apple Silicon Macs.
    private static let transportClasses = [
        "IOPortTransportStateDisplayPort",
        "IOPortTransportStateHDMI"
    ]

    /// The LG TV input (1-4) this Mac is connected to, or nil when no LG TV EDID is available.
    static func detectPort() -> Int? {
        for edid in connectedDisplayEDIDs() {
            if let port = EDIDParser.lgTVInputPort(from: edid) {
                return port
            }
        }
        return nil
    }

    private static func connectedDisplayEDIDs() -> [Data] {
        var results: [Data] = []
        for className in transportClasses {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else {
                continue
            }
            defer { IOObjectRelease(iterator) }
            while case let service = IOIteratorNext(iterator), service != 0 {
                defer { IOObjectRelease(service) }
                if let edid = IORegistryEntryCreateCFProperty(service, "EDID" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? Data {
                    results.append(edid)
                }
            }
        }
        return results
    }
}

enum EDIDParser {
    /// "GSM" is the EDID manufacturer ID used by LG Electronics displays and TVs.
    static let lgManufacturerID = "GSM"

    static func manufacturerID(from edid: Data) -> String? {
        let bytes = [UInt8](edid)
        guard bytes.count >= 128, bytes[0..<8] == [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00] else {
            return nil
        }
        let value = (UInt16(bytes[8]) << 8) | UInt16(bytes[9])
        let letters = [10, 5, 0].map { shift -> Character in
            Character(UnicodeScalar(UInt8((value >> UInt16(shift)) & 0x1F) + 64))
        }
        return String(letters)
    }

    /// The CEC physical address from the HDMI vendor-specific data block, as four nibbles.
    static func physicalAddress(from edid: Data) -> [Int]? {
        let bytes = [UInt8](edid)
        guard bytes.count >= 256 else { return nil }
        let extensionCount = Int(bytes[126])
        for blockIndex in 1...max(extensionCount, 1) {
            let start = blockIndex * 128
            guard bytes.count >= start + 128, bytes[start] == 0x02 else { continue }
            let block = Array(bytes[start..<(start + 128)])
            let detailedTimingOffset = Int(block[2])
            guard detailedTimingOffset >= 4, detailedTimingOffset <= 127 else { continue }
            var offset = 4
            while offset < detailedTimingOffset {
                let tag = block[offset] >> 5
                let length = Int(block[offset] & 0x1F)
                let end = offset + length
                guard end < detailedTimingOffset else { break }
                // HDMI 1.4 VSDB: tag 3, IEEE OUI 00-0C-03 stored least significant byte first.
                if tag == 3, length >= 5,
                   block[offset + 1] == 0x03, block[offset + 2] == 0x0C, block[offset + 3] == 0x00 {
                    let high = block[offset + 4]
                    let low = block[offset + 5]
                    return [Int(high >> 4), Int(high & 0x0F), Int(low >> 4), Int(low & 0x0F)]
                }
                offset = end + 1
            }
        }
        return nil
    }

    /// The LG TV input number for an LG EDID, from the first nibble of its physical address.
    static func lgTVInputPort(from edid: Data) -> Int? {
        guard manufacturerID(from: edid) == lgManufacturerID,
              let address = physicalAddress(from: edid),
              let port = address.first,
              (1...4).contains(port) else {
            return nil
        }
        return port
    }
}
