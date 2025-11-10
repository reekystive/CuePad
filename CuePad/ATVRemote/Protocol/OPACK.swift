import Foundation

/// OPACK (Object Packer) - Binary plist format used by Companion protocol
public enum OPACK {
  // MARK: - Encoding

  public static func encode(_ value: Any) throws -> Data {
    var objectList: [Data] = []
    return try pack(value, objectList: &objectList)
  }

  private static func pack(_ value: Any, objectList: inout [Data]) throws -> Data {
    var result = Data()

    // Null
    if value is NSNull {
      result.append(0x04)
      return result
    }

    // Boolean
    if let bool = value as? Bool {
      result.append(bool ? 0x01 : 0x02)
      return result
    }

    // Integer
    if let int = value as? Int {
      if int >= 0 && int < 0x28 {
        // Small int (0-39) encoded as single byte 0x08-0x2F
        result.append(UInt8(int + 8))
      } else if int >= 0 && int <= 0xFF {
        result.append(0x30)
        result.append(UInt8(int))
      } else if int >= 0 && int <= 0xFFFF {
        result.append(0x31)
        var value = UInt16(int)
        result.append(contentsOf: withUnsafeBytes(of: &value) { Data($0) })
      } else if int >= 0 && int <= 0xFFFF_FFFF {
        result.append(0x32)
        var value = UInt32(int)
        result.append(contentsOf: withUnsafeBytes(of: &value) { Data($0) })
      } else {
        result.append(0x33)
        var value = UInt64(bitPattern: Int64(int))
        result.append(contentsOf: withUnsafeBytes(of: &value) { Data($0) })
      }
      return result
    }

    // Float
    if let float = value as? Float {
      result.append(0x35)
      var value = float
      result.append(contentsOf: withUnsafeBytes(of: &value) { Data($0) })
      return result
    }

    // Double
    if let double = value as? Double {
      result.append(0x36)
      var value = double
      result.append(contentsOf: withUnsafeBytes(of: &value) { Data($0) })
      return result
    }

    // String
    if let string = value as? String {
      guard let encoded = string.data(using: .utf8) else {
        throw OPACKError.encodingFailed
      }

      let length = encoded.count

      if length <= 0x20 {
        result.append(UInt8(0x40 + length))
        result.append(contentsOf: encoded)
      } else if length <= 0xFF {
        result.append(0x61)
        result.append(UInt8(length))
        result.append(contentsOf: encoded)
      } else if length <= 0xFFFF {
        result.append(0x62)
        var len = UInt16(length)
        result.append(contentsOf: withUnsafeBytes(of: &len) { Data($0) })
        result.append(contentsOf: encoded)
      } else if length <= 0xFFFFFF {
        result.append(0x63)
        let bytes = withUnsafeBytes(of: UInt32(length)) { Array($0.prefix(3)) }
        result.append(contentsOf: bytes)
        result.append(contentsOf: encoded)
      } else {
        result.append(0x64)
        var len = UInt32(length)
        result.append(contentsOf: withUnsafeBytes(of: &len) { Data($0) })
        result.append(contentsOf: encoded)
      }
      return result
    }

    // Data (bytes)
    if let data = value as? Data {
      let length = data.count

      if length <= 0x20 {
        result.append(UInt8(0x70 + length))
        result.append(contentsOf: data)
      } else if length <= 0xFF {
        result.append(0x91)
        result.append(UInt8(length))
        result.append(contentsOf: data)
      } else if length <= 0xFFFF {
        result.append(0x92)
        var len = UInt16(length)
        result.append(contentsOf: withUnsafeBytes(of: &len) { Data($0) })
        result.append(contentsOf: data)
      } else {
        result.append(0x93)
        var len = UInt32(length)
        result.append(contentsOf: withUnsafeBytes(of: &len) { Data($0) })
        result.append(contentsOf: data)
      }
      return result
    }

    // Array
    if let array = value as? [Any] {
      let count = min(array.count, 0xF)
      result.append(UInt8(0xD0 + count))

      for item in array {
        try result.append(contentsOf: pack(item, objectList: &objectList))
      }

      if array.count >= 0xF {
        result.append(0x03)  // End marker
      }
      return result
    }

    // Dictionary
    if let dict = value as? [String: Any] {
      let count = min(dict.count, 0xF)
      result.append(UInt8(0xE0 + count))

      for (key, val) in dict {
        try result.append(contentsOf: pack(key, objectList: &objectList))
        try result.append(contentsOf: pack(val, objectList: &objectList))
      }

      if dict.count >= 0xF {
        result.append(0x03)  // End marker
      }
      return result
    }

    throw OPACKError.unsupportedType
  }

