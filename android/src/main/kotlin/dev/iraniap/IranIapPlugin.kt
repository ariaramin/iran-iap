package dev.iraniap

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding

/**
 * Stable Flutter plugin entry point.
 *
 * The concrete [SelectedStorePlugin] is supplied by exactly one Gradle source
 * set (`bazaar`, `myket`, or `stub`). The unselected store source set is never
 * compiled, and its native SDK is never placed on the dependency graph.
 */
class IranIapPlugin : FlutterPlugin, ActivityAware {
    private val delegate = SelectedStorePlugin()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        delegate.onAttachedToEngine(binding)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        delegate.onDetachedFromEngine(binding)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        delegate.onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        delegate.onDetachedFromActivityForConfigChanges()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        delegate.onReattachedToActivityForConfigChanges(binding)
    }

    override fun onDetachedFromActivity() {
        delegate.onDetachedFromActivity()
    }
}
