//
//  Formatting.swift
//  BluetoothScanner
//
//  How the scanner writes Bluetooth values out: names for UUIDs and
//  companies, bytes as hex or text, signal strength as bars.
//

import Foundation
import NucleantBluetooth

extension BluetoothPeripheral {
    /// The advertised name, else the system's, else none.
    var displayName: String {
        localName ?? name ?? "Unnamed"
    }

    /// One line on what it is: who made it, what it offers.
    var summary: String {
        var parts: [String] = []
        if let company = manufacturerData?.companyIdentifier {
            parts.append(company.name ?? "Company \(company.rawValue)")
        }
        if let service = serviceUUIDs.first {
            parts.append(service.displayName)
        }
        if serviceUUIDs.count > 1 {
            parts.append("+\(serviceUUIDs.count - 1) services")
        }
        if isConnectable == false {
            parts.append("Not connectable")
        }
        return parts.isEmpty ? id.uuidString : parts.joined(separator: " · ")
    }
}

extension BluetoothUUID {
    /// The assigned name for a standard UUID, else the UUID.
    var displayName: String {
        metadata?.name ?? description
    }
}

extension Data {
    /// "0A 1B 2C".
    var hex: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    /// The bytes as UTF-8, when they are printable text.
    var printableText: String? {
        guard !isEmpty, let text = String(data: self, encoding: .utf8) else { return nil }
        let printable = text.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.controlCharacters.contains(scalar) || scalar == "\n" || scalar == "\t"
        }
        return printable ? text : nil
    }

    /// Bytes from hex digits, spaces allowed between them: "01 ff", "01FF".
    init?(hexDigits: String) {
        let digits = hexDigits.filter { !$0.isWhitespace }
        guard !digits.isEmpty, digits.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        var index = digits.startIndex
        while index < digits.endIndex {
            let next = digits.index(index, offsetBy: 2)
            guard let byte = UInt8(digits[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}

extension GATTCharacteristicProperties {
    /// "Read · Write · Notify".
    var names: String {
        let all: [(GATTCharacteristicProperties, String)] = [
            (.broadcast, "Broadcast"),
            (.read, "Read"),
            (.writeWithoutResponse, "Write without response"),
            (.write, "Write"),
            (.notify, "Notify"),
            (.indicate, "Indicate"),
            (.signedWrite, "Signed write"),
            (.extendedProperties, "Extended"),
        ]
        return all.filter { contains($0.0) }.map(\.1).joined(separator: " · ")
    }
}

/// How many of four bars a signal fills.
func signalBars(_ rssi: RSSI?) -> Int {
    guard let dBm = rssi?.rawValue else { return 0 }
    switch dBm {
    case (-60)...: return 4
    case -70 ..< -60: return 3
    case -80 ..< -70: return 2
    case -90 ..< -80: return 1
    default: return 0
    }
}
