import java.util.Properties

// Secrets live in android/secrets.properties (gitignored). Copy
// secrets.properties.example and fill in the real values.
val secrets = Properties().apply {
    val file = rootProject.file("secrets.properties")
    if (file.exists()) {
        file.inputStream().use { load(it) }
    }
}

val productionSecrets = Properties().apply {
    val file = rootProject.file("production.secrets.properties")
    if (file.exists()) {
        file.inputStream().use { load(it) }
    }
}

fun secret(key: String): String =
    (secrets.getProperty(key) ?: System.getenv(key.replace(".", "_").uppercase()) ?: "PLACEHOLDER_$key")

fun productionSecret(key: String): String =
    (productionSecrets.getProperty(key)
        ?: System.getenv("PRODUCTION_${key.replace(".", "_").uppercase()}")
        ?: "PLACEHOLDER_production.$key")

val hasGoogleServices = file("google-services.json").exists()

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// Keep local builds working before a Firebase project is provisioned. Once
// app/google-services.json exists, the standard Google Services resource
// generation is enabled automatically.
if (hasGoogleServices) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "com.hadithly.app"
    compileSdk { version = release(36) }

    defaultConfig {
        applicationId = "com.hadithly.app"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"

        buildConfigField("String", "CONVEX_URL", "\"${secret("convex.url")}\"")
        buildConfigField("String", "CLERK_PUBLISHABLE_KEY", "\"${secret("clerk.publishableKey")}\"")
        buildConfigField("String", "REVENUECAT_API_KEY", "\"${secret("revenuecat.apiKey")}\"")
        buildConfigField("String", "PRIVACY_POLICY_URL", "\"${secret("privacy.url")}\"")
        buildConfigField("String", "TERMS_OF_USE_URL", "\"${secret("terms.url")}\"")
        buildConfigField("boolean", "FIREBASE_CONFIGURED", hasGoogleServices.toString())
    }

    buildTypes {
        release {
            // Local release evidence runs on the emulator, which requires a
            // signed APK; signing with the debug key matches the SHA-1
            // registered with Google for local release testing.
            signingConfig = signingConfigs.getByName("debug")
            buildConfigField("String", "CONVEX_URL", "\"https://giddy-ox-648.eu-west-1.convex.cloud\"")
            buildConfigField("String", "CLERK_PUBLISHABLE_KEY", "\"${productionSecret("clerk.publishableKey")}\"")
            buildConfigField("String", "REVENUECAT_API_KEY", "\"${productionSecret("revenuecat.apiKey")}\"")
            buildConfigField("String", "PRIVACY_POLICY_URL", "\"${productionSecret("privacy.url")}\"")
            buildConfigField("String", "TERMS_OF_USE_URL", "\"${productionSecret("terms.url")}\"")
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlin {
        jvmToolchain(21)
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.material.icons.extended)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.kotlinx.coroutines)
    implementation(libs.kotlinx.serialization)
    implementation(libs.clerk.api)
    implementation(libs.clerk.convex)
    implementation(libs.convex.mobile)
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.messaging)
    implementation(libs.revenuecat.purchases)

    testImplementation(libs.junit)

    debugImplementation(libs.androidx.ui.tooling)
}
