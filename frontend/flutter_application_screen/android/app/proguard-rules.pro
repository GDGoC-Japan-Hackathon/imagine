@@ -1,12 +1,54 @@
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