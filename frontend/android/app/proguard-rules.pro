# Flutter specific rules
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep the app's entry point
-keep class com.mindforge.mindforge.** { *; }

# Suppress warnings for missing classes
-dontwarn **
