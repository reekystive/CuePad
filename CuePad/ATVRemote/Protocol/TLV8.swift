import Foundation

/// TLV8 (Type-Length-Value with 8-bit length) encoding/decoding for HAP protocol
public enum TLV8 {
  // MARK: - TLV Types

  public enum TLVType: UInt8 {
    case method = 0x00
    case identifier = 0x01
    case salt = 0x02
    case publicKey = 0x03
    case proof = 0x04
    case encryptedData = 0x05
    case seqNo = 0x06
    case error = 0x07
    case backOff = 0x08
    case certificate = 0x09
    case signature = 0x0A
    case permissions = 0x0B
    case fragmentData = 0x0C
    case fragmentLast = 0x0D

    // Apple internal
    case name = 0x11
    case flags = 0x13
  }

  public enum Method: UInt8 {
    case pairSetup = 0x00
    case pairSetupWithAuth = 0x01
    case pairVerify = 0x02
    case addPairing = 0x03
    case removePairing = 0x04
    case listPairing = 0x05
  }

  public enum State: UInt8 {
    case m1 = 0x01
    case m2 = 0x02
    case m3 = 0x03
    case m4 = 0x04
    case m5 = 0x05
    case m6 = 0x06
  }

  public enum ErrorCode: UInt8 {
    case unknown = 0x01
    case authentication = 0x02
    case backOff = 0x03
    case maxPeers = 0x04
    case maxTries = 0x05
    case unavailable = 0x06
    case busy = 0x07
  }

  public enum Flags: UInt8 {
    case transientPairing = 0x10
  }

  // MARK: - Encoding

  /// Encode a dictionary to TLV8 bytes
  /// - Parameter data: Dictionary with UInt8 keys and Data values
  /// - Returns: TLV8 encoded data
  public static func encode(_ data: [UInt8: Data]) -> Data {
    var result = Data()

    for (key, value) in data.sorted(by: { $0.key < $1.key }) {
      var remaining = value

      // Split values > 255 bytes into multiple chunks
      while !remaining.isEmpty {
        let chunkSize = min(remaining.count, 255)
        let chunk = remaining.prefix(chunkSize)

        result.append(key)
        result.append(UInt8(chunkSize))
        result.append(contentsOf: chunk)

        remaining = remaining.dropFirst(chunkSize)
      }
    }

    return result
  }

  /// Encode a dictionary with TLVType keys
  public static func encode(_ data: [TLVType: Data]) -> Data {
    let dict = Dictionary(uniqueKeysWithValues: data.map { ($0.key.rawValue, $0.value) })
    return encode(dict)
  }

  // MARK: - Decoding

  /// Decode TLV8 bytes into a dictionary
  /// - Parameter data: TLV8 encoded data
  /// - Returns: Dictionary with UInt8 keys and Data values
  public static func decode(_ data: Data) -> [UInt8: Data] {
    var result: [UInt8: Data] = [:]
    var position = 0

    while position < data.count {
      guard position + 2 <= data.count else { break }

      let tag = data[position]
      let length = Int(data[position + 1])
      position += 2

      guard position + length <= data.count else { break }

      let value = data[position ..< position + length]
      position += length

      // Concatenate values with same tag (for values > 255 bytes)
      if let existing = result[tag] {
        result[tag] = existing + value
      } else {
        result[tag] = Data(value)
      }
    }

    return result
  }

  /// Decode TLV8 bytes with TLVType keys
  public static func decodeTyped(_ data: Data) -> [TLVType: Data] {
    let rawDict = decode(data)
    var result: [TLVType: Data] = [:]

    for (key, value) in rawDict {
      if let type = TLVType(rawValue: key) {
        result[type] = value
      }
    }

    return result
  }

  // MARK: - Convenience Methods

  /// Get a UInt8 value from TLV data
  public static func getUInt8(_ dict: [TLVType: Data], _ key: TLVType) -> UInt8? {
    guard let data = dict[key], !data.isEmpty else { return nil }
    return data[0]
  }

  /// Get a string value from TLV data
  public static func getString(_ dict: [TLVType: Data], _ key: TLVType) -> String? {
    guard let data = dict[key] else { return nil }
    return String(data: data, encoding: .utf8)
  }

  /// Create TLV data from a UInt8 value
  public static func data(from value: UInt8) -> Data {
    return Data([value])
  }

  /// Create TLV data from a string
  public static func data(from string: String) -> Data? {
    return string.data(using: .utf8)
  }
}

// MARK: - Debug Description

public extension TLV8 {
  /// Create human-readable string of TLV8 data for debugging
  static func stringify(_ data: Data) -> String {
    let dict = decodeTyped(data)
    var parts: [String] = []

    for (key, value) in dict.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
      let description: String

      switch key {
      case .method:
        if let methodValue = value.first, let method = Method(rawValue: methodValue) {
          description = "\(key)=\(method)"
        } else {
          description = "\(key)=0x\(value.hexString)"
        }

      case .seqNo:
        if let stateValue = value.first, let state = State(rawValue: stateValue) {
          description = "\(key)=\(state)"
        } else {
          description = "\(key)=0x\(value.hexString)"
        }

      case .error:
        if let errorValue = value.first, let error = ErrorCode(rawValue: errorValue) {
          description = "\(key)=\(error)"
        } else {
          description = "\(key)=0x\(value.hexString)"
        }

      case .backOff:
        if let seconds = value.first {
          description = "\(key)=\(seconds)s"
        } else {
          description = "\(key)=unknown"
        }

      default:
        description = "\(key)=\(value.count)bytes"
      }

      parts.append(description)
    }

    return parts.joined(separator: ", ")
  }
}

// MARK: - Data Extension

extension Data {
  var hexString: String {
    return map { String(format: "%02x", $0) }.joined()
  }
}
