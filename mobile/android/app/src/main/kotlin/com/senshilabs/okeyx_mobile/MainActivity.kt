package com.senshilabs.okeyx_mobile

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        @Volatile var inForeground = false
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        try { OkxNotifyWorker.schedule(this) } catch (e: Exception) { }
        if (android.os.Build.VERSION.SDK_INT >= 33 && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 4401)
        }
    }

    override fun onResume() { super.onResume(); inForeground = true }
    override fun onPause() { inForeground = false; super.onPause() }

    private val shareChannel = "com.senshilabs.okeyx_mobile/share"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannel).setMethodCallHandler { call, result ->
            // Uygulama içi güncelleme: önbellek klasörü, kurulum izni ve APK kurulumu.
            when (call.method) {
                "cacheDir" -> { result.success(cacheDir.absolutePath); return@setMethodCallHandler }
                "androidId" -> {
                    val id = android.provider.Settings.Secure.getString(contentResolver, android.provider.Settings.Secure.ANDROID_ID)
                    result.success(id); return@setMethodCallHandler
                }
                "canInstall" -> {
                    val ok = if (android.os.Build.VERSION.SDK_INT >= 26) packageManager.canRequestPackageInstalls() else true
                    result.success(ok); return@setMethodCallHandler
                }
                "openInstallSettings" -> {
                    try {
                        if (android.os.Build.VERSION.SDK_INT >= 26) {
                            startActivity(Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, android.net.Uri.parse("package:$packageName")))
                        }
                        result.success(true)
                    } catch (e: Exception) { result.error("settings_failed", e.message, null) }
                    return@setMethodCallHandler
                }
                "installApk" -> {
                    try {
                        val file = File(call.argument<String>("path") ?: "")
                        if (!file.exists()) { result.error("missing_file", "APK bulunamadı", null); return@setMethodCallHandler }
                        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) { result.error("install_failed", e.message, null) }
                    return@setMethodCallHandler
                }
            }
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