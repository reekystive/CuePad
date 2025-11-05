import Foundation

/// HID (Human Interface Device) commands for Companion protocol
public enum HIDCommand: UInt8 {
  case up = 1
  case down = 2
  case left = 3
  case right = 4
  case menu = 5
  case select = 6
  case home = 7
  case volumeUp = 8
  case volumeDown = 9
  case siri = 10
  case screensaver = 11
  case sleep = 12
  case wake = 13
  case playPause = 14
  case channelIncrement = 15
  case channelDecrement = 16
  case guide = 17
  case pageUp = 18
  case pageDown = 19

  /// Create HID command message for Companion protocol
  public func createMessage(pressed: Bool) throws -> Data {
    let payload: [String: Any] = [
      "_hBtS": pressed ? 1 : 0, // Button state: 1 = pressed, 0 = released
      "_hidC": Int(rawValue), // HID command code
    ]

    return try OPACK.encode(payload)
  }
}

/// Media control commands for Companion protocol
public enum MediaControlCommand: UInt8 {
  case play = 1
  case pause = 2
  case nextTrack = 3
  case previousTrack = 4
  case getVolume = 5
  case setVolume = 6
  case skipBy = 7
  case fastForwardBegin = 8
  case fastForwardEnd = 9
  case rewindBegin = 10
  case rewindEnd = 11
  case getCaptionSettings = 12
  case setCaptionSettings = 13

  /// Create media control message
  public func createMessage(params: [String: Any] = [:]) throws -> Data {
    var payload: [String: Any] = [
      "_mcc": Int(rawValue),
    ]

    // Add additional parameters (e.g., volume level, skip time)
    for (key, value) in params {
      payload[key] = value
    }

    return try OPACK.encode(payload)
  }
}

/// System status values
public enum SystemStatus: UInt8 {
  case unknown = 0x00
  case asleep = 0x01
  case screensaver = 0x02
  case awake = 0x03
  case idle = 0x04
}

/// Map ATVRemoteKey to HIDCommand
public extension ATVRemoteKey {
  var hidCommand: HIDCommand? {
    switch self {
    case .up: return .up
    case .down: return .down
    case .left: return .left
    case .right: return .right
    case .select: return .select
    case .menu: return .menu
    case .home: return .home
    case .volumeUp: return .volumeUp
    case .volumeDown: return .volumeDown
    case .playPause: return .playPause
    default: return nil
    }
  }

  var mediaControlCommand: MediaControlCommand? {
    switch self {
    case .skipForward: return .nextTrack
    case .skipBackward: return .previousTrack
    default: return nil
    }
  }
}
