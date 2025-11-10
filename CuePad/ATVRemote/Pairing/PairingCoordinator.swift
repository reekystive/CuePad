import Foundation

/// Coordinates HAP pairing message flow with proper async/await handling
public class PairingCoordinator {
  private var connection: CompanionConnection
  private var messageQueue: [CompanionMessage] = []
  private var waitingContinuations: [CheckedContinuation<CompanionMessage, Error>] = []

  private let queue = DispatchQueue(label: "com.cuepad.pairing")

  public init(connection: CompanionConnection) {
    self.connection = connection
    setupMessageHandler()
  }

  private func setupMessageHandler() {
    connection.onMessageReceived = { [weak self] message in
      self?.handleIncomingMessage(message)
    }
  }

  // MARK: - Message Waiting

  /// Wait for next message from device
  public func waitForMessage(timeout: TimeInterval = 10.0) async throws -> CompanionMessage {
    return try await withCheckedThrowingContinuation { continuation in
      queue.sync {
        // If we already have a message, return it immediately
        if !messageQueue.isEmpty {
          let message = messageQueue.removeFirst()
          continuation.resume(returning: message)
        } else {
          // Store continuation to be resumed when message arrives
          waitingContinuations.append(continuation)
        }
      }

      // Timeout handling
      Task {
        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        queue.sync {
          if let index = waitingContinuations.firstIndex(where: { _ in true }) {
            let cont = waitingContinuations.remove(at: index)
            cont.resume(throwing: PairingError.timeout)
          }
        }
      }
    }
  }

  private func handleIncomingMessage(_ message: CompanionMessage) {
    queue.sync {
      if let continuation = waitingContinuations.first {
        waitingContinuations.removeFirst()
        continuation.resume(returning: message)
      } else {
        // No one waiting, queue the message
        messageQueue.append(message)
      }
    }
  }

  // MARK: - Send and Wait

  /// Send a message and wait for response
  public func sendAndWait(_ message: CompanionMessage, timeout: TimeInterval = 10.0) async throws
    -> CompanionMessage
  {
    try await connection.send(message)
    return try await waitForMessage(timeout: timeout)
  }

  // MARK: - Errors

  public enum PairingError: Error, LocalizedError {
    case timeout
    case invalidResponse

    public var errorDescription: String? {
      switch self {
      case .timeout:
        return "Pairing message timeout"
      case .invalidResponse:
        return "Invalid pairing response"
      }
    }
  }
}
