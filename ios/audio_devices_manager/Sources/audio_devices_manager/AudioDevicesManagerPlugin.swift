import Flutter
import UIKit
import AVFoundation

public class AudioDevicesManagerPlugin: NSObject, FlutterPlugin {
    /// Флаг, чтобы не инициализировать сессию повторно
    private var isInitialized = false
    
    // MARK: - Свойства для аудио
    private var audioSession = AVAudioSession.sharedInstance()
    private var availableInputs: [AVAudioSessionPortDescription] = []
    private var selectedInput: AVAudioSessionPortDescription?
    private var availableDataSources: [AVAudioSessionDataSourceDescription] = []
    private var selectedDataSource: AVAudioSessionDataSourceDescription?
    
    // MARK: - EventChannel (для стримов изменений)
    private var eventSink: FlutterEventSink?
    
    // MARK: - Регистрация плагина (вызывается фреймворком Flutter)
    public static func register(with registrar: FlutterPluginRegistrar) {
        // MethodChannel: одноразовые запросы (getAvailableInputs, selectInput, и т. д.)
        let methodChannel = FlutterMethodChannel(
            name: "audio_devices_manager",
            binaryMessenger: registrar.messenger()
        )
        // EventChannel: события (изменение маршрута, выбор устройства и т. п.)
        let eventChannel = FlutterEventChannel(
            name: "audio_devices_manager_events",
            binaryMessenger: registrar.messenger()
        )
        
        let instance = AudioDevicesManagerPlugin()
        // Привязываем обработчик методов
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        // Привязываем обработчик стримов
        eventChannel.setStreamHandler(instance)
    }
    
    // MARK: - Обработка MethodChannel
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            initializeAudioSession()
            result(nil)
            
        case "getAvailableInputs":
            let inputsInfo = getAvailableInputsList()
            result(inputsInfo)
            
        case "selectInput":
            guard let args = call.arguments as? [String: Any],
                  let uid = args["uid"] as? String
            else {
                result(FlutterError(code: "BAD_ARGS", message: "No UID provided", details: nil))
                return
            }
            selectInput(uid: uid)
            result(nil)
            
        case "getSelectedInput":
            if let input = selectedInput {
                result([
                    "uid": input.uid,
                    "portName": input.portName
                ])
            } else {
                result(nil)
            }
            
        case "getAvailableDataSources":
            let dsList = getAvailableDataSourcesList()
            result(dsList)
            
        case "selectDataSource":
            guard let args = call.arguments as? [String: Any],
                  let dataSourceID = args["dataSourceID"] as? NSNumber
            else {
                result(FlutterError(code: "BAD_ARGS", message: "No dataSourceID provided", details: nil))
                return
            }
            selectDataSource(dataSourceID: dataSourceID)
            result(nil)

        case "getSelectedInputDeviceId":
            // На iOS выбор устройства применяется автоматически через setPreferredInput
            // Поэтому device ID не нужен - возвращаем nil
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

// MARK: - Реализация EventChannel (FlutterStreamHandler)
extension AudioDevicesManagerPlugin: FlutterStreamHandler {
    // Когда Dart подписывается на события
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        // При первой подписке сразу шлём текущее состояние
        sendDeviceUpdateEvent()
        return nil
    }
    
    // Когда Dart отписывается от событий
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}


