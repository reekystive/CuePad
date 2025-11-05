# CuePad - Apple TV Remote (Pure Swift)

纯 Swift 实现的 Apple TV 远程控制应用。

## ✨ 特性

- 🎯 **100% Swift** - 无 Python/Node.js 依赖
- 🔍 **自动发现** - Bonjour/mDNS 扫描
- 🔐 **HAP 配对** - 完整的加密配对流程
- 🎮 **完整遥控** - 所有标准 Apple TV 按键
- 💬 **文本输入** - RTI 协议支持
- 🎨 **SwiftUI** - 原生 macOS 界面

## 🚀 快速开始

### 1. 构建运行

```bash
open CuePad.xcodeproj
# ⌘R 运行
```

### 2. 配置（首次运行）

详见 [SETUP.md](SETUP.md)：
- 添加文件引用到 Xcode
- 配置网络权限
- 允许本地网络访问（会弹窗提示）

### 3. 使用

1. **扫描** - 点击 "Scan" 发现 Apple TV
2. **配对** - 点击设备，输入 TV 上显示的 4 位 PIN
3. **控制** - 使用遥控器按钮

下次连接自动使用保存的凭证，无需重新配对。

## 📊 实现状态

✅ **已完成**（可测试）：
- 设备发现 ✅ 已验证工作
- TCP 连接 ✅
- HAP 配对（M1-M6）✅
- Pair Verify（保存的凭证）✅
- 远程控制命令 ✅
- 文本输入 ✅
- PIN 输入 UI ✅
- 凭证管理 ✅

## 🏗️ 技术栈

- Swift 5.7+, SwiftUI
- Network.framework (TCP)
- CryptoKit (加密)
- NetService (Bonjour)
- BigInt (SRP 认证)

## 📁 代码结构

```
CuePad/
├── ATVRemote/              # 核心库
│   ├── Protocol/          # TLV8, OPACK, HID, Companion
│   ├── Crypto/            # SRP 认证
│   ├── Pairing/           # HAP 配对
│   └── Features/          # 文本输入
├── RemoteControlView.swift # UI + PIN 对话框
└── AppDelegate.swift
```

**总计**: ~3,200 行 Swift 代码

## 🔧 依赖

**Xcode 项目依赖**：
- BigInt (通过 Xcode → Add Package Dependency 添加)

**系统框架**：
- Foundation, SwiftUI, Network, CryptoKit

## 🐛 故障排除

**扫描不到设备**：
- 配置网络权限（见 SETUP.md）
- 允许本地网络访问
- 确保同一 WiFi

**配对失败**：
- 检查 PIN 码正确
- 查看控制台错误信息
- 重启 Apple TV 重试

## 📚 文档

- [SETUP.md](SETUP.md) - 详细配置步骤
- [Docs/PROTOCOL_SPEC.md](Docs/PROTOCOL_SPEC.md) - 协议规范

---

**Status**: ✅ 完整实现，可立即测试
