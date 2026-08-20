import java.io.File

// serious_python's Android plugin reads these from the process environment
// (not gradle.properties). Set them here so `flutter run` works without a
// custom shell. Paths are the repo-root dirs filled by
// tools/package_mathreader_python.ps1.
fun putEnv(key: String, value: String) {
    try {
        val env = System.getenv()
        val m = env.javaClass.getDeclaredField("m")
        m.isAccessible = true
        @Suppress("UNCHECKED_CAST")
        (m.get(env) as MutableMap<String, String>)[key] = value
    } catch (_: Exception) {
    }
    try {
        val pe = Class.forName("java.lang.ProcessEnvironment")
        val field = pe.getDeclaredField("theCaseInsensitiveEnvironment")
        field.isAccessible = true
        @Suppress("UNCHECKED_CAST")
        (field.get(null) as MutableMap<String, String>)[key] = value
    } catch (_: Exception) {
    }
}

val kotoRepoRoot = settings.rootDir.parentFile
// Keep app.zip in sync with python/mathreader_app/*.py without re-pip.
val pythonAppDir = File(kotoRepoRoot, "build/python-app")
val pythonSrcDir = File(kotoRepoRoot, "python/mathreader_app")
if (pythonAppDir.isDirectory && pythonSrcDir.isDirectory) {
    listOf("main.py", "mathreader_tflite.py").forEach { name ->
        val src = File(pythonSrcDir, name)
        if (src.isFile) src.copyTo(File(pythonAppDir, name), overwrite = true)
    }
}
putEnv("SERIOUS_PYTHON_VERSION", "3.12")
putEnv(
    "SERIOUS_PYTHON_SITE_PACKAGES",
    File(kotoRepoRoot, "build/site-packages").absolutePath,
)
putEnv("SERIOUS_PYTHON_APP", File(kotoRepoRoot, "build/python-app").absolutePath)
putEnv("SERIOUS_PYTHON_ANDROID_EXTRACT_PACKAGES", "mathreader")
putEnv("SERIOUS_PYTHON_BUNDLE_ID", "dev.changkevin.scrapyard")

pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
