# Proguard rules to ignore missing annotation processor classes
-dontwarn com.google.auto.value.extension.memoized.processor.**
-dontwarn com.google.auto.value.processor.**
-dontwarn autovalue.shaded.com.squareup.javapoet.**
-dontwarn com.google.auto.value.extension.toprettystring.processor.**

# Ignore javax.annotation.processing and javax.lang.model
-dontwarn javax.annotation.processing.**
-dontwarn javax.lang.model.**
-dontwarn javax.tools.**

# MediaPipe
-keep class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# Google Play Services & Navigation SDK
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**
-keep class com.google.android.libraries.maps.** { *; }
-dontwarn com.google.android.libraries.maps.**
-keep class com.google.android.libraries.navigation.** { *; }
-dontwarn com.google.android.libraries.navigation.**

# Support Library / AndroidX
-keep class androidx.** { *; }
-dontwarn androidx.**