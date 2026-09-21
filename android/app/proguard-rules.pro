# kotlinx.serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class shop.sportsearch.app.** {
    *** Companion;
}
-keepclasseswithmembers class shop.sportsearch.app.** {
    kotlinx.serialization.KSerializer serializer(...);
}
-keep,includedescriptorclasses class shop.sportsearch.app.**$$serializer { *; }

# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**

# Room creates the generated *_Impl database by reflection. It arrives here
# through WorkManager 2.7 (a Glance dependency), whose Room 2.2 consumer rule
# keeps the class but not its constructor - and R8 full mode strips an unused
# constructor unless told otherwise. The release build crashed on launch in
# androidx.startup with "Failed to create an instance of WorkDatabase".
-keep class * extends androidx.room.RoomDatabase { <init>(); }
