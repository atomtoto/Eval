# Skip's own rules come from the generated EvalBridge/proguard-rules.pro (see build.gradle.kts).
# SkipBridge also looks these Kotlin types up by name from native code.
-keep class kotlin.Pair { <init>(...); getFirst(); getSecond(); }
-keep class kotlin.Triple { <init>(...); getFirst(); getSecond(); getThird(); }
-keep interface kotlinx.coroutines.flow.Flow
