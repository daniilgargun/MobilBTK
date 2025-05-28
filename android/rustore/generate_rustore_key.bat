@echo off
echo Генерация ключа для RuStore...

set KEYSTORE_PATH=../app/release-keystore.jks
set KEY_ALIAS=release
set OUTPUT_PATH=./rustore_pepk_out.zip
set ENCRYPTION_KEY=00004fea5e5f61b50977b9b7954662b17d60b904168b74ef349ef3fe3f512e06d802faae5177dae8fdffcb5dbbadc870cd21fbdf9ace3ca7798d71a96bab1497be167814

REM Проверяем, введен ли пароль
set /p KEYSTORE_PASSWORD=Введите пароль хранилища ключей: 
set /p KEY_PASSWORD=Введите пароль ключа: 

echo Генерация ключа для RuStore используя PEPK...
java -jar pepk.jar --keystore=%KEYSTORE_PATH% --alias=%KEY_ALIAS% --output=%OUTPUT_PATH% --keystore-pass=%KEYSTORE_PASSWORD% --key-pass=%KEY_PASSWORD% --encryptionkey=%ENCRYPTION_KEY% --include-cert

echo.
if %ERRORLEVEL% EQU 0 (
    echo Ключ успешно сгенерирован в %OUTPUT_PATH%
    echo Используйте этот ZIP-архив при публикации в RuStore.
) else (
    echo Ошибка генерации ключа! Проверьте правильность введенных данных.
)
echo.
pause 