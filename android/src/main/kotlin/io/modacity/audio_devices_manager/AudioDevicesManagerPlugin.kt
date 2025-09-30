package io.modacity.audio_devices_manager

import android.content.Context
import android.content.SharedPreferences
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** AudioDevicesManagerPlugin */
class AudioDevicesManagerPlugin : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {
    /// MethodChannel для одноразовых запросов
    private lateinit var methodChannel: MethodChannel

    /// EventChannel для стримов событий
    private lateinit var eventChannel: EventChannel

    /// Android AudioManager
    private var audioManager: AudioManager? = null

    /// Context приложения
    private var context: Context? = null

    /// SharedPreferences для сохранения выбора пользователя
    private var sharedPreferences: SharedPreferences? = null

    /// EventSink для отправки событий в Dart
    private var eventSink: EventChannel.EventSink? = null

    /// Флаг инициализации
    private var isInitialized = false

    /// Список доступных входов
    private var availableInputs: List<AudioDeviceInfo> = emptyList()

    /// Текущий выбранный вход
    private var selectedInput: AudioDeviceInfo? = null

    /// Текущий выбранный audioSource (для dataSources)
    private var selectedAudioSource: Int = MediaRecorder.AudioSource.MIC

    /// Handler для UI thread операций
    private val mainHandler = Handler(Looper.getMainLooper())

    /// Callback для отслеживания изменений аудио устройств
    private val audioDeviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) {
            mainHandler.post {
                fetchAudioDevices()
            }
        }

        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) {
            mainHandler.post {
                fetchAudioDevices()
            }
        }
    }

    // MARK: - FlutterPlugin lifecycle

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        audioManager = context?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        sharedPreferences = context?.getSharedPreferences("audio_devices_manager", Context.MODE_PRIVATE)

        // Настраиваем MethodChannel
        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "audio_devices_manager")
        methodChannel.setMethodCallHandler(this)

        // Настраиваем EventChannel
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
        // При первой подписке отправляем текущее состояние
        sendDeviceUpdateEvent()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // MARK: - Инициализация

    private fun initialize() {
        if (isInitialized) {
            return
        }
        isInitialized = true

        // Регистрируем callback для отслеживания изменений
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            audioManager?.registerAudioDeviceCallback(audioDeviceCallback, mainHandler)
        }

        // Загружаем сохраненный audioSource
        selectedAudioSource = sharedPreferences?.getInt("selectedAudioSource", MediaRecorder.AudioSource.MIC)
            ?: MediaRecorder.AudioSource.MIC

        // Получаем текущее состояние устройств
        fetchAudioDevices()
    }

    // MARK: - Получение списка устройств

    private fun fetchAudioDevices() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            // Получаем все входные устройства
            availableInputs = audioManager?.getDevices(AudioManager.GET_DEVICES_INPUTS)
                ?.filter { isValidInputDevice(it) }
                ?: emptyList()

            // Загружаем последний выбранный вход
            loadSelectedInput()

            // Отправляем событие в Dart
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
            // Если есть productName, используем его
            val productName = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                device.productName.toString()
            } else {
                null
            }

            if (!productName.isNullOrEmpty() && productName != "null") {
                return productName
            }

            // Иначе используем тип устройства
            return when (device.type) {
                AudioDeviceInfo.TYPE_BUILTIN_MIC -> "Built-in Microphone"
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth Headset"
                AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Wired Headset"
                AudioDeviceInfo.TYPE_USB_DEVICE -> "USB Device"
                AudioDeviceInfo.TYPE_USB_HEADSET -> "USB Headset"
                else -> "Unknown"
            }
        }
        return "Unknown"
    }

    private fun deviceInfoToMap(device: AudioDeviceInfo): Map<String, String> {
        return mapOf(
            "uid" to device.id.toString(),
            "portName" to getDeviceName(device)
        )
    }

    // MARK: - Выбор входного устройства

    private fun selectInput(uid: String) {
        val device = availableInputs.firstOrNull { it.id.toString() == uid }
        if (device == null) {
            return
        }

        selectedInput = device

        // Сохраняем выбор
        sharedPreferences?.edit()?.putString("selectedAudioInput", uid)?.apply()

        // Устанавливаем preferred device для communication
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+ (API 31+)
            try {
                audioManager?.setCommunicationDevice(device)
            } catch (e: Exception) {
                // Устройство может не поддерживать communication режим
            }
        }

        // Отправляем событие
        sendDeviceUpdateEvent()
    }

    private fun loadSelectedInput() {
        val savedUID = sharedPreferences?.getString("selectedAudioInput", null)

        if (savedUID != null) {
            selectedInput = availableInputs.firstOrNull { it.id.toString() == savedUID }
        }

        // Если ничего не сохранено или устройство не найдено, берем первое
        if (selectedInput == null && availableInputs.isNotEmpty()) {
            selectedInput = availableInputs.first()
        }

        // Применяем выбор
        selectedInput?.let { device ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                try {
                    audioManager?.setCommunicationDevice(device)
                } catch (e: Exception) {
                    // Игнорируем ошибки
                }
            }
        }
    }

    // MARK: - Data Sources (эмуляция через audioSource)

    private fun getAvailableDataSourcesList(): List<Map<String, Any>> {
        // На Android нет прямого аналога iOS dataSources
        // Возвращаем типы audioSource как альтернативу
        return listOf(
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

    private fun selectDataSource(dataSourceID: Int) {
        selectedAudioSource = dataSourceID

        // Сохраняем выбор
        sharedPreferences?.edit()?.putInt("selectedAudioSource", dataSourceID)?.apply()

        // Отправляем событие
        sendDeviceUpdateEvent()
    }

    // MARK: - Отправка событий в Dart

    private fun sendDeviceUpdateEvent() {
        val sink = eventSink ?: return

        val data = mapOf(
            "availableInputs" to getAvailableInputsList(),
            "selectedInput" to (selectedInput?.let { deviceInfoToMap(it) }),
            "availableDataSources" to getAvailableDataSourcesList(),
            "selectedDataSource" to getSelectedDataSource()
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

    // MARK: - Очистка ресурсов

    private fun dispose() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            audioManager?.unregisterAudioDeviceCallback(audioDeviceCallback)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager?.clearCommunicationDevice()
        }

        eventSink = null
        isInitialized = false
    }
}