# neiry_kit

> Flutter plugin для работы с нейрогарнитурами Neiry — оборачивает Capsule C SDK и предоставляет идиоматичный Dart API для `mind_mobile`.

Плагин берёт на себя всё взаимодействие с нативным SDK: поиск устройств по Bluetooth, подключение, стриминг EEG-данных, работу с классификаторами нейросигналов и калибровку. `mind_mobile` подключает его как path-зависимость и работает только с Dart API — нативный слой скрыт.

## Установка

```yaml
dependencies:
  neiry_kit:
    path: ../neiry_kit
```

## Пример использования

```dart
// Поиск устройств
final locator = DeviceLocator();
final devices = await locator.requestDevices(type: DeviceType.any).first;

// Подключение и запуск стриминга
final device = await locator.createDevice(devices.first.serial);
await device.connect();
await device.start();

// Подписка на EEG
device.eegStream.listen((data) {
  print('${data.channelCount} каналов, ${data.sampleCount} сэмплов');
});

// NFB классификатор
final nfb = NfbClassifier(device);
nfb.stateStream.listen((state) {
  print('alpha: ${state.alpha}, beta: ${state.beta}');
});
```

## Документация

| Раздел | Описание |
|--------|----------|
| [Жизненный цикл устройства](docs/device-lifecycle.md) | Поиск, подключение, запуск и остановка |
| [Потоки данных](docs/data-streams.md) | EEG, PSD, артефакты, сопротивление, батарея |
| [Классификаторы](docs/classifiers.md) | NFB, физиологические состояния, эмоции, продуктивность, кардио |
| [Калибровка NFB](docs/calibration.md) | Индивидуальная калибровка, 4 стадии, quick mode |
| [Example app](docs/example-app.md) | Что покрывает тестовое приложение и как с ним работать |
