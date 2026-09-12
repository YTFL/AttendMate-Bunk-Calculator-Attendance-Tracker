# Proguard rules for BunkAttendance app
# This file is used by R8 to optimize and shrink the app size

# Flutter specific rules
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# Keep Play Store Split Install classes (required by Flutter)
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep custom application classes
-keep class com.ytfl.attendmate.** { *; }

# Keep enums
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Keep Parcelable implementations
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Keep serializable classes
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Keep SQLite
-keep class * extends android.database.sqlite.SQLiteOpenHelper { *; }

# Keep AndroidX
-keep class androidx.** { *; }
-keep class com.google.android.material.** { *; }

# Rules for common Flutter plugins
-keep class io.flutter.plugins.localnotifications.** { *; }
-keep class io.flutter.plugins.timezone.** { *; }
-keep class io.flutter.plugins.workmanager.** { *; }
-keep class io.flutter.plugins.googlesignin.** { *; }

# Google Play Services & Google Sign-In
-keep class com.google.android.gms.auth.api.signin.** { *; }
-keep class com.google.android.gms.common.api.** { *; }
-keep class com.google.android.gms.common.** { *; }

# FreeDroidWarn library
-keep class org.woheller69.freeDroidWarn.** { *; }
-dontwarn org.woheller69.freeDroidWarn.**
-keep class org.woheller69.freedroidwarn.** { *; }
-dontwarn org.woheller69.freedroidwarn.**

# Optimization settings
-optimizationpasses 5
-dontusemixedcaseclassnames
-verbose


