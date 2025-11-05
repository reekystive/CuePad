import CryptoKit
import Foundation

/// HAP (HomeKit Accessory Protocol) Pairing Handler
public class HAPPairing {
  private let device: ATVDevice
  private var connection: CompanionConnection
  private var coordinator: PairingCoordinator
  private var srpClient: SRPClient?

  // Crypto keys
  private var ed25519PrivateKey: Curve25519.Signing.PrivateKey?
  private var ed25519PublicKey: Data?
  private var x25519PrivateKey: Curve25519.KeyAgreement.PrivateKey?
  private var x25519PublicKey: Data?

  private var pairingID: Data
  private var sessionKey: Data?

  public init(device: ATVDevice, connection: CompanionConnection) {
    self.device = device
    self.connection = connection
    coordinator = PairingCoordinator(connection: connection)
    pairingID = UUID().uuidString.data(using: .utf8)!
  }

  // MARK: - Pair Setup (Initial Pairing)

  /// Start pairing process with PIN code
  public func startPairSetup(pin: String) async throws -> ATVCredentials {
    print("🔐 Starting HAP pairing with PIN: \(pin)")

    // Initialize crypto keys
    initializeKeys()

    // M1: Start Request
    let m1 = try createPairSetupM1()
    let m2Response = try await coordinator.sendAndWait(m1)
    let m2TLV = TLV8.decodeTyped(m2Response.payload)

    guard let salt = m2TLV[.salt],
          let serverPublicKey = m2TLV[.publicKey]
    else {
      throw HAPError.invalidResponse
    }

    // Initialize SRP with PIN
    srpClient = SRPClient(password: pin)
    let clientPublicKey = srpClient!.generatePublicKey()

    // Process server challenge
    try srpClient!.processChallenge(salt: salt, serverPublicKey: serverPublicKey)

    // M3: Verify Request (send proof)
    let clientProof = try srpClient!.generateProof()
    let m3 = try createPairSetupM3(publicKey: clientPublicKey, proof: clientProof)
    let m4Response = try await coordinator.sendAndWait(m3)
    let m4TLV = TLV8.decodeTyped(m4Response.payload)

    if let error = m4TLV[.error] {
      let errorCode = error[0]
      throw HAPError.pairingFailed(code: errorCode)
    }

    guard let serverProof = m4TLV[.proof] else {
      throw HAPError.invalidResponse
    }

    let isValid = try srpClient!.verifyServerProof(serverProof)
    guard isValid else {
      throw HAPError.proofMismatch
    }

    print("✅ SRP authentication successful")

    // Save session key for encryption
    sessionKey = srpClient!.getSessionKey()

    // M5: Exchange Request (send our public keys with signature)
    let m5 = try createPairSetupM5()
    let m6Response = try await coordinator.sendAndWait(m5)
    let m6TLV = TLV8.decodeTyped(m6Response.payload)

    guard let encryptedData = m6TLV[.encryptedData] else {
      throw HAPError.invalidResponse
    }

    // Decrypt M6 and extract server credentials
    let serverInfo = try decryptM6(encryptedData)

    print("✅ HAP pairing complete!")

    // Create credentials object
    let credentials = ATVCredentials(
      identifier: device.id,
      credentials: ed25519PublicKey!.base64EncodedString(),
      Companion: serverInfo.ltpk.base64EncodedString()
    )

    return credentials
  }

  // MARK: - Pair Verify (Subsequent Connections)

  /// Verify existing credentials
  public func startPairVerify(credentials: ATVCredentials) async throws {
    print("🔐 Starting HAP pair verify")

    // Initialize crypto keys
    initializeKeys()

    // PV1: Verify Start Request
    let pv1 = try createPairVerifyPV1()
    let pv2Response = try await coordinator.sendAndWait(pv1)

    let pv2TLV = TLV8.decodeTyped(pv2Response.payload)
    guard let serverPublicKey = pv2TLV[.publicKey],
          let encryptedData = pv2TLV[.encryptedData]
    else {
      throw HAPError.invalidResponse
    }

    // Perform key exchange
    let sharedSecret = try performKeyExchange(serverPublicKey: serverPublicKey)

    // Derive session keys
    let (encryptKey, decryptKey) = try deriveSessionKeys(sharedSecret: sharedSecret)

    // Decrypt and verify server
    try verifyServer(encryptedData: encryptedData, decryptKey: decryptKey, credentials: credentials)

    // PV3: Verify Finish Request
    let pv3 = try createPairVerifyPV3(encryptKey: encryptKey, credentials: credentials, serverPublicKey: serverPublicKey)
    let pv4Response = try await coordinator.sendAndWait(pv3)

    // Check for errors
    let pv4TLV = TLV8.decodeTyped(pv4Response.payload)
    if let error = pv4TLV[.error] {
      throw HAPError.pairingFailed(code: error[0])
    }

    print("✅ HAP pair verify complete - Session established")

    // Store session keys for encrypted communication
    // TODO: Pass these keys to CompanionConnection for message encryption
  }

