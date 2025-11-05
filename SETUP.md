# CuePad 快速配置

## 必须完成的 3 步

### 第 1 步：添加文件到 Xcode（2分钟）

在 Xcode 项目导航器中，右键点击 **CuePad** 组 → **Add Files to "CuePad"...**

**添加以下文件**（按住 ⌘ 多选）：
```
CuePad/ATVRemote/ATVDiscovery.swift
CuePad/ATVRemote/CompanionConnection.swift
CuePad/RemoteControlView.swift
```

**添加以下文件夹**（选择整个文件夹）：
```
CuePad/ATVRemote/Protocol/    （包含 4 个文件）
CuePad/ATVRemote/Features/    （包含 1 个文件）
```

**重要**：添加时确保勾选 ☑️ **Add to targets: CuePad**

### 第 2 步：配置网络权限（1分钟）

选择 **CuePad** target → **Info** 标签页

点击 **Custom macOS Application Target Properties** 下方的 **+** 按钮：

**添加第 1 个键**：
- Key: `NSBonjourServices`
- Type: Array
- 点击展开，添加两项：
  - Item 0 (String): `_companion-link._tcp`
  - Item 1 (String): `_airplay._tcp`

**添加第 2 个键**：
- Key: `NSLocalNetworkUsageDescription`  
- Type: String
- Value: `CuePad needs local network access to discover Apple TV devices`

### 第 3 步：启用 Sandbox 网络（30秒）

选择 **CuePad** target → **Signing & Capabilities** 标签

在 **App Sandbox** 下，展开 **Network**：
- ☑️ **Incoming Connections (Server)**
- ☑️ **Outgoing Connections (Client)**

### 完成！重新运行

```
⌘B (Build)
⌘R (Run)
```

**第一次运行时**：
- macOS 会弹出"本地网络访问"权限对话框
- **点击"允许"**

然后点击 "Scan" 按钮，应该就能看到设备了！

---

## 调试

### 如果还是 -72003 错误

**检查 Info.plist 配置**：
- Xcode → CuePad target → Info 标签
- 确认有 `NSBonjourServices` 和 `NSLocalNetworkUsageDescription`

### 如果没有权限弹窗

**手动授权**：
1. 系统设置 → 隐私与安全性
2. 本地网络
3. 找到 CuePad，勾选 ☑️

### 验证配置

在终端测试 mDNS：
```bash
dns-sd -B _companion-link._tcp .
```

如果能看到设备，说明网络正常，问题在应用配置。

---

**配置完成后应该看到**：
```
🔍 Starting Apple TV discovery...
📱 Found service: Living Room TV of type _companion-link._tcp.
✅ Resolved: Living Room TV at 192.168.1.100:49152
```

