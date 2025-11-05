import Combine
import SwiftUI

@MainActor
class RemoteViewModel: ObservableObject {
  @Published var devices: [ATVDevice] = []
  @Published var isScanning = false
  @Published var isConnected = false
  @Published var currentDevice: ATVDevice?
  @Published var statusMessage = "Ready"
  @Published var errorMessage: String?

  private let remote = ATVRemote()
  private let credManager = ATVCredentialsManager()

  init() {
    remote.delegate = self
  }

  // MARK: - Discovery

  func scanForDevices() {
    Task {
      isScanning = true
      statusMessage = "Scanning for devices..."
      errorMessage = nil

      do {
        devices = try await remote.scanForDevices()
        statusMessage = "Found \(devices.count) device(s)"
      } catch {
        errorMessage = "Scan failed: \(error.localizedDescription)"
        statusMessage = "Scan failed"
      }

      isScanning = false
    }
  }

  // MARK: - Connection

  func connect(to device: ATVDevice) {
    Task {
      statusMessage = "Connecting to \(device.name)..."
      errorMessage = nil

      do {
        try await remote.connect(to: device)
        currentDevice = device
        isConnected = true
        statusMessage = "Connected to \(device.name)"
      } catch {
        errorMessage = "Connection failed: \(error.localizedDescription)"
        statusMessage = "Connection failed"
      }
    }
  }

  func disconnect() {
    Task {
      do {
        try await remote.disconnect()
        currentDevice = nil
        isConnected = false
        statusMessage = "Disconnected"
      } catch {
        errorMessage = "Disconnect failed: \(error.localizedDescription)"
      }
    }
  }

  // MARK: - Remote Control

  func sendKey(_ key: ATVRemoteKey) {
    Task {
      do {
        try await remote.sendKey(key)
      } catch {
        errorMessage = "Command failed: \(error.localizedDescription)"
      }
    }
  }

  func sendKeyWithAction(_ key: ATVRemoteKey, action: ATVInputAction) {
    Task {
      do {
        try await remote.sendKey(key, action: action)
      } catch {
        errorMessage = "Command failed: \(error.localizedDescription)"
      }
    }
  }
}

// MARK: - Delegate

extension RemoteViewModel: ATVRemoteDelegate {
  nonisolated func remoteDidConnect() {
    Task { @MainActor in
      isConnected = true
      statusMessage = "Connected"
    }
  }

  nonisolated func remoteDidDisconnect() {
    Task { @MainActor in
      isConnected = false
      statusMessage = "Disconnected"
    }
  }

  nonisolated func remoteConnectionLost() {
    Task { @MainActor in
      errorMessage = "Connection lost"
    }
  }
}

// MARK: - Views

struct RemoteControlView: View {
  @StateObject private var viewModel = RemoteViewModel()

  var body: some View {
    HSplitView {
      // Left sidebar
      VStack(alignment: .leading, spacing: 16) {
        Text("Apple TV Devices")
          .font(.headline)

        if viewModel.isScanning {
          ProgressView("Scanning...")
            .padding()
        } else {
          List(viewModel.devices) { device in
            Button {
              viewModel.connect(to: device)
            } label: {
              VStack(alignment: .leading) {
                Text(device.name)
                  .font(.body)
                Text("\(device.address):\(device.port)")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
          }
          .frame(minHeight: 200)
        }

        HStack {
          Button("Scan") {
            viewModel.scanForDevices()
          }
          .disabled(viewModel.isScanning)

          Spacer()

          if viewModel.isConnected {
            Button("Disconnect") {
              viewModel.disconnect()
            }
          }
        }
        .padding(.top, 8)

        Divider()

        // Status
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Circle()
              .fill(viewModel.isConnected ? Color.green : Color.red)
              .frame(width: 10, height: 10)
            Text(viewModel.statusMessage)
              .font(.caption)
          }

          if let error = viewModel.errorMessage {
            Text(error)
              .font(.caption)
              .foregroundColor(.red)
          }

          if let device = viewModel.currentDevice {
            Text("Device: \(device.name)")
              .font(.caption)
            if let model = device.model {
              Text("Model: \(model)")
                .font(.caption)
            }
          }
        }
        .padding(.top, 8)

        Spacer()
      }
      .padding()
      .frame(minWidth: 280)

      // Right control panel
      VStack(spacing: 24) {
        Text("Remote Control")
          .font(.title)

        if viewModel.isConnected {
          // D-Pad
          VStack(spacing: 12) {
            Button {
              viewModel.sendKey(.up)
            } label: {
              Image(systemName: "chevron.up")
                .font(.title)
                .frame(width: 60, height: 60)
            }

            HStack(spacing: 12) {
              Button {
                viewModel.sendKey(.left)
              } label: {
                Image(systemName: "chevron.left")
                  .font(.title)
                  .frame(width: 60, height: 60)
              }

              Button {
                viewModel.sendKey(.select)
              } label: {
                Text("OK")
                  .font(.headline)
                  .frame(width: 60, height: 60)
              }
              .buttonStyle(.borderedProminent)

              Button {
                viewModel.sendKey(.right)
              } label: {
                Image(systemName: "chevron.right")
                  .font(.title)
                  .frame(width: 60, height: 60)
              }
            }

            Button {
              viewModel.sendKey(.down)
            } label: {
              Image(systemName: "chevron.down")
                .font(.title)
                .frame(width: 60, height: 60)
            }
          }
          .padding(.vertical, 20)

          // Menu buttons
          HStack(spacing: 16) {
            Button("Menu") {
              viewModel.sendKey(.menu)
            }
            .frame(width: 80)

            Button("Home") {
              viewModel.sendKey(.home)
            }
            .frame(width: 80)
          }

          Divider()

          // Playback controls
          HStack(spacing: 16) {
            Button {
              viewModel.sendKey(.skipBackward)
            } label: {
              Image(systemName: "backward.fill")
            }

            Button {
              viewModel.sendKey(.playPause)
            } label: {
              Image(systemName: "playpause.fill")
            }
            .buttonStyle(.borderedProminent)

            Button {
              viewModel.sendKey(.skipForward)
            } label: {
              Image(systemName: "forward.fill")
            }
          }
          .font(.title2)

          Divider()

          // Volume controls
          HStack(spacing: 16) {
            Button {
              viewModel.sendKey(.volumeDown)
            } label: {
              Image(systemName: "speaker.wave.1.fill")
            }

            Button {
              viewModel.sendKey(.volumeUp)
            } label: {
              Image(systemName: "speaker.wave.3.fill")
            }
          }
          .font(.title2)

        } else {
          Text("Not Connected")
            .foregroundColor(.secondary)
            .padding()

          Text("Scan for devices and connect to start controlling your Apple TV")
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding()
        }

        Spacer()
      }
      .padding()
      .frame(minWidth: 400)
    }
    .frame(minWidth: 700, minHeight: 500)
  }
}

// MARK: - Preview

#Preview {
  RemoteControlView()
}
