# kotlinx.serialization genera serializadores por reflexión sobre las clases anotadas.
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**

-keepclassmembers class com.risingpadel.** {
    *** Companion;
}
-keepclasseswithmembers class com.risingpadel.** {
    kotlinx.serialization.KSerializer serializer(...);
}
-keep,includedescriptorclasses class com.risingpadel.core.model.**$$serializer { *; }
-keep,includedescriptorclasses class com.risingpadel.core.sync.**$$serializer { *; }
