import Combine
import Foundation
import Network
import SwiftUI

// MARK: - Advanced Debug Tools View

struct AdvancedDebugToolsView: View {
  @StateObject private var networkMonitor = NetworkMonitor()
  @StateObject private var cryptoMonitor = CryptoMonitor()
  @ObservedObject var logger: DebugLogger

  @State private var selectedTool = DebugTool.messageInspector
  @State private var packetCaptureEnabled = false
  @State private var cryptoAnalysisEnabled = false

  enum DebugTool: String, CaseIterable {
    case messageInspector = "Message Inspector"
    case cryptoAnalyzer = "Crypto Analyzer"
    case networkMonitor = "Network Monitor"
    case protocolDecoder = "Protocol Decoder"
    case performanceProfiler = "Performance Profiler"
  }

  var body: some View {
    VStack(spacing: 0) {
      // Tool Selection
      Picker("Debug Tool", selection: $selectedTool) {
        ForEach(DebugTool.allCases, id: \.self) { tool in
          Text(tool.rawValue).tag(tool)
        }
      }
      .pickerStyle(.segmented)
      .padding()

      Divider()

      // Tool Content
      Group {
        switch selectedTool {
        case .messageInspector:
          MessageInspectorView(logger: logger)
        case .cryptoAnalyzer:
          CryptoAnalyzerView(cryptoMonitor: cryptoMonitor)
        case .networkMonitor:
          NetworkMonitorView(networkMonitor: networkMonitor)
        case .protocolDecoder:
          ProtocolDecoderView(logger: logger)
        case .performanceProfiler:
          PerformanceProfilerView()
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .navigationTitle("Advanced Debug Tools")
  }
}

// MARK: - Message Inspector

struct MessageInspectorView: View {
  @ObservedObject var logger: DebugLogger
  @State private var selectedMessage: DebugLogEntry?
  @State private var messageFilter = MessageFilter.all

  enum MessageFilter: String, CaseIterable {
    case all = "All Messages"
    case incoming = "Incoming"
    case outgoing = "Outgoing"
    case errors = "Errors Only"
  }

  var filteredMessages: [DebugLogEntry] {
    logger.logs.filter { entry in
      switch messageFilter {
      case .all:
        return entry.category == "MESSAGE"
      case .incoming:
        return entry.category == "MESSAGE" && entry.message.contains("Received")
      case .outgoing:
        return entry.category == "MESSAGE" && entry.message.contains("Sent")
      case .errors:
        return entry.category == "MESSAGE" && entry.level == .error
      }
    }
  }

  var body: some View {
    HSplitView {
      // Message List
      VStack(alignment: .leading) {
        HStack {
          Text("Messages")
            .font(.headline)

          Spacer()

          Picker("Filter", selection: $messageFilter) {
            ForEach(MessageFilter.allCases, id: \.self) { filter in
              Text(filter.rawValue).tag(filter)
            }
          }
          .pickerStyle(.menu)
          .frame(maxWidth: 150)
        }

        List(filteredMessages, selection: $selectedMessage) { message in
          MessageRowView(message: message)
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
      }
      .frame(minWidth: 300)

      // Message Detail
      VStack(alignment: .leading) {
        Text("Message Details")
          .font(.headline)

        if let message = selectedMessage {
          MessageDetailView(message: message)
        } else {
          Text("Select a message to view details")
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .frame(minWidth: 400)
    }
  }
}

struct MessageRowView: View {
  let message: DebugLogEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(message.timestamp, style: .time)
          .font(.caption2)
          .foregroundColor(.secondary)

        Text(message.level.rawValue)
          .font(.caption2)
          .fontWeight(.semibold)
          .foregroundColor(message.level.color)

        Spacer()
      }

      Text(message.message)
        .font(.caption)
        .lineLimit(2)
    }
    .padding(.vertical, 2)
  }
}

struct MessageDetailView: View {
  let message: DebugLogEntry

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        // Basic Info
        GroupBox("Basic Information") {
          VStack(alignment: .leading, spacing: 4) {
            DetailRow(label: "Timestamp", value: "\(message.timestamp)")
            DetailRow(label: "Level", value: message.level.rawValue)
            DetailRow(label: "Category", value: message.category)
            DetailRow(label: "Message", value: message.message)
          }
        }

        // Details
        if let details = message.details {
          GroupBox("Additional Details") {
            VStack(alignment: .leading, spacing: 4) {
              ForEach(Array(details.keys.sorted()), id: \.self) { key in
                if let value = details[key] {
                  DetailRow(label: key, value: "\(value)")
                }
              }
            }
          }
        }

        // Protocol Analysis
        if message.category == "MESSAGE", let details = message.details {
          GroupBox("Protocol Analysis") {
            ProtocolAnalysisView(messageDetails: details)
          }
        }

        Spacer()
      }
      .padding()
    }
  }
}

