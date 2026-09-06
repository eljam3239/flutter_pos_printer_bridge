# Zebra SDK ProGuard Rules
# Keep all Zebra SDK classes
-keep class com.zebra.sdk.** { *; }
-keepclassmembers class com.zebra.sdk.** { *; }
-dontwarn com.zebra.sdk.**

# Keep Jackson JSON library classes (required by Zebra SDK)
-keep class com.fasterxml.jackson.** { *; }
-keepclassmembers class com.fasterxml.jackson.** { *; }
-dontwarn com.fasterxml.jackson.**

# Keep Jackson databind
-keepattributes *Annotation*,EnclosingMethod,Signature
-keepnames class com.fasterxml.jackson.databind.** { *; }
-dontwarn com.fasterxml.jackson.databind.**

# Keep Apache Commons Lang3
-keep class org.apache.commons.lang3.** { *; }
-dontwarn org.apache.commons.lang3.**

# Keep the plugin class
-keep class com.zebra.zebra_printer_android.** { *; }
-keepclassmembers class com.zebra.zebra_printer_android.** { *; }
