#!/bin/bash

echo "Экспорт сертификата для RuStore в формате PEM..."

KEYSTORE_PATH="../app/release-keystore.jks"
KEY_ALIAS="release"
OUTPUT_DER="./rustore_cert.der"
OUTPUT_PEM="./rustore_cert.pem"

# Запрашиваем пароль
read -sp "Введите пароль хранилища ключей (1235674Dann): " KEYSTORE_PASSWORD
echo

echo "1. Экспорт сертификата в формате DER..."
keytool -exportcert -keystore "$KEYSTORE_PATH" -alias "$KEY_ALIAS" -file "$OUTPUT_DER" -storepass "$KEYSTORE_PASSWORD"

echo "2. Конвертация сертификата из DER в PEM..."
if command -v openssl &> /dev/null; then
    openssl x509 -inform DER -outform PEM -in "$OUTPUT_DER" -out "$OUTPUT_PEM"
    
    if [ $? -eq 0 ]; then
        echo "Сертификат успешно экспортирован в $OUTPUT_PEM"
        echo "Используйте этот файл при публикации в RuStore в разделе 'Загрузите сертификат загрузки'"
    else
        echo "Произошла ошибка при конвертации сертификата."
    fi
else
    echo "OpenSSL не найден. Вы можете выполнить конвертацию одним из способов:"
    echo "1. Установите OpenSSL и запустите скрипт снова"
    echo "2. Используйте онлайн-конвертер: https://www.sslshopper.com/ssl-converter.html"
    echo "   - Загрузите файл $OUTPUT_DER"
    echo "   - Выберите конвертацию из DER в PEM"
    echo "   - Скачайте результат как rustore_cert.pem"
fi 