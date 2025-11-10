import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Debug Log Entry

public struct DebugLogEntry: Identifiable, Hashable {
  public let id = UUID()
  public let timestamp: Date
  public let level: LogLevel
  public let category: String
  public let message: String
  public let details: [String: Any]?

  public enum LogLevel: String, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case success = "SUCCESS"

    public var color: Color {
      switch self {
      case .debug: return .gray
      case .info: return .blue
      case .warning: return .orange
      case .error: return .red
      case .success: return .green
      }
    }
  }

  public static func == (lhs: DebugLogEntry, rhs: DebugLogEntry) -> Bool {
    lhs.id == rhs.id
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

// MARK: - Debug Logger

@MainActor
public class DebugLogger: ObservableObject {
  @Published public var logs: [DebugLogEntry] = []
  private let maxLogs = 1000

  public init() {}

  public func log(
    _ level: DebugLogEntry.LogLevel, category: String, message: String,
    details: [String: Any]? = nil
  ) {
    let entry = DebugLogEntry(
      timestamp: Date(),
      level: level,
      category: category,
      message: message,
      details: details
    )

    logs.insert(entry, at: 0)

    // Keep only recent logs
    if logs.count > maxLogs {
      logs = Array(logs.prefix(maxLogs))
    }

    // Also print to console
    print("[\(level.rawValue)] [\(category)] \(message)")
    if let details = details {
      print("  Details: \(details)")
    }
  }

  public func clear() {
    logs.removeAll()
  }

  public func exportLogs() -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium

    return logs.reversed().map { entry in
      var output =
        "[\(formatter.string(from: entry.timestamp))] [\(entry.level.rawValue)] [\(entry.category)] \(entry.message)"
      if let details = entry.details {
        output += "\n  Details: \(details)"
      }
      return output
    }.joined(separator: "\n")
  }
}

// MARK: - Debug Remote Control

@MainActor
class DebugRemoteController: ObservableObject {
  @Published var devices: [ATVDevice] = []
  @Published var selectedDevice: ATVDevice?
  @Published var isScanning = false
  @Published var isConnecting = false
  @Published var isPairing = false
  @Published var isConnected = false
  @Published var pinCode = ""
  @Published var connectionStep = ""
  @Published var pairingStep = ""

  private let remote = ATVRemote()
  private let credManager = ATVCredentialsManager()
  let logger: DebugLogger

  init(logger: DebugLogger) {
    self.logger = logger
    remote.delegate = self
    logger.log(.info, category: "INIT", message: "Debug Remote Controller initialized")
  }

  // MARK: - Discovery

  func startDiscovery() {
    Task {
      isScanning = true
      devices.removeAll()
      logger.log(.info, category: "DISCOVERY", message: "Starting device discovery")

      do {
        logger.log(.debug, category: "DISCOVERY", message: "Calling scanForDevices()")
        let foundDevices = try await remote.scanForDevices()

        devices = foundDevices
        logger.log(
          .success, category: "DISCOVERY", message: "Discovery completed",
          details: ["deviceCount": foundDevices.count])

        for device in foundDevices {
          logger.log(
            .info, category: "DISCOVERY", message: "Found device: \(device.name)",
            details: [
              "id": device.id,
              "address": device.address,
              "port": device.port,
              "model": device.model ?? "Unknown",
            ])
        }

      } catch {
        logger.log(
          .error, category: "DISCOVERY", message: "Discovery failed: \(error.localizedDescription)",
          details: ["error": error.localizedDescription])
      }

      isScanning = false
    }
  }

  func stopDiscovery() {
    logger.log(.info, category: "DISCOVERY", message: "Stopping discovery")
    // The remote automatically stops discovery after timeout
  }

  // MARK: - Connection

