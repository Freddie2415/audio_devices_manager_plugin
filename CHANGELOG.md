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