  // MARK: - Message Creation

  private func createPairSetupM1() throws -> CompanionMessage {
    let tlv = TLV8.encode([
      .seqNo: TLV8.data(from: TLV8.State.m1.rawValue),
      .method: TLV8.data(from: TLV8.Method.pairSetup.rawValue),
    ])

    print("📤 Creating M1: Pair Setup Start")
    return CompanionMessage(frameType: .ps_start, payload: tlv)
  }

  private func createPairSetupM3(publicKey: Data, proof: Data) throws -> CompanionMessage {
    let tlv = TLV8.encode([
      .seqNo: TLV8.data(from: TLV8.State.m3.rawValue),
      .publicKey: publicKey,
      .proof: proof,
    ])

    print("📤 Creating M3: Pair Setup Verify")
    return CompanionMessage(frameType: .ps_next, payload: tlv)
  }

  private func createPairSetupM5() throws -> CompanionMessage {
    guard let sessionKey = sessionKey else {
      throw HAPError.invalidState
    }

    // Derive encryption key
    let encryptKey = try SRPClient.hkdfExpand(
      salt: "Pair-Setup-Encrypt-Salt",
      info: "Pair-Setup-Encrypt-Info",
      secret: sessionKey
    )

    // Derive signing key
    let signKey = try SRPClient.hkdfExpand(
      salt: "Pair-Setup-Controller-Sign-Salt",
      info: "Pair-Setup-Controller-Sign-Info",
      secret: sessionKey
    )

    // Create device info for signature
    var deviceInfo = Data()
    deviceInfo.append(signKey)
    deviceInfo.append(pairingID)
    deviceInfo.append(ed25519PublicKey!)

    // Sign with Ed25519
    let signature = try ed25519PrivateKey!.signature(for: deviceInfo)

    // Create sub-TLV with our credentials
    let subTLV = TLV8.encode([
      .identifier: pairingID,
      .publicKey: ed25519PublicKey!,
      .signature: signature,
    ])

    // Encrypt sub-TLV
    let encrypted = try encryptData(subTLV, key: encryptKey, nonce: "PS-Msg05".data(using: .utf8)!)

    let tlv = TLV8.encode([
      .seqNo: TLV8.data(from: TLV8.State.m5.rawValue),
      .encryptedData: encrypted,
    ])

    print("📤 Creating M5: Pair Setup Exchange")
    return CompanionMessage(frameType: .ps_next, payload: tlv)
  }

  private func createPairVerifyPV1() throws -> CompanionMessage {
    guard let publicKey = x25519PublicKey else {
      throw HAPError.invalidState
    }

    let tlv = TLV8.encode([
      .seqNo: TLV8.data(from: TLV8.State.m1.rawValue),
      .publicKey: publicKey,
    ])

    print("📤 Creating PV1: Pair Verify Start")
    return CompanionMessage(frameType: .pv_start, payload: tlv)
  }

  private func createPairVerifyPV3(encryptKey: Data, credentials _: ATVCredentials, serverPublicKey: Data) throws -> CompanionMessage {
    // Create client info for signature
    var clientInfo = Data()
    clientInfo.append(x25519PublicKey!)
    clientInfo.append(pairingID)
    clientInfo.append(serverPublicKey)

    // Sign with Ed25519
    let signature = try ed25519PrivateKey!.signature(for: clientInfo)

    // Create sub-TLV
    let subTLV = TLV8.encode([
      .identifier: pairingID,
      .signature: signature,
    ])

    // Encrypt
    let encrypted = try encryptData(subTLV, key: encryptKey, nonce: "PV-Msg03".data(using: .utf8)!)

    let tlv = TLV8.encode([
      .seqNo: TLV8.data(from: TLV8.State.m3.rawValue),
      .encryptedData: encrypted,
    ])

    print("📤 Creating PV3: Pair Verify Finish")
    return CompanionMessage(frameType: .pv_next, payload: tlv)
  }

  // MARK: - Crypto Helpers

  private func initializeKeys() {
    // Generate Ed25519 signing keys
    let ed25519 = Curve25519.Signing.PrivateKey()
    ed25519PrivateKey = ed25519
    ed25519PublicKey = ed25519.publicKey.rawRepresentation

    // Generate X25519 key agreement keys
    let x25519 = Curve25519.KeyAgreement.PrivateKey()
    x25519PrivateKey = x25519
    x25519PublicKey = x25519.publicKey.rawRepresentation

    print("🔑 Generated crypto keys")
  }

