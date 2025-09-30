## 📢 **audio_devices_manager**
*A Flutter plugin for managing audio input and output devices on iOS and Android.*

🚀 **Current Status**: iOS **✅** | Android **✅**

---

### 📌 **Features**
- 🔍 Get a list of available **audio input devices** (microphones)
- 🎧 Get a list of **audio output devices** (speakers, headphones)
- 🎤 Select an **audio input device**
- 🔊 Select a **microphone data source** (e.g., Wide Spectrum, Voice Isolation)
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
  final audioManager = AudioDevicesManager();
  List<AudioOutput> outputs = await audioManager.getAvailableOutputs();
  print("Available Outputs: ${outputs.map((e) => e.name).toList()}");
}
```

### 🎤 **Select an input device**
```dart
void selectMicrophone(String inputId) async {
  final audioManager = AudioDevicesManager();
  await audioManager.selectInput(inputId);
  print("Selected input: $inputId");
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
  final audioManager = AudioDevicesManager();
  audioManager.onAudioRouteChanged.listen((event) {
    print("Audio route changed!");
    print("New Inputs: ${event.inputs}");
    print("New Outputs: ${event.outputs}");
  });
}
```

---

## 🔧 **API Reference**
| Method | Description |
|--------|-------------|
| `getAvailableInputs()` | Returns a list of available audio input devices. |
| `getAvailableOutputs()` | Returns a list of available audio output devices. |
| `selectInput(String inputId)` | Sets the preferred audio input device. |
| `getAvailableDataSources(String inputId)` | Returns available microphone data sources for a selected input. |
| `selectDataSource(String inputId, String sourceId)` | Sets the preferred microphone data source. |
| `getSelectedInputDeviceId()` | **Android only**: Returns device ID for use with `AudioRecord.setPreferredDevice()`. Returns null on iOS. |
| `onAudioRouteChanged` | A stream that listens for audio input/output changes. |

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
- **Device Selection**:
  - On Android 12+ (API 31+), uses `setCommunicationDevice()` for VoIP/WebRTC
  - **For audio recording (MediaRecorder/AudioRecord)**: You must use `getSelectedInputDeviceId()` and call `setPreferredDevice()` - see [RECORDING_INTEGRATION.md](RECORDING_INTEGRATION.md)
- **Bluetooth**: Full support for Bluetooth headsets (requires BLUETOOTH_CONNECT permission on Android 12+)

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
- 🔊 Add **audio recording and playback** features
- 📈 Improve error handling and logging
- 🧪 Add comprehensive unit and integration tests
- 📱 Add support for audio output device selection
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

