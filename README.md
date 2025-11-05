# CuePad - Apple TV Remote (Pure Swift)

纯 Swift 实现的 Apple TV 远程控制，无需 Python。

## 快速开始

### 1. 配置 Xcode 项目

**添加文件**（在 Xcode 中右键 CuePad 文件夹 → Add Files）：
- `CuePad/ATVRemote/Protocol/` 全部文件
- `CuePad/ATVRemote/Features/TextInput.swift`
- `CuePad/ATVRemote/ATVDiscovery.swift`
- `CuePad/ATVRemote/CompanionConnection.swift`
- `CuePad/RemoteControlView.swift`

**配置权限**（CuePad target → Signing & Capabilities）：
- App Sandbox → Network → 勾选 Client & Server

**设置文件路径**（Build Settings）：
- Code Signing Entitlements: `CuePad/CuePad.entitlements`
- Info.plist File: `CuePad/Info.plist`

详细步骤见 [SETUP.md](SETUP.md)

### 2. 构建运行

```bash
⌘B (Build)
⌘R (Run)
```

### 3. 使用

1. 点击 "Scan" 扫描设备
2. 点击设备名称连接
3. 使用遥控器按钮控制

## 当前状态

✅ **已实现**：
- 设备发现（Bonjour）
- TCP 连接
- 完整协议（TLV8, OPACK, HID）
- SwiftUI 界面
- 文本输入 API

🔧 **需要配置**：
- SRP/HAP 配对（需要 BigInt 包）

## 故障排除

**扫描不到设备 (-72000 错误)**：
- 配置网络权限（见上方）
- 系统设置 → 隐私 → 本地网络 → 允许 CuePad

**文件看不见**：
- 在 Xcode 中手动添加文件引用

**设备拒绝命令**：
- 需要完成 HAP 配对（需要 BigInt 依赖）

## 技术栈

- Swift 5.7+
- SwiftUI
- Network.framework
- CryptoKit
- NetService (Bonjour)

## 文档

- [SETUP.md](SETUP.md) - 详细配置步骤
- [Docs/PROTOCOL_SPEC.md](Docs/PROTOCOL_SPEC.md) - 协议规范

## 代码统计

- 2,674 行 Swift 代码
- 12 个核心模块
- 完整的协议实现

---

**Status**: ✅ 核心完成，需要配置 Xcode 项目引用和权限
