package io.modacity.audio_devices_manager

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.content.Context
import android.content.SharedPreferences
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** AudioDevicesManagerPlugin */
class AudioDevicesManagerPlugin : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val TAG = "AudioDevicesManager"

        // Static list of available data sources (audioSource types)
        private val AVAILABLE_DATA_SOURCES = listOf(
            mapOf(
                "dataSourceID" to MediaRecorder.AudioSource.MIC,
                "dataSourceName" to "Standard Microphone"
            ),
            mapOf(
                "dataSourceID" to MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                "dataSourceName" to "Voice Communication"
            ),
            mapOf(
                "dataSourceID" to MediaRecorder.AudioSource.VOICE_RECOGNITION,
                "dataSourceName" to "Voice Recognition"
            ),
            mapOf(
                "dataSourceID" to MediaRecorder.AudioSource.CAMCORDER,
                "dataSourceName" to "Camcorder"
            )
        )
    }
    /// MethodChannel for one-time requests
    private lateinit var methodChannel: MethodChannel

    /// EventChannel for event streams
    private lateinit var eventChannel: EventChannel

    /// Android AudioManager
    private var audioManager: AudioManager? = null

    /// Application context
    private var context: Context? = null

    /// SharedPreferences for saving user selection
    private var sharedPreferences: SharedPreferences? = null

    /// EventSink for sending events to Dart
    private var eventSink: EventChannel.EventSink? = null

    /// Initialization flag
    private var isInitialized = false

    /// List of available inputs
    private var availableInputs: List<AudioDeviceInfo> = emptyList()

    /// Currently selected input
    private var selectedInput: AudioDeviceInfo? = null

    /// Currently selected audioSource (for dataSources)
    private var selectedAudioSource: Int = MediaRecorder.AudioSource.MIC

    /// List of available outputs
    private var availableOutputs: List<AudioDeviceInfo> = emptyList()

    /// Currently selected output
    private var selectedOutput: AudioDeviceInfo? = null

    /// Handler for UI thread operations
    private val mainHandler = Handler(Looper.getMainLooper())

    /// Bluetooth name cache to prevent expensive lookups
    private val bluetoothNameCache = mutableMapOf<String, String>()
    private var bluetoothCacheTimestamp = 0L
    private val CACHE_VALIDITY_MS = 5000L // 5 seconds

    /// Debounce for device change events
    private var updateDebounceRunnable: Runnable? = null
    private val DEBOUNCE_DELAY_MS = 300L

    /// Callback for tracking audio device changes
    private val audioDeviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) {
            fetchAudioDevicesDebounced()
        }

        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) {
            fetchAudioDevicesDebounced()
        }
    }

    // MARK: - FlutterPlugin lifecycle

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        audioManager = context?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        sharedPreferences = context?.getSharedPreferences("audio_devices_manager", Context.MODE_PRIVATE)

        // Setup MethodChannel
        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "audio_devices_manager")
        methodChannel.setMethodCallHandler(this)

        // Setup EventChannel
        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "audio_devices_manager_events")
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        dispose()
    }

    // MARK: - MethodChannel handler

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "initialize" -> {
                initialize()
                result.success(null)
            }

            "getAvailableInputs" -> {
                val inputs = getAvailableInputsList()
                result.success(inputs)
            }

            "selectInput" -> {
                val uid = call.argument<String>("uid")
                if (uid == null) {
                    result.error("BAD_ARGS", "No UID provided", null)
                    return
                }
                selectInput(uid)
                result.success(null)
            }

            "getSelectedInput" -> {
                val selected = selectedInput?.let { deviceInfoToMap(it) }
                result.success(selected)
            }

            "getAvailableDataSources" -> {
                val sources = getAvailableDataSourcesList()
                result.success(sources)
            }

            "selectDataSource" -> {
                val dataSourceID = call.argument<Int>("dataSourceID")
                if (dataSourceID == null) {
                    result.error("BAD_ARGS", "No dataSourceID provided", null)
                    return
                }
                selectDataSource(dataSourceID)
                result.success(null)
            }

            "getSelectedInputDeviceId" -> {
                val deviceId = selectedInput?.id
                result.success(deviceId)
            }

            "getAvailableOutputs" -> {
                val outputs = getAvailableOutputsList()
                result.success(outputs)
            }

            "selectOutput" -> {
                val uid = call.argument<String>("uid")
                if (uid == null) {
                    result.error("BAD_ARGS", "No UID provided", null)
                    return
                }
                selectOutput(uid)
                result.success(null)
            }

            "getSelectedOutput" -> {
                val selected = selectedOutput?.let { outputDeviceInfoToMap(it) }
                result.success(selected)
            }

            "getSelectedOutputDeviceId" -> {
                val deviceId = selectedOutput?.id
                result.success(deviceId)
            }

            "setDefaultToSpeaker" -> {
                // No-op on Android - use selectOutput instead
                result.success(null)
            }

            "showRoutePicker" -> {
                // No-op on Android - not applicable
                result.success(null)
            }

            "dispose" -> {
                dispose()
                result.success(null)
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    // MARK: - EventChannel.StreamHandler

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        // Send current state on first subscription
        sendDeviceUpdateEvent()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // MARK: - Initialization

    private fun initialize() {
        if (isInitialized) {
            return
        }
        isInitialized = true

        // Register callback for tracking changes
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            audioManager?.registerAudioDeviceCallback(audioDeviceCallback, mainHandler)
        }

        // Load saved audioSource
        selectedAudioSource = sharedPreferences?.getInt("selectedAudioSource", MediaRecorder.AudioSource.MIC)
            ?: MediaRecorder.AudioSource.MIC

        // Get current device state
        fetchAudioDevices()
    }

    // MARK: - Fetching device list

    /// Debounced version of fetchAudioDevices to prevent excessive calls
    private fun fetchAudioDevicesDebounced() {
        updateDebounceRunnable?.let { mainHandler.removeCallbacks(it) }

        updateDebounceRunnable = Runnable {
            fetchAudioDevices()
        }

        mainHandler.postDelayed(updateDebounceRunnable!!, DEBOUNCE_DELAY_MS)
    }

    private fun fetchAudioDevices() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            // Get all input devices
            availableInputs = audioManager?.getDevices(AudioManager.GET_DEVICES_INPUTS)
                ?.filter { isValidInputDevice(it) }
                ?: emptyList()

            // Load last selected input
            loadSelectedInput()

            // Get all output devices
            availableOutputs = audioManager?.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                ?.filter { isValidOutputDevice(it) }
                ?: emptyList()

            // Load last selected output
            loadSelectedOutput()

            // Send event to Dart
            sendDeviceUpdateEvent()
        }
    }

    private fun isValidInputDevice(device: AudioDeviceInfo): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return when (device.type) {
                AudioDeviceInfo.TYPE_BUILTIN_MIC,
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                AudioDeviceInfo.TYPE_WIRED_HEADSET,
                AudioDeviceInfo.TYPE_USB_DEVICE,
                AudioDeviceInfo.TYPE_USB_HEADSET -> true
                else -> false
            }
        }
        return false
    }

    private fun getAvailableInputsList(): List<Map<String, String>> {
        return availableInputs.map { device ->
            mapOf(
                "uid" to device.id.toString(),
                "portName" to getDeviceName(device)
            )
        }
    }

    private fun getDeviceName(device: AudioDeviceInfo): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            // For built-in and wired devices use human-readable names by type
            // For external (USB/Bluetooth) get actual device name
            return when (device.type) {
                AudioDeviceInfo.TYPE_BUILTIN_MIC -> "Built-in Microphone"
                AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Wired Headset"
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> {
                    // For Bluetooth get device name via BluetoothAdapter
                    getBluetoothDeviceName(device) ?: "Bluetooth Headset"
                }
                AudioDeviceInfo.TYPE_USB_DEVICE,
                AudioDeviceInfo.TYPE_USB_HEADSET -> {
                    // For USB devices show productName if available
                    val productName = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        device.productName.toString()
                    } else null

                    if (!productName.isNullOrEmpty() && productName != "null") {
                        productName
                    } else {
                        if (device.type == AudioDeviceInfo.TYPE_USB_HEADSET) "USB Headset" else "USB Device"
                    }
                }
                else -> "Unknown"
            }
        }
        return "Unknown"
    }

    private fun getBluetoothDeviceName(device: AudioDeviceInfo): String? {
        // Check runtime permission for Bluetooth (API 31+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (context?.checkSelfPermission(android.Manifest.permission.BLUETOOTH_CONNECT)
                != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                Log.w(TAG, "BLUETOOTH_CONNECT permission not granted")
                return null
            }
        }

        val deviceId = device.id.toString()
        val now = System.currentTimeMillis()

        // Check cache validity
        if (now - bluetoothCacheTimestamp < CACHE_VALIDITY_MS) {
            bluetoothNameCache[deviceId]?.let {
                Log.d(TAG, "Using cached Bluetooth name: $it")
                return it
            }
        }

        // If cache is stale, clear it
        if (now - bluetoothCacheTimestamp >= CACHE_VALIDITY_MS) {
            bluetoothNameCache.clear()
        }

        // Get name from Bluetooth adapter
        val name = getBluetoothDeviceNameInternal(device)
        if (name != null) {
            bluetoothNameCache[deviceId] = name
            bluetoothCacheTimestamp = now
            Log.d(TAG, "Cached Bluetooth name: $name for device: $deviceId")
        }

        return name
    }

    @Suppress("MissingPermission")
    private fun getBluetoothDeviceNameInternal(device: AudioDeviceInfo): String? {
        try {
            val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
            if (bluetoothAdapter == null) {
                Log.d(TAG, "BluetoothAdapter is null")
                return null
            }

            // Method 1: Try via address (Android P+)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val address = device.address
                Log.d(TAG, "Device address: $address")
                if (!address.isNullOrEmpty()) {
                    try {
                        val bluetoothDevice = bluetoothAdapter.getRemoteDevice(address)
                        val name = bluetoothDevice.name
                        Log.d(TAG, "Bluetooth device name from address: $name")
                        if (!name.isNullOrEmpty()) {
                            return name
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error getting device by address: ${e.message}")
                    }
                }
            }

            // Method 2: Search for actively connected device among bonded devices
            try {
                val bondedDevices = bluetoothAdapter.bondedDevices
                Log.d(TAG, "Bonded devices count: ${bondedDevices?.size ?: 0}")

                if (bondedDevices != null && bondedDevices.isNotEmpty()) {
                    // First search for connected device
                    var connectedAudioDevice: String? = null

                    for (btDevice in bondedDevices) {
                        try {
                            val deviceClass = btDevice.bluetoothClass
                            val majorClass = deviceClass?.majorDeviceClass
                            val name = btDevice.name

                            // Log all devices for diagnostics
                            Log.d(TAG, "Bonded device: $name, address: ${btDevice.address}, majorClass: $majorClass, bondState: ${btDevice.bondState}")

                            // Check if device is connected
                            try {
                                val isConnectedMethod = btDevice.javaClass.getMethod("isConnected")
                                val isConnected = isConnectedMethod.invoke(btDevice) as Boolean
                                Log.d(TAG, "  -> isConnected: $isConnected")

                                if (isConnected && deviceClass != null) {
                                    // Audio/Video class (0x0400 = 1024)
                                    if (majorClass == 1024) {
                                        Log.d(TAG, "Found CONNECTED audio device: $name")
                                        if (!name.isNullOrEmpty()) {
                                            connectedAudioDevice = name
                                            break
                                        }
                                    }
                                }
                            } catch (e: Exception) {
                                Log.d(TAG, "  -> Cannot check connection status: ${e.message}")
                            }
                        } catch (e: SecurityException) {
                            // Permission denied - skip this device
                            Log.d(TAG, "  -> Permission denied for device info: ${e.message}")
                        }
                    }

                    // If found connected device, return it
                    if (connectedAudioDevice != null) {
                        return connectedAudioDevice
                    }

                    // If no connected device found, use first audio device as fallback
                    for (btDevice in bondedDevices) {
                        try {
                            val deviceClass = btDevice.bluetoothClass
                            if (deviceClass != null) {
                                val majorClass = deviceClass.majorDeviceClass
                                if (majorClass == 1024) {
                                    val name = btDevice.name
                                    if (!name.isNullOrEmpty()) {
                                        Log.d(TAG, "Using first audio device as fallback: $name")
                                        return name
                                    }
                                }
                            }
                        } catch (e: SecurityException) {
                            // Permission denied - skip this device
                            Log.d(TAG, "  -> Permission denied for fallback device: ${e.message}")
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error getting bonded devices: ${e.message}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in getBluetoothDeviceName: ${e.message}")
        }
        return null
    }

    private fun deviceInfoToMap(device: AudioDeviceInfo): Map<String, String> {
        return mapOf(
            "uid" to device.id.toString(),
            "portName" to getDeviceName(device)
        )
    }

    private fun outputDeviceInfoToMap(device: AudioDeviceInfo): Map<String, String> {
        return mapOf(
            "uid" to device.id.toString(),
            "portName" to getOutputDeviceName(device)
        )
    }

    // MARK: - Input device selection

    private fun selectInput(uid: String) {
        val device = availableInputs.firstOrNull { it.id.toString() == uid }
        if (device == null) {
            return
        }

        selectedInput = device

        // Save selection
        sharedPreferences?.edit()?.putString("selectedAudioInput", uid)?.apply()

        // Send event
        sendDeviceUpdateEvent()
    }

    private fun loadSelectedInput() {
        val savedUID = sharedPreferences?.getString("selectedAudioInput", null)

        if (savedUID != null) {
            selectedInput = availableInputs.firstOrNull { it.id.toString() == savedUID }
        }

        // If nothing saved or device not found, take first one
        if (selectedInput == null && availableInputs.isNotEmpty()) {
            selectedInput = availableInputs.first()
        }
    }

    // MARK: - Output device management

    private fun isValidOutputDevice(device: AudioDeviceInfo): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return when (device.type) {
                AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
                AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                AudioDeviceInfo.TYPE_WIRED_HEADSET,
                AudioDeviceInfo.TYPE_USB_DEVICE,
                AudioDeviceInfo.TYPE_USB_HEADSET -> true
                else -> false
            }
        }
        return false
    }

    private fun getAvailableOutputsList(): List<Map<String, String>> {
        return availableOutputs.map { device ->
            mapOf(
                "uid" to device.id.toString(),
                "portName" to getOutputDeviceName(device)
            )
        }
    }

    private fun getOutputDeviceName(device: AudioDeviceInfo): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return when (device.type) {
                AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "Built-in Speaker"
                AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "Built-in Earpiece"
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "Wired Headphones"
                AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Wired Headset"
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> {
                    // For Bluetooth get device name via BluetoothAdapter
                    getBluetoothDeviceName(device) ?: "Bluetooth Headset"
                }
                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> {
                    // For Bluetooth get device name via BluetoothAdapter
                    getBluetoothDeviceName(device) ?: "Bluetooth Audio"
                }
                AudioDeviceInfo.TYPE_USB_DEVICE,
                AudioDeviceInfo.TYPE_USB_HEADSET -> {
                    // For USB devices show productName if available
                    val productName = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        device.productName.toString()
                    } else null

                    if (!productName.isNullOrEmpty() && productName != "null") {
                        productName
                    } else {
                        if (device.type == AudioDeviceInfo.TYPE_USB_HEADSET) "USB Headset" else "USB Device"
                    }
                }
                else -> "Unknown"
            }
        }
        return "Unknown"
    }

    private fun selectOutput(uid: String) {
        val device = availableOutputs.firstOrNull { it.id.toString() == uid }
        if (device == null) {
            return
        }

        selectedOutput = device

        // Save selection
        sharedPreferences?.edit()?.putString("selectedAudioOutput", uid)?.apply()

        // For Android S (API 31+) we can use setCommunicationDevice
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                audioManager?.setCommunicationDevice(device)
                Log.d("AudioDevicesManager", "Successfully set communication device: ${getOutputDeviceName(device)}")
            } catch (e: Exception) {
                Log.e("AudioDevicesManager", "Error setting communication device: ${e.message}")
            }
        } else {
            Log.d("AudioDevicesManager", "Device selection saved. Use getSelectedOutputDeviceId() to apply to AudioTrack")
        }

        // Send event
        sendDeviceUpdateEvent()
    }

    private fun loadSelectedOutput() {
        val savedUID = sharedPreferences?.getString("selectedAudioOutput", null)

        if (savedUID != null) {
            selectedOutput = availableOutputs.firstOrNull { it.id.toString() == savedUID }
        }

        // If nothing saved or device not found, take first one
        if (selectedOutput == null && availableOutputs.isNotEmpty()) {
            selectedOutput = availableOutputs.first()
        }

        // For Android S+ restore the communication device
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && selectedOutput != null) {
            try {
                audioManager?.setCommunicationDevice(selectedOutput!!)
            } catch (e: Exception) {
                Log.e("AudioDevicesManager", "Error restoring communication device: ${e.message}")
            }
        }
    }

    // MARK: - Data Sources (emulation via audioSource)

    private fun getAvailableDataSourcesList(): List<Map<String, Any>> {
        // Return static list from companion object
        return AVAILABLE_DATA_SOURCES
    }

    private fun selectDataSource(dataSourceID: Int) {
        selectedAudioSource = dataSourceID

        // Save selection
        sharedPreferences?.edit()?.putInt("selectedAudioSource", dataSourceID)?.apply()

        // Send event
        sendDeviceUpdateEvent()
    }

    // MARK: - Sending events to Dart

    private fun sendDeviceUpdateEvent() {
        val sink = eventSink ?: return

        val data = mapOf(
            "availableInputs" to getAvailableInputsList(),
            "selectedInput" to (selectedInput?.let { deviceInfoToMap(it) }),
            "availableDataSources" to getAvailableDataSourcesList(),
            "selectedDataSource" to getSelectedDataSource(),
            "availableOutputs" to getAvailableOutputsList(),
            "selectedOutput" to (selectedOutput?.let { outputDeviceInfoToMap(it) })
        )

        mainHandler.post {
            sink.success(data)
        }
    }

    private fun getSelectedDataSource(): Map<String, Any>? {
        val sources = getAvailableDataSourcesList()
        return sources.firstOrNull {
            (it["dataSourceID"] as? Int) == selectedAudioSource
        }
    }

    // MARK: - Resource cleanup

    private fun dispose() {
        // Protect against repeated dispose calls without initialization
        if (!isInitialized) {
            return
        }

        // Cancel any pending debounce callbacks
        updateDebounceRunnable?.let { mainHandler.removeCallbacks(it) }
        updateDebounceRunnable = null

        // Unregister audio device callback
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            audioManager?.unregisterAudioDeviceCallback(audioDeviceCallback)
        }

        // Clear Bluetooth cache
        bluetoothNameCache.clear()
        bluetoothCacheTimestamp = 0L

        // Clear all references to prevent memory leaks
        eventSink = null
        context = null
        audioManager = null
        sharedPreferences = null

        // Clear device lists
        availableInputs = emptyList()
        availableOutputs = emptyList()
        selectedInput = null
        selectedOutput = null

        isInitialized = false
    }
}