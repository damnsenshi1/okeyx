package com.senshilabs.okeyx_mobile

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val shareChannel = "com.senshilabs.okeyx_mobile/share"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannel).setMethodCallHandler { call, result ->
            if (call.method != "shareImage") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            try {
                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) {
                    result.error("missing_path", "PaylaÅŸÄ±lacak dosya yolu boÅŸ.", null)
                    return@setMethodCallHandler
                }
                val file = File(path)
                if (!file.exists()) {
                    result.error("missing_file", "PaylaÅŸÄ±m gÃ¶rseli bulunamadÄ±.", null)
                    return@setMethodCallHandler
                }
                val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
                val sendIntent = Intent(Intent.ACTION_SEND).apply {
                    type = "image/png"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    putExtra(Intent.EXTRA_TEXT, call.argument<String>("text") ?: "OkeyX 101")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                val chooserTitle = call.argument<String>("chooserTitle") ?: "OkeyX ile paylaÅŸ"
                startActivity(Intent.createChooser(sendIntent, chooserTitle))
                result.success(true)
            } catch (e: Exception) {
                result.error("share_failed", e.message ?: "PaylaÅŸÄ±m baÅŸlatÄ±lamadÄ±.", null)
            }
        }
    }
}