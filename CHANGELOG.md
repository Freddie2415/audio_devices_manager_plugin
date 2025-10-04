## 0.0.5

* 🐛 **Android Fix**: Fixed Bluetooth device names showing phone model instead of actual device name (e.g., "AirPods" instead of "Redmi Note 8")
* 🔍 **Smart Detection**: Implemented active Bluetooth device detection - prioritizes currently connected audio devices
* 🧹 **Code Cleanup**: Removed `setCommunicationDevice()` logic (not needed for audio recording use cases)
* 📜 **Permissions**: Removed `MODIFY_AUDIO_SETTINGS` permission (not required for device enumeration)
* 🌍 **Localization**: Translated all code comments to English
* ⚡ **Minimal Permissions**: Plugin now requires only Bluetooth permissions for device name resolution

## 0.0.4

* 🐛 **Bug Fix**: Fixed missing dispose method handler in iOS MethodChannel
* 🛡️ **Safety**: Added guard against repeated dispose calls in Android
* 🔧 **Stability**: Wrapped clearCommunicationDevice in try-catch for better error handling

## 0.0.3

* ✅ **Recording Integration**: Added `getSelectedInputDeviceId()` method for integration with AudioRecord
* 📖 **Integration Guide**: New RECORDING_INTEGRATION.md with complete examples for native recording
* 🔧 **Better Android Support**: Now provides device ID for manual integration with recording libraries
* 📝 **Documentation**: Updated README with recording integration warnings and examples
* ⚠️ **Important Notice**: Android users must manually call `audioRecord.setPreferredDevice()` - see docs

## 0.0.2

* ✅ **Android implementation**: Full Android support added using AudioManager and AudioDeviceInfo API
* ✅ **Real-time device monitoring**: AudioDeviceCallback integration for device connect/disconnect events
* ✅ **Permission handling**: Added runtime permission requests in example app
* ✅ **Cross-platform parity**: All iOS methods now available on Android
* ✅ **Data Sources emulation**: Android audioSource types mapped to iOS dataSources concept
* 📝 **Documentation**: Added ANDROID_IMPLEMENTATION.md with technical details
* 🔧 **Configuration**: Updated minSdkVersion to 23, added necessary permissions

## 0.0.1

* 🎉 **Initial iOS release**: iOS implementation with AVAudioSession
* 🎤 Audio input device enumeration and selection
* 🔊 Data sources support (Wide Spectrum, Voice Isolation)
* 📡 Real-time audio route change notifications via EventChannel
* 💾 Persistent device selection with UserDefaults
