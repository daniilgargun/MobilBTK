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
# Яндекс.Реклама
# ---------------------------------------------------------------------------
-keep class com.yandex.mobile.ads.** { *; }
-keep class com.yandex.metrica.** { *; }
-dontwarn com.yandex.**
-keep class com.my.target.** { *; }
-dontwarn com.my.target.**
-dontwarn com.android.billingclient.**

# ---------------------------------------------------------------------------
# Google Play Services / Play Core (используются upgrader и app-update)
# ---------------------------------------------------------------------------
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication

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