  func connectToDevice(_ device: ATVDevice) {
    Task {
      isConnecting = true
      selectedDevice = device
      connectionStep = "Initializing"

      logger.log(
        .info, category: "CONNECTION", message: "Starting connection to device",
        details: [
          "deviceName": device.name,
          "deviceId": device.id,
          "address": "\(device.address):\(device.port)",
        ])

      do {
        // Check for saved credentials first
        connectionStep = "Checking saved credentials"
        logger.log(.debug, category: "CONNECTION", message: "Checking for saved credentials")

        if let savedCreds = credManager.loadDeviceCredentials(identifier: device.id) {
          logger.log(
            .info, category: "CONNECTION", message: "Found saved credentials",
            details: [
              "credentialsId": savedCreds.identifier,
              "hasCredentials": !savedCreds.credentials.isEmpty,
              "hasCompanion": !(savedCreds.Companion?.isEmpty ?? true),
            ])

          connectionStep = "Connecting with saved credentials"
          try await remote.connectWithCredentials(to: device, credentials: savedCreds)

          connectionStep = "Connected with authentication"
          isConnected = true
          logger.log(
            .success, category: "CONNECTION",
            message: "Successfully connected with saved credentials")

        } else {
          logger.log(
            .info, category: "CONNECTION",
            message: "No saved credentials found, establishing basic connection")

          connectionStep = "Establishing TCP connection"
          try await remote.connect(to: device)

          connectionStep = "TCP connected - Pairing required"
          logger.log(
            .warning, category: "CONNECTION",
            message: "TCP connection established but pairing required")
        }

      } catch {
        connectionStep = "Connection failed"
        logger.log(
          .error, category: "CONNECTION",
          message: "Connection failed: \(error.localizedDescription)",
          details: ["error": error.localizedDescription])
      }

      isConnecting = false
    }
  }

  func disconnect() {
    Task {
      logger.log(.info, category: "CONNECTION", message: "Disconnecting from device")

      do {
        try await remote.disconnect()
        isConnected = false
        selectedDevice = nil
        connectionStep = ""
        logger.log(.success, category: "CONNECTION", message: "Disconnected successfully")
      } catch {
        logger.log(
          .error, category: "CONNECTION",
          message: "Disconnect failed: \(error.localizedDescription)")
      }
    }
  }

  // MARK: - Pairing

  func startPairing() {
    guard !pinCode.isEmpty, pinCode.count == 4 else {
      logger.log(
        .error, category: "PAIRING", message: "Invalid PIN code",
        details: ["pinLength": pinCode.count])
      return
    }

    Task {
      isPairing = true
      pairingStep = "Starting pairing process"

      logger.log(
        .info, category: "PAIRING", message: "Starting HAP pairing process",
        details: ["pin": "****"])

      do {
        pairingStep = "Initializing crypto keys"
        logger.log(.debug, category: "PAIRING", message: "Initializing cryptographic keys")

        pairingStep = "Sending M1 (Pair Setup Start)"
        logger.log(.debug, category: "PAIRING", message: "Sending M1: Pair Setup Start request")

        pairingStep = "Processing M2 response"
        logger.log(.debug, category: "PAIRING", message: "Processing M2 response from device")

        pairingStep = "Performing SRP authentication"
        logger.log(.debug, category: "PAIRING", message: "Performing SRP authentication with PIN")

        pairingStep = "Sending M3 (Verify Request)"
        logger.log(
          .debug, category: "PAIRING", message: "Sending M3: Verify Request with client proof")

        pairingStep = "Validating M4 response"
        logger.log(.debug, category: "PAIRING", message: "Validating M4 response and server proof")

        pairingStep = "Key exchange (M5/M6)"
        logger.log(.debug, category: "PAIRING", message: "Performing Ed25519 key exchange")

        let credentials = try await remote.pairDevice(pin: pinCode)

        pairingStep = "Saving credentials"
        logger.log(.debug, category: "PAIRING", message: "Saving pairing credentials")

        // Save credentials
        if let device = selectedDevice {
          try credManager.saveCredentials(credentials)
          try credManager.saveDeviceCredentials(credentials, deviceName: device.name)

          logger.log(
            .success, category: "PAIRING", message: "Pairing completed successfully",
            details: [
              "credentialsId": credentials.identifier,
              "deviceName": device.name,
            ])
        }

        isConnected = true
        pairingStep = "Pairing completed"
        pinCode = ""

      } catch {
        pairingStep = "Pairing failed"
        logger.log(
          .error, category: "PAIRING", message: "Pairing failed: \(error.localizedDescription)",
          details: ["error": error.localizedDescription])
      }

      isPairing = false
    }
  }

