import BigInt
import CryptoKit
import Foundation

/// SRP (Secure Remote Password) protocol implementation for HAP
/// Based on SRP-6a specification
public class SRPClient {
  // SRP-3072 constants (from RFC 5054)
  private static let prime3072 = BigUInt(
    "FFFFFFFF" + "FFFFFFFF" + "C90FDAA2" + "2168C234" + "C4C6628B" + "80DC1CD1" + "29024E08"
      + "8A67CC74" + "020BBEA6" + "3B139B22" + "514A0879" + "8E3404DD" + "EF9519B3" + "CD3A431B"
      + "302B0A6D" + "F25F1437" + "4FE1356D" + "6D51C245" + "E485B576" + "625E7EC6" + "F44C42E9"
      + "A637ED6B" + "0BFF5CB6" + "F406B7ED" + "EE386BFB" + "5A899FA5" + "AE9F2411" + "7C4B1FE6"
      + "49286651" + "ECE45B3D" + "C2007CB8" + "A163BF05" + "98DA4836" + "1C55D39A" + "69163FA8"
      + "FD24CF5F" + "83655D23" + "DCA3AD96" + "1C62F356" + "208552BB" + "9ED52907" + "7096966D"
      + "670C354E" + "4ABC9804" + "F1746C08" + "CA18217C" + "32905E46" + "2E36CE3B" + "E39E772C"
      + "180E8603" + "9B2783A2" + "EC07A28F" + "B5C55DF0" + "6F4C52C9" + "DE2BCBF6" + "95581718"
      + "3995497C" + "EA956AE5" + "15D22618" + "98FA0510" + "15728E5A" + "8AAAC42D" + "AD33170D"
      + "04507A33" + "A85521AB" + "DF1CBA64" + "ECFB8504" + "58DBEF0A" + "8AEA7157" + "5D060C7D"
      + "B3970F85" + "A6E1E4C7" + "ABF5AE8C" + "DB0933D7" + "1E8C94E0" + "4A25619D" + "CEE3D226"
      + "1AD2EE6B" + "F12FFA06" + "D98A0864"
      + "D87602733EC86A64521F2B18177B200CBBE117577A615D6C770988C0BAD946E208E24FA074E5AB3143DB5BFCE0FD108E4B82D120A92108011A723C12A787E6D788719A10BDBA5B2699C327186AF4E23C1A946834B6150BDA2583E9CA2AD44CE8DBBBC2DB04DE8EF92E8EFC141FBECAA6287C59474E6BC05D99B2964FA090C3A2233BA186515BE7ED1F612970CEE2D7AFB81BDD762170481CD0069127D5B05AA993B4EA988D8FDDC186FFB7DC90A6C08F4DF435C934063199FFFFFFFFFFFFFFFF",
    radix: 16
  )!

  private static let generator = BigUInt(5)

  // State
  private var username: String
  private var password: String
  private var privateKey: BigUInt
  private var publicKey: BigUInt?
  private var salt: Data?
  private var serverPublicKey: BigUInt?
  private var sharedSecret: BigUInt?
  private var sessionKey: Data?

  public init(username: String = "Pair-Setup", password: String) {
    self.username = username
    self.password = password

    // Generate random private key (a)
    let randomBytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
    privateKey = BigUInt(Data(randomBytes))
  }

  // MARK: - SRP Steps

  /// Step 1: Generate public key A = g^a % N
  public func generatePublicKey() -> Data {
    let N = Self.prime3072
    let g = Self.generator

    // A = g^a mod N
    publicKey = g.power(privateKey, modulus: N)

    // Convert to bytes (384 bytes for 3072-bit)
    var bytes = publicKey!.serialize()

    // Pad to 384 bytes if needed
    while bytes.count < 384 {
      bytes.insert(0, at: 0)
    }

    return Data(bytes)
  }

  /// Step 2: Process server response (salt + B)
  public func processChallenge(salt: Data, serverPublicKey: Data) throws {
    self.salt = salt

    // Convert server public key from bytes
    self.serverPublicKey = BigUInt(serverPublicKey)

    // Compute shared secret
    try computeSharedSecret()
  }

