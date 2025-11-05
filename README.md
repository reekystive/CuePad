# CuePad

A native macOS Apple TV Remote application written in pure Swift.

<p align="center">
  <img src="https://img.shields.io/badge/Swift-5.7+-orange.svg" />
  <img src="https://img.shields.io/badge/Platform-macOS-blue.svg" />
  <img src="https://img.shields.io/badge/License-MIT-green.svg" />
</p>

## ✨ Features

- 🎯 **100% Pure Swift** - No Python or Node.js dependencies
- 🔍 **Automatic Discovery** - Finds Apple TV devices via Bonjour/mDNS
- 🔐 **HAP Pairing** - Complete HomeKit Accessory Protocol implementation
- 🎮 **Full Remote Control** - All standard Apple TV buttons (Menu, Select, Play/Pause, etc.)
- 💬 **Text Input** - Remote Text Input (RTI) protocol support
- 🎨 **SwiftUI Interface** - Native macOS UI with modern design
- 💾 **Credential Management** - Saves pairing credentials for automatic reconnection

## 🚀 Quick Start

### Prerequisites

- macOS 12.0+
- Xcode 14.0+
- Apple TV (4th generation or later) on the same network

### Installation

1. **Clone the repository**

   ```bash
   git clone https://github.com/yourusername/CuePad.git
   cd CuePad
   ```

2. **Open in Xcode**

   ```bash
   open CuePad.xcodeproj
   ```

3. **Add Package Dependencies**

   In Xcode: File → Add Package Dependencies...

   - Add `https://github.com/attaswift/BigInt.git`

4. **Configure Required Files** (First-time setup)

   In Xcode Project Navigator, right-click **CuePad** group → **Add Files to "CuePad"...**

   Add these files (hold ⌘ to multi-select):

   ```
   CuePad/ATVRemote/ATVDiscovery.swift
   CuePad/ATVRemote/CompanionConnection.swift
   CuePad/RemoteControlView.swift
   ```

   Add these folders (select entire folders):

   ```
   CuePad/ATVRemote/Protocol/    (4 files)
   CuePad/ATVRemote/Features/    (1 file)
   ```

   ⚠️ **Important**: When adding, ensure **Add to targets: CuePad** is checked

5. **Configure Network Permissions**

   Select **CuePad** target → **Info** tab

   Click **+** under **Custom macOS Application Target Properties**:

   **Add Key 1:**

   - Key: `NSBonjourServices`
   - Type: Array
   - Items:
     - Item 0 (String): `_companion-link._tcp`
     - Item 1 (String): `_airplay._tcp`

   **Add Key 2:**

   - Key: `NSLocalNetworkUsageDescription`
   - Type: String
   - Value: `CuePad needs local network access to discover Apple TV devices`

6. **Enable App Sandbox Network**

   Select **CuePad** target → **Signing & Capabilities** tab

   Under **App Sandbox**, expand **Network**:

   - ☑️ **Incoming Connections (Server)**
   - ☑️ **Outgoing Connections (Client)**

7. **Build and Run**

   ```
   ⌘B (Build)
   ⌘R (Run)
   ```

   On first launch, macOS will prompt for **Local Network Access** - click **Allow**.

### Usage

1. **Scan for Devices** - Click "Scan" button to discover Apple TV devices
2. **Pair Device** - Click on a device, enter the 4-digit PIN shown on TV screen
3. **Control** - Use the remote control buttons to navigate
4. **Text Input** - Available when keyboard input is active on Apple TV

Credentials are saved after pairing - subsequent connections are automatic.

## 📊 Implementation Status

### ✅ Completed Features

- [x] Device Discovery (Bonjour/mDNS)
- [x] TCP Connection (Network.framework)
- [x] HAP Pairing (M1-M6 flow)
- [x] Pair Verify (saved credentials)
- [x] SRP-6a Authentication (with BigInt)
- [x] Curve25519 Key Exchange
- [x] ChaCha20-Poly1305 Encryption
- [x] HID Commands (remote control)
- [x] Media Control Commands
- [x] Text Input (RTI protocol)
- [x] Credential Storage
- [x] SwiftUI Interface
- [x] PIN Input Dialog

### 🎯 Tested & Working

- ✅ Device scanning (verified with real Apple TVs)
- ✅ TCP connection establishment
- 🧪 Complete pairing flow (ready for testing)
- 🧪 Remote control commands (ready for testing)

## 🏗️ Architecture

### Project Structure

