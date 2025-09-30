# Migration Guide

## Upgrading from 0.0.1 to 0.0.2

Version 0.0.2 adds full Android support while maintaining 100% backward compatibility with existing iOS code.

### ✅ No Breaking Changes

If you're already using version 0.0.1 on iOS, **no code changes are required**. Your app will continue to work exactly as before.

### 🆕 New Features in 0.0.2

1. **Android Support** - The plugin now works on Android 6.0+ (API 23+)
2. **Runtime Permissions** - Added permission handling support
3. **Better Documentation** - Added technical implementation details

### 📱 For New Android Users

If you're implementing the plugin on Android for the first time, you need to:

#### 1. Request Runtime Permissions

Add `permission_handler` to your `pubspec.yaml`:

```yaml
dependencies:
  permission_handler: ^11.3.1
```

Then request permissions before using the plugin:

```dart
import 'package:permission_handler/permission_handler.dart';

// Request microphone permission
final micStatus = await Permission.microphone.request();

if (micStatus.isGranted) {
  // Initialize audio manager
  await AudioDevicesManager.initialize();
}

// On Android 12+, also request Bluetooth permission for BT devices
if (Platform.isAndroid) {
  await Permission.bluetoothConnect.request();
}
```

#### 2. Check Minimum SDK Version

Ensure your app's `android/app/build.gradle` has:

```gradle
android {
    defaultConfig {
        minSdkVersion 23  // Android 6.0 or higher
    }
}
```

### 📝 Platform-Specific Notes

#### Data Sources Behavior

**iOS:**
Returns physical microphone characteristics:
- Wide Spectrum
- Voice Isolation
- Cardioid pattern

**Android:**
Returns audio processing modes:
- Standard Microphone
- Voice Communication
- Voice Recognition
- Camcorder

Both achieve similar results but use different underlying mechanisms.

#### Device Selection

**iOS:**
Uses `AVAudioSession.setPreferredInput()` - works on all supported iOS versions.

**Android:**
- Android 12+ (API 31+): Uses `AudioManager.setCommunicationDevice()` - full system-wide routing
- Android 6-11 (API 23-30): Selection is tracked but apps need to use `AudioRecord.setPreferredDevice()` when recording

### 🔧 Example App Updates

The example app now includes:
- Automatic permission requests
- Visual permission status indicator
- Support for both iOS and Android

See `example/lib/home_page.dart` for reference implementation.

### 🐛 Known Limitations

1. **Android Pre-12**: Device selection is tracked but not enforced system-wide
2. **Bluetooth A2DP**: Only SCO (voice) headsets support microphone input
3. **Device Names**: On Android < 9, device names may be generic (e.g., "Bluetooth Headset" instead of brand name)

### 📚 Additional Resources

- [ANDROID_IMPLEMENTATION.md](ANDROID_IMPLEMENTATION.md) - Technical details for Android
- [README.md](README.md) - General usage guide
- [API Reference](README.md#-api-reference) - Complete method documentation

### 💬 Questions or Issues?

If you encounter any issues during migration, please:
1. Check the [README.md](README.md) for updated documentation
2. Review the example app for reference implementation
3. Open an issue on GitHub with details about your setup