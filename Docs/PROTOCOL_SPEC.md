<!-- markdownlint-disable MD024 MD040 MD036 MD034 -->

# Apple TV Remote Protocol Specification

## Document Version

Version 1.0  
Date: 2025-11-05

## Purpose

This document provides a complete specification of the Apple TV Remote control protocol used in the `atv-desktop-remote` project. By following this specification, developers should be able to implement a fully functional Apple TV Remote CLI with complete feature parity.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [System Requirements](#system-requirements)
3. [WebSocket Server Setup](#websocket-server-setup)
4. [Device Discovery (Scanning)](#device-discovery-scanning)
5. [Device Pairing](#device-pairing)
6. [Connecting to a Paired Device](#connecting-to-a-paired-device)
7. [Sending Control Commands](#sending-control-commands)
8. [Keyboard and Text Input](#keyboard-and-text-input)
9. [Connection State Management](#connection-state-management)
10. [Complete Protocol Message Reference](#complete-protocol-message-reference)
11. [Implementation Guide](#implementation-guide)
12. [Error Handling](#error-handling)

---

## Architecture Overview

### System Components

The Apple TV Remote system consists of three main components:

1. **WebSocket Server** (Python)

   - Built using Python's `websockets` library
   - Uses the `pyatv` library for Apple TV communication
   - Handles device discovery, pairing, and control operations
   - Default port: `8765`
   - Runs on `localhost`

2. **Client Application** (JavaScript/Electron in this implementation)

   - Connects to the WebSocket server
   - Sends commands as JSON messages
   - Receives responses and state updates
   - Manages credentials and device selection

3. **Apple TV Device**
   - Discovered via mDNS/Bonjour
   - Communicates using two protocols:
     - **AirPlay Protocol**: For basic remote control
     - **Companion Protocol**: For advanced features (keyboard input, power state)

### Communication Flow

```
Client <--WebSocket JSON--> Python Server <--pyatv--> Apple TV
```

All messages between client and server use JSON format over WebSocket connection.

---

## System Requirements

### Server Requirements

- Python 3.7 or higher
- Python packages:
  - `pyatv` (latest version)
  - `websockets` (for WebSocket server)
- Network access to the local subnet (for mDNS discovery)

### Network Requirements

- Client and server must be able to communicate on localhost:8765 (or custom port)
- Apple TV must be on the same local network
- mDNS/Bonjour must not be blocked by firewall

---

## WebSocket Server Setup

### Server Initialization

The WebSocket server must:

1. Import required modules: `pyatv`, `websockets`, `asyncio`, `json`
2. Create an asyncio event loop
3. Start WebSocket server on localhost:8765
4. Handle incoming client connections

### Basic Server Structure

```python
import pyatv
import websockets
import asyncio
import json
from pyatv.const import InputAction, Protocol

# Global state
scan_lookup = {}  # Store scanned devices
active_device = None  # Current connected device
active_remote = None  # Remote control interface
active_pairing = None  # Current pairing session
pairing_atv = None  # Device being paired
current_config = None  # Config for reconnection

async def ws_main(websocket):
    """Handle WebSocket client connection"""
    async for message in websocket:
        j = json.loads(message)
        await parseRequest(j, websocket)

async def main(port=8765):
    async with websockets.serve(ws_main, "localhost", port):
        await asyncio.Future()  # Run forever

# Start server
loop = asyncio.get_event_loop()
loop.run_until_complete(main())
```

### Message Format

All messages use JSON format:

**Client → Server:**

```json
{
  "cmd": "command_name",
  "data": "command_data_or_object"
}
```

**Server → Client:**

```json
{
  "command": "response_name",
  "data": "response_data_or_array_or_object"
}
```

---

## Device Discovery (Scanning)

### Scanning for Apple TV Devices

#### Client Request

```json
{
  "cmd": "scan"
}
```

#### Server Processing

1. Use `pyatv.scan(loop)` to discover devices on the network
2. Filter devices to only include Apple TVs (devices with "TV" in model string)
3. Create a lookup dictionary mapping display names to device objects
4. Return array of device names

```python
async def handle_scan(websocket):
    atvs = await pyatv.scan(loop)
    ar = []
    scan_lookup = {}

    # Filter for Apple TV devices only
    atvs = [x for x in atvs if "TV" in x.device_info.model_str]

    # Create display names
    for atv in atvs:
        display_name = f"{atv.name} ({atv.address})"
        ar.append(display_name)
        scan_lookup[display_name] = atv

    # Send results
    await send_command(websocket, "scanResult", ar)
```

#### Server Response

```json
{
  "command": "scanResult",
  "data": ["Living Room TV (192.168.1.100)", "Bedroom TV (192.168.1.101)"]
}
```

#### Device Object Structure

Each discovered device contains:

- `name`: Device name (e.g., "Living Room TV")
- `address`: IP address
- `identifier`: Unique device identifier (used for reconnection)
- `device_info.model_str`: Model information

---

## Device Pairing

### Overview

Pairing requires **TWO separate pairing processes**:

1. **AirPlay Protocol Pairing** (Step 1)
2. **Companion Protocol Pairing** (Step 2)

Both protocols require entering a 4-digit PIN code displayed on the Apple TV screen.

### Step 1: Start AirPlay Pairing

#### Client Request

```json
{
  "cmd": "startPair",
  "data": "Living Room TV (192.168.1.100)"
}
```

#### Server Processing

```python
async def handle_start_pair(device_name, websocket):
    global pairing_atv, active_pairing, scan_lookup

    # Get device from scan results
    atv = scan_lookup[device_name]
    pairing_atv = atv

    # Start AirPlay pairing
    pairing = await pyatv.pair(atv, Protocol.AirPlay, loop)
    active_pairing = pairing
    await pairing.begin()

    # Apple TV now displays 4-digit PIN on screen
```

At this point:

- The Apple TV displays a 4-digit PIN code on the screen
- The client should prompt the user to enter this code

### Step 2: Complete AirPlay Pairing

#### Client Request

```json
{
  "cmd": "finishPair1",
  "data": "1234"
}
```

#### Server Processing

```python
async def handle_finish_pair1(pin_code, websocket):
    global active_pairing, pairing_atv, pairing_creds

    # Submit PIN
    active_pairing.pin(pin_code)
    await active_pairing.finish()

    if active_pairing.has_paired:
        # Save AirPlay credentials
        creds = active_pairing.service.credentials
        identifier = pairing_atv.identifier
        pairing_creds = {
            "credentials": creds,
            "identifier": identifier
        }

        # Notify client to proceed to step 2
        await send_command(websocket, "startPair2")

        # Start Companion protocol pairing
        pairing = await pyatv.pair(pairing_atv, Protocol.Companion, loop)
        active_pairing = pairing
        await pairing.begin()

        # Apple TV displays a NEW 4-digit PIN
    else:
        # Pairing failed - wrong PIN
        print("Did not pair with device!")
```

#### Server Response

```json
{
  "command": "startPair2"
}
```

### Step 3: Complete Companion Pairing

#### Client Request

```json
{
  "cmd": "finishPair2",
  "data": "5678"
}
```

#### Server Processing

```python
async def handle_finish_pair2(pin_code, websocket):
    global active_pairing, pairing_creds

    # Submit PIN for Companion protocol
    active_pairing.pin(pin_code)
    await active_pairing.finish()

    if active_pairing.has_paired:
        # Add Companion credentials
        pairing_creds["Companion"] = active_pairing.service.credentials

        # Send all credentials to client
        await send_command(websocket, "pairCredentials", pairing_creds)
```

#### Server Response (Final Credentials)

```json
{
  "command": "pairCredentials",
  "data": {
    "credentials": "AIRPLAY_CREDENTIAL_STRING",
    "identifier": "DEVICE_UNIQUE_ID",
    "Companion": "COMPANION_CREDENTIAL_STRING"
  }
}
```

### Credential Storage

The client MUST store these credentials permanently (e.g., in a config file):

- `credentials`: AirPlay protocol credential string
- `identifier`: Device unique identifier (used for scanning specific device)
- `Companion`: Companion protocol credential string

**Important:** These credentials are required for all future connections and should be stored securely.

---

## Connecting to a Paired Device

### Connection Request

#### Client Request

```json
{
  "cmd": "connect",
  "data": {
    "identifier": "DEVICE_UNIQUE_ID",
    "credentials": "AIRPLAY_CREDENTIAL_STRING",
    "Companion": "COMPANION_CREDENTIAL_STRING"
  }
}
```

#### Server Processing

```python
async def handle_connect(data, websocket):
    global active_device, active_remote, current_config

    # Extract credentials
    identifier = data["identifier"]
    airplay_creds = data["credentials"]

    # Build credentials dict
    stored_credentials = {Protocol.AirPlay: airplay_creds}
    if "Companion" in data:
        stored_credentials[Protocol.Companion] = data["Companion"]

    # Scan for specific device
    atvs = await pyatv.scan(loop, identifier=identifier)
    if not atvs:
        await send_command(websocket, "connection_failure")
        return

    atv = atvs[0]

    # Set credentials on config
    for protocol, credentials in stored_credentials.items():
        atv.set_credentials(protocol, credentials)

    # Connect to device
    try:
        device = await pyatv.connect(atv, loop)
        active_device = device
        active_remote = device.remote_control
        current_config = atv  # Store for reconnection

        # Setup listeners
        setup_listeners(device)

        await send_command(websocket, "connected")

    except Exception as ex:
        await send_command(websocket, "connection_failure")
```

#### Server Response (Success)

```json
{
  "command": "connected"
}
```

#### Server Response (Failure)

```json
{
  "command": "connection_failure"
}
```

### Connection State Check

#### Client Request

```json
{
  "cmd": "is_connected"
}
```

#### Server Response

```json
{
  "command": "is_connected",
  "data": "true"
}
```

or

```json
{
  "command": "is_connected",
  "data": "false"
}
```

---

## Sending Control Commands

### Available Commands

The following remote control commands are supported:

| Command         | Description        | Input Action Support |
| --------------- | ------------------ | -------------------- |
| `up`            | D-pad up           | Yes                  |
| `down`          | D-pad down         | Yes                  |
| `left`          | D-pad left         | Yes                  |
| `right`         | D-pad right        | Yes                  |
| `select`        | Select/OK button   | Yes                  |
| `menu`          | Menu button        | Yes                  |
| `top_menu`      | Top menu button    | Yes                  |
| `home`          | Home/TV button     | No                   |
| `home_hold`     | Long press Home/TV | No                   |
| `play_pause`    | Play/Pause toggle  | No                   |
| `skip_forward`  | Next/Skip forward  | No                   |
| `skip_backward` | Previous/Skip back | No                   |
| `volume_up`     | Increase volume    | No                   |
| `volume_down`   | Decrease volume    | No                   |

### Simple Command (Single Tap)

#### Client Request

```json
{
  "cmd": "key",
  "data": "select"
}
```

#### Server Processing

```python
async def handle_key_command(data):
    if not active_remote or not active_device:
        await send_command(websocket, "command_failed", "not_connected")
        return

    valid_keys = ['play_pause', 'left', 'right', 'down', 'up',
                   'select', 'menu', 'top_menu', 'home', 'home_hold',
                   'skip_backward', 'skip_forward', 'volume_up', 'volume_down']

    no_action_keys = ['volume_up', 'volume_down', 'play_pause', 'home_hold']

    key = data
    if isinstance(data, str) and key in valid_keys:
        try:
            # Commands in no_action_keys don't take InputAction parameter
            if key in no_action_keys:
                await getattr(active_remote, key)()
            else:
                # Default single tap
                await getattr(active_remote, key)(InputAction.SingleTap)
        except Exception as ex:
            await send_command(websocket, "command_failed", str(ex))
```

### Command with Input Action (Tap, Double Tap, Hold)

#### Client Request

```json
{
  "cmd": "key",
  "data": {
    "key": "select",
    "taction": "Hold"
  }
}
```

Where `taction` can be:

- `"SingleTap"`: Single press
- `"DoubleTap"`: Double press
- `"Hold"`: Long press

#### Server Processing

```python
async def handle_key_with_action(data):
    key = data['key']
    taction = InputAction[data['taction']]  # Convert string to InputAction enum

    if key in valid_keys:
        await getattr(active_remote, key)(taction)
```

### Command Response

On failure:

```json
{
  "command": "command_failed",
  "data": "not_connected"
}
```

On success: No response is sent (fire-and-forget)

---

## Keyboard and Text Input

### Overview

The Companion protocol enables text input functionality. This allows sending text directly to search fields and text input areas on the Apple TV.

### Check Keyboard Focus State

#### Client Request

```json
{
  "cmd": "kbfocus"
}
```

#### Server Processing

```python
async def handle_kbfocus(websocket):
    if not active_device:
        return

    has_focus = (active_device.keyboard.text_focus_state ==
                 pyatv_const.KeyboardFocusState.Focused)

    await send_command(websocket, "kbfocus-status", has_focus)
```

#### Server Response

```json
{
  "command": "kbfocus-status",
  "data": true
}
```

### Get Current Text

Retrieves the current text in the focused input field.

#### Client Request

```json
{
  "cmd": "gettext"
}
```

#### Server Processing

```python
async def handle_gettext(websocket):
    if active_device.keyboard.text_focus_state != pyatv_const.KeyboardFocusState.Focused:
        return  # No response if not focused

    current_text = await active_device.keyboard.text_get()
    await send_command(websocket, "current-text", current_text)
```

#### Server Response

```json
{
  "command": "current-text",
  "data": "current text content"
}
```

### Set Text

Replaces the entire text in the focused input field.

#### Client Request

```json
{
  "cmd": "settext",
  "data": {
    "text": "New search query"
  }
}
```

#### Server Processing

```python
async def handle_settext(data):
    if active_device.keyboard.text_focus_state != pyatv_const.KeyboardFocusState.Focused:
        return  # Ignore if not focused

    text = data["text"]
    await active_device.keyboard.text_set(text)
```

No response is sent on success.

### Keyboard Focus State Change Events

The server monitors keyboard focus state and sends updates to the client:

```python
class ATVKeyboardListener(pyatv.interface.KeyboardListener):
    def focusstate_update(self, old_state, new_state):
        if active_ws:
            loop.run_until_complete(
                send_command(active_ws, "keyboard_changestate",
                           [str(old_state), str(new_state)])
            )
```

#### Server Event (Unsolicited)

```json
{
  "command": "keyboard_changestate",
  "data": ["Unfocused", "Focused"]
}
```

Possible states:

- `"Focused"`: A text input field is active
- `"Unfocused"`: No text input field is active

---

## Connection State Management

### Listeners and Events

The server implements several listener classes to monitor device state:

#### 1. Connection Listener

Monitors connection state changes and handles automatic reconnection.

```python
class ATVConnectionListener(pyatv.interface.DeviceListener):
    def connection_lost(self, exception):
        """Called when connection is unexpectedly lost"""
        # Attempt automatic reconnection
        loop.create_task(attempt_reconnection())

        # Notify client
        if active_ws:
            loop.run_until_complete(
                send_command(active_ws, "connection_lost")
            )

    def connection_closed(self):
        """Called when connection is intentionally closed"""
        # No reconnection attempt
        if active_ws:
            loop.run_until_complete(
                send_command(active_ws, "connection_closed")
            )
```

#### Connection Lost Event

```json
{
  "command": "connection_lost"
}
```

#### Connection Closed Event

```json
{
  "command": "connection_closed"
}
```

#### 2. Power State Listener

Monitors Apple TV power state changes.

```python
class ATVPowerListener(pyatv.interface.PowerListener):
    def powerstate_update(self, old_state, new_state):
        if active_ws:
            loop.run_until_complete(
                send_command(active_ws, "power_state_changed", {
                    "old_state": str(old_state),
                    "new_state": str(new_state)
                })
            )
```

#### Power State Change Event

```json
{
  "command": "power_state_changed",
  "data": {
    "old_state": "Off",
    "new_state": "On"
  }
}
```

### Automatic Reconnection

When connection is lost, the server attempts automatic reconnection:

```python
async def attempt_reconnection():
    if not current_config:
        return False

    try:
        # Close old connection
        if active_device:
            await active_device.close()

        # Reconnect using stored config
        device = await pyatv.connect(current_config, loop)
        active_device = device
        active_remote = device.remote_control

        # Re-setup listeners
        setup_listeners(device)

        # Notify client of success
        if active_ws:
            await send_command(active_ws, "reconnected")

        return True

    except Exception as ex:
        # Notify client of failure
        if active_ws:
            await send_command(active_ws, "reconnection_failed")

        return False
```

#### Reconnection Success Event

```json
{
  "command": "reconnected"
}
```

#### Reconnection Failed Event

```json
{
  "command": "reconnection_failed"
}
```

### Disconnect Command

Intentionally disconnect from the Apple TV.

#### Client Request

```json
{
  "cmd": "disconnect"
}
```

#### Server Processing

```python
async def handle_disconnect(websocket):
    global active_device, active_remote, current_config

    # Close connection
    if active_device:
        await active_device.close()

    # Reset state
    active_device = None
    active_remote = None
    current_config = None

    await send_command(websocket, "disconnected")
```

#### Server Response

```json
{
  "command": "disconnected"
}
```

---

## Complete Protocol Message Reference

### Client → Server Commands

| Command        | Data Type        | Description                               |
| -------------- | ---------------- | ----------------------------------------- |
| `scan`         | -                | Scan for Apple TV devices                 |
| `startPair`    | string           | Start pairing with device (display name)  |
| `finishPair1`  | string           | Complete AirPlay pairing (4-digit PIN)    |
| `finishPair2`  | string           | Complete Companion pairing (4-digit PIN)  |
| `connect`      | object           | Connect to paired device with credentials |
| `disconnect`   | -                | Disconnect from current device            |
| `is_connected` | -                | Check connection status                   |
| `ping_device`  | -                | Ping device to verify connection          |
| `key`          | string or object | Send remote control command               |
| `kbfocus`      | -                | Check keyboard focus state                |
| `gettext`      | -                | Get current text from input field         |
| `settext`      | object           | Set text in input field                   |
| `quit`         | -                | Stop server                               |
| `echo`         | any              | Echo test (returns same data)             |

### Server → Client Responses

| Command                | Data Type | Description                              |
| ---------------------- | --------- | ---------------------------------------- |
| `scanResult`           | array     | List of discovered devices               |
| `startPair2`           | -         | Prompt for second pairing code           |
| `pairCredentials`      | object    | Final pairing credentials                |
| `connected`            | -         | Successfully connected to device         |
| `connection_failure`   | -         | Failed to connect                        |
| `disconnected`         | -         | Successfully disconnected                |
| `is_connected`         | string    | Connection status ("true"/"false")       |
| `ping_result`          | string    | Ping result                              |
| `command_failed`       | string    | Command execution failed (error message) |
| `kbfocus-status`       | boolean   | Keyboard focus state                     |
| `current-text`         | string    | Current text from input field            |
| `keyboard_changestate` | array     | Focus state changed [old, new]           |
| `connection_lost`      | -         | Connection lost unexpectedly             |
| `connection_closed`    | -         | Connection closed intentionally          |
| `reconnected`          | -         | Automatic reconnection successful        |
| `reconnection_failed`  | -         | Automatic reconnection failed            |
| `power_state_changed`  | object    | Power state changed                      |
| `echo_reply`           | any       | Echo response                            |

---

## Implementation Guide

### Building a CLI Client

Here's a step-by-step guide to implementing an Apple TV Remote CLI:

#### 1. Setup WebSocket Connection

```python
import asyncio
import websockets
import json

async def connect_to_server():
    uri = "ws://localhost:8765"
    async with websockets.connect(uri) as websocket:
        return websocket

async def send_command(websocket, cmd, data=None):
    message = {"cmd": cmd}
    if data is not None:
        message["data"] = data
    await websocket.send(json.dumps(message))

async def receive_message(websocket):
    message = await websocket.recv()
    return json.loads(message)
```

#### 2. Scan for Devices

```python
async def scan_devices(websocket):
    await send_command(websocket, "scan")

    while True:
        response = await receive_message(websocket)
        if response["command"] == "scanResult":
            devices = response["data"]
            return devices
```

#### 3. Pair with Device (Two-Step Process)

```python
async def pair_device(websocket, device_name):
    # Step 1: Start AirPlay pairing
    await send_command(websocket, "startPair", device_name)

    pin1 = input("Enter first 4-digit PIN from TV: ")
    await send_command(websocket, "finishPair1", pin1)

    # Wait for startPair2 response
    while True:
        response = await receive_message(websocket)
        if response["command"] == "startPair2":
            break

    # Step 2: Complete Companion pairing
    pin2 = input("Enter second 4-digit PIN from TV: ")
    await send_command(websocket, "finishPair2", pin2)

    # Wait for credentials
    while True:
        response = await receive_message(websocket)
        if response["command"] == "pairCredentials":
            credentials = response["data"]
            return credentials
```

#### 4. Store and Load Credentials

```python
import json

def save_credentials(credentials, filename="atv_credentials.json"):
    with open(filename, 'w') as f:
        json.dump(credentials, f)

def load_credentials(filename="atv_credentials.json"):
    try:
        with open(filename, 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        return None
```

#### 5. Connect to Device

```python
async def connect_device(websocket, credentials):
    await send_command(websocket, "connect", credentials)

    while True:
        response = await receive_message(websocket)
        if response["command"] == "connected":
            return True
        elif response["command"] == "connection_failure":
            return False
```

#### 6. Send Control Commands

```python
async def send_key(websocket, key_name):
    """Send simple key press"""
    await send_command(websocket, "key", key_name)

async def send_key_hold(websocket, key_name):
    """Send long press"""
    await send_command(websocket, "key", {
        "key": key_name,
        "taction": "Hold"
    })
```

#### 7. Complete CLI Example

```python
import asyncio
import websockets
import json

async def main():
    uri = "ws://localhost:8765"

    async with websockets.connect(uri) as websocket:
        # Try to load existing credentials
        creds = load_credentials()

        if not creds:
            # First time setup: scan and pair
            print("Scanning for Apple TV devices...")
            devices = await scan_devices(websocket)

            print("\nAvailable devices:")
            for i, device in enumerate(devices):
                print(f"{i+1}. {device}")

            choice = int(input("\nSelect device number: ")) - 1
            device_name = devices[choice]

            print(f"\nPairing with {device_name}...")
            creds = await pair_device(websocket, device_name)
            save_credentials(creds)
            print("Pairing complete!")

        # Connect to device
        print("Connecting to Apple TV...")
        if await connect_device(websocket, creds):
            print("Connected successfully!")
        else:
            print("Connection failed!")
            return

        # Command loop
        print("\nCommands: up, down, left, right, select, menu, home, play_pause, quit")

        while True:
            cmd = input("> ").strip().lower()

            if cmd == "quit":
                break
            elif cmd in ['up', 'down', 'left', 'right', 'select', 'menu',
                         'home', 'play_pause', 'volume_up', 'volume_down']:
                await send_key(websocket, cmd)
            else:
                print("Unknown command")

if __name__ == "__main__":
    asyncio.run(main())
```

---

## Error Handling

### Common Error Scenarios

#### 1. Connection Timeout

- **Cause**: Device not found or not responding
- **Detection**: No response to `connect` command within timeout period
- **Action**: Retry or prompt user to check network/device

#### 2. Invalid Credentials

- **Cause**: Credentials expired or device reset
- **Detection**: `connection_failure` response to `connect` command
- **Action**: Re-pair with device

#### 3. Wrong PIN During Pairing

- **Symptom**: `has_paired` is False after `finishPair1` or `finishPair2`
- **Action**: Restart pairing process

#### 4. Device Not on Network

- **Cause**: Apple TV powered off or disconnected
- **Detection**: Empty scan results or connection timeout
- **Action**: Prompt user to check device

#### 5. WebSocket Connection Lost

- **Detection**: WebSocket connection exception
- **Action**: Reconnect to WebSocket server

#### 6. Text Input Not Available

- **Symptom**: `kbfocus-status` returns false
- **Action**: Inform user that no text field is active on TV

### Error Handling Best Practices

1. **Implement Timeouts**: Don't wait forever for responses
2. **Retry Logic**: Retry failed operations with exponential backoff
3. **Credential Validation**: Verify credentials exist before attempting connection
4. **User Feedback**: Provide clear error messages to users
5. **Graceful Degradation**: If Companion protocol fails, basic AirPlay commands should still work

---

## Advanced Features

### Long Press Detection

To implement long press (e.g., for context menus):

```python
await send_command(websocket, "key", {
    "key": "select",
    "taction": "Hold"
})
```

### Volume Control

Volume commands don't support input actions:

```python
await send_command(websocket, "key", "volume_up")
await send_command(websocket, "key", "volume_down")
```

### Home Button Long Press

To trigger the App Switcher:

```python
await send_command(websocket, "key", "home_hold")
```

### Skip Forward/Backward

For media playback:

```python
await send_command(websocket, "key", "skip_forward")
await send_command(websocket, "key", "skip_backward")
```

---

## Protocol Notes and Limitations

### Important Considerations

1. **Pairing Must Be Completed in Order**: AirPlay first, then Companion
2. **PINs Are Different**: Each protocol displays a separate 4-digit PIN
3. **Companion Protocol is Optional**: Basic remote functions work with AirPlay only
4. **Text Input Requires Companion**: Keyboard features only work if Companion is paired
5. **Connection Persistence**: The server maintains connection even if WebSocket client disconnects
6. **Single Client Limitation**: Only one WebSocket client should send commands at a time
7. **Network Requirement**: Client, server, and Apple TV must be on same network
8. **Credential Security**: Store credentials securely (they provide full device access)

### Protocol Versions

This specification is based on:

- pyatv library: Latest version (as of project creation)
- AirPlay Protocol: Standard Apple AirPlay remote control
- Companion Protocol: Apple TV Companion protocol for advanced features

---

## Testing and Debugging

### Test Commands

#### Echo Test

Verify WebSocket connection:

```json
{ "cmd": "echo", "data": "test" }
```

Expected response:

```json
{ "command": "echo_reply", "data": "test" }
```

#### Ping Test

Verify device connection:

```json
{ "cmd": "ping_device" }
```

Expected response:

```json
{ "command": "ping_result", "data": "connected" }
```

### Debugging Tips

1. **Enable Logging**: Use `logging` module to see pyatv debug output
2. **Monitor Network**: Use Wireshark to inspect mDNS and device traffic
3. **Check Credentials**: Verify credential strings are stored/loaded correctly
4. **Test Protocols Separately**: Test AirPlay commands first, then Companion features
5. **Verify Device State**: Check that Apple TV is awake and on network

---

## Security Considerations

1. **Credential Storage**: Encrypt credentials if storing on multi-user systems
2. **WebSocket Security**: Consider adding authentication to WebSocket server
3. **Network Exposure**: Server binds to localhost only (not externally accessible)
4. **Credential Transmission**: Credentials sent over localhost WebSocket (not encrypted but not network-exposed)
5. **Apple TV Access**: Anyone with credentials has full control of the device

---

## Appendix A: InputAction Enum Values

Valid values for `taction` parameter:

- `SingleTap`: Single press (default)
- `DoubleTap`: Double press
- `Hold`: Long press/hold

Not all commands support all input actions. Commands in the `no_action_keys` list don't accept input actions.

---

## Appendix B: Keyboard Focus States

States from `pyatv_const.KeyboardFocusState`:

- `Focused`: Text input field is active and ready for input
- `Unfocused`: No text input field is active

---

## Appendix C: Complete Command List with Examples

### Navigation Commands

```python
# D-pad navigation
await send_command(ws, "key", "up")
await send_command(ws, "key", "down")
await send_command(ws, "key", "left")
await send_command(ws, "key", "right")

# Select button
await send_command(ws, "key", "select")

# With hold action
await send_command(ws, "key", {"key": "select", "taction": "Hold"})
```

### Menu Commands

```python
# Menu button
await send_command(ws, "key", "menu")

# Top menu
await send_command(ws, "key", "top_menu")

# Home button
await send_command(ws, "key", "home")

# Home long press (app switcher)
await send_command(ws, "key", "home_hold")
```

### Playback Commands

```python
# Play/Pause toggle
await send_command(ws, "key", "play_pause")

# Skip forward/backward
await send_command(ws, "key", "skip_forward")
await send_command(ws, "key", "skip_backward")
```

### Volume Commands

```python
# Volume control
await send_command(ws, "key", "volume_up")
await send_command(ws, "key", "volume_down")
```

### Text Input Commands

```python
# Check if text field is active
await send_command(ws, "kbfocus")

# Get current text
await send_command(ws, "gettext")

# Set new text
await send_command(ws, "settext", {"text": "Search query"})
```

---

## Conclusion

This specification provides all the information needed to implement a fully functional Apple TV Remote CLI or GUI application. The protocol is built on top of the excellent `pyatv` library and provides a simple WebSocket-based interface for remote control.

Key implementation steps:

1. Start WebSocket server with pyatv
2. Scan for devices
3. Pair with device (two-step process)
4. Save credentials
5. Connect using stored credentials
6. Send commands as needed

For questions or issues, refer to:

- pyatv documentation: https://pyatv.dev/
- This project: https://github.com/bsharper/atv-desktop-remote

---

**Document End**
