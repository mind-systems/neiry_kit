# Example app

Example app в `example/` — основной инструмент верификации плагина на реальном железе. Прежде чем `mind_mobile` начнёт использовать какой-либо API, он должен быть проверен через example app.

## Архитектура

Приложение разделено на три слоя с чёткими границами ответственности.

**`NeiryService`** (`example/lib/services/neiry_service.dart`) — единственный владелец логики устройства. Чистый Dart-класс без зависимостей на Flutter или Riverpod. Управляет `DeviceLocator`, `Device` и всеми шестью классификаторами. При вызове `connect()` немедленно создаёт все классификаторы — они живут до `disconnect()` и не пересоздаются при `start()`/`stop()`. Публикует данные как broadcast-стримы (`eegStream`, `cardioStream`, `memsStream` и т.д.).

**Riverpod-провайдеры** (`example/lib/providers/`) — тонкий мост между сервисом и UI. `neiryServiceProvider` держит синглтон `NeiryService`. Каждый поток данных обёрнут в `StreamProvider` с throttle там, где нужно для плавности. `PhysioActionsNotifier` и `ProductivityActionsNotifier` экспонируют команды (`startBaselineCalibration`, `resetAccumulatedFatigue`) и делегируют к классификаторам через сервис. `CalibrationNotifier` управляет NFB-калибровкой через `NfbCalibrator`.

**Экраны** (`example/lib/screens/`) — чистый UI. Каждый экран работает только через `ref.watch` / `ref.read` на провайдерах, ничего не знает о `NeiryService` напрямую.

```
NeiryService
  ├── scan() / connect(serial, nfbData?, useCalibration?) / start() / stop() / disconnect()
  ├── eegStream, psdStream, resistanceStream, batteryStream
  ├── physioStream, emotionsStream, cardioStream
  ├── memsStream, nfbStream
  ├── productivityIndexesStream, productivityMetricsStream
  └── calibrator → NfbCalibrator

Riverpod providers
  ├── neiryServiceProvider (singleton, app lifetime)
  ├── deviceConnectionStateProvider, deviceModeProvider, deviceUiStateProvider
  ├── eegProvider (100ms), psdProvider (500ms), memsProvider (100ms), ...
  ├── physioActionsProvider, productivityActionsProvider
  └── calibrationProvider (AsyncNotifier)

Screens → ref.watch / ref.read → providers → NeiryService
```

## Вкладки

Приложение использует `StatefulShellRoute.indexedStack` — все вкладки остаются смонтированными после первого открытия, стримы не прерываются при переключении.

**Device** — поиск и подключение. Сканирование вызывает `neiryService.scan()`. После выбора устройства `connect(serial, nfbData: savedCalibration)` создаёт все классификаторы сразу. Кнопки Start / Stop / Disconnect управляют `neiryService.start()` / `stop()` / `disconnect()`.

**Streams** — сырые данные: EEG по каналам, PSD-полосы, сопротивление электродов, уровень заряда, флаги артефактов.

**Classifiers** — физиологические состояния и эмоции. Значения из `physioStateProvider` и `emotionsStateProvider`. Кнопки калибровки физио делегируют к `physioActionsProvider.notifier`.

**Productivity + Cardio** — продуктивность и кардио. Команды через `productivityActionsProvider.notifier`.

**MEMS** — акселерометр и гироскоп, throttle 100 мс.

**Calibration** — NFB-калибровка. Полная (4 стадии × 20 с) или быстрая (30 с); после завершения доступны обе кнопки повторного запуска, а при невалидном результате под статусом выводится причина (`failReason`). Импорт/экспорт `IndividualNfbData` через файловый picker. Здесь же единый переключатель «Использовать NFB-калибровку»: сохраняет предпочтение и при следующем подключении применяет калибровку к MEMS, продуктивности и кардио (SDK не позволяет пересоздавать классификаторы на ходу). Живые значения NFB-ритмов во время и после калибровки.

## Запуск

```bash
cd example
flutter run
```

Для работы нужна реальная нейрогарнитура Neiry — симуляторы (`SinWave`, `Noise`) позволяют проверить поток данных, но классификаторы на синтетических данных не дают осмысленных результатов.

При первом запуске iOS запросит разрешение на Bluetooth. На Android runtime-разрешения запрашиваются перед сканированием.

## Роль в разработке плагина

Каждый новый API в плагине должен появиться в example app раньше, чем он будет использован в `mind_mobile`. Экраны используют только публичный Dart API плагина — никаких `import 'package:neiry_kit/src/...'`.

## Интеграция в mind_mobile

`NeiryService` спроектирован для переноса в `mind_mobile` как долгоживущий сервис уровня приложения:

```dart
// lib/Core/App.dart
class App {
  final NeiryService neiryService;

  static Future<void> initialize() async {
    shared = App._(neiryService: NeiryService());
    runApp(ProviderScope(...));
  }
}
```

Экран настройки BCI подключает устройство и проводит калибровку — после закрытия `NeiryService` продолжает жить в `App.shared`. Данные текут в фоновый сервис, который пакует и отправляет их на сервер. Ни один экран не владеет жизненным циклом устройства.
