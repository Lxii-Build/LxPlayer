# kotlinx.serialization：@Serializable 类的合成 serializer 通过反射查找，
# R8 看不到引用会把它们剪掉，导致 release 包一解析 JSON 就崩。
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class cc.lxii.player.** {
    *** Companion;
}
-keepclasseswithmembers class cc.lxii.player.** {
    kotlinx.serialization.KSerializer serializer(...);
}
-keep,includedescriptorclasses class cc.lxii.player.**$$serializer { *; }

# Media3 通过反射实例化解码器与渲染器扩展。
-dontwarn androidx.media3.**

# OkHttp 在 JVM 上会引用一些仅编译期存在的平台类。
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
