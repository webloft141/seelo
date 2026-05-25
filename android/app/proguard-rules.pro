# Flutter specific
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }

# Play Core (used by Flutter deferred components)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Firebase Auth
-keep class com.google.firebase.auth.** { *; }

# Firebase Crashlytics
-keep class com.google.firebase.crashlytics.** { *; }

# JSON parsing
-keep class org.json.** { *; }

# Kotlin
-keep class kotlin.** { *; }

# Socket.IO
-keep class io.socket.** { *; }

# Keep model classes used for JSON serialization
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Keep generic signatures
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