  // MARK: - Decoding

  public static func decode(_ data: Data) throws -> Any {
    let (value, _) = try unpack(data, objectList: [])
    return value
  }

  private static func unpack(_ data: Data, objectList: [Any]) throws -> (Any, Data) {
    guard !data.isEmpty else {
      throw OPACKError.insufficientData
    }

    let objects = objectList
    let marker = data[0]
    var remaining = data.dropFirst()
    var value: Any

    switch marker {
    // Boolean true
    case 0x01:
      value = true

    // Boolean false
    case 0x02:
      value = false

    // Null
    case 0x04:
      value = NSNull()

    // UUID
    case 0x05:
      guard remaining.count >= 16 else { throw OPACKError.insufficientData }
      value = UUID(
        uuid: (
          remaining[0], remaining[1], remaining[2], remaining[3],
          remaining[4], remaining[5], remaining[6], remaining[7],
          remaining[8], remaining[9], remaining[10], remaining[11],
          remaining[12], remaining[13], remaining[14], remaining[15]
        ))
      remaining = remaining.dropFirst(16)

    // Small integers (0-39)
    case 0x08...0x2F:
      value = Int(marker - 8)

    // Integers with size
    case 0x30:
      guard remaining.count >= 1 else { throw OPACKError.insufficientData }
      value = Int(remaining[0])
      remaining = remaining.dropFirst()

    case 0x31:
      guard remaining.count >= 2 else { throw OPACKError.insufficientData }
      value = remaining.withUnsafeBytes { $0.load(as: UInt16.self) }
      remaining = remaining.dropFirst(2)

    case 0x32:
      guard remaining.count >= 4 else { throw OPACKError.insufficientData }
      value = remaining.withUnsafeBytes { $0.load(as: UInt32.self) }
      remaining = remaining.dropFirst(4)

    case 0x33:
      guard remaining.count >= 8 else { throw OPACKError.insufficientData }
      value = remaining.withUnsafeBytes { $0.load(as: UInt64.self) }
      remaining = remaining.dropFirst(8)

    // Float
    case 0x35:
      guard remaining.count >= 4 else { throw OPACKError.insufficientData }
      value = remaining.withUnsafeBytes { $0.load(as: Float.self) }
      remaining = remaining.dropFirst(4)

    // Double
    case 0x36:
      guard remaining.count >= 8 else { throw OPACKError.insufficientData }
      value = remaining.withUnsafeBytes { $0.load(as: Double.self) }
      remaining = remaining.dropFirst(8)

    // String (small, 0-32 bytes)
    case 0x40...0x60:
      let length = Int(marker - 0x40)
      guard remaining.count >= length else { throw OPACKError.insufficientData }
      let stringData = remaining.prefix(length)
      guard let string = String(data: stringData, encoding: .utf8) else {
        throw OPACKError.decodingFailed
      }
      value = string
      remaining = remaining.dropFirst(length)

    // String (with length prefix)
    case 0x61...0x64:
      let lengthBytes = Int(marker & 0x0F)
      guard remaining.count >= lengthBytes else { throw OPACKError.insufficientData }

      let length: Int
      switch lengthBytes {
      case 1:
        length = Int(remaining[0])
      case 2:
        length = Int(remaining.withUnsafeBytes { $0.load(as: UInt16.self) })
      case 3:
        length = Int(remaining[0]) | (Int(remaining[1]) << 8) | (Int(remaining[2]) << 16)
      case 4:
        length = Int(remaining.withUnsafeBytes { $0.load(as: UInt32.self) })
      default:
        throw OPACKError.invalidFormat
      }

      remaining = remaining.dropFirst(lengthBytes)
      guard remaining.count >= length else { throw OPACKError.insufficientData }

      let stringData = remaining.prefix(length)
      guard let string = String(data: stringData, encoding: .utf8) else {
        throw OPACKError.decodingFailed
      }
      value = string
      remaining = remaining.dropFirst(length)

    // Data (small, 0-32 bytes)
    case 0x70...0x90:
      let length = Int(marker - 0x70)
      guard remaining.count >= length else { throw OPACKError.insufficientData }
      value = Data(remaining.prefix(length))
      remaining = remaining.dropFirst(length)

    // Data (with length prefix)
    case 0x91...0x94:
      let lengthBytes = 1 << ((marker & 0x0F) - 1)
      guard remaining.count >= lengthBytes else { throw OPACKError.insufficientData }

      let length: Int
      switch lengthBytes {
      case 1:
        length = Int(remaining[0])
      case 2:
        length = Int(remaining.withUnsafeBytes { $0.load(as: UInt16.self) })
      case 4:
        length = Int(remaining.withUnsafeBytes { $0.load(as: UInt32.self) })
      case 8:
        length = Int(remaining.withUnsafeBytes { $0.load(as: UInt64.self) })
      default:
        throw OPACKError.invalidFormat
      }

      remaining = remaining.dropFirst(lengthBytes)
      guard remaining.count >= length else { throw OPACKError.insufficientData }

      value = Data(remaining.prefix(length))
      remaining = remaining.dropFirst(length)

    // Array
    case 0xD0...0xDF:
      let count = Int(marker & 0x0F)
      var array: [Any] = []

      if count == 0x0F {
        // Endless array, read until 0x03 marker
        while !remaining.isEmpty, remaining[0] != 0x03 {
          let (item, rest) = try unpack(remaining, objectList: objects)
          array.append(item)
          remaining = rest
        }
        if !remaining.isEmpty, remaining[0] == 0x03 {
          remaining = remaining.dropFirst()
        }
      } else {
        for _ in 0..<count {
          let (item, rest) = try unpack(remaining, objectList: objects)
          array.append(item)
          remaining = rest
        }
      }

      value = array

    // Dictionary
    case 0xE0...0xEF:
      let count = Int(marker & 0x0F)
      var dict: [String: Any] = [:]

      if count == 0x0F {
        // Endless dict, read until 0x03 marker
        while !remaining.isEmpty, remaining[0] != 0x03 {
          let (keyValue, rest1) = try unpack(remaining, objectList: objects)
          let (val, rest2) = try unpack(rest1, objectList: objects)

          if let key = keyValue as? String {
            dict[key] = val
          }
          remaining = rest2
        }
        if !remaining.isEmpty, remaining[0] == 0x03 {
          remaining = remaining.dropFirst()
        }
      } else {
        for _ in 0..<count {
          let (keyValue, rest1) = try unpack(remaining, objectList: objects)
          let (val, rest2) = try unpack(rest1, objectList: objects)

          if let key = keyValue as? String {
            dict[key] = val
          }
          remaining = rest2
        }
      }

      value = dict

    default:
      throw OPACKError.unsupportedMarker(marker)
    }

    return (value, remaining)
  }

  // MARK: - Errors

  public enum OPACKError: Error, LocalizedError {
    case encodingFailed
    case decodingFailed
    case unsupportedType
    case unsupportedMarker(UInt8)
    case insufficientData
    case invalidFormat

    public var errorDescription: String? {
      switch self {
      case .encodingFailed:
        return "Failed to encode data"
      case .decodingFailed:
        return "Failed to decode data"
      case .unsupportedType:
        return "Unsupported data type"
      case .unsupportedMarker(let marker):
        return "Unsupported OPACK marker: 0x\(String(format: "%02X", marker))"
      case .insufficientData:
        return "Insufficient data for decoding"
      case .invalidFormat:
        return "Invalid OPACK format"
      }
    }
  }
}

// MARK: - Convenience Extensions

extension OPACK {
  /// Encode a dictionary to OPACK
  public static func encodeDictionary(_ dict: [String: Any]) throws -> Data {
    return try encode(dict)
  }

  /// Decode OPACK to a dictionary
  public static func decodeDictionary(_ data: Data) throws -> [String: Any] {
    let value = try decode(data)
    guard let dict = value as? [String: Any] else {
      throw OPACKError.invalidFormat
    }
    return dict
  }
}