struct DetailRow: View {
  let label: String
  let value: String

  var body: some View {
    HStack {
      Text("\(label):")
        .fontWeight(.medium)
        .frame(minWidth: 100, alignment: .leading)

      Text(value)
        .textSelection(.enabled)

      Spacer()
    }
    .font(.caption)
  }
}

struct ProtocolAnalysisView: View {
  let messageDetails: [String: Any]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let frameType = messageDetails["frameType"] as? String {
        Text("Frame Type: \(frameType)")
          .font(.caption)
          .fontWeight(.medium)
      }

      if let payloadSize = messageDetails["payloadSize"] as? Int {
        Text("Payload Size: \(payloadSize) bytes")
          .font(.caption)
      }

      if let decoded = messageDetails["decodedPayload"] as? [String: Any] {
        Text("Decoded Content:")
          .font(.caption)
          .fontWeight(.medium)

        ForEach(Array(decoded.keys.sorted()), id: \.self) { key in
          let valueDescription = String(describing: decoded[key] ?? "nil")
          Text(verbatim: "  \(key): \(valueDescription)")
            .font(.system(.caption, design: .monospaced))
        }
      }
    }
  }
}

// MARK: - Crypto Analyzer

@MainActor
class CryptoMonitor: ObservableObject {
  @Published var keyExchangeHistory: [CryptoEvent] = []
  @Published var encryptionStats = EncryptionStats()

  struct CryptoEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let operation: String
    let success: Bool
    let details: [String: Any]
  }

  struct EncryptionStats {
    var messagesEncrypted = 0
    var messagesDecrypted = 0
    var encryptionErrors = 0
    var decryptionErrors = 0
    var averageEncryptionTime: TimeInterval = 0
    var averageDecryptionTime: TimeInterval = 0
  }

  func recordCryptoEvent(_ operation: String, success: Bool, details: [String: Any] = [:]) {
    let event = CryptoEvent(
      timestamp: Date(),
      operation: operation,
      success: success,
      details: details
    )
    keyExchangeHistory.insert(event, at: 0)

    // Update stats
    switch operation {
    case "encryption":
      if success {
        encryptionStats.messagesEncrypted += 1
      } else {
        encryptionStats.encryptionErrors += 1
      }
    case "decryption":
      if success {
        encryptionStats.messagesDecrypted += 1
      } else {
        encryptionStats.decryptionErrors += 1
      }
    default:
      break
    }
  }
}

extension CryptoMonitor.CryptoEvent: Hashable {
  static func == (lhs: CryptoMonitor.CryptoEvent, rhs: CryptoMonitor.CryptoEvent) -> Bool {
    lhs.id == rhs.id
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

struct CryptoAnalyzerView: View {
  @ObservedObject var cryptoMonitor: CryptoMonitor
  @State private var selectedEvent: CryptoMonitor.CryptoEvent?

  var body: some View {
    HSplitView {
      // Crypto Events List
      VStack(alignment: .leading) {
        Text("Cryptographic Operations")
          .font(.headline)

        List(cryptoMonitor.keyExchangeHistory, selection: $selectedEvent) { event in
          VStack(alignment: .leading, spacing: 2) {
            HStack {
              Text(event.timestamp, style: .time)
                .font(.caption2)
                .foregroundColor(.secondary)

              Circle()
                .fill(event.success ? .green : .red)
                .frame(width: 6, height: 6)

              Spacer()
            }

            Text(event.operation.capitalized)
              .font(.caption)
              .fontWeight(.medium)
          }
          .padding(.vertical, 2)
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
      }
      .frame(minWidth: 250)

      // Stats and Details
      VStack(alignment: .leading, spacing: 16) {
        // Stats
        GroupBox("Encryption Statistics") {
          Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
              Text("Messages Encrypted:")
              Text("\(cryptoMonitor.encryptionStats.messagesEncrypted)")
                .fontWeight(.medium)
            }

            GridRow {
              Text("Messages Decrypted:")
              Text("\(cryptoMonitor.encryptionStats.messagesDecrypted)")
                .fontWeight(.medium)
            }

            GridRow {
              Text("Encryption Errors:")
              Text("\(cryptoMonitor.encryptionStats.encryptionErrors)")
                .fontWeight(.medium)
                .foregroundColor(.red)
            }

            GridRow {
              Text("Decryption Errors:")
              Text("\(cryptoMonitor.encryptionStats.decryptionErrors)")
                .fontWeight(.medium)
                .foregroundColor(.red)
            }
          }
          .font(.caption)
        }

        // Event Details
        if let event = selectedEvent {
          GroupBox("Event Details") {
            VStack(alignment: .leading, spacing: 4) {
              DetailRow(label: "Operation", value: event.operation)
              DetailRow(label: "Result", value: event.success ? "Success" : "Failed")
              DetailRow(label: "Timestamp", value: "\(event.timestamp)")

              if !event.details.isEmpty {
                Text("Additional Details:")
                  .font(.caption)
                  .fontWeight(.medium)
                  .padding(.top, 8)

                ForEach(Array(event.details.keys.sorted()), id: \.self) { key in
                  DetailRow(label: key, value: "\(event.details[key] ?? "nil")")
                }
              }
            }
          }
        }

        Spacer()
      }
      .frame(minWidth: 400)
    }
  }
}

// MARK: - Network Monitor

@MainActor
class NetworkMonitor: ObservableObject {
  @Published var networkStats = NetworkStats()
  @Published var connectionHistory: [ConnectionEvent] = []

