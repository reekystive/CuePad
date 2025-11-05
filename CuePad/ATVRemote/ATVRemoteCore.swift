import Foundation

/// Delegate protocol for ATVRemote events
public protocol ATVRemoteDelegate: AnyObject {
  func remoteDidConnect()
  func remoteDidDisconnect()
  func remoteConnectionLost()
  func remoteKeyboardFocusChanged(oldState: ATVKeyboardFocusState, newState: ATVKeyboardFocusState)
  func remotePowerStateChanged(oldState: String, newState: String)
}

// Make delegate methods optional
public extension ATVRemoteDelegate {
  func remoteDidConnect() {}
  func remoteDidDisconnect() {}
  func remoteConnectionLost() {}
  func remoteKeyboardFocusChanged(
    oldState _: ATVKeyboardFocusState, newState _: ATVKeyboardFocusState
  ) {}
  func remotePowerStateChanged(oldState _: String, newState _: String) {}
}

/// Main Apple TV Remote control class (native implementation)
public class ATVRemote {
  // MARK: - Properties

  private let discovery: ATVDiscovery
  private var connection: CompanionConnection?
  private var credentialsManager: ATVCredentialsManager
  private var textInput: CompanionTextInput?
  private var hapPairing: HAPPairing?

  public weak var delegate: ATVRemoteDelegate?

  public private(set) var connectionState: ATVConnectionState = .disconnected
  public private(set) var currentDevice: ATVDevice?
  public private(set) var discoveredDevices: [ATVDevice] = []
  public private(set) var keyboardFocusState: CompanionTextInput.KeyboardFocusState = .unfocused

  // MARK: - Initialization

  public init() {
    discovery = ATVDiscovery()
    credentialsManager = ATVCredentialsManager()
    setupDiscoveryHandlers()
  }

  private func setupDiscoveryHandlers() {
    discovery.onDeviceFound = { [weak self] device in
      print("📱 Found device: \(device.name)")
      self?.discoveredDevices.append(device)
    }

    discovery.onDeviceRemoved = { [weak self] deviceId in
      self?.discoveredDevices.removeAll { $0.id == deviceId }
    }
  }

  // MARK: - Device Discovery

  public func scanForDevices() async throws -> [ATVDevice] {
    discoveredDevices.removeAll()
    discovery.startDiscovery()

    // Wait for discovery to find devices
    try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

    discovery.stopDiscovery()
    return discoveredDevices
  }

  // MARK: - Pairing

  /// Pair with device using PIN code
  public func pairDevice(pin: String) async throws -> ATVCredentials {
    guard let connection = connection, let device = currentDevice else {
      throw ATVRemoteError.notConnected
    }

    let pairing = HAPPairing(device: device, connection: connection)
    hapPairing = pairing

    let credentials = try await pairing.startPairSetup(pin: pin)
    return credentials
  }

  /// Connect with saved credentials
  public func connectWithCredentials(to device: ATVDevice, credentials: ATVCredentials) async throws {
    // First establish TCP connection
    try await connect(to: device)

    // Then perform pair verify
    guard let connection = connection else {
      throw ATVRemoteError.notConnected
    }

    let pairing = HAPPairing(device: device, connection: connection)
    try await pairing.startPairVerify(credentials: credentials)

    print("✅ Authenticated with saved credentials")
  }

  // MARK: - Connection

  public func connect(to device: ATVDevice) async throws {
    connectionState = .connecting
    currentDevice = device

    let connection = CompanionConnection(device: device)
    self.connection = connection

    connection.onConnected = { [weak self] in
      self?.connectionState = .connected
      self?.delegate?.remoteDidConnect()
    }

    connection.onDisconnected = { [weak self] _ in
      self?.connectionState = .disconnected
      self?.delegate?.remoteDidDisconnect()
    }

    connection.onMessageReceived = { [weak self] message in
      self?.handleMessage(message)
    }

    try await connection.connect()

    // Initialize text input
    textInput = CompanionTextInput(connection: connection)
    textInput?.onFocusChanged = { [weak self] state in
      self?.keyboardFocusState = state
      print("⌨️ Keyboard focus: \(state)")
    }

    // TODO: Perform HAP pairing/authentication here
    print("✅ Connected to \(device.name)")

    // Send session start message
    do {
      let sessionStart = try CompanionMessage.sessionStart()
      try await connection.send(sessionStart)
      print("📤 Sent session start")
    } catch {
      print("⚠️ Failed to send session start: \(error)")
    }
  }

  public func disconnect() async throws {
    connection?.disconnect()
    connection = nil
    currentDevice = nil
    connectionState = .disconnected
    delegate?.remoteDidDisconnect()
  }

  // MARK: - Remote Control

  public func sendKey(_ key: ATVRemoteKey, action: ATVInputAction = .singleTap) async throws {
    guard let connection = connection else {
      throw ATVRemoteError.notConnected
    }

    print("📤 Sending key: \(key) with action: \(action)")

    // Use HID command if available
    if let hidCommand = key.hidCommand {
      try await sendHIDCommand(hidCommand, action: action)
    }
    // Use media control command if available
    else if let mediaCommand = key.mediaControlCommand {
      try await sendMediaCommand(mediaCommand)
    } else {
      throw ATVRemoteError.unsupportedKey
    }
  }

