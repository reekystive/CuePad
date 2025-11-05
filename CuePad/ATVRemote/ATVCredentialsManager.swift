import Foundation

/// Manages storage and retrieval of Apple TV credentials
public class ATVCredentialsManager {
  private let fileManager = FileManager.default
  private let credentialsFileName = "atv_credentials.json"

  private var credentialsDirectory: URL {
    let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let bundleID = Bundle.main.bundleIdentifier ?? "com.cuepad.atvremote"
    let directory = appSupport.appendingPathComponent(bundleID)

    // Create directory if it doesn't exist
    try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

    return directory
  }

  private var credentialsFileURL: URL {
    return credentialsDirectory.appendingPathComponent(credentialsFileName)
  }

  // MARK: - Save & Load

  public init() {}

  public func saveCredentials(_ credentials: ATVCredentials) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    let data = try encoder.encode(credentials)
    try data.write(to: credentialsFileURL)
  }

  public func loadCredentials() throws -> ATVCredentials {
    let data = try Data(contentsOf: credentialsFileURL)
    let decoder = JSONDecoder()
    return try decoder.decode(ATVCredentials.self, from: data)
  }

  public func hasStoredCredentials() -> Bool {
    return fileManager.fileExists(atPath: credentialsFileURL.path)
  }

  public func deleteCredentials() throws {
    if hasStoredCredentials() {
      try fileManager.removeItem(at: credentialsFileURL)
    }
  }

  // MARK: - Multiple Devices Support

  private var multipleCredentialsFileURL: URL {
    return credentialsDirectory.appendingPathComponent("atv_devices.json")
  }

  public struct DeviceCredentials: Codable {
    public let deviceName: String
    public let credentials: ATVCredentials
    public let lastConnected: Date
  }

  public func saveDeviceCredentials(_ credentials: ATVCredentials, deviceName: String) throws {
    var devices = loadAllDevices()

    // Remove existing entry for this identifier
    devices.removeAll { $0.credentials.identifier == credentials.identifier }

    // Add new entry
    let deviceCreds = DeviceCredentials(
      deviceName: deviceName,
      credentials: credentials,
      lastConnected: Date()
    )
    devices.append(deviceCreds)

    // Save
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(devices)
    try data.write(to: multipleCredentialsFileURL)
  }

  public func loadAllDevices() -> [DeviceCredentials] {
    guard fileManager.fileExists(atPath: multipleCredentialsFileURL.path) else {
      return []
    }

    do {
      let data = try Data(contentsOf: multipleCredentialsFileURL)
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .iso8601
      return try decoder.decode([DeviceCredentials].self, from: data)
    } catch {
      print("Failed to load devices: \(error)")
      return []
    }
  }

  public func loadDeviceCredentials(identifier: String) -> ATVCredentials? {
    let devices = loadAllDevices()
    return devices.first { $0.credentials.identifier == identifier }?.credentials
  }

  public func deleteDevice(identifier: String) throws {
    var devices = loadAllDevices()
    devices.removeAll { $0.credentials.identifier == identifier }

    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(devices)
    try data.write(to: multipleCredentialsFileURL)
  }
}