  private func computeSharedSecret() throws {
    guard let B = serverPublicKey,
      let A = publicKey,
      let salt = salt
    else {
      throw SRPError.invalidState
    }

    let N = Self.prime3072
    let g = Self.generator

    // u = H(A | B)
    var hashData = Data()
    hashData.append(contentsOf: A.serialize().suffix(384))
    hashData.append(contentsOf: B.serialize().suffix(384))
    let u = BigUInt(SHA512.hash(data: hashData).withUnsafeBytes { Data($0) })

    // x = H(salt | H(username | ":" | password))
    var innerHash = Data()
    innerHash.append(contentsOf: username.data(using: .utf8)!)
    innerHash.append(UInt8(ascii: ":"))
    innerHash.append(contentsOf: password.data(using: .utf8)!)
    let innerHashResult = SHA512.hash(data: innerHash)

    var xHashData = salt
    xHashData.append(contentsOf: innerHashResult)
    let x = BigUInt(SHA512.hash(data: xHashData).withUnsafeBytes { Data($0) })

    // k = H(N | g)
    var kHashData = Data()
    kHashData.append(contentsOf: N.serialize().suffix(384))
    kHashData.append(contentsOf: g.serialize())
    let k = BigUInt(SHA512.hash(data: kHashData).withUnsafeBytes { Data($0) })

    // S = (B - k * g^x) ^ (a + u * x) % N
    let gx = g.power(x, modulus: N)
    let kgx = (k * gx) % N

    var base: BigUInt
    if B >= kgx {
      base = (B - kgx) % N
    } else {
      base = (N + B - kgx) % N
    }

    let exponent = (privateKey + u * x) % (N - 1)
    let S = base.power(exponent, modulus: N)

    sharedSecret = S

    // K = H(S)
    var sBytes = S.serialize()
    while sBytes.count < 384 {
      sBytes.insert(0, at: 0)
    }
    sessionKey = Data(SHA512.hash(data: Data(sBytes)))
  }

  /// Step 3: Generate proof M1 = H(H(N) XOR H(g) | H(username) | salt | A | B | K)
  public func generateProof() throws -> Data {
    guard let A = publicKey,
      let B = serverPublicKey,
      let salt = salt,
      let K = sessionKey
    else {
      throw SRPError.invalidState
    }

    let N = Self.prime3072
    let g = Self.generator

    // H(N) XOR H(g)
    let hashN = SHA512.hash(data: Data(N.serialize()))
    let hashG = SHA512.hash(data: Data(g.serialize()))
    let hashNxorG = Data(zip(hashN, hashG).map { $0 ^ $1 })

    // H(username)
    let hashUser = SHA512.hash(data: username.data(using: .utf8)!)

    // Concatenate all
    var proofData = Data()
    proofData.append(contentsOf: hashNxorG)
    proofData.append(contentsOf: hashUser)
    proofData.append(salt)
    proofData.append(contentsOf: A.serialize().suffix(384))
    proofData.append(contentsOf: B.serialize().suffix(384))
    proofData.append(K)

    return Data(SHA512.hash(data: proofData))
  }

  /// Verify server proof M2 = H(A | M1 | K)
  public func verifyServerProof(_ serverProof: Data) throws -> Bool {
    guard let A = publicKey,
      let K = sessionKey
    else {
      throw SRPError.invalidState
    }

    let clientProof = try generateProof()

    var proofData = Data()
    proofData.append(contentsOf: A.serialize().suffix(384))
    proofData.append(clientProof)
    proofData.append(K)

    let expectedProof = SHA512.hash(data: proofData)

    return Data(expectedProof) == serverProof
  }

  /// Get the session key after successful authentication
  public func getSessionKey() -> Data? {
    return sessionKey
  }

  // MARK: - Errors

  public enum SRPError: Error, LocalizedError {
    case invalidState
    case proofMismatch
    case invalidServerKey

    public var errorDescription: String? {
      switch self {
      case .invalidState:
        return "SRP client in invalid state"
      case .proofMismatch:
        return "SRP proof verification failed"
      case .invalidServerKey:
        return "Invalid server public key"
      }
    }
  }
}

// MARK: - HKDF Extension

extension SRPClient {
  /// HKDF key derivation
  public static func hkdfExpand(salt: String, info: String, secret: Data, length: Int = 32) throws
    -> Data
  {
    let saltData = salt.data(using: .utf8)!
    let infoData = info.data(using: .utf8)!

    let inputKey = SymmetricKey(data: secret)
    let derived = HKDF<SHA512>.deriveKey(
      inputKeyMaterial: inputKey,
      salt: saltData,
      info: infoData,
      outputByteCount: length
    )

    return derived.withUnsafeBytes { Data($0) }
  }
}