```
CuePad/
├── ATVRemote/                      # Core library
│   ├── ATVRemoteCore.swift        # Main controller
│   ├── ATVRemoteProtocol.swift    # Protocol definitions
│   ├── ATVDiscovery.swift         # Bonjour discovery
│   ├── CompanionConnection.swift  # TCP connection
│   ├── ATVCredentialsManager.swift # Credential storage
│   ├── Protocol/                  # Protocol implementations
│   │   ├── TLV8.swift            # TLV8 encoding
│   │   ├── OPACK.swift           # OPACK serialization
│   │   ├── HIDCommand.swift      # HID commands
│   │   └── CompanionMessage.swift # Message framing
│   ├── Crypto/                    # Cryptography
│   │   └── SRPClient.swift       # SRP-6a authentication
│   ├── Pairing/                   # HAP pairing
│   │   ├── HAPPairing.swift      # Pairing handler
│   │   └── PairingCoordinator.swift # Message coordination
│   └── Features/                  # Additional features
│       └── TextInput.swift        # RTI text input
├── RemoteControlView.swift        # SwiftUI interface
└── AppDelegate.swift              # App delegate

Total: ~3,400 lines of Swift code
```

### Technology Stack

- **Language**: Swift 5.7+
- **UI Framework**: SwiftUI
- **Networking**: Network.framework (TCP/TLS)
- **Service Discovery**: NetService (Bonjour/mDNS)
- **Cryptography**: CryptoKit (system framework)
- **Dependencies**: BigInt (for SRP large integer arithmetic)

### Protocols Implemented

- **HAP (HomeKit Accessory Protocol)**: Pairing and authentication
- **Companion Protocol**: Apple TV remote control
- **SRP-6a**: Secure Remote Password authentication
- **TLV8**: Tag-Length-Value encoding
- **OPACK**: Binary plist-like serialization
- **RTI**: Remote Text Input

## 🐛 Troubleshooting

### No Devices Found

**Check network permissions:**

1. System Settings → Privacy & Security → Local Network
2. Ensure CuePad is checked ☑️
3. Restart the application

**Verify configuration:**

- Info.plist contains `NSBonjourServices` and `NSLocalNetworkUsageDescription`
- App Sandbox has network permissions enabled
- Apple TV and Mac are on the same Wi-Fi network

**Test mDNS manually:**

```bash
dns-sd -B _companion-link._tcp .
```

If devices appear here but not in the app, the issue is in app configuration.

### Pairing Fails

- **Double-check PIN**: Ensure you enter the 4-digit code correctly
- **Check console logs**: Look for error messages in Xcode console
- **Restart Apple TV**: Sometimes helps clear pairing state
- **Delete old pairing**: Go to Apple TV Settings → Remotes and Devices

### Build Errors

**Missing BigInt:**

- Add package dependency in Xcode: File → Add Package Dependencies
- URL: `https://github.com/attaswift/BigInt.git`

**Files not found:**

- Ensure all files are added to Xcode project with correct target membership
- Check that files appear in Build Phases → Compile Sources

## 🤝 Contributing

Contributions are welcome! Here's how you can help:

### Development Setup

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make your changes
4. Test thoroughly with a real Apple TV
5. Commit using conventional commits: `git commit -m "✨ feat: add feature"`
6. Push to your fork: `git push origin feature/my-feature`
7. Open a Pull Request

### Code Style

- Follow Swift API Design Guidelines
- Use SwiftFormat for formatting (`.swiftformat` config included)
- Document public APIs with comments
- Keep functions focused and testable

### Commit Convention

Use emoji-prefixed conventional commits:

- ✨ `feat:` - New features
- 🐛 `fix:` - Bug fixes
- 📝 `docs:` - Documentation changes
- 🎨 `style:` - Code style/formatting
- ♻️ `refactor:` - Code refactoring
- ⚡ `perf:` - Performance improvements
- ✅ `test:` - Adding tests
- 🔧 `chore:` - Maintenance tasks

### Testing

Since this involves hardware interaction:

- Test with real Apple TV devices
- Document tested hardware and tvOS versions
- Include console logs for debugging

### Areas for Contribution

- [ ] Automated tests (mocking network layer)
- [ ] Support for multiple Apple TV connections
- [ ] Screen mirroring support
- [ ] Custom button mappings
- [ ] Keyboard shortcuts
- [ ] Dark mode improvements
- [ ] Localization
- [ ] iOS companion app

## 📚 Documentation

- [PROTOCOL_SPEC.md](Docs/PROTOCOL_SPEC.md) - Protocol specifications and implementation details
- [Apple TV Companion Protocol](https://github.com/postlund/pyatv) - Reference implementation

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **[pyatv](https://github.com/postlund/pyatv)** - Reference implementation and protocol documentation
- **Apple** - For HomeKit Accessory Protocol and related technologies
- **Swift Community** - For excellent cryptography libraries

## 🔗 Related Projects

- [pyatv](https://github.com/postlund/pyatv) - Python library for Apple TV
- [node-appletv](https://github.com/evandcoleman/node-appletv) - Node.js implementation

---

**Status**: ✅ Fully implemented and ready for testing

**Maintained by**: [@reekystive](https://github.com/reekystive)

If you find this project helpful, please consider giving it a ⭐!
