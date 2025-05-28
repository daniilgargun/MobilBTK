@echo off
echo Экспорт сертификата для RuStore в формате PEM...

set KEYSTORE_PATH=../app/release-keystore.jks
set KEY_ALIAS=release
set OUTPUT_DER=./rustore_cert.der
set OUTPUT_PEM=./rustore_cert.pem

REM Проверяем, введен ли пароль
set /p KEYSTORE_PASSWORD=Введите пароль хранилища ключей (1235674Dann): 

echo 1. Экспорт сертификата в формате DER...
keytool -exportcert -keystore %KEYSTORE_PATH% -alias %KEY_ALIAS% -file %OUTPUT_DER% -storepass %KEYSTORE_PASSWORD%

echo 2. Конвертация сертификата из DER в PEM...
echo (Требуется OpenSSL, если у вас его нет, установите или используйте онлайн-конвертер)
openssl x509 -inform DER -outform PEM -in %OUTPUT_DER% -out %OUTPUT_PEM%

echo.
if %ERRORLEVEL% EQU 0 (
    echo Сертификат успешно экспортирован в %OUTPUT_PEM%
    echo Используйте этот файл при публикации в RuStore в разделе "Загрузите сертификат загрузки"
) else (
    echo Если вы видите ошибку, возможно, у вас не установлен OpenSSL.
    echo Вы можете выполнить конвертацию одним из способов:
    echo 1. Установите OpenSSL и запустите скрипт снова
    echo 2. Используйте онлайн-конвертер: https://www.sslshopper.com/ssl-converter.html
    echo   - Загрузите файл %OUTPUT_DER%
    echo   - Выберите конвертацию из DER в PEM
    echo   - Скачайте результат как rustore_cert.pem
)
echo.
pause 