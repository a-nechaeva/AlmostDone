plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.ksp)
    alias(libs.plugins.roborazzi)
}

val robolectricSdk by configurations.creating

android {
    namespace = "com.example.mobile_android"
    compileSdk { version = release(36) }

    defaultConfig {
        applicationId = "com.example.mobile_android"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        manifestPlaceholders["YANDEX_CLIENT_ID"] = "de795e46d251424297db41a56379f2d3"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
        freeCompilerArgs += listOf("-opt-in=androidx.compose.material3.ExperimentalMaterial3Api")
    }

    buildFeatures { compose = true }
    testOptions {
        unitTests.isIncludeAndroidResources = true
        unitTests.all {
            it.maxHeapSize = "2g"
            it.maxParallelForks = 1
            it.systemProperty("user.language", "ru")
            it.systemProperty("user.country", "RU")
            it.systemProperty("user.timezone", "UTC")
            it.inputs.files(robolectricSdk)
            it.systemProperty("robolectric.offline", "true")
            it.doFirst {
                it.systemProperty("robolectric.dependency.dir", robolectricSdk.singleFile.parent)
            }
        }
    }
    lint { abortOnError = true }
}

roborazzi {
    outputDir.set(file("src/test/screenshots"))
    compare { outputDir.set(file("build/outputs/roborazzi")) }
}

// Roborazzi's cache restore/finalizer can recreate missing references even after verification
// fails.
tasks
    .matching {
        it.name == "restoreOutputDirRoborazzi" || it.name.startsWith("finalizeTestRoborazzi")
    }
    .configureEach {
        onlyIf {
            providers.gradleProperty("roborazzi.test.record").orNull == "true" ||
                gradle.taskGraph.allTasks.any {
                    it.name.startsWith("recordRoborazzi") ||
                        it.name.startsWith("verifyAndRecordRoborazzi")
                }
        }
    }

ksp { arg("room.schemaLocation", "$projectDir/schemas") }

dependencies {
    robolectricSdk("org.robolectric:android-all-instrumented:16-robolectric-13921718-i7") {
        isTransitive = false
    }
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)
    implementation(libs.androidx.datastore.preferences)
    ksp(libs.androidx.room.compiler)

    testImplementation(libs.junit)
    testImplementation(libs.robolectric)
    testImplementation(libs.roborazzi)
    testImplementation(libs.roborazzi.compose)
    testImplementation(platform(libs.androidx.compose.bom))
    testImplementation(libs.androidx.compose.ui.test.junit4)
    testImplementation(libs.kotlinx.coroutines.test)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(libs.androidx.room.testing)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    debugImplementation(libs.androidx.compose.ui.tooling)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
    implementation("com.yandex.android:authsdk:3.1.3")
}
