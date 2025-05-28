@echo off
echo Экспорт сертификата для RuStore...

echo Используем JDK 'keytool' для экспорта сертификата

REM Получаем путь к Java
FOR /F "tokens=* USEBACKQ" %%F IN (`where java`) DO (
  SET JAVA_PATH=%%F
)
set JAVA_BIN_DIR=%JAVA_PATH:java.exe=%

echo Используем keytool из: %JAVA_BIN_DIR%
set KEYTOOL=%JAVA_BIN_DIR%keytool.exe

REM Настройка путей
set KEYSTORE_PATH=../app/release-keystore.jks
set KEY_ALIAS=release
set OUTPUT_DER=./rustore_cert.der

REM Устанавливаем пароль
set KEYSTORE_PASSWORD=1235674Dann

echo Экспорт сертификата в формате DER...
"%KEYTOOL%" -exportcert -keystore %KEYSTORE_PATH% -alias %KEY_ALIAS% -file %OUTPUT_DER% -storepass %KEYSTORE_PASSWORD%

if %ERRORLEVEL% EQU 0 (
    echo Сертификат успешно экспортирован в %OUTPUT_DER%
    echo.
    echo ВАЖНО: Теперь вам нужно конвертировать DER в PEM формат!
    echo Для этого вы можете использовать онлайн-конвертер:
    echo https://www.sslshopper.com/ssl-converter.html
    echo.
    echo 1. Загрузите файл %OUTPUT_DER% 
    echo 2. Выберите конвертацию из DER в PEM
    echo 3. Скачайте результат как rustore_cert.pem
    echo 4. Используйте этот файл для загрузки в RuStore
) else (
    echo Ошибка при экспорте сертификата.
)

echo.
pause 