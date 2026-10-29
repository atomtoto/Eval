import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.atom.eval"
    compileSdk = 37
    // Strips the native libraries with the NDK that comes with the Swift SDK for Android.
    swiftAndroidNdk()?.let { ndk ->
        ndkPath = ndk.path
        ndkVersion = Properties().apply { ndk.resolve("source.properties").reader().use { load(it) } }
            .getProperty("Pkg.Revision")
    }

    defaultConfig {
        applicationId = "com.atom.Eval"
        // The Swift SDK for Android targets API 28.
        minSdk = 28
        targetSdk = 36
        versionCode = 1
        versionName = "0.1"
        // Read by Skip to load the native EvalBridge library.
        manifestPlaceholders["SKIP_BRIDGE_MODULES"] = "EvalBridge"
        // EvalCore relies on a 64-bit Int, as on iOS.
        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro",
                          gradle.extra["evalBridgeProguardRules"] as String)
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }

    packaging {
        jniLibs {
            pickFirsts.add("**/*.so")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("eval.bridge:EvalBridge")
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.material3)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.activity.compose)
    implementation(libs.lifecycle.viewmodel.compose)
    debugImplementation(libs.compose.ui.tooling)
}

/** The newest NDK installed with a Swift SDK for Android, if any. */
fun swiftAndroidNdk(): File? =
    File(System.getProperty("user.home"), "Library/org.swift.swiftpm/swift-sdks")
        .listFiles { file -> file.name.endsWith("_android.artifactbundle") }?.maxOrNull()
        ?.resolve("swift-android")?.listFiles { file -> file.name.startsWith("android-ndk-") }?.maxOrNull()
