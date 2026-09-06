# Epson SDK ProGuard Rules
# Keep all Epson SDK classes - required because native library uses JNI to find Java classes
-keep class com.epson.** { *; }
-keepclassmembers class com.epson.** { *; }
-dontwarn com.epson.**

# Keep Epson epos2 classes specifically
-keep class com.epson.epos2.** { *; }
-keepclassmembers class com.epson.epos2.** { *; }

# Keep Epson epsonio classes (used by native Bluetooth implementation)
-keep class com.epson.epsonio.** { *; }
-keepclassmembers class com.epson.epsonio.** { *; }

# Keep the plugin class
-keep class com.example.epson_printer_android.** { *; }
-keepclassmembers class com.example.epson_printer_android.** { *; }

# Prevent obfuscation of classes used via JNI
-keepnames class com.epson.** { *; }
-keepnames class com.epson.epsonio.bluetooth.** { *; }
