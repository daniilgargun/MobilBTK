-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Сохраняем Android классы, которые могут использоваться Flutter
-keep class androidx.** { *; }
-keep class android.** { *; }

# Правила для HTTP и JSON библиотек
-keep class com.google.gson.** { *; }

# Правила для изображений
-keep class com.squareup.okhttp.** { *; }
-keep interface com.squareup.okhttp.** { *; }

# SharedPreferences
-keep class androidx.preference.** { *; }

# Кэширование
-keep class okio.** { *; }
-keep class okhttp3.** { *; }

# Правила для пакетов из pubspec.yaml
-keep class io.flutter.plugins.connectivity.** { *; }
-keep class io.flutter.plugins.pathprovider.** { *; }
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class io.flutter.plugins.url_launcher.** { *; }

# Генерируемые классы Hive
-keep class ** { *; }
-keepclassmembers class ** { *; }

# Сохраняем R-классы, которые могут быть доступны через рефлексию
-keepclassmembers class **.R$* {
    public static <fields>;
}

# Сохраняем модели данных
-keep class com.gargun.btktimetable.models.** { *; }

# Правила для HTTP соединений
-keepattributes Signature
-keepattributes *Annotation*
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**

# Добавляем правило для подавления предупреждения о SplitCompatApplication
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication

# Правила для Яндекс.Реклама SDK
-keep class com.yandex.** { *; }
-dontwarn com.yandex.**
-keep class com.my.target.** { *; }
-dontwarn com.my.target.**
-keep class com.android.billingclient.** { *; }
-dontwarn com.android.billingclient.** 