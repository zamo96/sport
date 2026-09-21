import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// google-services.json carries the Firebase project and is not in version
// control, so the plugin is applied only when the file is present. Without it
// the app builds and runs exactly as before, just without push: Firebase never
// initializes and PushRegistration notices and stays quiet.
val hasFirebaseConfig = file("google-services.json").exists()
if (hasFirebaseConfig) {
    apply(plugin = libs.plugins.google.services.get().pluginId)
}

// Sign in with Google needs the *web* OAuth client ID (client_type 3). Firebase
// writes it into google-services.json once Google sign-in is enabled for the
// project, so it is read from there unless local.defaults.properties overrides
// it. Empty means the button stays hidden.
fun googleWebClientIdFromFirebase(): String {
    val servicesFile = file("google-services.json")
    if (!servicesFile.exists()) return ""
    return runCatching {
        @Suppress("UNCHECKED_CAST")
        val json = groovy.json.JsonSlurper().parse(servicesFile) as Map<String, Any?>
        val clients = json["client"] as? List<Map<String, Any?>> ?: emptyList()
        clients
            .flatMap { (it["oauth_client"] as? List<Map<String, Any?>>).orEmpty() }
            .firstOrNull { (it["client_type"] as? Number)?.toInt() == 3 }
            ?.get("client_id") as? String
    }.getOrNull().orEmpty()
}

// Mirrors ios/TennisSearchIOS/Configs/*.xcconfig.
// Copy local.defaults.properties.example to local.defaults.properties to point
// debug builds at a backend running on this machine.
val localDefaults = Properties().apply {
    val file = rootProject.file("local.defaults.properties")
    if (file.exists()) {
        file.inputStream().use { load(it) }
    }
}

fun config(key: String, fallback: String): String =
    (localDefaults.getProperty(key) ?: fallback).trim()

fun boolConfig(key: String, fallback: String): String =
    if (config(key, fallback).lowercase() in setOf("yes", "true")) "true" else "false"

android {
    namespace = "shop.sportsearch.app"
    compileSdk = 37

    defaultConfig {
        applicationId = "shop.sportsearch.app"
        minSdk = 26
        targetSdk = 37
        versionCode = 2026090602
        versionName = "1.1.1"

        vectorDrawables.useSupportLibrary = true

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        buildConfigField("boolean", "HAS_FIREBASE_CONFIG", hasFirebaseConfig.toString())
        // The web OAuth client ID from Google Cloud: public, but specific to the
        // project, so it lives in local.defaults.properties like the API host.
        buildConfigField(
            "String",
            "GOOGLE_WEB_CLIENT_ID",
            "\"${config("GOOGLE_WEB_CLIENT_ID", "").ifBlank { googleWebClientIdFromFirebase() }}\"",
        )
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
            buildConfigField("String", "API_SCHEME", "\"${config("API_SCHEME", "https")}\"")
            buildConfigField("String", "API_BASE_URL", "\"${config("API_BASE_URL", "sportsearch.shop")}\"")
            buildConfigField("boolean", "USE_MOCK_DATA", boolConfig("USE_MOCK_DATA", "NO"))
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            buildConfigField("String", "API_SCHEME", "\"https\"")
            buildConfigField("String", "API_BASE_URL", "\"sportsearch.shop\"")
            buildConfigField("boolean", "USE_MOCK_DATA", "false")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.foundation)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.androidx.navigation.compose)

    // The iOS app ships an "Upcoming games" home-screen widget; Glance is the
    // Compose-shaped way to build the same thing here.
    implementation(libs.androidx.glance.appwidget)
    implementation(libs.androidx.glance.material3)

    implementation(libs.okhttp)
    implementation(libs.okhttp.logging)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.coil.compose)
    // Pure-Java QR encoder; iOS uses CoreImage's CIQRCodeGenerator, which has no
    // Android equivalent in the platform.
    implementation(libs.zxing.core)
    // iOS draws maps with MapKit, which needs no key. Google Maps on Android does,
    // and this project has none, so OpenStreetMap tiles via osmdroid stand in.
    implementation(libs.osmdroid.android)

    // The profile video trimmer: ExoPlayer previews the clip the way AVPlayer
    // does, Transformer cuts it the way AVAssetExportSession does.
    implementation(libs.androidx.media3.exoplayer)
    implementation(libs.androidx.media3.ui)
    implementation(libs.androidx.media3.transformer)
    implementation(libs.androidx.media3.effect)
    implementation(libs.androidx.media3.common)

    // Sign in with Google - the Android stand-in for Sign in with Apple.
    implementation(libs.androidx.credentials)
    implementation(libs.androidx.credentials.play.services)
    implementation(libs.googleid)

    // Push. The messaging library is safe to ship without google-services.json:
    // it simply finds no default FirebaseApp and never asks for a token.
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.messaging)

    coreLibraryDesugaring(libs.desugar.jdk.libs)

    debugImplementation(libs.androidx.compose.ui.tooling)
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("junit:junit:4.13.2")
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.ext.junit)
}