  // MARK: - Remote Commands

  func sendRemoteKey(_ key: ATVRemoteKey, action: ATVInputAction = .singleTap) {
    Task {
      logger.log(
        .info, category: "REMOTE", message: "Sending remote command",
        details: [
          "key": String(describing: key),
          "action": String(describing: action),
        ])

      do {
        try await remote.sendKey(key, action: action)
        logger.log(.success, category: "REMOTE", message: "Command sent successfully")
      } catch {
        logger.log(
          .error, category: "REMOTE", message: "Command failed: \(error.localizedDescription)",
          details: ["error": error.localizedDescription])
      }
    }
  }

  func testSequence() {
    Task {
      logger.log(.info, category: "TEST", message: "Starting test sequence")

      do {
        // Test navigation
        logger.log(.debug, category: "TEST", message: "Testing navigation - Up")
        try await remote.sendKey(.up)
        try await Task.sleep(nanoseconds: 500_000_000)

        logger.log(.debug, category: "TEST", message: "Testing navigation - Down")
        try await remote.sendKey(.down)
        try await Task.sleep(nanoseconds: 500_000_000)

        logger.log(.debug, category: "TEST", message: "Testing navigation - Left")
        try await remote.sendKey(.left)
        try await Task.sleep(nanoseconds: 500_000_000)

        logger.log(.debug, category: "TEST", message: "Testing navigation - Right")
        try await remote.sendKey(.right)
        try await Task.sleep(nanoseconds: 500_000_000)

        logger.log(.success, category: "TEST", message: "Test sequence completed")
      } catch {
        logger.log(
          .error, category: "TEST", message: "Test sequence failed: \(error.localizedDescription)")
      }
    }
  }
}

// MARK: - Remote Delegate

extension DebugRemoteController: ATVRemoteDelegate {
  nonisolated func remoteDidConnect() {
    Task { @MainActor in
      logger.log(.success, category: "DELEGATE", message: "Remote connected")
      isConnected = true
    }
  }

  nonisolated func remoteDidDisconnect() {
    Task { @MainActor in
      logger.log(.info, category: "DELEGATE", message: "Remote disconnected")
      isConnected = false
    }
  }

  nonisolated func remoteConnectionLost() {
    Task { @MainActor in
      logger.log(.warning, category: "DELEGATE", message: "Remote connection lost")
      isConnected = false
    }
  }

  nonisolated func remoteKeyboardFocusChanged(
    oldState: ATVKeyboardFocusState, newState: ATVKeyboardFocusState
  ) {
    Task { @MainActor in
      logger.log(
        .info, category: "DELEGATE", message: "Keyboard focus changed",
        details: [
          "oldState": String(describing: oldState),
          "newState": String(describing: newState),
        ])
    }
  }

  nonisolated func remotePowerStateChanged(oldState: String, newState: String) {
    Task { @MainActor in
      logger.log(
        .info, category: "DELEGATE", message: "Power state changed",
        details: [
          "oldState": oldState,
          "newState": newState,
        ])
    }
  }
}

// MARK: - Main Debug Panel View

struct DebugPanelView: View {
  @StateObject private var logger = DebugLogger()
  @StateObject private var controller: DebugRemoteController
  @State private var selectedLogLevel: DebugLogEntry.LogLevel?
  @State private var selectedCategory: String?
  @State private var searchText = ""
  @State private var showAdvancedTools = false

  init() {
    let tempLogger = DebugLogger()
    _controller = StateObject(wrappedValue: DebugRemoteController(logger: tempLogger))
    _logger = StateObject(wrappedValue: tempLogger)
  }

