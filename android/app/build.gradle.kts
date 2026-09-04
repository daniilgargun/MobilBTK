plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.gargun.btktimetable"
    compileSdk = 36 // Устанавливаем compileSdk в соответствии с targetSdk
    // NDK r28+ требуется для корректного выравнивания нативных
    // библиотек под страницы памяти 16 КБ (требование Google Play).
    ndkVersion = "28.2.13676358"

    compileOptions {
        // Java 17: плагины (в частности flutter_local_notifications 22)
        // публикуются собранными под 17, с Java 8 сборка падает на
        // "class file has wrong version".
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }


    defaultConfig {
        applicationId = "com.gargun.btktimetable"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        // Google Play: с 31.08.2026 обновления должны быть собраны под Android 16 (API 36)
        targetSdk = 36
        versionCode = 17
        versionName = "1.0.13"
    }

    signingConfigs {
        // key.properties не хранится в репозитории. Без него (например, в CI)
        // конфигурация подписи не создаётся, иначе Gradle падал на строке "null".
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"].toString()
                keyPassword = keystoreProperties["keyPassword"].toString()
                storeFile = file(keystoreProperties["storeFile"].toString())
                storePassword = keystoreProperties["storePassword"].toString()
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // Отладочная подпись: собрать и проверить сборку можно,
                // но опубликовать такой артефакт нельзя.
                logger.warn("key.properties не найден — release подписывается debug-ключом")
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
        debug {
            // Отключаем минификацию для отладочной сборки
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    // Требование Google Play (с 01.11.2025): поддержка страниц памяти 16 КБ.
    // Несжатые нативные библиотеки позволяют системе загружать их с корректным выравниванием.
    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
    }

    // Splits отключены для уменьшения размера AAB (Google Play сам создаст раздельные APK)
    // Для Google Play лучше не использовать splits, так как Play Console сам оптимизирует доставку
    splits {
        abi {
            isEnable = false
        }
    }
}

// Kotlin 2.3: kotlinOptions { jvmTarget } удалён из публичного DSL.
kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")

    // Библиотеки com.google.android.play (app-update, asset-delivery, review)
    // отсюда убраны: их не вызывает ни Kotlin-код приложения, ни один из
    // плагинов. Они появились как замена устаревшей Play Core, но остались
    // неиспользованными и просто ехали в каждой сборке.

    // Яндекс.Ads отдельно не подключаем: плагин yandex_mobileads объявляет
    // com.yandex.android:mobileads своей версии сам. Прибитая здесь 7.12.0
    // разошлась с плагином 8.4.0 и только вводила в заблуждение.
}
