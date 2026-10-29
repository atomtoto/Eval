// Eval for Android: a Jetpack Compose app on top of the EvalCore engine, which
// Skip Fuse compiles natively for Android and bridges to Kotlin (EvalBridge).
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "Eval"
include(":app")

// Transpile EvalBridge with Skip so that its Gradle project is up to date, then
// include it: `eval.bridge:EvalBridge` resolves to that project, whose build
// cross-compiles the Swift code for Android.
val bridgePackage = rootDir.resolve("EvalBridge")
val skipOutput = bridgePackage.resolve(".build/plugins/outputs/evalbridge/EvalBridge/destination/skipstone")
val pluginRef = File.createTempFile("skip-plugin-path", ".tmp")
val prebuild = providers.exec {
    // Through a shell, so that the PATH below also applies to finding skip.
    commandLine("/bin/sh", "-c", "exec skip plugin --prebuild --package-path \"$1\" --plugin-ref \"$2\"",
                "sh", bridgePackage.path, pluginRef.path)
    environment("PATH", "${System.getenv("PATH")}:/opt/homebrew/bin")
    isIgnoreExitValue = true
}
val prebuildErrors = prebuild.standardError.asText.get()
print(prebuild.standardOutput.asText.get())
print(prebuildErrors)
val prebuildExit = prebuild.result.get().exitValue
if (prebuildExit != 0) {
    throw GradleException("skip plugin --prebuild failed with exit code $prebuildExit:\n" +
                          prebuildErrors.lines().takeLast(40).joinToString("\n"))
}

// Gradle refuses two versions of the Android plugin in one build: the app uses the
// versions of the Skip modules.
val skipCatalog = skipOutput.resolve("settings.gradle.kts").readText()
val appCatalog = rootDir.resolve("gradle/libs.versions.toml").readText()
for ((skipKey, appKey) in listOf("android-gradle-plugin" to "agp", "kotlin" to "kotlin")) {
    val skipVersion = Regex("version\\(\"$skipKey\", \"([^\"]+)\"\\)").find(skipCatalog)?.groupValues?.get(1)
    val appVersion = Regex("^$appKey = \"([^\"]+)\"", RegexOption.MULTILINE).find(appCatalog)?.groupValues?.get(1)
    check(skipVersion == appVersion) {
        "gradle/libs.versions.toml: $appKey = \"$appVersion\" must match Skip's $skipKey $skipVersion"
    }
}

// Debug and release builds of EvalBridge share one folder of native libraries:
// release builds start from an empty one, so that no debug library ships.
if (gradle.startParameter.taskNames.any { it.contains("Release") }) {
    skipOutput.resolve("EvalBridge/build/jni-libs").deleteRecursively()
}

gradle.extra["evalBridgeProguardRules"] = skipOutput.resolve("EvalBridge/proguard-rules.pro").path
includeBuild(skipOutput)
