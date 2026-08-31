# Keep kotlinx.serialization serializers for the wire models.
-keepclassmembers class com.hadithly.app.** {
    *** Companion;
}
-keepclasseswithmembers class com.hadithly.app.** {
    kotlinx.serialization.KSerializer serializer(...);
}
