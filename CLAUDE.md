# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Flutter plugin for managing audio input and output devices on iOS and Android. It provides enumeration, selection, and real-time monitoring of audio devices like microphones, speakers, Bluetooth headsets, wired headphones, and USB audio devices.

**Key characteristics:**
- Cross-platform plugin (iOS via Swift + AVAudioSession, Android via Kotlin + AudioManager)
- Platform channels architecture (MethodChannel for requests, EventChannel for real-time updates)
- **NEW**: Full output device management (speakers, headphones, Bluetooth)
- Version: 0.0.6
- Min SDK: Dart ^3.7.0, Flutter >=3.3.0, Android API 23+

## Common Commands

### Testing
```bash
# Run all tests
flutter test

# Run tests in example app
cd example && flutter test
```

### Building
```bash
# Build example app for iOS
cd example && flutter build ios

# Build example app for Android
cd example && flutter build apk

# Run example app
cd example && flutter run
```

### Linting
```bash
# Analyze Dart code
flutter analyze

# Format Dart code
dart format .
```

### Native Development
```bash
# iOS: Open native code in Xcode
open ios/audio_devices_manager.xcworkspace

# Android: Build native code
cd android && ./gradlew build
```

## Architecture

### Three-Layer Platform Channel Pattern

1. **Dart API Layer** (`lib/audio_devices_manager.dart`)
   - Single static class with MethodChannel and EventChannel
   - All methods are static - no instance management needed
   - MethodChannel handles request/response calls
   - EventChannel provides Stream for real-time device updates

2. **iOS Layer** (`ios/.../AudioDevicesManagerPlugin.swift`)
   - Uses AVAudioSession API
   - Device selection via `setPreferredInput()` - applies globally to all recording
   - Data sources represent physical microphone characteristics (e.g., "Voice Isolation", "Wide Spectrum")
   - NotificationCenter monitors route changes (device connect/disconnect)

3. **Android Layer** (`android/.../AudioDevicesManagerPlugin.kt`)
   - Uses AudioManager + AudioDeviceInfo API (API 23+)
   - Device selection tracked via SharedPreferences
   - **Critical difference from iOS**: Device selection must be manually applied to AudioRecord via `setPreferredDevice()`
   - Data sources emulated via MediaRecorder.AudioSource types (not physical mic characteristics)
   - AudioDeviceCallback monitors device changes

### Platform Differences (Critical for Implementation)

**Input Devices:**

**iOS:**
- `selectInput()` applies globally - all recording APIs automatically use selected device
- `getSelectedInputDeviceId()` returns null (device ID not needed)

**Android:**
- `selectInput()` only tracks selection - does NOT route audio automatically
- Must call `getSelectedInputDeviceId()` and pass to `AudioRecord.setPreferredDevice()`
- See RECORDING_INTEGRATION.md for complete integration patterns

**Output Devices:**

**iOS:**
- `selectOutput()` is informational only - cannot programmatically select specific output device
- System controls output routing based on category options
- Use `setDefaultToSpeaker()` to control speaker vs other outputs
- For user control, must use system Route Picker UI

**Android:**
- `selectOutput()` provides full programmatic control
- Uses `AudioManager.setCommunicationDevice()` on API 31+
- For older APIs: Use `getSelectedOutputDeviceId()` with `AudioTrack.setPreferredDevice()`
- Supports: Built-in Speaker, Earpiece, Bluetooth (SCO/A2DP), Wired Headphones, USB

**Data Sources:**
- iOS: Physical microphone modes (AVAudioSessionDataSourceDescription)
- Android: Audio source types for MediaRecorder (MIC, VOICE_COMMUNICATION, VOICE_RECOGNITION, CAMCORDER)

### Event Flow Architecture

**Initialization:**
```
Flutter call initialize()
  → Plugin registers AudioDeviceCallback (Android) / NotificationCenter (iOS)
  → Load saved preferences from SharedPreferences / UserDefaults
  → Fetch current device list
  → Send initial state via EventChannel
```

**Device Change:**
```
Hardware event (plug/unplug)
  → AudioDeviceCallback / NotificationCenter fires
  → Fetch updated device list
  → Restore previously selected device if still available
  → Send update via EventChannel Stream
```

**User Selection:**
```
Flutter calls selectInput(uid)
  → Find device by ID
  → Save to SharedPreferences / UserDefaults
  → iOS: setPreferredInput() (applies globally)
  → Android: Only track selection (app must use getSelectedInputDeviceId())
  → Send update via EventChannel
```

