# Proguard rules to ignore missing annotation processor classes
# These warnings are common when using libraries that include AutoValue but don't exclude its processor in release builds.

-dontwarn com.google.auto.value.extension.memoized.processor.**
-dontwarn com.google.auto.value.processor.**
-dontwarn autovalue.shaded.com.squareup.javapoet.**
-dontwarn com.google.auto.value.extension.toprettystring.processor.**

# Ignore javax.annotation.processing and javax.lang.model if they are only used by the above processors
-dontwarn javax.annotation.processing.**
-dontwarn javax.lang.model.**
-dontwarn javax.tools.**

# MediaPipe Keep Rules
# MediaPipe uses reflection and JNI to call native functions, so we must keep the classes and members.
-keep class com.google.mediapipe.** { *; }
-keep interface com.google.mediapipe.** { *; }

# Also keep the specific tasks we are using
-keep class com.google.mediapipe.tasks.vision.facelandmarker.** { *; }
-keep class com.google.mediapipe.tasks.core.** { *; }
-keep class com.google.mediapipe.framework.** { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Flutter wrapper classes and MethodChannel handlers
-keep class com.example.flutter_application_screen.** { *; }

# Google Maps and Navigation SDK
# These are essential for the navigation features to work in release mode
-keep class com.google.android.libraries.navigation.** { *; }
-keep interface com.google.android.libraries.navigation.** { *; }
-keep class com.google.android.gms.maps.** { *; }
-keep interface com.google.android.gms.maps.** { *; }
-keep class com.google.android.gms.common.** { *; }
-keep interface com.google.android.gms.common.** { *; }

# Camera Plugin
-keep class io.flutter.plugins.camera.** { *; }

# Audioplayers and Record Plugins
-keep class xyz.luan.audioplayers.** { *; }
-keep com.example.record.** { *; }

# General Flutter Plugin rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }
