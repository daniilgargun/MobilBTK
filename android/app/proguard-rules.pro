# ============================================================================
#  Правила R8/ProGuard для release-сборки
#
#  ВАЖНО: здесь НЕ должно быть правил вида "-keep class ** { *; }".
#  Такое правило сохраняет вообще все классы и полностью отключает
#  сокращение и обфускацию, из-за чего isMinifyEnabled/isShrinkResources
#  перестают работать, а размер APK/AAB вырастает в разы.
# ============================================================================

# ---------------------------------------------------------------------------
# Flutter
# ---------------------------------------------------------------------------
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# ---------------------------------------------------------------------------
# Классы приложения, к которым система обращается по имени
# (провайдеры виджетов и RemoteViewsService резолвятся через Class.forName
#  из home_widget и из системы виджетов Android)
# ---------------------------------------------------------------------------
-keep class com.gargun.btktimetable.MainActivity { *; }
-keep class com.gargun.btktimetable.ScheduleWidget { *; }
-keep class com.gargun.btktimetable.ScheduleWidgetService { *; }
-keep class com.gargun.btktimetable.BellScheduleWidgetProvider { *; }
-keep class com.gargun.btktimetable.BellScheduleWidgetService { *; }
-keep class * extends android.appwidget.AppWidgetProvider { *; }
-keep class * extends android.widget.RemoteViewsService { *; }
-keep class es.antonborri.home_widget.** { *; }

# ---------------------------------------------------------------------------
# flutter_local_notifications
#
# Плагин хранит запланированные уведомления в SharedPreferences в виде JSON и
# разбирает его Gson'ом — то есть по именам полей, через рефлексию. R8 эти
# имена переименовывает, причём в каждой сборке по-своему: записи, сделанные
# предыдущей версией приложения, после обновления перестают читаться, и
# запланированные напоминания о парах молча пропадают.
#
# Раньше это прикрывало общее правило "-keep class ** { *; }", которое
# отключало сокращение целиком. Правило убрано как вредное, поэтому нужные
# классы перечисляются явно — так требует документация плагина.
#
# Чёрный экран при запуске был не отсюда: иконку уведомления вырезал
# сокращатель ресурсов, см. res/raw/keep.xml.
# ---------------------------------------------------------------------------
-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**

# ---------------------------------------------------------------------------
# Gson (используется flutter_local_notifications)
# ---------------------------------------------------------------------------
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
# Generic-типы полей нужны Gson для разбора коллекций.
-keepattributes Signature,InnerClasses,EnclosingMethod

# ---------------------------------------------------------------------------
# Яндекс.Реклама
# ---------------------------------------------------------------------------
-keep class com.yandex.mobile.ads.** { *; }
-keep class com.yandex.metrica.** { *; }
-dontwarn com.yandex.**
-keep class com.my.target.** { *; }
-dontwarn com.my.target.**
-dontwarn com.android.billingclient.**

# ---------------------------------------------------------------------------
# Play Core: сами библиотеки не подключены, но Flutter ссылается на классы
# отложенных компонентов. Без -dontwarn R8 падает на недостающих классах.
# ---------------------------------------------------------------------------
-dontwarn com.google.android.play.core.**

# ---------------------------------------------------------------------------
# Firebase
# ---------------------------------------------------------------------------
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# ---------------------------------------------------------------------------
# Сериализация
# ---------------------------------------------------------------------------
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    !static !transient <fields>;
    !private <fields>;
    !private <methods>;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Enum-ы (обращение через valueOf при десериализации)
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Parcelable
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}

# R-классы, доступные через рефлексию
-keepclassmembers class **.R$* {
    public static <fields>;
}

# ---------------------------------------------------------------------------
# Атрибуты
# ---------------------------------------------------------------------------
-keepattributes Signature
-keepattributes Exceptions
-keepattributes InnerClasses
-keepattributes EnclosingMethod
-keepattributes *Annotation*
-keepattributes AnnotationDefault
-keepattributes RuntimeVisibleAnnotations,RuntimeVisibleParameterAnnotations
# Читаемые стек-трейсы в Play Console (в связке с загрузкой mapping.txt)
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