  struct NetworkStats {
    var bytesSent: Int = 0
    var bytesReceived: Int = 0
    var packetsLost: Int = 0
    var averageLatency: TimeInterval = 0
    var connectionAttempts: Int = 0
    var successfulConnections: Int = 0
  }

  struct ConnectionEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let event: String
    let details: [String: Any]
  }

  func recordNetworkEvent(_ event: String, details: [String: Any] = [:]) {
    let connectionEvent = ConnectionEvent(
      timestamp: Date(),
      event: event,
      details: details
    )
    connectionHistory.insert(connectionEvent, at: 0)

    // Update stats based on event
    switch event {
    case "connection_attempt":
      networkStats.connectionAttempts += 1
    case "connection_success":
      networkStats.successfulConnections += 1
    case "data_sent":
      if let bytes = details["bytes"] as? Int {
        networkStats.bytesSent += bytes
      }
    case "data_received":
      if let bytes = details["bytes"] as? Int {
        networkStats.bytesReceived += bytes
      }
    default:
      break
    }
  }
}

struct NetworkMonitorView: View {
  @ObservedObject var networkMonitor: NetworkMonitor

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      GroupBox("Network Statistics") {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
          GridRow {
            Text("Bytes Sent:")
            Text(
              ByteCountFormatter.string(
                fromByteCount: Int64(networkMonitor.networkStats.bytesSent), countStyle: .memory)
            )
            .fontWeight(.medium)
          }

          GridRow {
            Text("Bytes Received:")
            Text(
              ByteCountFormatter.string(
                fromByteCount: Int64(networkMonitor.networkStats.bytesReceived), countStyle: .memory
              )
            )
            .fontWeight(.medium)
          }

          GridRow {
            Text("Connection Attempts:")
            Text("\(networkMonitor.networkStats.connectionAttempts)")
              .fontWeight(.medium)
          }

          GridRow {
            Text("Successful Connections:")
            Text("\(networkMonitor.networkStats.successfulConnections)")
              .fontWeight(.medium)
              .foregroundColor(.green)
          }

          GridRow {
            Text("Success Rate:")
            Text(
              String(
                format: "%.1f%%",
                networkMonitor.networkStats.connectionAttempts > 0
                  ? Double(networkMonitor.networkStats.successfulConnections)
                    / Double(networkMonitor.networkStats.connectionAttempts) * 100.0 : 0.0)
            )
            .fontWeight(.medium)
          }
        }
        .font(.caption)
      }
      .padding(.horizontal)

      Text("Connection History")
        .font(.headline)
        .padding(.horizontal)

      List(networkMonitor.connectionHistory) { event in
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text(event.timestamp, style: .time)
              .font(.caption2)
              .foregroundColor(.secondary)

            Text(event.event.replacingOccurrences(of: "_", with: " ").capitalized)
              .font(.caption)
              .fontWeight(.medium)

            Spacer()
          }

          if !event.details.isEmpty {
            Text(event.details.map { "\($0.key): \($0.value)" }.joined(separator: ", "))
              .font(.caption2)
              .foregroundColor(.secondary)
              .lineLimit(2)
          }
        }
        .padding(.vertical, 2)
      }
      .listStyle(.bordered(alternatesRowBackgrounds: true))
    }
  }
}

