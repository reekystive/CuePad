import Foundation
import Network

/// Companion protocol connection to Apple TV
@MainActor
public class CompanionConnection {
  private var connection: NWConnection?
  private let device: ATVDevice
  private let queue = DispatchQueue(label: "com.cuepad.companion")

  public var onConnected: (() -> Void)?
  public var onDisconnected: ((Error?) -> Void)?
  public var onMessageReceived: ((CompanionMessage) -> Void)?

  private var isConnected = false
  private var receiveBuffer = Data()

  public init(device: ATVDevice) {
    self.device = device
  }

  // MARK: - Connection Management

  public func connect() async throws {
    let host = NWEndpoint.Host(device.address)
    let port = NWEndpoint.Port(integerLiteral: UInt16(device.port))
    let connection = NWConnection(host: host, port: port, using: .tcp)

    self.connection = connection

    let defaultStateHandler: @Sendable (NWConnection.State) -> Void = { [weak self] state in
      guard let self = self else { return }
      Task { @MainActor in
        self.handleStateUpdate(state)
      }
    }

    connection.stateUpdateHandler = defaultStateHandler
    connection.start(queue: queue)

    do {
      try await waitForReady(connection: connection, defaultHandler: defaultStateHandler)
    } catch {
      connection.cancel()
      throw error
    }
  }

  private func waitForReady(
    connection: NWConnection,
    defaultHandler: @Sendable @escaping (NWConnection.State) -> Void
  ) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      let waitingHandler: @Sendable (NWConnection.State) -> Void = { [weak self] state in
        guard let self = self else { return }

        switch state {
        case .ready:
          connection.stateUpdateHandler = defaultHandler
          Task { @MainActor in
            self.startReceiving()
            self.handleStateUpdate(state)
          }
          continuation.resume()

        case .failed(let error):
          connection.stateUpdateHandler = defaultHandler
          Task { @MainActor in
            self.handleStateUpdate(state)
          }
          continuation.resume(throwing: error)

        case .cancelled:
          connection.stateUpdateHandler = defaultHandler
          Task { @MainActor in
            self.handleStateUpdate(state)
          }
          continuation.resume(throwing: CompanionError.connectionCancelled)

        default:
          break
        }
      }

      connection.stateUpdateHandler = waitingHandler
    }
  }

  public func disconnect() {
    connection?.cancel()
    connection = nil
    isConnected = false
  }

  // MARK: - Message Handling

  public func send(_ message: CompanionMessage) async throws {
    guard let connection = connection, isConnected else {
      throw CompanionError.notConnected
    }

    let data = message.encode()

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      connection.send(
        content: data,
        completion: .contentProcessed { error in
          if let error = error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume()
          }
        }
      )
    }
  }

  public func send(_ data: Data) async throws {
    guard let connection = connection, isConnected else {
      throw CompanionError.notConnected
    }

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      connection.send(
        content: data,
        completion: .contentProcessed { error in
          if let error = error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume()
          }
        }
      )
    }
  }

  private func startReceiving() {
    guard let connection = connection else { return }

    connection.receiveMessage { [weak self] data, _, isComplete, error in
      guard let self = self else { return }

      Task { @MainActor in
        if let data = data, !data.isEmpty {
          self.receiveBuffer.append(data)
          self.processReceiveBuffer()
        }

        if let error = error {
          print("❌ Receive error: \(error)")
          self.onDisconnected?(error)
          return
        }

        if isComplete {
          self.onDisconnected?(nil)
          return
        }

        self.startReceiving()
      }
    }
  }

  private func processReceiveBuffer() {
    do {
      let (messages, remaining) = try CompanionMessage.decodeMultiple(receiveBuffer)

      for message in messages {
        onMessageReceived?(message)
      }

      receiveBuffer = remaining
    } catch {
      print("⚠️ Failed to decode message: \(error)")
      // Keep buffer for next attempt
    }
  }

  private func handleStateUpdate(_ state: NWConnection.State) {
    switch state {
    case .ready:
      print("✅ Connected to \(device.name)")
      isConnected = true
      onConnected?()

    case .failed(let error):
      print("❌ Connection failed: \(error)")
      isConnected = false
      onDisconnected?(error)

    case .cancelled:
      print("⏹ Connection cancelled")
      isConnected = false
      onDisconnected?(nil)

    case .waiting(let error):
      print("⏳ Waiting: \(error)")

    default:
      break
    }
  }

  // MARK: - Errors

  public enum CompanionError: Error {
    case invalidAddress
    case notConnected
    case connectionCancelled
    case invalidResponse
  }
}
