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

                    else -> result.notImplemented()
                }
            }
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