  var filteredLogs: [DebugLogEntry] {
    logger.logs.filter { entry in
      let matchesLevel = selectedLogLevel == nil || entry.level == selectedLogLevel
      let matchesCategory =
        selectedCategory == nil || selectedCategory == "All" || entry.category == selectedCategory
      let matchesSearch =
        searchText.isEmpty || entry.message.localizedCaseInsensitiveContains(searchText)
        || entry.category.localizedCaseInsensitiveContains(searchText)

      return matchesLevel && matchesCategory && matchesSearch
    }
  }

  var categories: [String] {
    let allCategories = Set(logger.logs.map { $0.category })
    return ["All"] + allCategories.sorted()
  }

  var body: some View {
    HSplitView {
      // Left Panel - Controls
      VStack(alignment: .leading, spacing: 16) {
        Text("Debug Controls")
          .font(.headline)

        Divider()

        // Discovery Section
        VStack(alignment: .leading, spacing: 8) {
          Text("Device Discovery")
            .font(.subheadline)
            .fontWeight(.semibold)

          HStack {
            Button("Scan") {
              controller.startDiscovery()
            }
            .disabled(controller.isScanning)

            Button("Stop") {
              controller.stopDiscovery()
            }
            .disabled(!controller.isScanning)
          }

          if controller.isScanning {
            ProgressView("Scanning...")
              .scaleEffect(0.8)
          }

          List(controller.devices) { device in
            Button {
              controller.connectToDevice(device)
            } label: {
              VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                  .font(.caption)
                Text("\(device.address):\(device.port)")
                  .font(.caption2)
                  .foregroundColor(.secondary)
              }
            }
            .disabled(controller.isConnecting)
          }
          .frame(height: 120)
        }

        Divider()

        // Connection Section
        VStack(alignment: .leading, spacing: 8) {
          Text("Connection")
            .font(.subheadline)
            .fontWeight(.semibold)

          if let device = controller.selectedDevice {
            Text("Device: \(device.name)")
              .font(.caption)

            if !controller.connectionStep.isEmpty {
              Text("Step: \(controller.connectionStep)")
                .font(.caption)
                .foregroundColor(.blue)
            }
          }

          HStack {
            Circle()
              .fill(controller.isConnected ? .green : .red)
              .frame(width: 8, height: 8)
            Text(controller.isConnected ? "Connected" : "Disconnected")
              .font(.caption)
          }

          if controller.isConnected {
            Button("Disconnect") {
              controller.disconnect()
            }
          }
        }

        Divider()

        // Pairing Section
        VStack(alignment: .leading, spacing: 8) {
          Text("HAP Pairing")
            .font(.subheadline)
            .fontWeight(.semibold)

          if !controller.pairingStep.isEmpty {
            Text("Step: \(controller.pairingStep)")
              .font(.caption)
              .foregroundColor(.orange)
          }

          TextField("PIN Code", text: $controller.pinCode)
            .textFieldStyle(.roundedBorder)
            .font(.system(.caption, design: .monospaced))
            .disabled(controller.isPairing)

          Button("Start Pairing") {
            controller.startPairing()
          }
          .disabled(controller.isPairing || controller.pinCode.count != 4)

          if controller.isPairing {
            ProgressView("Pairing...")
              .scaleEffect(0.8)
          }
        }

        Divider()

        // Remote Commands Section
        VStack(alignment: .leading, spacing: 8) {
          Text("Remote Commands")
            .font(.subheadline)
            .fontWeight(.semibold)

          LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 4) {
            Button("↑") { controller.sendRemoteKey(.up) }
              .frame(height: 30)
            Button("") {}
              .disabled(true)
              .opacity(0)
            Button("") {}
              .disabled(true)
              .opacity(0)

            Button("←") { controller.sendRemoteKey(.left) }
              .frame(height: 30)
            Button("OK") { controller.sendRemoteKey(.select) }
              .frame(height: 30)
            Button("→") { controller.sendRemoteKey(.right) }
              .frame(height: 30)

            Button("") {}
              .disabled(true)
              .opacity(0)
            Button("↓") { controller.sendRemoteKey(.down) }
              .frame(height: 30)
            Button("") {}
              .disabled(true)
              .opacity(0)
          }
          .disabled(!controller.isConnected)

          HStack {
            Button("Menu") { controller.sendRemoteKey(.menu) }
            Button("Home") { controller.sendRemoteKey(.home) }
          }
          .disabled(!controller.isConnected)

          Button("Test Sequence") {
            controller.testSequence()
          }
          .disabled(!controller.isConnected)
        }

        Spacer()
      }
      .padding()
      .frame(minWidth: 280, maxWidth: 320)

