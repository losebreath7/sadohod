# Нативные проекты приложения продавца «садоход»

Эта папка содержит **отдельные** `android/` и `ios/` проекты для
существующего Flutter-приложения продавца. Это не WebView и не новая
реализация экранов: `lib/main.dart`, товары, профиль, чаты и авторизация
остаются одними и теми же для Flutter Web, Android и iOS.

Идентификаторы пока выбраны для разработки:
- Android `applicationId`: `ru.sadohod.seller`.
- iOS `PRODUCT_BUNDLE_IDENTIFIER`: `ru.sadohod.seller`.
- Отображаемое имя: `садоход · продавец`.

**Перед первой публикацией** подтвердите окончательные идентификаторы,
имя издателя и иконку продавца. Сейчас используются исходные иконки
общего приложения «садоход» (наследие покупательского Flutter-каркаса).
После первой публикации менять идентификатор без новой карточки приложения
нельзя. Дизайн Flutter-экранов не изменялся.

## Android: Windows / Android Studio

Нужны установленный Flutter SDK (Dart >= 3.10), Android SDK, JDK 17,
доступный Android-эмулятор или телефон с USB-отладкой. Запускайте в
корневой папке `seller_app`:

```powershell
flutter doctor -v
flutter pub get
flutter devices
flutter run -d <android-device-id> --dart-define=API_BASE_URL=https://YOUR-API-DOMAIN
```

Проверочная сборка APK:

```powershell
flutter build apk --debug --dart-define=API_BASE_URL=https://YOUR-API-DOMAIN
```

Android-эмулятор может обращаться к **локальному** серверу компьютера по
`http://10.0.2.2:8000` (только debug). Для физического Android,
TestFlight и Store нужен достижимый **HTTPS** URL сервера. `localhost`
на устройстве означает само устройство, не Docker на компьютере.
Для отладки в одной сети можно явно указать доступный адрес сервера;
обычный Android release запрещает незашифрованный HTTP.

### Подпись релизного Android AAB

Создайте собственный upload keystore **вне Git**. Скопируйте
`android/key.properties.example` в `android/key.properties` и укажите
реальные значения. Файл и `.jks` исключены из Git. Не передавайте ключи
в чат и никогда не храните их в репозитории.

```powershell
flutter build appbundle --release --dart-define=API_BASE_URL=https://YOUR-API-DOMAIN
```

Если `android/key.properties` отсутствует, релизная конфигурация **не
подписывает** AAB debug-ключом. Для Google Play требуется подписанный AAB,
а также заполненные карточка приложения и политика конфиденциальности.

## iOS: macOS + Xcode

Исходники Xcode-проекта находятся в `ios/Runner.xcodeproj`.
Для сборки необходимы macOS, Xcode и Flutter SDK. Зависимости плагинов подключаются через Swift Package Manager (Flutter 3.50+), без CocoaPods.

```sh
cd seller_app
flutter pub get
flutter build ios --simulator --no-codesign --dart-define=API_BASE_URL=https://YOUR-API-DOMAIN
```

Для публикации нужен Apple Developer Team, Bundle ID,
сертификат/профиль подписи и архив Xcode или `flutter build ipa`.
Настройки подписи пользователей и закрытые ключи не включены в Git.

В `ios/Runner/Info.plist` указаны системные описания доступа к камере и
библиотеке фотографий (для добавления товаров). iOS 15+.

## Смоук-тест на **настоящем** телефоне

Проверить без Web-оболочки: вход по email-коду и восстановление сессии
после перезапуска, добавление/замену фотографий, выбор павильона,
публикацию и скрытие товара, чат и прикреплённые файлы, системную
клавиатуру, SafeArea, нижнюю навигацию, отображение уведомлений и
сетевые ошибки. Flutter Web/Chrome-скриншоты **не заменяют** нативную
проверку. До неё нельзя считать готовой публикацию в магазинах.

## О сохранности данных

Нативные проекты меняют только `seller_app/`.
Сервер FastAPI, PostgreSQL, Docker Volumes, товары и приложение
покупателя остаются без изменений. Используются те же API, но
**отдельная** сессия продавца в защищённом хранилище.
