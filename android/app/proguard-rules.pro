# R8 / ProGuard keep-rules for release shrinking (isMinifyEnabled = true).
# Flutter's engine rules are applied automatically; these cover plugins that
# rely on reflection and would otherwise be stripped/obfuscated.

# --- Flutter engine ---
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# --- Play Core: referenced by Flutter's deferred-components hooks but the lib
# isn't bundled (we don't use split installs). Silence R8's missing-class check.
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# --- flutter_local_notifications: uses Gson reflection for scheduled payloads ---
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# --- flutter_rust_bridge / JNI: native methods must keep their names ---
-keepclasseswithmembernames class * {
    native <methods>;
}

# --- Keep annotations & generic signatures broadly (safe, tiny) ---
-keepattributes EnclosingMethod,InnerClasses
