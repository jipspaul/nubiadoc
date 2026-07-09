# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Google Play Core — référencé par le code Flutter deferred-components mais NON
# utilisé par ces apps. Depuis l'activation de R8/minify (#3452), R8 échouait sur
# ces classes manquantes. On les ignore (dontwarn) + keep.
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }
