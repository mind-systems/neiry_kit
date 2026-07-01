# Neiry SDK — classes referenced only from JNI (libCapsuleClient.so / libneiry_jni.so),
# not from Kotlin/Java, so R8 strips them without an explicit keep rule.
-keep class com.neurosdk2.** { *; }
-keep class com.neiry.neiry_kit.** { *; }