// MARK: - Вспомогательные методы
extension AudioDevicesManagerPlugin {
    /// Основной метод инициализации аудиосессии
    private func initializeAudioSession() {
        // Защита от повторных инициализаций
        guard !isInitialized else {
            // Уже инициализировано, пропускаем
            return
        }
        isInitialized = true
        
        // Настраиваем аудиосессию
        do {
            try audioSession.setCategory(.playAndRecord,
                                         mode: .default,
                                         options: [.allowBluetooth,
                                                   .allowBluetoothA2DP,
                                                   .defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            print("Error setting audio session: \(error.localizedDescription)")
        }
        
        // Сразу получаем текущее состояние устройств
        fetchAudioDevices()
        
        // Подписываемся на изменения маршрута
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }
    
    /// Обработчик изменения маршрута аудио (подключение/отключение наушников и т. д.)
    @objc private func handleRouteChange(_ notification: Notification) {
        DispatchQueue.main.async {
            self.fetchAudioDevices()
        }
    }
    
    /// Обновляем список доступных входов и выбранное устройство
    private func fetchAudioDevices() {
        availableInputs = audioSession.availableInputs ?? []
        
        // Загружаем последний выбранный вход (из UserDefaults), если есть
        loadSelectedInput()
        
        // Обновляем dataSources
        updateDataSources()
        
        // Шлём ивент в Dart
        sendDeviceUpdateEvent()
    }
    
    // MARK: - Работа со списком входов
    
    /// Возвращает массив словарей для Dart
    private func getAvailableInputsList() -> [[String: String]] {
        return availableInputs.map {
            [
                "uid": $0.uid,
                "portName": $0.portName
            ]
        }
    }
    
    /// Выбор входа по uid
    private func selectInput(uid: String) {
        guard let input = availableInputs.first(where: { $0.uid == uid }) else { return }
        
        do {
            try audioSession.setPreferredInput(input)
            selectedInput = input
            UserDefaults.standard.set(uid, forKey: "selectedAudioInput")
        } catch {
            print("Error selecting audio input: \(error.localizedDescription)")
        }
        
        // Обновим dataSources, сообщим об изменениях
        updateDataSources()
        sendDeviceUpdateEvent()
    }
    
    /// Загрузка ранее сохранённого входа
    private func loadSelectedInput() {
        guard
            let savedUID = UserDefaults.standard.string(forKey: "selectedAudioInput"),
            let input = availableInputs.first(where: { $0.uid == savedUID })
        else {
            // Если ничего не сохранено, берём первый
            selectedInput = availableInputs.first
            return
        }
        
        do {
            try audioSession.setPreferredInput(input)
            selectedInput = input
        } catch {
            print("Error setting saved input: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Data Sources
    
    /// Обновляем список dataSources
    private func updateDataSources() {
        availableDataSources = selectedInput?.dataSources ?? []
        loadSelectedDataSource()
    }
    
    private func getAvailableDataSourcesList() -> [[String: Any]] {
        return availableDataSources.map { ds in
            [
                "dataSourceID": ds.dataSourceID,
                "dataSourceName": ds.dataSourceName
            ]
        }
    }
    
    private func selectDataSource(dataSourceID: NSNumber) {
        guard
            let input = selectedInput,
            let source = availableDataSources.first(where: { $0.dataSourceID == dataSourceID })
        else {
            return
        }
        do {
            try input.setPreferredDataSource(source)
            selectedDataSource = source
            UserDefaults.standard.set(source.dataSourceID, forKey: "selectedDataSource")
        } catch {
            print("Error selecting microphone data source: \(error.localizedDescription)")
        }
        sendDeviceUpdateEvent()
    }
    
    private func loadSelectedDataSource() {
        guard
            let savedDataSourceID = UserDefaults.standard.value(forKey: "selectedDataSource") as? NSNumber,
            let source = availableDataSources.first(where: { $0.dataSourceID == savedDataSourceID })
        else {
            selectedDataSource = availableDataSources.first
            return
        }
        do {
            try selectedInput?.setPreferredDataSource(source)
            selectedDataSource = source
        } catch {
            print("Error loading saved data source: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Отправка события (EventChannel)
    
    /// Отправляем текущее состояние (список устройств + выбранное) в Dart
    private func sendDeviceUpdateEvent() {
        guard let eventSink = eventSink else { return }
        
        let data: [String: Any] = [
            "availableInputs": getAvailableInputsList(),
            "selectedInput": selectedInput.map {
                [
                    "uid": $0.uid,
                    "portName": $0.portName
                ]
            } ?? NSNull(),
            "availableDataSources": getAvailableDataSourcesList(),
            "selectedDataSource": selectedDataSource.map {
                [
                    "dataSourceID": $0.dataSourceID,
                    "dataSourceName": $0.dataSourceName
                ]
            } ?? NSNull()
        ]
        
        eventSink(data)
    }
    
    // MARK: - (Опционально) Метод для снятия подписок и деактивации
    
    /// Вы можете при необходимости вызвать это из Dart, чтобы полностью «выключить» плагин
    private func dispose() {
        NotificationCenter.default.removeObserver(self)
        try? audioSession.setActive(false)
        eventSink = nil
        isInitialized = false
    }
}
