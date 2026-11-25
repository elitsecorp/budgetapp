package com.budgetapp.budget_app

import android.Manifest
import android.net.Uri
import android.os.Bundle
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Live stream of incoming SMS (forwarded by SmsReceiver).
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "budget_app/sms_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    SmsReceiver.sink = events
                }

                override fun onCancel(arguments: Any?) {
                    SmsReceiver.sink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "budget_app/sms")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "drainPending" -> result.success(SmsReceiver.drain(applicationContext))

                    "hasReadSmsPermission" -> result.success(hasSmsPermission())

                    "getInbox" -> {
                        val limit = call.argument<Int>("limit") ?: 1000
                        try {
                            result.success(readInbox(limit))
                        } catch (e: SecurityException) {
                            result.error("PERMISSION", "READ_SMS not granted", e.message)
                        }
                    }

                    "lookupContact" -> {
                        val address = call.argument<String>("address") ?: ""
                        result.success(findContactName(address))
                    }

                    "downloadAndInstallApk" -> {
                        val url = call.argument<String>("url") ?: ""
                        if (url.isEmpty()) {
                            result.error("ARGS", "URL is empty", null)
                        } else {
                            downloadAndInstallApk(url, result)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    /** Display name from Contacts for a numeric address (needs READ_CONTACTS). */
    private fun findContactName(address: String): String? {
        if (address.any { it.isLetter() }) return null
        return try {
            val uri = android.provider.ContactsContract.PhoneLookup.CONTENT_FILTER_URI.buildUpon()
                .appendPath(address)
                .build()
            contentResolver.query(
                uri,
                arrayOf(android.provider.ContactsContract.PhoneLookup.DISPLAY_NAME),
                null, null, null
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        } catch (e: SecurityException) {
            null
        }
    }

    /**
     * Downloads the APK on a background thread into the cache dir, then fires
     * the system package-installer intent via the app's FileProvider.
     * [result] replies once the install prompt has been launched (or with an
     * error). The only network usage in the whole app.
     */
    private fun downloadAndInstallApk(
        url: String,
        result: io.flutter.plugin.common.MethodChannel.Result
    ) {
        Thread {
            try {
                val target = java.io.File(cacheDir, "update.apk")
                if (target.exists()) target.delete()

                val connection = java.net.URL(url).openConnection() as java.net.HttpURLConnection
                connection.connectTimeout = 30_000
                connection.readTimeout = 60_000
                connection.connect()
                if (connection.responseCode !in 200..299) {
                    throw java.io.IOException("HTTP ${connection.responseCode}")
                }
                connection.inputStream.use { input ->
                    java.io.FileOutputStream(target).use { output ->
                        val buffer = ByteArray(64 * 1024)
                        while (true) {
                            val read = input.read(buffer)
                            if (read == -1) break
                            output.write(buffer, 0, read)
                        }
                    }
                }

                val uri = androidx.core.content.FileProvider.getUriForFile(
                    this,
                    "$packageName.fileprovider",
                    target
                )
                val intent = android.content.Intent(android.content.Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "application/vnd.android.package-archive")
                    addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    result.success("Downloaded ${(target.length() / 1024 / 1024)} MB — install prompt opened")
                }
            } catch (e: Exception) {
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    result.error("DOWNLOAD", e.message ?: e.javaClass.simpleName, null)
                }
            }
        }.start()
    }

    private fun hasSmsPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED

    /** Reads the device SMS inbox (requires READ_SMS) newest-first. */
    private fun readInbox(limit: Int): List<Map<String, Any>> {
        val out = mutableListOf<Map<String, Any>>()
        if (!hasSmsPermission()) return out

        val projection = arrayOf("_id", "address", "body", "date")
        val cursor = contentResolver.query(
            Uri.parse("content://sms/inbox"), projection, null, null, "date DESC"
        ) ?: return out

        cursor.use {
            var n = 0
            while (it.moveToNext() && n < limit) {
                out.add(
                    mapOf(
                        "address" to (it.getString(1) ?: ""),
                        "body" to (it.getString(2) ?: ""),
                        "date" to it.getLong(3)
                    )
                )
                n++
            }
        }
        return out
    }
}
