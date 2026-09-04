pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // AGP держим на 8.x, хотя Flutter уже предупреждает про 9.0.1.
    //
    // В AGP 9 по умолчанию включён новый DSL, а плагин org.jetbrains.kotlin.android
    // с ним несовместим и падает прямо при применении. Обойти это можно только
    // переходом на встроенный Kotlin от AGP (android.builtInKotlin=true), но
    // миграционный скрипт самого Flutter выставляет builtInKotlin=false и
    // newDsl=false, да и Android-часть плагинов Flutter применяет kotlin-android
    // у себя — то есть починить это в своём проекте нельзя.
    //
    // Gradle 9.1 (его Flutter тоже просит) пробовали здесь же: сборка один раз
    // упала падением Dart-компилятора, второй раз зависла насмерть. Обе версии
    // имеет смысл поднимать после того, как их поддержит Flutter.
    id("com.android.application") version "8.13.2" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")
