# ML Kit text recognition: plugin references optional language packs we don't bundle.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**

-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }

# Flutter / plugins used via reflection or JNI.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.tekartik.sqflite.** { *; }
-keep class com.flet.serious_python.** { *; }
-dontwarn io.flutter.embedding.**
-dontwarn com.chaquo.python.**
