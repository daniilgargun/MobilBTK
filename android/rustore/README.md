# Публикация в RuStore

## Подготовка ключа для RuStore

1. Скачайте инструмент PEPK (Play Encrypt Private Key) от Google:
   - [Ссылка на PEPK](https://www.gstatic.com/play-apps-publisher-rapid/tools/pepk/pepk.jar)
   - Скопируйте файл `pepk.jar` в эту директорию (`android/rustore/`)

2. Сгенерируйте ключ для RuStore:
   - **Windows**: запустите скрипт `generate_rustore_key.bat`
   - **Linux/Mac**: запустите скрипт `generate_rustore_key.sh` (сначала выполните `chmod +x generate_rustore_key.sh`)

3. Результатом будет файл `rustore_pepk_out.zip` - это зашифрованный ключ для RuStore

## Экспорт сертификата загрузки (PEM формат)

RuStore требует загрузить сертификат в формате PEM. Для его получения:

1. Запустите скрипт экспорта сертификата:
   - **Windows**: запустите скрипт `export_certificate.bat`
   - **Linux/Mac**: запустите скрипт `export_certificate.sh` (сначала выполните `chmod +x export_certificate.sh`)

2. Введите пароль от вашего хранилища ключей (keystore) - `1235674Dann`

3. Результатом будет файл `rustore_cert.pem` - это сертификат загрузки для RuStore

Примечание: Скрипт требует наличия OpenSSL. Если у вас его нет, вы можете:
- Установить OpenSSL ([Windows](https://slproweb.com/products/Win32OpenSSL.html), Linux: `sudo apt-get install openssl`, Mac: `brew install openssl`)
- Использовать онлайн-конвертер: https://www.sslshopper.com/ssl-converter.html (загрузите файл `rustore_cert.der` и конвертируйте его в PEM)

## Создание APK для RuStore

1. Выполните команду для создания релизного APK:
   ```
   flutter build apk --release
   ```

2. Релизный APK будет доступен по пути:
   ```
   build/app/outputs/flutter-apk/app-release.apk
   ```

## Публикация в RuStore

1. Зарегистрируйтесь в [личном кабинете разработчика RuStore](https://console.rustore.ru/)

2. Создайте новое приложение и заполните всю необходимую информацию:
   - Название
   - Описание
   - Категория
   - Возрастной рейтинг
   - Скриншоты и иконки
   - Политика конфиденциальности

3. Загрузите подпись приложения:
   - В разделе "Загрузка подписи приложения" загрузите созданный ZIP-архив `rustore_pepk_out.zip`
   - В разделе "Загрузите сертификат загрузки" загрузите файл `rustore_cert.pem`

4. Загрузите APK:
   - Загрузите ваш APK файл (`app-release.apk`)

5. Отправьте приложение на модерацию

## Требования RuStore

- APK должен быть подписан тем же ключом, что и ваши предыдущие релизы в Google Play
- Рекомендуется сохранять тот же `applicationId` (package name) как в Google Play
- Уровень API должен быть не ниже 24 (Android 7.0)

## Особенности публикации в RuStore

- RuStore использует тот же механизм загрузки подписи, что и Google Play для сохранения совместимости
- Ключ шифрования используется для безопасной передачи вашего закрытого ключа в RuStore
- Вам не нужно создавать новый ключ - используется тот же ключ, которым подписано ваше приложение

## Проверка перед публикацией

- Проверьте работу всех функций приложения на устройствах без сервисов Google
- Убедитесь, что приложение не содержит ссылок на сервисы Google, недоступные в RuStore
- Проверьте работу платежных систем, если они используются в приложении 