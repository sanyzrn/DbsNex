# Flutter's Gradle plugin already contributes the core Flutter rules; these
# cover the native-backed plugins Nex depends on.

# sqlite3 / sqlite3_flutter_libs load native symbols reflectively.
-keep class com.tekartik.** { *; }
-keep class org.sqlite.** { *; }

# just_audio / just_audio_windows and the ExoPlayer backend.
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**

# record uses MediaRecorder reflection on some OEM ROMs.
-keep class com.llfbandit.record.** { *; }

# Keep the widget provider referenced only from AndroidManifest.xml.
-keep class com.sanyzrn.nex.CaptureWidgetProvider { *; }
-keep class com.sanyzrn.nex.MainActivity { *; }

# Strip verbose logging from release builds.
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
}
