@echo off
keytool -exportcert -keystore ../app/release-keystore.jks -alias release -file rustore_cert.der -storepass 1235674Dann
echo Сертификат экспортирован в rustore_cert.der
echo Теперь вам нужно конвертировать его в PEM формат
pause 