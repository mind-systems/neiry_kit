# Завершение сессии и освобождение устройства

Правильный порядок вызовов при остановке стриминга и отключении устройства критичен. SDK Capsule держит нативные JNI-ссылки на BLE-объекты, и если освободить их раньше или позже нужного момента — процесс падает с `SIGABRT` или `Fatal signal 64`.

## Инварианты SDK

Три жёстких ограничения со стороны нативного слоя:

| # | Требование | Нарушение → |
|---|---|---|
| A | `nativeUnregisterDeviceCallbacks` до удаления JNI-ссылок на EventSink | `0xebadde09` — фоновый поток SDK обращается к удалённой ссылке |
| B | Все классификаторы освобождены **до** `nativeReleaseDevice` | `SIGABRT` — `IsClassifierSupported` обращается к уже освобождённому хендлу |
| C | `nativeReleaseDevice` до того как `BluetoothGatt.unregisterApp()` успеет отработать | `Fatal signal 64` — SDK держит устаревшие GATT JNI-ссылки |

Инварианты A, B и C несовместимы при наивном порядке (`stop → отмена подписок → dispose классификаторов`), поэтому `Device` предоставляет два разных метода остановки.

## Единственный путь завершения

На уровне `NeiryService` существует только одна операция завершения — **disconnect**. Кнопка «Stop» — это тоже disconnect: устройство либо подключено, либо нет.

```
unregisterCallbacks()        // A: остановить фоновые потоки SDK
отменить fan-in подписки     // безопасно: фоновые потоки остановлены
dispose всех классификаторов // B: хендл ещё жив, IsClassifierSupported работает
device.disconnect()          // C: nativeDisconnect + nativeRelease → хендл = 0
device.dispose()             // no-op, соединение уже закрыто
```

На практике в `NeiryService`:

```dart
// 1. Остановить фоновые потоки SDK
await device.unregisterCallbacks();

// 2. Отменить fan-in подписки
for (final sub in activeSubscriptions) await sub.cancel();

// 3. Dispose классификаторов (хендл ещё жив)
await Future.wait([nfb?.dispose(), physio?.dispose(), cardio?.dispose(), ...]);

// 4. Если шёл стриминг — остановить сессию (без release)
if (wasStarted) await device.stopStream();

// 5. Отключить и освободить хендл (nativeDisconnect + nativeRelease)
await device.disconnect();

// 6. Очистить Dart-объект
await device.dispose();
```

`NeiryService.stop()` — алиас для `disconnect()`. Отдельной «паузы» без отключения нет.

## О `stop()` и `stopStream()` на уровне Device

Эти методы существуют на уровне `Device`, но напрямую не используются снаружи `NeiryService`:

| Метод | nativeStop | nativeRelease | Роль |
|---|---|---|---|
| `stopStream()` | ✅ | ❌ | Внутренний шаг в disconnect-последовательности |
| `stop()` | ✅ | ✅ немедленно | Не используется — освобождает хендл до dispose классификаторов |

## Неправильные порядки

| Ошибочная последовательность | Результат |
|---|---|
| Отменить подписки до `nativeStop` | `0xebadde09`: фоновый поток уже вошёл в коллбек, EventSink удалён |
| Dispose классификаторов после `nativeRelease` | `SIGABRT`: `IsClassifierSupported` обращается к освобождённому хендлу |
| `nativeRelease` после `unregisterApp()` | `Fatal signal 64`: SDK держит устаревшие GATT JNI-ссылки |
| `disconnect()` без предшествующего `stop()` на активной сессии | Cardio-модуль пере-включает PPG во время BLE-teardown, нестабильное состояние |

## Устаревший endOfStream при повторном сканировании

### Проблема

При повторном вызове `DeviceLocator.requestDevices()` Flutter выбрасывает `Bad state: No element` — новый скан завершается немедленно без единого результата.

Причина — устойчивая гонка на уровне Flutter binary messenger. Когда скан N завершается, Kotlin вызывает `realSink.endOfStream()`, и в Dart-очередь отправляется `null`-сообщение. Если пользователь нажимает «Скан» до того, как Dart обработал этот `null`, новый скан успевает зарегистрировать свой обработчик канала раньше. `null`-сообщение от предыдущего скана достигает нового обработчика → `controller.close()` → `.first` получает `onDone` без данных → `Bad state: No element`.

Это не зависит от задержки между сканами — гонка возникает даже при нажатии через несколько секунд, потому что Dart-очередь и платформенный поток работают независимо.

В логах видно, что `scan stream done` появляется **до** Kotlin-логов `onListen`, хотя физически Kotlin выполнился раньше — это артефакт смешивания UI-потока (Dart) и platform-потока (Kotlin) в logcat.

### Дополнительный симптом со стороны Kotlin

Нативный C SDK также посылает немедленный `endOfStream` на текущий sink примерно через 50 мс после `nativeRequestDevices` — он сбрасывает состояние предыдущего скана. Этот `endOfStream` приходит уже на **новый** sink, поэтому проверка идентичности `currentSink === this` не помогает.

### Решение — два независимых слоя защиты

**Dart (`DeviceLocator.requestDevices`)** — отказ от `receiveBroadcastStream`. Вместо него бинарный обработчик регистрируется напрямую через `ServicesBinding.instance.defaultBinaryMessenger.setMessageHandler`. В нём отслеживается флаг `dataReceived`:

- `null`-сообщение при `dataReceived = false` → устаревший `endOfStream`, молча игнорируется, обработчик остаётся активным
- `null`-сообщение при `dataReceived = true` → настоящий `endOfStream`, поток закрывается штатно

**Kotlin (`DeviceLocatorBridge`)** — `AtomicBoolean eventReceived` на каждый `onListen`. `endOfStream` пробрасывается в Dart только если перед ним пришёл хотя бы один `success` или `error`. Это блокирует немедленный SDK-reset без данных, который возникает при повторном `nativeRequestDevices`.

Оба слоя нужны: Dart-слой перехватывает устаревший `null` из Dart-очереди, Kotlin-слой перехватывает немедленный SDK-reset до того, как `null` вообще уходит в Dart.

## Повторное подключение после Disconnect

После полного disconnect `Device` объект нельзя переиспользовать — он `disposed`. Для новой сессии:

```dart
// Новый Device через тот же DeviceLocator
final device = await locator.createDevice(serial);
await device.connect();
```

`DeviceLocator` не нужно пересоздавать — он синглтон и сохраняет нативный хэндл.

### Обязательный повторный скан перед connect

`nativeReleaseDevice` очищает внутренний список найденных устройств внутри C SDK. Если вызвать `createDevice(serial)` после disconnect без предшествующего скана, SDK выбросит `Empty list of available devices`.

Поэтому после каждого disconnect UI обязан сбросить кэш результатов скана и сбросить выбранный серийный номер — пользователь должен нажать «Scan» заново, прежде чем сможет нажать «Connect».

В example app это реализовано через `_clearScan()` в `device_screen.dart`: `setState` убирает наблюдателя `deviceScanProvider`, а в post-frame callback вызывается `ref.invalidate` — именно в таком порядке, чтобы инвалидация провайдера без активных слушателей не спровоцировала нежелательный автоматический скан.
