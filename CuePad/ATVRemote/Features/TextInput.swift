import Foundation

/// Text input support for Companion protocol
public class CompanionTextInput {
  private weak var connection: CompanionConnection?

  public var focusState: KeyboardFocusState = .unfocused
  public var onFocusChanged: ((KeyboardFocusState) -> Void)?

  public enum KeyboardFocusState {
    case focused
    case unfocused
  }

  public init(connection: CompanionConnection) {
    self.connection = connection
  }

  // MARK: - Text Operations

  /// Get current text from focused input field
  public func getText() async throws -> String {
    guard focusState == .focused else {
      throw TextInputError.notFocused
    }

    let payload: [String: Any] = [
      "_t": "_tiStart",
      "_tiData": [
        "text": "",
        "clear": false,
      ],
    ]

    let data = try OPACK.encode(payload)
    let message = CompanionMessage(frameType: .event, payload: data)

    try await connection?.send(message)

    // TODO: Wait for response with current text
    return ""
  }

  /// Set text in focused input field (replaces existing)
  public func setText(_ text: String) async throws {
    guard focusState == .focused else {
      throw TextInputError.notFocused
    }

    let payload: [String: Any] = [
      "_t": "_tiStart",
      "_tiData": [
        "text": text,
        "clear": true,  // Clear previous input
      ],
    ]

    let data = try OPACK.encode(payload)
    let message = CompanionMessage(frameType: .event, payload: data)

    try await connection?.send(message)
  }

  /// Append text to focused input field
  public func appendText(_ text: String) async throws {
    guard focusState == .focused else {
      throw TextInputError.notFocused
    }

    let payload: [String: Any] = [
      "_t": "_tiStart",
      "_tiData": [
        "text": text,
        "clear": false,  // Append to existing
      ],
    ]

    let data = try OPACK.encode(payload)
    let message = CompanionMessage(frameType: .event, payload: data)

    try await connection?.send(message)
  }

  /// Clear all text in focused input field
  public func clearText() async throws {
    guard focusState == .focused else {
      throw TextInputError.notFocused
    }

    let payload: [String: Any] = [
      "_t": "_tiStart",
      "_tiData": [
        "text": "",
        "clear": true,
      ],
    ]

    let data = try OPACK.encode(payload)
    let message = CompanionMessage(frameType: .event, payload: data)

    try await connection?.send(message)
  }

  /// Stop text input session
  public func stopTextInput() async throws {
    let payload: [String: Any] = [
      "_t": "_tiStopped"
    ]

    let data = try OPACK.encode(payload)
    let message = CompanionMessage(frameType: .event, payload: data)

    try await connection?.send(message)
  }

  // MARK: - Event Handling

  /// Handle text input event from device
  public func handleTextInputEvent(_ data: [String: Any]) {
    // Check if "_tiD" key exists (indicates focused state)
    let newState: KeyboardFocusState = data["_tiD"] != nil ? .focused : .unfocused

    if newState != focusState {
      focusState = newState
      onFocusChanged?(newState)
    }
  }

  // MARK: - Errors

  public enum TextInputError: Error, LocalizedError {
    case notFocused
    case invalidResponse

    public var errorDescription: String? {
      switch self {
      case .notFocused:
        return "No text field is currently focused on Apple TV"
      case .invalidResponse:
        return "Invalid response from device"
      }
    }
  }
}