// MARK: - Protocol Decoder

struct ProtocolDecoderView: View {
  @ObservedObject var logger: DebugLogger
  @State private var rawData = ""
  @State private var decodedResult = ""
  @State private var selectedFormat = DataFormat.opack

  enum DataFormat: String, CaseIterable {
    case opack = "OPACK"
    case tlv8 = "TLV8"
    case hex = "Hex"
    case base64 = "Base64"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Protocol Decoder")
        .font(.headline)

      HStack {
        Picker("Format", selection: $selectedFormat) {
          ForEach(DataFormat.allCases, id: \.self) { format in
            Text(format.rawValue).tag(format)
          }
        }
        .pickerStyle(.segmented)

        Spacer()

        Button("Decode") {
          decodeData()
        }
        .buttonStyle(.borderedProminent)
      }

      GroupBox("Raw Data Input") {
        TextEditor(text: $rawData)
          .font(.system(.caption, design: .monospaced))
          .frame(minHeight: 100)
      }

      GroupBox("Decoded Output") {
        ScrollView {
          Text(decodedResult)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 200)
      }

      Spacer()
    }
    .padding()
  }

  private func decodeData() {
    guard !rawData.isEmpty else {
      decodedResult = "Please enter data to decode"
      return
    }

    do {
      switch selectedFormat {
      case .opack:
        let data = Data(rawData.utf8)
        let decoded = try OPACK.decode(data)
        decodedResult = "OPACK Decoded:\n\(decoded)"

      case .tlv8:
        let data = Data(rawData.utf8)
        let tlv = TLV8.decodeTyped(data)
        decodedResult = "TLV8 Decoded:\n"
        for (type, value) in tlv {
          decodedResult +=
            "\(type): \(value.map { String(format: "%02x", $0) }.joined(separator: " "))\n"
        }

      case .hex:
        let cleanHex = rawData.replacingOccurrences(of: " ", with: "").replacingOccurrences(
          of: "\n", with: "")
        if cleanHex.count % 2 == 0 {
          let data = Data(cleanHex.hexadecimal ?? [])
          decodedResult = "Hex to Bytes: \(data.count) bytes\n"
          decodedResult += "As UTF-8: \(String(data: data, encoding: .utf8) ?? "Invalid UTF-8")\n"
          decodedResult +=
            "As Data: \(data.map { String(format: "%02x", $0) }.joined(separator: " "))"
        } else {
          decodedResult = "Invalid hex string (odd number of characters)"
        }

      case .base64:
        if let data = Data(base64Encoded: rawData) {
          decodedResult = "Base64 Decoded: \(data.count) bytes\n"
          decodedResult += "As UTF-8: \(String(data: data, encoding: .utf8) ?? "Invalid UTF-8")\n"
          decodedResult +=
            "As Hex: \(data.map { String(format: "%02x", $0) }.joined(separator: " "))"
        } else {
          decodedResult = "Invalid Base64 string"
        }
      }
    } catch {
      decodedResult = "Decoding error: \(error.localizedDescription)"
    }
  }
}

// MARK: - Performance Profiler

struct PerformanceProfilerView: View {
  @State private var isProfilingEnabled = false
  @State private var performanceData: [PerformanceMetric] = []

  struct PerformanceMetric: Identifiable {
    let id = UUID()
    let operation: String
    let duration: TimeInterval
    let timestamp: Date
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Performance Profiler")
          .font(.headline)

        Spacer()

        Toggle("Enable Profiling", isOn: $isProfilingEnabled)
      }

      if performanceData.isEmpty {
        Text("No performance data collected yet")
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List(performanceData, id: \.id) { metric in
          HStack {
            Text(metric.operation)
              .font(.caption)

            Spacer()

            Text(String(format: "%.2f ms", metric.duration * 1000))
              .font(.system(.caption, design: .monospaced))

            Text(metric.timestamp, style: .time)
              .font(.caption2)
              .foregroundColor(.secondary)
          }
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
      }
    }
    .padding()
  }
}

// MARK: - Helper Extensions

extension String {
  var hexadecimal: [UInt8]? {
    var startIndex = self.startIndex
    return (0..<count / 2).compactMap { _ in
      let endIndex = index(startIndex, offsetBy: 2, limitedBy: self.endIndex) ?? self.endIndex
      defer { startIndex = endIndex }
      return UInt8(self[startIndex..<endIndex], radix: 16)
    }
  }
}
