package dev.iraniap

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import org.json.JSONArray
import org.json.JSONObject

internal class PaymentCallbackBridge(
    context: Context,
    private val channel: MethodChannel,
) : PluginRegistry.NewIntentListener {
    private val preferences: SharedPreferences =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    fun attach(binding: ActivityPluginBinding) {
        binding.addOnNewIntentListener(this)
        record(binding.activity.intent?.dataString)
    }

    fun detach(binding: ActivityPluginBinding) {
        binding.removeOnNewIntentListener(this)
    }

    override fun onNewIntent(intent: Intent): Boolean {
        record(intent.dataString)
        return false
    }

    fun register(arguments: Map<*, *>): PaymentSessionRegistration {
        try {
            val session = arguments["session"] as? Map<*, *>
                ?: return PaymentSessionRegistration.malformed
            val expiresAt = (arguments["expiresAt"] as? Number)?.toLong()
                ?: return PaymentSessionRegistration.malformed
            val expectedState = session["expectedState"] as? String
                ?: return PaymentSessionRegistration.malformed
            val persistedSession = preferences.getString(SESSION, null)
            val persistedState = persistedSession?.let {
                JSONObject(it).optString("expectedState")
            }
            if (!persistedState.isNullOrEmpty() && persistedState != expectedState) {
                return PaymentSessionRegistration.active
            }
            preferences.edit()
                .putString(SESSION, JSONObject(session).toString())
                .putLong(EXPIRES_AT, expiresAt)
                .apply()
            return PaymentSessionRegistration.accepted
        } catch (_: RuntimeException) {
            return PaymentSessionRegistration.malformed
        }
    }

    fun consumePending(): String? {
        val value = preferences.getString(CALLBACK, null)
        preferences.edit().remove(CALLBACK).apply()
        return value
    }

    fun recovery(): Map<String, Any?>? {
        val session = preferences.getString(SESSION, null) ?: return null
        return mapOf(
            "session" to jsonToMap(JSONObject(session)),
            "expiresAt" to preferences.getLong(EXPIRES_AT, 0),
            "callbackUrl" to preferences.getString(CALLBACK, null),
        )
    }

    fun clear(sessionId: String?) {
        val persistedSession = preferences.getString(SESSION, null) ?: return
        val persistedState = runCatching {
            JSONObject(persistedSession).optString("expectedState")
        }.getOrNull()
        if (sessionId == null || sessionId != persistedState) return
        preferences.edit().remove(SESSION).remove(EXPIRES_AT).remove(CALLBACK).apply()
    }

    private fun record(url: String?) {
        if (url.isNullOrBlank() || !preferences.contains(SESSION)) return
        preferences.edit().putString(CALLBACK, url).apply()
        channel.invokeMethod("paymentCallback", mapOf("url" to url), object : MethodChannel.Result {
            override fun success(result: Any?) {
                clearCallback(url)
            }

            override fun error(code: String, message: String?, details: Any?) = clearCallback(url)
            override fun notImplemented() = Unit
        })
    }

    private fun clearCallback(url: String) {
        if (preferences.getString(CALLBACK, null) == url) {
            preferences.edit().remove(CALLBACK).apply()
        }
    }

    private fun jsonToMap(json: JSONObject): Map<String, Any?> = json.keys().asSequence().associateWith { key ->
        when (val value = json.get(key)) {
            is JSONArray -> (0 until value.length()).map(value::get)
            JSONObject.NULL -> null
            else -> value
        }
    }

    private companion object {
        const val PREFERENCES = "iran_iap.payment_callback"
        const val SESSION = "session"
        const val EXPIRES_AT = "expiresAt"
        const val CALLBACK = "callback"
    }
}

internal enum class PaymentSessionRegistration { accepted, active, malformed }
