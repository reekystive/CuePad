import Foundation
import Network

/// Apple TV device discovered via Bonjour
public struct ATVDevice: Identifiable, Hashable {
  public let id: String
  public let name: String
  public let address: String
  public let port: Int
  public let model: String?
  public let properties: [String: String]

  public init(
    id: String, name: String, address: String, port: Int, model: String? = nil,
    properties: [String: String] = [:]
  ) {
    self.id = id
    self.name = name
    self.address = address
    self.port = port
    self.model = model
    self.properties = properties
  }
}

/// Device discovery using Bonjour/mDNS
public class ATVDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
  private let companionBrowser = NetServiceBrowser()
  private let airplayBrowser = NetServiceBrowser()
  private var resolvingServices: Set<NetService> = []
  private var discoveredDevices: [String: ATVDevice] = [:]

  public var onDeviceFound: ((ATVDevice) -> Void)?
  public var onDeviceRemoved: ((String) -> Void)?

  override public init() {
    super.init()
    companionBrowser.delegate = self
    airplayBrowser.delegate = self
  }

  // MARK: - Public API

  public func startDiscovery() {
    print("🔍 Starting Apple TV discovery...")
    // Search for Companion protocol (primary)
    companionBrowser.searchForServices(ofType: "_companion-link._tcp.", inDomain: "local.")
    // Also search for AirPlay (backup)
    airplayBrowser.searchForServices(ofType: "_airplay._tcp.", inDomain: "local.")
  }

  public func stopDiscovery() {
    print("⏹ Stopping discovery...")
    companionBrowser.stop()
    airplayBrowser.stop()
    resolvingServices.forEach { $0.stop() }
    resolvingServices.removeAll()
  }

  public func getDiscoveredDevices() -> [ATVDevice] {
    return Array(discoveredDevices.values)
  }

  // MARK: - NetServiceBrowserDelegate

  public func netServiceBrowser(
    _: NetServiceBrowser, didFind service: NetService, moreComing _: Bool
  ) {
    print("📱 Found service: \(service.name) of type \(service.type)")

    // Resolve the service to get IP and port
    service.delegate = self
    resolvingServices.insert(service)
    service.resolve(withTimeout: 10.0)
  }

  public func netServiceBrowser(
    _: NetServiceBrowser, didRemove service: NetService, moreComing _: Bool
  ) {
    let deviceId = "\(service.name)_\(service.type)"
    print("❌ Lost service: \(service.name)")

    discoveredDevices.removeValue(forKey: deviceId)
    onDeviceRemoved?(deviceId)
  }

  public func netServiceBrowser(
    _: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]
  ) {
    print("❌ Discovery failed: \(errorDict)")
  }

  // MARK: - NetServiceDelegate

  public func netServiceDidResolveAddress(_ service: NetService) {
    guard let addresses = service.addresses, !addresses.isEmpty else {
      print("⚠️ No addresses found for \(service.name)")
      resolvingServices.remove(service)
      return
    }

    // Get first IPv4 address
    var ipAddress: String?
    for addressData in addresses {
      let data = addressData as Data
      let family = data.withUnsafeBytes { $0.load(fromByteOffset: 1, as: UInt8.self) }

      if family == AF_INET {
        data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
          let sockaddrPtr = ptr.baseAddress!.assumingMemoryBound(to: sockaddr_in.self)
          var addr = sockaddrPtr.pointee
          ipAddress = withUnsafePointer(to: &addr.sin_addr) { addrPtr in
            String(cString: inet_ntoa(addrPtr.pointee))
          }
        }
        break
      }
    }

    guard let ip = ipAddress else {
      print("⚠️ No IPv4 address for \(service.name)")
      resolvingServices.remove(service)
      return
    }

    // Extract properties from TXT record
    var properties: [String: String] = [:]
    if let txtData = service.txtRecordData() {
      let txtDict = NetService.dictionary(fromTXTRecord: txtData)
      for (key, value) in txtDict {
        if let stringValue = String(data: value, encoding: .utf8) {
          properties[key] = stringValue
        }
      }
    }

    // Create device
    let deviceId = properties["deviceid"] ?? "\(service.name)_\(service.type)"
    let model = properties["model"] ?? properties["rpmd"]

    let device = ATVDevice(
      id: deviceId,
      name: service.name,
      address: ip,
      port: service.port,
      model: model,
      properties: properties
    )

    print("✅ Resolved: \(device.name) at \(device.address):\(device.port)")

    discoveredDevices[deviceId] = device
    onDeviceFound?(device)
    resolvingServices.remove(service)
  }

  public func netService(_ service: NetService, didNotResolve errorDict: [String: NSNumber]) {
    print("❌ Failed to resolve \(service.name): \(errorDict)")
    resolvingServices.remove(service)
  }
}
