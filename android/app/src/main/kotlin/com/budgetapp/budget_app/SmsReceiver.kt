package com.budgetapp.budget_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import io.flutter.plugin.common.EventChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * Listens for incoming SMS (declared in AndroidManifest.xml).
 *
 * Every message is immediately persisted to SharedPreferences so nothing is
 * lost when Flutter/Dart is not running (e.g. app closed, phone rebooted into
 * a background process). If the Dart side is listening on the EventChannel,
 * it is also forwarded live for instant UI updates.
 */
class SmsReceiver : BroadcastReceiver() {

    companion object {
        @Volatile
        var sink: EventChannel.EventSink? = null

        private const val PREFS = "sms_queue"
        private const val KEY = "pending"

        fun store(context: Context, address: String, body: String, date: Long) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val arr = JSONArray(prefs.getString(KEY, "[]") ?: "[]")
            arr.put(JSONObject().apply {
                put("address", address)
                put("body", body)
                put("date", date)
            })
            prefs.edit().putString(KEY, arr.toString()).apply()
        }

        /** Returns all queued messages and clears the queue. */
        fun drain(context: Context): List<Map<String, Any>> {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val raw = prefs.getString(KEY, "[]") ?: "[]"
            val arr = JSONArray(raw)
            val out = mutableListOf<Map<String, Any>>()
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                out.add(
                    mapOf(
                        "address" to o.optString("address", ""),
                        "body" to o.optString("body", ""),
                        "date" to o.optLong("date", 0L)
                    )
                )
            }
            prefs.edit().remove(KEY).apply()
            return out
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (parts.isEmpty()) return

        // Multi-part messages share originating address + timestamp; join them.
        val grouped = LinkedHashMap<Pair<String, Long>, StringBuilder>()
        val order = mutableListOf<Pair<String, Long>>()
        for (msg in parts) {
            val address = msg.originatingAddress ?: ""
            val date = msg.timestampMillis
            val key = address to date
            if (!grouped.containsKey(key)) {
                grouped[key] = StringBuilder()
                order.add(key)
            }
            grouped[key]!!.append(msg.messageBody ?: "")
        }

        for (key in order) {
            val (address, date) = key
            val body = grouped[key].toString()
            store(context, address, body, date)
            // onReceive runs on the main thread, which EventSink requires.
            sink?.success(mapOf("address" to address, "body" to body, "date" to date))
        }
    }
}
