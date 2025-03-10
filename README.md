## 📢 **audio_devices_manager**
*A Flutter plugin for managing audio input and output devices on iOS.*

🚀 **Current Status**: iOS **✅** | Android **❌** *(not implemented yet)*

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
      url: https://github.com/your-username/audio_devices_manager.git
```

For **iOS**, add this permission to your `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>We need access to the microphone for audio recording</string>
```

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
| `onAudioRouteChanged` | A stream that listens for audio input/output changes. |

---

## ❓ **Platform Support**
| Platform | Support |
|----------|---------|
| **iOS** | ✅ Implemented (AVAudioSession) |
| **Android** | ❌ Not implemented yet |

---

## 📜 **Roadmap**
- ✅ Implement **iOS** support
- ⏳ Add **Android** support (using `AudioManager`)
- 🔊 Add **audio recording and playback** features
- 📈 Improve error handling and logging

---

## 🛠 **Contributing**
Contributions are welcome! Feel free to:
- **Fork** the repo
- **Create a new branch** (`feature/android-support`)
- **Make changes** and **submit a PR** 🚀

---

## 📝 **License**
This project is licensed under the **MIT License**.

