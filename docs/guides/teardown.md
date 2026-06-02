[← Сценарий сессии](session-guide.md) · [Back to README](../../README.md) · [Обработка ошибок →](error-handling.md)

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

## Два пути завершения

### Путь 1 — Disconnect (полное завершение сессии)

Используется когда нужно остановить стриминг и освободить устройство.

```
device.stopStream()          // A: unregister + nativeStop, хендл НЕ освобождается
отменить fan-in подписки     // безопасно: фоновые потоки SDK остановлены
dispose всех классификаторов // B: хендл ещё жив, классификаторы обращаются к SDK
device.disconnect()          // C: nativeDisconnect + nativeRelease → хендл = 0
device.dispose()             // no-op, соединение уже закрыто
```

`stopStream()` останавливает фоновые потоки SDK (инвариант A), но **не освобождает хендл** — классификаторы могут обратиться к SDK в безопасном состоянии (инвариант B). `disconnect()` вызывает `nativeReleaseDevice` синхронно — до того как BLE-стек асинхронно обработает `unregisterApp()` (инвариант C).

На практике в `NeiryService`:

```dart
// 1. Остановить стриминг (unregister + nativeStop, без release)
if (device.isStarted) await device.stopStream();

// 2. Отменить fan-in подписки
for (final sub in activeSubscriptions) await sub.cancel();

// 3. Dispose классификаторов (хендл ещё жив)
await Future.wait([nfb?.dispose(), physio?.dispose(), cardio?.dispose(), ...]);

// 4. Отключить и освободить хендл (nativeDisconnect + nativeRelease)
await device.disconnect();

// 5. Очистить Dart-объект
await device.dispose();
```

### Путь 2 — Stop only (остановка без отключения)

Используется когда нужно остановить стриминг, но **не** отключать BLE.  
Реализован кнопкой «Stop» в примере приложения.

```dart
await device.stop();  // unregister + nativeStop + nativeRelease → хендл = 0
```

`stop()` освобождает хендл немедленно — после этого вызов `start()` без предварительного переподключения завершится ошибкой `NO_DEVICE`. Чтобы возобновить стриминг, нужно заново пройти Connect → Start.

## Разница между `stop()` и `stopStream()`

| Метод | nativeStop | nativeRelease | Когда использовать |
|---|---|---|---|
| `stop()` | ✅ | ✅ немедленно | Кнопка «Stop» — полная остановка без Disconnect |
| `stopStream()` | ✅ | ❌ | Первый шаг в disconnect-последовательности |

## Неправильные порядки

| Ошибочная последовательность | Результат |
|---|---|
| Отменить подписки до `nativeStop` | `0xebadde09`: фоновый поток уже вошёл в коллбек, EventSink удалён |
| Dispose классификаторов после `nativeRelease` | `SIGABRT`: `IsClassifierSupported` обращается к освобождённому хендлу |
| `nativeRelease` после `unregisterApp()` | `Fatal signal 64`: SDK держит устаревшие GATT JNI-ссылки |
| `disconnect()` без предшествующего `stop()` на активной сессии | Cardio-модуль пере-включает PPG во время BLE-teardown, нестабильное состояние |

## Повторное подключение после Disconnect

После полного disconnect `Device` объект нельзя переиспользовать — он `disposed`. Для новой сессии:

```dart
// Новый Device через тот же DeviceLocator
final device = await locator.createDevice(serial);
await device.connect();
```

`DeviceLocator` не нужно пересоздавать — он синглтон и сохраняет нативный хэндл.

## See Also

- [Жизненный цикл устройства](../reference/device-lifecycle.md) — состояния и переходы Device
- [Сценарий сессии](session-guide.md) — полный маршрут от сканирования до классификаторов
- [Обработка ошибок](error-handling.md) — типы исключений и стратегии восстановления