## Key Implementation Patterns

### Android Bluetooth Device Names
The plugin implements sophisticated Bluetooth device name resolution (AudioDevicesManagerPlugin.kt:257-360):
1. Attempt via device address (API 28+)
2. Search bonded devices for actively connected audio device using reflection to check `isConnected()`
3. Fallback to first paired audio device (majorDeviceClass == 1024)
4. Returns null if all methods fail

This complexity is necessary because Android doesn't provide direct BT device names via AudioDeviceInfo.

### Persistence Strategy
- **iOS**: UserDefaults stores `selectedAudioInput` (String UID) and `selectedDataSource` (NSNumber)
- **Android**: SharedPreferences stores `selectedAudioInput` (String device ID) and `selectedAudioSource` (Int)
- On plugin initialization, saved selections are restored if devices still available
- If saved device not found, first available device is selected

### Resource Management
Both platforms implement `dispose()`:
- Unregister device change callbacks/observers
- Clear EventChannel sink
- Set `isInitialized = false` to prevent repeated disposal
- Android: Unregister AudioDeviceCallback
- iOS: Remove NotificationCenter observers, deactivate AVAudioSession

## Integration with Audio Recording

**Critical for Android developers**: This plugin enumerates and tracks device selection but does NOT automatically route audio on Android. See RECORDING_INTEGRATION.md for complete patterns.

**Pattern for all recording libraries:**
```dart
// 1. User selects device
await AudioDevicesManager.selectInput(deviceUid);

// 2. iOS: Done! Recording automatically uses selected device
// Android: Get device ID and pass to native code
final deviceId = await AudioDevicesManager.getSelectedInputDeviceId();

// 3. Android native: call audioRecord.setPreferredDevice(deviceInfo)
```

## Permissions

**iOS** (Info.plist):
- `NSMicrophoneUsageDescription` - Required for microphone access (only if using recording)

**Android** (Auto-added to manifest):
- `BLUETOOTH_CONNECT` (API 31+) - Required for Bluetooth device names (request at runtime)
- `BLUETOOTH` (API 30-) - Legacy Bluetooth support (request at runtime)
- `MODIFY_AUDIO_SETTINGS` - Required for output device selection via `setCommunicationDevice()` (normal protection level, no runtime request needed)

**Note**: As of v0.0.6, `RECORD_AUDIO` is NOT required for device enumeration. Only request it if your app performs actual audio recording.

## Testing Strategy

When modifying this plugin:

1. **Unit Tests**: Mock AudioManager/AVAudioSession, test device filtering and preference persistence
2. **Integration Tests**: Requires physical devices with:
   - Bluetooth headsets (emulators don't support BT audio)
   - Wired headsets with microphones
   - USB audio interfaces (Android)
3. **Test Scenarios**:
   - Hot-plugging devices during recording
   - App backgrounding/foregrounding
   - Permission denial handling
   - Device selection persistence across app restarts

## Important Files for Common Tasks

**Adding new input device types:**
- Android: AudioDevicesManagerPlugin.kt (`isValidInputDevice`)
- iOS: No filtering needed (AVAudioSession handles all types)

**Adding new output device types:**
- Android: AudioDevicesManagerPlugin.kt (`isValidOutputDevice`)
- iOS: Uses AVAudioSession currentRoute.outputs

**Modifying device enumeration:**
- Android: AudioDevicesManagerPlugin.kt (`fetchAudioDevices`)
- iOS: AudioDevicesManagerPlugin.swift (`fetchAudioDevices`, `fetchOutputDevices`)

**Changing device name logic:**
- Android: AudioDevicesManagerPlugin.kt (`getDeviceName`, `getOutputDeviceName`)
- iOS: Uses AVAudioSessionPortDescription.portName directly

**Adding new MethodChannel methods:**
1. Add case to `onMethodCall` in native code (Swift/Kotlin)
2. Add static method to lib/audio_devices_manager.dart
3. Update EventChannel data structure if needed (`sendDeviceUpdateEvent`)
4. Update example app to demonstrate new feature

## Known Limitations

1. **iOS Output Selection**: Cannot programmatically select specific Bluetooth device - system controls routing
2. **Android API < 31**: `setCommunicationDevice()` unavailable for outputs - must use AudioTrack.setPreferredDevice()
3. **Android Data Sources**: Not true equivalent to iOS - returns audio source types instead of physical mic characteristics
4. **Bluetooth A2DP**: Only SCO (voice) headsets enumerated as inputs - A2DP (music) devices don't support microphone
