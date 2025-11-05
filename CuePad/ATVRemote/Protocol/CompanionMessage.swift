import Foundation

/// Companion protocol message frame structure
public struct CompanionMessage {
  // MARK: - Frame Types

  public enum FrameType: UInt8 {
    case ps_start = 0x01
    case ps_next = 0x02
    case pv_start = 0x03
    case pv_next = 0x04
    case event = 0x06
  }

  // MARK: - Message Types

  public enum MessageType: String {
    // Session
    case sessionStart = "_sessionStart"
    case sessionStop = "_sessionStop"

    // HID
    case hidEvent = "_hidT"

    // Media Control
    case mediaControl = "_mcc"

    // Text Input
    case textInput = "_tiStart"
    case textInputStop = "_tiStopped"

    // System
    case systemStatus = "_systemStatus"
    case interest = "_interest"

    // Events
    case nowPlayingInfo = "_nowPlayingInfo"
    case nowPlayingArtwork = "_nowPlayingArtwork"
  }

  // MARK: - Message Structure

  public let frameType: FrameType
  public let flags: UInt8
  public let payload: Data

  public init(frameType: FrameType, flags: UInt8 = 0, payload: Data) {
    self.frameType = frameType
    self.flags = flags
    self.payload = payload
  }

  // MARK: - Encoding

  /// Encode message to wire format
  /// Format: | Length (4 bytes BE) | Type (1 byte) | Flags (1 byte) | Payload |
  public func encode() -> Data {
    var result = Data()

    // Total length (excluding length field itself)
    let totalLength = 2 + payload.count // type (1) + flags (1) + payload
    var lengthBE = UInt32(totalLength).bigEndian
    result.append(contentsOf: withUnsafeBytes(of: &lengthBE) { Data($0) })

    // Frame type and flags
    result.append(frameType.rawValue)
    result.append(flags)

    // Payload
    result.append(contentsOf: payload)

    return result
  }

  // MARK: - Decoding

  /// Decode message from wire format
  public static func decode(_ data: Data) throws -> CompanionMessage {
    guard data.count >= 6 else {
      throw CompanionMessageError.insufficientData
    }

    // Read length (4 bytes, big endian)
    let length = data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

    guard data.count >= 4 + Int(length) else {
      throw CompanionMessageError.insufficientData
    }

    // Read frame type and flags
    guard let frameType = FrameType(rawValue: data[4]) else {
      throw CompanionMessageError.unknownFrameType(data[4])
    }

    let flags = data[5]

    // Read payload
    let payloadStart = 6
    let payloadEnd = min(4 + Int(length), data.count)
    let payload = Data(data[payloadStart ..< payloadEnd])

    return CompanionMessage(frameType: frameType, flags: flags, payload: payload)
  }

  /// Decode multiple messages from a buffer
  public static func decodeMultiple(_ data: Data) throws -> ([CompanionMessage], Data) {
    var messages: [CompanionMessage] = []
    var remaining = data

    while remaining.count >= 6 {
      // Read length
      let length = remaining.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
      let totalLength = 4 + Int(length)

      guard remaining.count >= totalLength else {
        // Incomplete message, return what we have and the remaining data
        break
      }

      let messageData = remaining.prefix(totalLength)
      let message = try decode(messageData)
      messages.append(message)

      remaining = remaining.dropFirst(totalLength)
    }

    return (messages, remaining)
  }

  // MARK: - Convenience Constructors

  /// Create HID event message
  public static func hidEvent(command: HIDCommand, pressed: Bool) throws -> CompanionMessage {
    let payload = try command.createMessage(pressed: pressed)
    return CompanionMessage(frameType: .event, payload: payload)
  }

  /// Create media control message
  public static func mediaControl(command: MediaControlCommand, params: [String: Any] = [:]) throws
    -> CompanionMessage
  {
    let payload = try command.createMessage(params: params)
    return CompanionMessage(frameType: .event, payload: payload)
  }

  /// Create session start message
  public static func sessionStart() throws -> CompanionMessage {
    let payload: [String: Any] = [
      "_i": UUID().uuidString,
      "_t": MessageType.sessionStart.rawValue,
    ]

    let data = try OPACK.encode(payload)
    return CompanionMessage(frameType: .event, payload: data)
  }

  /// Create interest subscription message
  public static func subscribeEvent(_ event: String) throws -> CompanionMessage {
    let payload: [String: Any] = [
      "_t": MessageType.interest.rawValue,
      "_regEvents": [event],
    ]

    let data = try OPACK.encode(payload)
    return CompanionMessage(frameType: .event, payload: data)
  }

  // MARK: - Errors

  public enum CompanionMessageError: Error, LocalizedError {
    case insufficientData
    case unknownFrameType(UInt8)
    case invalidPayload

    public var errorDescription: String? {
      switch self {
      case .insufficientData:
        return "Insufficient data to decode message"
      case let .unknownFrameType(type):
        return "Unknown frame type: 0x\(String(format: "%02X", type))"
      case .invalidPayload:
        return "Invalid message payload"
      }
    }
  }
}