      // Right Panel - Logs and Advanced Tools
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("Debug Logs")
            .font(.headline)

          Spacer()

          Button("Advanced Tools") {
            showAdvancedTools.toggle()
          }

          Button("Clear") {
            logger.clear()
          }

          Button("Export") {
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.plainText]
            savePanel.nameFieldStringValue = "debug_logs.txt"

            if savePanel.runModal() == .OK, let url = savePanel.url {
              let content = logger.exportLogs()
              try? content.write(to: url, atomically: true, encoding: .utf8)
            }
          }
        }

        // Filters
        HStack {
          Picker("Level", selection: $selectedLogLevel) {
            Text("All Levels").tag(Optional<DebugLogEntry.LogLevel>.none)
            ForEach(DebugLogEntry.LogLevel.allCases, id: \.self) { level in
              Text(level.rawValue).tag(Optional(level))
            }
          }
          .pickerStyle(.menu)
          .frame(maxWidth: 120)

          Picker("Category", selection: $selectedCategory) {
            ForEach(categories, id: \.self) { category in
              Text(category).tag(Optional(category))
            }
          }
          .pickerStyle(.menu)
          .frame(maxWidth: 120)

          TextField("Search", text: $searchText)
            .textFieldStyle(.roundedBorder)
        }

        // Logs List
        List(filteredLogs) { entry in
          LogEntryView(entry: entry)
        }
        .listStyle(.plain)
      }
      .padding()
      .frame(minWidth: 500)
    }
    .frame(minWidth: 800, minHeight: 600)
    .navigationTitle("Apple TV Remote Debug Panel")
    .sheet(isPresented: $showAdvancedTools) {
      AdvancedDebugToolsView(logger: logger)
        .frame(minWidth: 800, minHeight: 600)
    }
  }
}

// MARK: - Log Entry View

struct LogEntryView: View {
  let entry: DebugLogEntry
  @State private var isExpanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        // Timestamp
        Text(entry.timestamp, style: .time)
          .font(.caption2)
          .foregroundColor(.secondary)
          .frame(width: 70, alignment: .leading)

        // Level
        Text(entry.level.rawValue)
          .font(.caption2)
          .fontWeight(.semibold)
          .foregroundColor(entry.level.color)
          .frame(width: 60, alignment: .leading)

        // Category
        Text(entry.category)
          .font(.caption2)
          .fontWeight(.medium)
          .frame(width: 80, alignment: .leading)

        // Message
        Text(entry.message)
          .font(.caption)
          .lineLimit(isExpanded ? nil : 1)

        Spacer()

        if entry.details != nil {
          Button {
            isExpanded.toggle()
          } label: {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
              .font(.caption2)
          }
          .buttonStyle(.plain)
        }
      }

      if isExpanded, let details = entry.details {
        VStack(alignment: .leading, spacing: 2) {
          Text("Details:")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)

          ForEach(Array(details.keys.sorted()), id: \.self) { key in
            HStack {
              Text(key)
                .font(.caption2)
                .fontWeight(.medium)
              Text(": \(String(describing: details[key] ?? ""))")
                .font(.caption2)
            }
            .padding(.leading, 8)
          }
        }
        .padding(.leading, 220)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(4)
      }
    }
    .padding(.vertical, 2)
  }
}

// MARK: - Preview

#Preview {
  DebugPanelView()
    .frame(width: 1000, height: 700)
}
