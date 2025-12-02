## 📢 **audio_devices_manager**
*A Flutter plugin for managing audio input and output devices on iOS and Android.*

🚀 **Current Status**: iOS **✅** | Android **✅**

---

### 📌 **Features**
- 🔍 Get a list of available **audio input devices** (microphones)
- 🎧 Get a list of **audio output devices** (speakers, headphones, Bluetooth)
- 🎤 Select an **audio input device**
- 🔊 Select an **audio output device** (full control on Android, limited on iOS)
- 🎚️ Select a **microphone data source** (e.g., Wide Spectrum, Voice Isolation)
- 📱 **Listen for real-time audio route changes** (when devices are plugged in or removed)

---

## 📚 **Installation**
Add this dependency to your `pubspec.yaml` file:

```yaml
dependencies:
  audio_devices_manager:
  git:
    url: https://github.com/Freddie2415/audio_devices_manager_plugin
    ref: main
```

### **iOS Setup**
Add this permission to your `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>We need access to the microphone for audio recording</string>
```

### **Android Setup**
The plugin automatically adds required permissions to your `AndroidManifest.xml`. However, you need to request runtime permissions in your app:

```dart
import 'package:permission_handler/permission_handler.dart';

// Request microphone permission
await Permission.microphone.request();
await Permission.bluetoothConnect.request(); // For Bluetooth devices
```

**Minimum Android version:** Android 6.0 (API 23)

---

## 🛠 **Usage**
### ✅ **Import the package**
```dart
import 'package:audio_devices_manager/audio_devices_manager.dart';
```

### 🎤 **Get available audio inputs**
```dart
void fetchInputs() async {
  final audioManager = AudioDevicesManager();
  List<AudioInput> inputs = await audioManager.getAvailableInputs();
  print("Available Inputs: ${inputs.map((e) => e.name).toList()}");
}
```

### 🎧 **Get available audio outputs**
```dart
void fetchOutputs() async {
  List<Map<String, dynamic>> outputs = await AudioDevicesManager.getAvailableOutputs();
  print("Available Outputs: $outputs");
}
```

### 🎤 **Select an input device**
```dart
void selectMicrophone(String inputId) async {
  await AudioDevicesManager.selectInput(inputId);
  print("Selected input: $inputId");
}
```

### 🔊 **Select an output device**
```dart
void selectSpeaker(String outputId) async {
  await AudioDevicesManager.selectOutput(outputId);
  print("Selected output: $outputId");

  // Android only: Get device ID for AudioTrack integration
  if (Platform.isAndroid) {
    final deviceId = await AudioDevicesManager.getSelectedOutputDeviceId();
    print("Android Output Device ID: $deviceId");
    // Use deviceId with audioTrack.setPreferredDevice()
  }
}
```

### 🔊 **Get and select microphone data sources**
```dart
void fetchAndSelectDataSource(String inputId) async {
  final audioManager = AudioDevicesManager();
  List<AudioSource> sources = await audioManager.getAvailableDataSources(inputId);

  if (sources.isNotEmpty) {
    await audioManager.selectDataSource(inputId, sources.first.id);
    print("Selected data source: ${sources.first.name}");
  }
}
```

### 📱 **Listen for audio route changes**
```dart
void listenToAudioChanges() {
  AudioDevicesManager.deviceEvents().listen((event) {
    print("Audio route changed!");
    print("Available Inputs: ${event['availableInputs']}");
    print("Selected Input: ${event['selectedInput']}");
    print("Available Outputs: ${event['availableOutputs']}");
    print("Selected Output: ${event['selectedOutput']}");
    print("Data Sources: ${event['availableDataSources']}");
  });
}
```

---