  private func sendHIDCommand(_ command: HIDCommand, action: ATVInputAction) async throws {
    guard let connection = connection else {
      throw ATVRemoteError.notConnected
    }

    switch action {
    case .singleTap:
      // Press
      let pressMessage = try CompanionMessage.hidEvent(command: command, pressed: true)
      try await connection.send(pressMessage)

      // Small delay
      try await Task.sleep(nanoseconds: 50_000_000) // 50ms

      // Release
      let releaseMessage = try CompanionMessage.hidEvent(command: command, pressed: false)
      try await connection.send(releaseMessage)

    case .hold:
      // Press
      let pressMessage = try CompanionMessage.hidEvent(command: command, pressed: true)
      try await connection.send(pressMessage)

      // Hold for 1 second
      try await Task.sleep(nanoseconds: 1_000_000_000)

      // Release
      let releaseMessage = try CompanionMessage.hidEvent(command: command, pressed: false)
      try await connection.send(releaseMessage)

    case .doubleTap:
      // First tap
      let press1 = try CompanionMessage.hidEvent(command: command, pressed: true)
      try await connection.send(press1)
      try await Task.sleep(nanoseconds: 50_000_000)
      let release1 = try CompanionMessage.hidEvent(command: command, pressed: false)
      try await connection.send(release1)

      // Small delay
      try await Task.sleep(nanoseconds: 100_000_000)

      // Second tap
      let press2 = try CompanionMessage.hidEvent(command: command, pressed: true)
      try await connection.send(press2)
      try await Task.sleep(nanoseconds: 50_000_000)
      let release2 = try CompanionMessage.hidEvent(command: command, pressed: false)
      try await connection.send(release2)
    }
  }

  private func sendMediaCommand(_ command: MediaControlCommand, params: [String: Any] = [:])
    async throws
  {
    guard let connection = connection else {
      throw ATVRemoteError.notConnected
    }

    let message = try CompanionMessage.mediaControl(command: command, params: params)
    try await connection.send(message)
  }

  private func handleMessage(_ message: CompanionMessage) {
    print("📥 Received message: type=\(message.frameType), payload=\(message.payload.count) bytes")

    // Try to decode OPACK payload
    do {
      let decoded = try OPACK.decode(message.payload)

      if let dict = decoded as? [String: Any] {
        // Handle text input events
        if dict["_t"] as? String == "_tiStarted" || dict["_t"] as? String == "_tiStopped" {
          textInput?.handleTextInputEvent(dict)
        }

        // Handle other events
        handleEventData(dict)
      }
    } catch {
      // Non-OPACK message or decoding error
      print("⚠️ Could not decode message payload: \(error)")
    }
  }

  private func handleEventData(_: [String: Any]) {
    // TODO: Handle various event types
    // - System status
    // - Now playing info
    // - Media control flags
    // - etc.
  }

  // MARK: - Navigation Shortcuts

  public func up() async throws { try await sendKey(.up) }
  public func down() async throws { try await sendKey(.down) }
  public func left() async throws { try await sendKey(.left) }
  public func right() async throws { try await sendKey(.right) }
  public func select() async throws { try await sendKey(.select) }
  public func menu() async throws { try await sendKey(.menu) }
  public func topMenu() async throws { try await sendKey(.topMenu) }
  public func home() async throws { try await sendKey(.home) }
  public func homeHold() async throws { try await sendKey(.homeHold) }
  public func playPause() async throws { try await sendKey(.playPause) }
  public func skipForward() async throws { try await sendKey(.skipForward) }
  public func skipBackward() async throws { try await sendKey(.skipBackward) }
  public func volumeUp() async throws { try await sendKey(.volumeUp) }
  public func volumeDown() async throws { try await sendKey(.volumeDown) }

  // MARK: - Text Input

  public func checkKeyboardFocus() async throws -> Bool {
    return keyboardFocusState == .focused
  }

  public func getCurrentText() async throws -> String {
    guard let textInput = textInput else {
      throw ATVRemoteError.notConnected
    }

    return try await textInput.getText()
  }

  public func setText(_ text: String) async throws {
    guard let textInput = textInput else {
      throw ATVRemoteError.notConnected
    }

    print("📝 Setting text: \(text)")
    try await textInput.setText(text)
  }

  public func appendText(_ text: String) async throws {
    guard let textInput = textInput else {
      throw ATVRemoteError.notConnected
    }

    try await textInput.appendText(text)
  }

  public func clearText() async throws {
    guard let textInput = textInput else {
      throw ATVRemoteError.notConnected
    }

    try await textInput.clearText()
  }

  // MARK: - Error Types

  public enum ATVRemoteError: Error, LocalizedError {
    case notConnected
    case deviceNotFound
    case pairingRequired
    case invalidResponse
    case unsupportedKey

    public var errorDescription: String? {
      switch self {
      case .notConnected:
        return "Not connected to Apple TV"
      case .deviceNotFound:
        return "Device not found"
      case .pairingRequired:
        return "Device pairing required"
      case .invalidResponse:
        return "Invalid response from device"
      case .unsupportedKey:
        return "Unsupported key command"
      }
    }
  }
}
