package dev.changkevin.scrapyard

import android.content.ClipData
import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "scrapyard/share",
        ).setMethodCallHandler { call, result ->
            if (call.method != "shareFile") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            val mime = call.argument<String>("mime") ?: "image/png"
            if (path.isNullOrBlank()) {
                result.error("SHARE", "Missing file path", null)
                return@setMethodCallHandler
            }
            try {
                shareFile(path, mime)
                result.success(null)
            } catch (e: Exception) {
                result.error("SHARE", e.message, null)
            }
        }
    }

    private fun shareFile(path: String, mime: String) {
        val file = File(path)
        if (!file.exists()) {
            throw IllegalArgumentException("File not found")
        }
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file,
        )
        val share = Intent(Intent.ACTION_SEND).apply {
            type = mime
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = ClipData.newRawUri("", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(share, null))
    }
}