## 🔧 **API Reference**
| Method | Description |
|--------|-------------|
| `initialize()` | Initialize audio session and start monitoring device changes. |
| `getAvailableInputs()` | Returns a list of available audio input devices. |
| `getAvailableOutputs()` | Returns a list of available audio output devices. |
| `selectInput(String uid)` | Sets the preferred audio input device. |
| `selectOutput(String uid)` | Sets the preferred audio output device. **Android**: Full control. **iOS**: Limited control. |
| `getSelectedInput()` | Returns currently selected input device. |
| `getSelectedOutput()` | Returns currently selected output device. |
| `getAvailableDataSources()` | Returns available microphone data sources for the selected input. |
| `selectDataSource(int dataSourceID)` | Sets the preferred microphone data source. |
| `getSelectedInputDeviceId()` | **Android only**: Returns device ID for use with `AudioRecord.setPreferredDevice()`. Returns null on iOS. |
| `getSelectedOutputDeviceId()` | **Android only**: Returns device ID for use with `AudioTrack.setPreferredDevice()`. Returns null on iOS. |
| `setDefaultToSpeaker(bool enable)` | **iOS only**: Enable/disable built-in speaker. No effect on Android. |
| `deviceEvents()` | Stream that listens for audio device changes (inputs, outputs, data sources). |
| `dispose()` | Clean up plugin resources. |

---

## ❓ **Platform Support**
| Platform | Support | Details |
|----------|---------|---------|
| **iOS** | ✅ Fully Implemented | AVAudioSession API |
| **Android** | ✅ Fully Implemented | AudioManager + AudioDeviceInfo API (API 23+) |

### **Android Implementation Notes**
- **Data Sources**: On Android, `getAvailableDataSources()` returns audio source types instead of physical microphone characteristics:
  - `Standard Microphone` - Default audio source
  - `Voice Communication` - Optimized for VoIP calls
  - `Voice Recognition` - Optimized for speech recognition
  - `Camcorder` - Optimized for video recording
- **Input Device Selection**:
  - Plugin provides device enumeration and selection tracking
  - **For audio recording (MediaRecorder/AudioRecord)**: You must use `getSelectedInputDeviceId()` and call `setPreferredDevice()` - see [RECORDING_INTEGRATION.md](RECORDING_INTEGRATION.md)
- **Output Device Selection**:
  - Full programmatic control over output devices
  - `selectOutput()` uses `AudioManager.setCommunicationDevice()` on API 31+
  - For older versions: Use `getSelectedOutputDeviceId()` with `AudioTrack.setPreferredDevice()`
  - Supports: Built-in Speaker, Built-in Earpiece, Bluetooth (SCO/A2DP), Wired Headphones, USB Audio
- **Bluetooth**: Full support for Bluetooth headsets with accurate device names (requires BLUETOOTH_CONNECT permission on Android 12+)

### **iOS Implementation Notes**
- **Input Device Selection**: Full programmatic control via `AVAudioSession.setPreferredInput()`
- **Output Device Selection**: **Limited control** due to iOS API restrictions:
  - Cannot programmatically select specific Bluetooth devices
  - Can control via category options (e.g., `setDefaultToSpeaker()`)
  - System decides output routing based on priorities
  - For user selection: Must use system Route Picker UI
- **Data Sources**: Physical microphone characteristics (e.g., "Voice Isolation", "Wide Spectrum")

### **⚠️ Important for Audio Recording**

**iOS:** Device selection works automatically for all recording APIs ✅

**Android:** You must manually integrate with your recording code:
```dart
// Select device
await AudioDevicesManager.selectInput(deviceUid);

// Get device ID
final deviceId = await AudioDevicesManager.getSelectedInputDeviceId();

// Pass to your AudioRecord and call setPreferredDevice()
// See RECORDING_INTEGRATION.md for complete examples
```

📖 **[Full Integration Guide →](RECORDING_INTEGRATION.md)**

---

## 📜 **Roadmap**
- ✅ Implement **iOS** support
- ✅ Add **Android** support (using `AudioManager` + `AudioDeviceInfo`)
- ✅ Add support for **audio output device selection**
- 🔊 Add **audio recording and playback** features
- 📈 Improve error handling and logging
- 🧪 Add comprehensive unit and integration tests
- 🌐 Consider macOS/Windows support

---

## 🛠 **Contributing**
Contributions are welcome! Feel free to:
- **Fork** the repo
- **Create a new branch** (`feature/android-support`)
- **Make changes** and **submit a PR** 🚀

---

## 📝 **License**
This project is licensed under the **MIT License**.

