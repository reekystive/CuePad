import Foundation

// MARK: - Protocol Message Structures

/// Client to Server message structure
public struct ATVClientMessage: Codable {
  let cmd: String
  let data: ATVMessageData?

  enum CodingKeys: String, CodingKey {
    case cmd, data
  }

  init(cmd: String, data: ATVMessageData? = nil) {
    self.cmd = cmd
    self.data = data
  }
}

/// Server to Client message structure
public struct ATVServerMessage: Codable {
  let command: String
  let data: ATVMessageData?
}

/// Flexible data type that can be string, array, object, or boolean
public enum ATVMessageData: Codable {
  case string(String)
  case array([String])
  case object([String: String])
  case boolean(Bool)
  case keyCommand(ATVKeyCommand)
  case textCommand(ATVTextCommand)
  case credentials(ATVCredentials)
  case powerState(ATVPowerState)
  case keyboardState([String])

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([String].self) {
      self = .array(value)
    } else if let value = try? container.decode(Bool.self) {
      self = .boolean(value)
    } else if let value = try? container.decode(ATVKeyCommand.self) {
      self = .keyCommand(value)
    } else if let value = try? container.decode(ATVTextCommand.self) {
      self = .textCommand(value)
    } else if let value = try? container.decode(ATVCredentials.self) {
      self = .credentials(value)
    } else if let value = try? container.decode(ATVPowerState.self) {
      self = .powerState(value)
    } else if let value = try? container.decode([String: String].self) {
      self = .object(value)
    } else {
      throw DecodingError.typeMismatch(
        ATVMessageData.self,
        DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid data type")
      )
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()

    switch self {
    case .string(let value):
      try container.encode(value)
    case .array(let value):
      try container.encode(value)
    case .object(let value):
      try container.encode(value)
    case .boolean(let value):
      try container.encode(value)
    case .keyCommand(let value):
      try container.encode(value)
    case .textCommand(let value):
      try container.encode(value)
    case .credentials(let value):
      try container.encode(value)
    case .powerState(let value):
      try container.encode(value)
    case .keyboardState(let value):
      try container.encode(value)
    }
  }
}

// MARK: - Command Structures

/// Key command with optional input action
public struct ATVKeyCommand: Codable {
  let key: String
  let taction: String?
}

/// Text input command
public struct ATVTextCommand: Codable {
  let text: String
}

/// Device credentials
public struct ATVCredentials: Codable {
  public let identifier: String
  public let credentials: String
  public let Companion: String?

  enum CodingKeys: String, CodingKey {
    case identifier
    case credentials
    case Companion
  }

  public init(identifier: String, credentials: String, Companion: String? = nil) {
    self.identifier = identifier
    self.credentials = credentials
    self.Companion = Companion
  }
}

/// Power state change
public struct ATVPowerState: Codable {
  let old_state: String
  let new_state: String
}

// MARK: - Remote Control Keys

public enum ATVRemoteKey: String, CaseIterable {
  case up
  case down
  case left
  case right
  case select
  case menu
  case topMenu = "top_menu"
  case home
  case homeHold = "home_hold"
  case playPause = "play_pause"
  case skipForward = "skip_forward"
  case skipBackward = "skip_backward"
  case volumeUp = "volume_up"
  case volumeDown = "volume_down"

  public var supportsInputAction: Bool {
    switch self {
    case .volumeUp, .volumeDown, .playPause, .homeHold:
      return false
    default:
      return true
    }
  }
}

// MARK: - Input Actions

public enum ATVInputAction: String {
  case singleTap = "SingleTap"
  case doubleTap = "DoubleTap"
  case hold = "Hold"
}

// MARK: - Connection State

public enum ATVConnectionState {
  case disconnected
  case connecting
  case connected
  case connectionLost
  case reconnecting
}

// MARK: - Keyboard Focus State

public enum ATVKeyboardFocusState: String {
  case focused = "Focused"
  case unfocused = "Unfocused"
}

// MARK: - Commands

public enum ATVCommand {
  // Device Discovery
  case scan

  // Pairing
  case startPair(deviceName: String)
  case finishPair1(pin: String)
  case finishPair2(pin: String)

  // Connection
  case connect(credentials: ATVCredentials)
  case disconnect
  case isConnected
  case pingDevice

  // Remote Control
  case key(key: String)
  case keyWithAction(key: String, action: ATVInputAction)

  // Keyboard
  case kbFocus
  case getText
  case setText(text: String)

  // Server Control
  case quit
  case echo(data: String)

  var commandName: String {
    switch self {
    case .scan: return "scan"
    case .startPair: return "startPair"
    case .finishPair1: return "finishPair1"
    case .finishPair2: return "finishPair2"
    case .connect: return "connect"
    case .disconnect: return "disconnect"
    case .isConnected: return "is_connected"
    case .pingDevice: return "ping_device"
    case .key, .keyWithAction: return "key"
    case .kbFocus: return "kbfocus"
    case .getText: return "gettext"
    case .setText: return "settext"
    case .quit: return "quit"
    case .echo: return "echo"
    }
  }

  func toMessage() -> ATVClientMessage {
    switch self {
    case .scan, .disconnect, .isConnected, .pingDevice, .kbFocus, .getText, .quit:
      return ATVClientMessage(cmd: commandName, data: nil)

    case .startPair(let deviceName):
      return ATVClientMessage(cmd: commandName, data: .string(deviceName))

    case .finishPair1(let pin), .finishPair2(let pin):
      return ATVClientMessage(cmd: commandName, data: .string(pin))

    case .connect(let credentials):
      return ATVClientMessage(cmd: commandName, data: .credentials(credentials))

    case .key(let key):
      return ATVClientMessage(cmd: commandName, data: .string(key))

    case .keyWithAction(let key, let action):
      return ATVClientMessage(
        cmd: commandName,
        data: .keyCommand(ATVKeyCommand(key: key, taction: action.rawValue))
      )

    case .setText(let text):
      return ATVClientMessage(
        cmd: commandName,
        data: .textCommand(ATVTextCommand(text: text))
      )

    case .echo(let data):
      return ATVClientMessage(cmd: commandName, data: .string(data))
    }
  }
}

// MARK: - Response Types

public enum ATVResponse {
  case scanResult([String])
  case startPair2
  case pairCredentials(ATVCredentials)
  case connected
  case connectionFailure
  case disconnected
  case isConnected(Bool)
  case pingResult(String)
  case commandFailed(String)
  case kbFocusStatus(Bool)
  case currentText(String)
  case keyboardChangeState(old: ATVKeyboardFocusState, new: ATVKeyboardFocusState)
  case connectionLost
  case connectionClosed
  case reconnected
  case reconnectionFailed
  case powerStateChanged(old: String, new: String)
  case echoReply(String)
  case unknown(String)
}
