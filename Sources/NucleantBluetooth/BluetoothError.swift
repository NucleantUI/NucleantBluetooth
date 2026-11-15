//
//  BluetoothError.swift
//  NucleantBluetooth
//

/// What went wrong talking to a peripheral, with the system's own message.
///
/// Requests don't throw: their outcome lands on the object they were made
/// on, as its `error` (a peripheral's, a service's, a characteristic's).
public enum BluetoothError: Error, Sendable, Equatable, CustomStringConvertible {
    /// `connect()` did not get a connection.
    case connectionFailed(String)
    /// A connection ended without `disconnect()` being asked for.
    case connectionLost(String)
    /// Services or characteristics could not be discovered.
    case discoveryFailed(String)
    /// The signal strength could not be read.
    case rssiFailed(String)
    /// A characteristic's value could not be read.
    case readFailed(String)
    /// A value could not be written to a characteristic.
    case writeFailed(String)
    /// Notifications could not be turned on or off.
    case notificationFailed(String)

    public var description: String {
        switch self {
        case .connectionFailed(let message): "Connection failed: \(message)"
        case .connectionLost(let message): "Connection lost: \(message)"
        case .discoveryFailed(let message): "Discovery failed: \(message)"
        case .rssiFailed(let message): "Reading the signal strength failed: \(message)"
        case .readFailed(let message): "Read failed: \(message)"
        case .writeFailed(let message): "Write failed: \(message)"
        case .notificationFailed(let message): "Notifications failed: \(message)"
        }
    }
}
