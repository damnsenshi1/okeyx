package com.senshilabs.okeyx_mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

/**
 * Oyun kapalıyken (Firebase olmadan) bildirim: Android her ~15 dakikada bir
 * bu işi çalıştırır; sunucudaki okunmamış bildirimlere (davet, arkadaşlık,
 * altın, hediye, çanak) ve GitHub'daki yeni sürüme bakıp telefona bildirim düşer.
 */
class OkxNotifyWorker(ctx: Context, params: WorkerParameters) : Worker(ctx, params) {
    override fun doWork(): Result {
        if (MainActivity.inForeground) return Result.success()
        val flutter = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val pid = flutter.getString("flutter.okx_bg_pid", null)
        val token = flutter.getString("flutter.okx_bg_token", null)
        val api = flutter.getString("flutter.okx_bg_api", null)
        val state = applicationContext.getSharedPreferences("okx_bg_state", Context.MODE_PRIVATE)
        ensureChannel(applicationContext)
        try {
            if (!pid.isNullOrBlank() && !token.isNullOrBlank() && !api.isNullOrBlank()) {
                val body = get("$api/api/account/$pid/notifications", mapOf("X-Account-Token" to token))
                if (body != null) {
                    val rows = JSONObject(body).optJSONArray("notifications")
                    val seen = state.getStringSet("seen", emptySet())!!.toMutableSet()
                    val nowSec = System.currentTimeMillis() / 1000
                    if (rows != null) {
                        for (i in 0 until minOf(rows.length(), 20)) {
                            val n = rows.getJSONObject(i)
                            val id = n.optString("id")
                            if (id.isBlank() || seen.contains(id) || n.optBoolean("read")) continue
                            seen.add(id)
                            // Çok eski bildirimleri telefona düşürme (ilk kurulumda yığılmasın).
                            if (nowSec - n.optLong("created_at", nowSec) > 6 * 3600) continue
                            notify(applicationContext, id.hashCode(), n.optString("title", "OKEYX"), n.optString("message", ""))
                        }
                    }
                    state.edit().putStringSet("seen", seen.toList().takeLast(200).toSet()).apply()
                }
            }
            // Yeni sürüm
            val rel = get("https://api.github.com/repos/damnsenshi1/okeyx/releases/latest", mapOf("Accept" to "application/vnd.github+json"))
            if (rel != null) {
                val tag = JSONObject(rel).optString("tag_name")
                val build = Regex("-b(\\d+)$").find(tag)?.groupValues?.get(1)?.toIntOrNull() ?: 0
                val current = try {
                    @Suppress("DEPRECATION")
                    applicationContext.packageManager.getPackageInfo(applicationContext.packageName, 0).versionCode
                } catch (e: Exception) { 0 }
                if (build > current && state.getInt("notified_build", 0) < build) {
                    state.edit().putInt("notified_build", build).apply()
                    val name = Regex("^v([\\d.]+)").find(tag)?.groupValues?.get(1) ?: tag
                    notify(applicationContext, 7001, "Yeni sürüm hazır: OKEYX $name", "Oyunu aç, GÜNCELLE'ye bas.")
                }
            }
        } catch (e: Exception) {
            return Result.success()
        }
        return Result.success()
    }

    private fun get(url: String, headers: Map<String, String>): String? {
        val c = URL(url).openConnection() as HttpURLConnection
        c.connectTimeout = 10000; c.readTimeout = 10000
        c.setRequestProperty("User-Agent", "okeyx-app")
        headers.forEach { (k, v) -> c.setRequestProperty(k, v) }
        return try {
            if (c.responseCode != 200) null else c.inputStream.bufferedReader().use { it.readText() }
        } finally { c.disconnect() }
    }

    companion object {
        private const val CHANNEL = "okeyx_genel"

        fun ensureChannel(ctx: Context) {
            if (Build.VERSION.SDK_INT >= 26) {
                val nm = ctx.getSystemService(NotificationManager::class.java)
                if (nm.getNotificationChannel(CHANNEL) == null) {
                    nm.createNotificationChannel(NotificationChannel(CHANNEL, "OKEYX bildirimleri", NotificationManager.IMPORTANCE_HIGH).apply {
                        description = "Masa davetleri, arkadaşlık istekleri, hediyeler ve yeni sürüm"
                    })
                }
            }
        }

        fun notify(ctx: Context, id: Int, title: String, text: String) {
            val open = Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            val pi = PendingIntent.getActivity(ctx, id, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val n = NotificationCompat.Builder(ctx, CHANNEL)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .setContentIntent(pi)
                .build()
            try { NotificationManagerCompat.from(ctx).notify(id, n) } catch (e: SecurityException) { }
        }

        fun schedule(ctx: Context) {
            try {
                WorkManager.initialize(ctx.applicationContext, androidx.work.Configuration.Builder().build())
            } catch (e: Exception) { /* zaten başlatılmış */ }
            val req = PeriodicWorkRequestBuilder<OkxNotifyWorker>(15, TimeUnit.MINUTES)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build()
            WorkManager.getInstance(ctx.applicationContext).enqueueUniquePeriodicWork("okeyx_notify", ExistingPeriodicWorkPolicy.KEEP, req)
        }
    }
}
