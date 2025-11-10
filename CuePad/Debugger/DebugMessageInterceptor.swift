import Foundation

// MARK: - Debug Message Interceptor

public class DebugMessageInterceptor {
  public static let shared = DebugMessageInterceptor()

  private(set) var logger: DebugLogger?

  private init() {}

  public func setLogger(_ logger: DebugLogger) {
    self.logger = logger
  }

  public func logCompanionMessage(_ message: CompanionMessage, direction: MessageDirection) {
    guard let logger = logger else { return }

    Task { @MainActor in
      let details: [String: Any] = [
        "frameType": String(describing: message.frameType),
        "payloadSize": message.payload.count,
        "direction": direction.rawValue,
      ]

      // Try to decode OPACK payload for additional info
      var decodedInfo: [String: Any] = [:]
      do {
        let decoded = try OPACK.decode(message.payload)
        if let dict = decoded as? [String: Any] {
          decodedInfo = dict
        }
      } catch {
        decodedInfo["decodeError"] = error.localizedDescription
      }

      var allDetails = details
      if !decodedInfo.isEmpty {
        allDetails["decodedPayload"] = decodedInfo
      }

      logger.log(
        direction == .outgoing ? .info : .debug,
        category: "MESSAGE",
        message: "\(direction == .outgoing ? "Sent" : "Received") \(message.frameType) message",
        details: allDetails
      )
    }
  }

  public func logTCPConnection(host: String, port: Int, event: ConnectionEvent) {
    guard let logger = logger else { return }

    Task { @MainActor in
      let details: [String: Any] = [
        "host": host,
        "port": port,
        "event": event.rawValue,
      ]

      let level: DebugLogEntry.LogLevel =
        switch event {
        case .connecting: .debug
        case .connected: .success
        case .disconnected, .error: .warning
        case .timeout: .error
        }

      logger.log(
        level,
        category: "TCP",
        message: "TCP connection \(event.rawValue)",
        details: details
      )
    }
  }

  public func logCryptoOperation(
    _ operation: CryptoOperation, success: Bool, details: [String: Any]? = nil
  ) {
    guard let logger = logger else { return }

    Task { @MainActor in
      var logDetails: [String: Any] = [
        "operation": operation.rawValue,
        "success": success,
      ]

      if let additionalDetails = details {
        logDetails.merge(additionalDetails) { (_, new) in new }
      }

      logger.log(
        success ? .success : .error,
        category: "CRYPTO",
        message: "\(operation.rawValue) \(success ? "succeeded" : "failed")",
        details: logDetails
      )
    }
  }

  public enum MessageDirection: String {
    case incoming = "incoming"
    case outgoing = "outgoing"
  }

  public enum ConnectionEvent: String {
    case connecting = "connecting"
    case connected = "connected"
    case disconnected = "disconnected"
    case error = "error"
    case timeout = "timeout"
  }

  public enum CryptoOperation: String {
    case keyGeneration = "key_generation"
    case keyExchange = "key_exchange"
    case encryption = "encryption"
    case decryption = "decryption"
    case signing = "signing"
    case verification = "verification"
    case srpAuth = "srp_authentication"
    case hkdfDerivation = "hkdf_derivation"
  }
}

// MARK: - Enhanced Debug Extensions

extension ATVRemote {
  public func enableDebugMode(logger: DebugLogger) {
    DebugMessageInterceptor.shared.setLogger(logger)
    // This would be called from within ATVRemote methods to log operations
  }
}

extension HAPPairing {
  public func logPairingStep(_ step: String, details: [String: Any]? = nil) {
    DebugMessageInterceptor.shared.logger?.log(
      .debug,
      category: "HAP_PAIRING",
      message: step,
      details: details
    )
  }
}

extension CompanionConnection {
  public func logConnectionEvent(
    _ event: DebugMessageInterceptor.ConnectionEvent, details: [String: Any]? = nil
  ) {
    // This would be implemented to log connection events
    print("Connection event: \(event) - \(details ?? [:])")
  }
}

// MARK: - Protocol Debug Helpers

public struct ProtocolDebugHelper {
  public static func formatTLV8Data(_ data: Data) -> String {
    let tlv = TLV8.decodeTyped(data)
    guard !tlv.isEmpty else {
      return "TLV8 Data: (empty)"
    }

    var output = "TLV8 Data:\n"

    for (type, value) in tlv {
      output += "  \(type): \(value.hexSpacedString)\n"
    }

    return output
  }

  public static func formatOPACKData(_ data: Data) -> String {
    do {
      let decoded = try OPACK.decode(data)
      return "OPACK Data: \(decoded)"
    } catch {
      return "Failed to decode OPACK: \(error)"
    }
  }

  public static func formatCompanionFrame(_ message: CompanionMessage) -> String {
    var output = "Frame Type: \(message.frameType)\n"
    output += "Payload Size: \(message.payload.count) bytes\n"

    // Try to decode payload
    if message.payload.count > 0 {
      // Try OPACK first
      if let opackResult = try? OPACK.decode(message.payload) {
        output += "OPACK Content: \(opackResult)\n"
      }
      // Try TLV8 if OPACK fails
      else if message.payload.count >= 2 {
        let tlv = TLV8.decodeTyped(message.payload)
        if tlv.isEmpty {
          output += "Raw Payload: \(message.payload.hexSpacedString)\n"
        } else {
          output += "TLV8 Content:\n"
          for (type, value) in tlv {
            output += "  \(type): \(value.hexSpacedString)\n"
          }
        }
      } else {
        output += "Raw Payload: \(message.payload.hexSpacedString)\n"
      }
    }

    return output
  }
}

// MARK: - Data Extension for Hex Display

extension Data {
  fileprivate var hexSpacedString: String {
    map { String(format: "%02x", $0) }.joined(separator: " ")
  }
}
