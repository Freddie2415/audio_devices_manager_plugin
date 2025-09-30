# Android Implementation Details

## 📋 Overview
This document describes the Android implementation of the `audio_devices_manager` plugin.

## 🏗️ Architecture

### Core Components

1. **AudioDevicesManagerPlugin** (Main plugin class)
   - Implements `FlutterPlugin`, `MethodCallHandler`, `EventChannel.StreamHandler`
   - Manages AudioManager lifecycle
   - Handles device enumeration and selection

2. **AudioManager** (Android system service)
   - Used to enumerate audio devices
   - Provides device change callbacks
   - Manages communication device routing

3. **AudioDeviceCallback** (Device change listener)
   - Monitors device connections/disconnections
   - Triggers device list updates
   - Sends events to Flutter via EventChannel

## 🔧 Implementation Details

### Device Enumeration

```kotlin
audioManager?.getDevices(AudioManager.GET_DEVICES_INPUTS)
```

**Supported device types:**
- `TYPE_BUILTIN_MIC` - Built-in microphone
- `TYPE_BLUETOOTH_SCO` - Bluetooth headset
- `TYPE_WIRED_HEADSET` - Wired headset with mic
- `TYPE_USB_DEVICE` - USB audio device
- `TYPE_USB_HEADSET` - USB headset

### Device Selection

**Android 12+ (API 31+):**
```kotlin
audioManager?.setCommunicationDevice(device)
```

**Android 6-11 (API 23-30):**
Device selection is tracked but not enforced system-wide. Apps need to use `AudioRecord.setPreferredDevice()` when recording.

### Data Sources Emulation

Since Android doesn't have direct equivalents to iOS `dataSources`, we expose `MediaRecorder.AudioSource` types:

| Android AudioSource | Description | iOS Equivalent |
|---------------------|-------------|----------------|
| `MIC` | Standard microphone | Wide Spectrum |
| `VOICE_COMMUNICATION` | Optimized for calls | Voice Isolation |
| `VOICE_RECOGNITION` | Optimized for ASR | - |
| `CAMCORDER` | Optimized for video | - |

### Real-time Updates

```kotlin
audioManager?.registerAudioDeviceCallback(audioDeviceCallback, handler)
```

- `onAudioDevicesAdded()` - Called when device connected
- `onAudioDevicesRemoved()` - Called when device disconnected
- Both trigger `fetchAudioDevices()` → `sendDeviceUpdateEvent()`

### Persistence

Uses `SharedPreferences` to save:
- `selectedAudioInput` (String) - Device ID
- `selectedAudioSource` (Int) - Audio source type

## 📱 API Level Support

| Feature | Min API | Optimal API | Notes |
|---------|---------|-------------|-------|
| AudioDeviceInfo | 23 | 23+ | Core functionality |
| AudioDeviceCallback | 23 | 23+ | Device monitoring |
| setCommunicationDevice | 31 | 31+ | Device routing |
| BLUETOOTH_CONNECT | 31 | 31+ | Permission for BT |

**Minimum SDK:** 23 (Android 6.0 Marshmallow)

## 🔐 Permissions

### Manifest Permissions
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
```

### Runtime Permissions Required
- `RECORD_AUDIO` - Required for microphone access
- `BLUETOOTH_CONNECT` (API 31+) - Required for Bluetooth device names

## 🔄 Event Flow

### Initialization Flow
```
Flutter: initialize()
    ↓
Plugin: initialize()
    ↓
Register AudioDeviceCallback
    ↓
Load saved preferences
    ↓
fetchAudioDevices()
    ↓
sendDeviceUpdateEvent() → Flutter Stream
```

### Device Change Flow
```
Hardware: Device plugged in/out
    ↓
AudioDeviceCallback: onAudioDevicesAdded/Removed()
    ↓
fetchAudioDevices()
    ↓
loadSelectedInput() - restore if available
    ↓
sendDeviceUpdateEvent() → Flutter Stream
```

### Device Selection Flow
```
Flutter: selectInput(uid)
    ↓
Plugin: selectInput(uid)
    ↓
Find device by ID
    ↓
Save to SharedPreferences
    ↓
setCommunicationDevice() [API 31+]
    ↓
sendDeviceUpdateEvent() → Flutter Stream
```

## 🧪 Testing Considerations

### Unit Tests
- Mock AudioManager
- Test device filtering logic
- Test preference saving/loading
- Test event stream behavior

### Integration Tests
- Test on physical devices with:
  - Bluetooth headsets
  - Wired headsets
  - USB audio devices
- Test device hot-plugging
- Test app restart (preference restoration)

## ⚠️ Known Limitations

1. **Device Selection Pre-API 31**
   - `setCommunicationDevice()` not available
   - Selection is tracked but not system-enforced
   - Apps must use `AudioRecord.setPreferredDevice()` manually

2. **Data Sources**
   - Not a true equivalent to iOS dataSources
   - Returns audioSource types instead
   - Actual effect depends on device hardware

3. **Device Names**
   - API 28+ has `productName`
   - Older versions fall back to device type names
   - May not match physical product names

4. **Bluetooth A2DP**
   - Only SCO (voice) headsets are enumerated as inputs
   - A2DP (music) devices don't support microphone input

## 🔍 Debugging

### Enable Logging
Add to plugin code:
```kotlin
private val TAG = "AudioDevicesManager"

Log.d(TAG, "Available devices: ${availableInputs.size}")
Log.d(TAG, "Selected device: ${selectedInput?.productName}")
```

### Common Issues

**No devices found:**
- Check `RECORD_AUDIO` permission granted
- Verify minSdkVersion = 23
- Check device has microphone hardware

**Bluetooth device not appearing:**
- Check `BLUETOOTH_CONNECT` permission (API 31+)
- Ensure Bluetooth headset is connected
- Check device supports SCO profile

**Device selection not working:**
- On API < 31, selection is tracked but not enforced
- Check `MODIFY_AUDIO_SETTINGS` permission
- Verify device ID is correct

## 📚 References

- [AudioManager Documentation](https://developer.android.com/reference/android/media/AudioManager)
- [AudioDeviceInfo Documentation](https://developer.android.com/reference/android/media/AudioDeviceInfo)
- [AudioDeviceCallback Documentation](https://developer.android.com/reference/android/media/AudioDeviceCallback)
- [Audio routing guide](https://developer.android.com/develop/connectivity/telecom/voip-app/api-updates)