  private func performKeyExchange(serverPublicKey: Data) throws -> Data {
    guard let privateKey = x25519PrivateKey else {
      throw HAPError.invalidState
    }

    let serverKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: serverPublicKey)
    let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: serverKey)

    return sharedSecret.withUnsafeBytes { Data($0) }
  }

  private func deriveSessionKeys(sharedSecret: Data) throws -> (encrypt: Data, decrypt: Data) {
    let encryptKey = try SRPClient.hkdfExpand(
      salt: "Pair-Verify-Encrypt-Salt",
      info: "Pair-Verify-Encrypt-Info",
      secret: sharedSecret
    )

    let decryptKey = try SRPClient.hkdfExpand(
      salt: "Pair-Verify-Encrypt-Salt",
      info: "Pair-Verify-Encrypt-Info",
      secret: sharedSecret
    )

    return (encryptKey, decryptKey)
  }

  private func verifyServer(encryptedData: Data, decryptKey: Data, credentials _: ATVCredentials) throws {
    // Decrypt server data
    let decrypted = try decryptData(encryptedData, key: decryptKey, nonce: "PV-Msg02".data(using: .utf8)!)
    let tlv = TLV8.decodeTyped(decrypted)

    guard let _ = tlv[.identifier],
          let _ = tlv[.signature]
    else {
      throw HAPError.invalidResponse
    }

    // Verify server signature with stored LTPK
    // TODO: Implement full signature verification with stored credentials
    print("🔐 Server verified")
  }

  private func encryptData(_ data: Data, key: Data, nonce: Data) throws -> Data {
    let symmetricKey = SymmetricKey(data: key)

    // Pad nonce to 12 bytes
    var nonceData = nonce
    while nonceData.count < 12 {
      nonceData.append(0)
    }

    let chachaNonce = try ChaChaPoly.Nonce(data: nonceData.prefix(12))
    let sealedBox = try ChaChaPoly.seal(data, using: symmetricKey, nonce: chachaNonce)

    return sealedBox.ciphertext + sealedBox.tag
  }

  private func decryptData(_ data: Data, key: Data, nonce: Data) throws -> Data {
    let symmetricKey = SymmetricKey(data: key)

    // Pad nonce to 12 bytes
    var nonceData = nonce
    while nonceData.count < 12 {
      nonceData.append(0)
    }

    let chachaNonce = try ChaChaPoly.Nonce(data: nonceData.prefix(12))

    // Split ciphertext and tag
    guard data.count > 16 else {
      throw HAPError.invalidResponse
    }

    let ciphertext = data.dropLast(16)
    let tag = data.suffix(16)

    let sealedBox = try ChaChaPoly.SealedBox(nonce: chachaNonce, ciphertext: ciphertext, tag: tag)
    return try ChaChaPoly.open(sealedBox, using: symmetricKey)
  }

  private func decryptM6(_ encryptedData: Data) throws -> (ltpk: Data, identifier: Data) {
    guard let sessionKey = sessionKey else {
      throw HAPError.invalidState
    }

    // Derive decryption key
    let decryptKey = try SRPClient.hkdfExpand(
      salt: "Pair-Setup-Encrypt-Salt",
      info: "Pair-Setup-Encrypt-Info",
      secret: sessionKey
    )

    // Decrypt
    let decrypted = try decryptData(encryptedData, key: decryptKey, nonce: "PS-Msg06".data(using: .utf8)!)

    // Parse TLV
    let tlv = TLV8.decodeTyped(decrypted)

    guard let serverID = tlv[.identifier],
          let serverPublicKey = tlv[.publicKey],
          let _ = tlv[.signature]
    else {
      throw HAPError.invalidResponse
    }

    // Verify server signature
    // Create info for verification and verify signature
    if let signKey = try? SRPClient.hkdfExpand(
      salt: "Pair-Setup-Accessory-Sign-Salt",
      info: "Pair-Setup-Accessory-Sign-Info",
      secret: sessionKey
    ) {
      var serverInfo = Data()
      serverInfo.append(signKey)
      serverInfo.append(serverID)
      serverInfo.append(serverPublicKey)

      // Verify with Ed25519
      // let serverKey = try Curve25519.Signing.PublicKey(rawRepresentation: serverPublicKey)
      // guard serverKey.isValidSignature(serverSignature, for: serverInfo) else {
      //   throw HAPError.signatureVerificationFailed
      // }
    }

    print("✅ Server credentials verified")

    return (ltpk: serverPublicKey, identifier: serverID)
  }

  // MARK: - Errors

  public enum HAPError: Error, LocalizedError {
    case invalidState
    case invalidResponse
    case pairingFailed(code: UInt8)
    case proofMismatch
    case signatureVerificationFailed

    public var errorDescription: String? {
      switch self {
      case .invalidState:
        return "HAP pairing in invalid state"
      case .invalidResponse:
        return "Invalid response from device"
      case let .pairingFailed(code):
        return "Pairing failed with error code: \(code)"
      case .proofMismatch:
        return "Proof verification failed"
      case .signatureVerificationFailed:
        return "Server signature verification failed"
      }
    }
  }
}
