package dev.iraniap

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import ir.myket.billingclient.IabHelper
import ir.myket.billingclient.util.IabResult
import ir.myket.billingclient.util.Purchase
import ir.myket.billingclient.util.SkuDetails
import java.util.concurrent.atomic.AtomicBoolean

internal class SelectedStorePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private var applicationContext: Context? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var paymentCallbacks: PaymentCallbackBridge? = null
    private var helper: IabHelper? = null
    private var initialized = false
    private var activePublicKey: String? = null
    private val operationInProgress = AtomicBoolean(false)
    private val initializing = AtomicBoolean(false)
    @Volatile private var lifecycleGeneration = 0L

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
        paymentCallbacks = PaymentCallbackBridge(binding.applicationContext, channel)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        cleanup()
        activityBinding?.let { paymentCallbacks?.detach(it) }
        activityBinding = null
        paymentCallbacks = null
        channel.setMethodCallHandler(null)
        applicationContext = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        paymentCallbacks?.attach(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
        activityBinding?.let { paymentCallbacks?.detach(it) }
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        paymentCallbacks?.attach(binding)
    }

    override fun onDetachedFromActivity() {
        activity = null
        activityBinding?.let { paymentCallbacks?.detach(it) }
        activityBinding = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "selectedStore" -> result.success("myket")
            "initialize" -> try {
                initialize(call, result)
            } catch (throwable: Throwable) {
                cleanup()
                result.throwableError("platform", "Unexpected Myket initialization failure.", throwable)
            }
            "queryProducts" -> withOperation(result) { queryProducts(call, it) }
            "purchase" -> withOperation(result) { purchase(call, it) }
            "openPaymentUrl" -> openPaymentUrl(activity, call, result)
            "registerPaymentSession" -> registerPaymentSession(call, result)
            "consumePendingPaymentCallback" -> result.success(paymentCallbacks?.consumePending())
            "recoverPaymentSession" -> result.success(paymentCallbacks?.recovery())
            "clearPaymentSession" -> clearPaymentSession(call, result)
            "queryPurchases" -> withOperation(result) { queryPurchases(call, it) }
            "consume" -> withOperation(result) { consume(call, it) }
            "dispose" -> {
                if (initializing.get() || operationInProgress.get()) {
                    result.iapError(
                        "operationInProgress",
                        "Cannot dispose Myket billing while an operation is in progress.",
                    )
                } else {
                    cleanup()
                    result.success(null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun registerPaymentSession(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        when (arguments?.let { paymentCallbacks?.register(it) }) {
            PaymentSessionRegistration.accepted -> result.success(null)
            PaymentSessionRegistration.active -> result.iapError(
                "operationInProgress",
                "Another payment session is active.",
            )
            else -> result.iapError("configuration", "Payment session is malformed.")
        }
    }

    private fun clearPaymentSession(call: MethodCall, result: MethodChannel.Result) {
        paymentCallbacks?.clear(call.argument<String>("sessionId"))
        result.success(null)
    }

    private fun initialize(call: MethodCall, result: MethodChannel.Result) {
        val key = call.argument<String>("publicKey")?.takeIf { it.isNotBlank() }
        if (key == null) {
            result.iapError("configuration", "Myket publicKey must not be blank.")
            return
        }
        if (initialized) {
            if (activePublicKey != key) {
                result.iapError("configuration", "Myket billing is already initialized with a different public key.")
            } else {
                result.success(
                    mapOf(
                        "supportsSubscriptions" to (helper?.subscriptionsSupported() == true),
                        "supportsConsumption" to true,
                        "supportsDynamicPricing" to false,
                    ),
                )
            }
            return
        }
        val context = applicationContext ?: run {
            result.iapError("platform", "Plugin is not attached to an Android context.")
            return
        }
        if (!isPackageInstalled(context, MYKET_PACKAGE)) {
            result.iapError("storeNotInstalled", "Myket is not installed on this device.")
            return
        }
        if (!initializing.compareAndSet(false, true)) {
            result.iapError("operationInProgress", "Myket billing initialization is already in progress.")
            return
        }
        val generation = lifecycleGeneration
        val newHelper = IabHelper(context, key)
        helper = newHelper
        newHelper.startSetup { setupResult ->
            if (isCurrent(generation, newHelper)) {
                initializing.set(false)
                if (setupResult.isSuccess) {
                    initialized = true
                    activePublicKey = key
                    result.success(
                        mapOf(
                            "supportsSubscriptions" to newHelper.subscriptionsSupported(),
                            "supportsConsumption" to true,
                            "supportsDynamicPricing" to false,
                        ),
                    )
                } else {
                    initialized = false
                    activePublicKey = null
                    helper = null
                    runCatching { newHelper.dispose() }
                    lifecycleGeneration++
                    result.iabResultError(setupResult, "Myket billing setup failed.")
                }
            }
        }
    }

    private fun queryProducts(call: MethodCall, result: MethodChannel.Result) {
        val billing = requireReady(result) ?: return finishOperation()
        val ids = call.argument<List<String>>("productIds").orEmpty()
        val requestedType = call.argument<String>("type") ?: TYPE_INAPP
        val generation = lifecycleGeneration
        billing.queryInventoryAsync(true, ids) { queryResult, inventory ->
            if (isCurrent(generation, billing)) {
                if (queryResult.isFailure || inventory == null) {
                    result.iabResultError(queryResult, "Myket product query failed.")
                } else {
                    val products = inventory.allProducts
                        .filterIsInstance<SkuDetails>()
                        .filter { normalizeType(it.type) == requestedType }
                        .filter { ids.contains(it.sku) }
                        .map(::skuToMap)
                    result.success(products)
                }
                finishOperation()
            }
        }
    }

    private fun purchase(call: MethodCall, result: MethodChannel.Result) {
        val billing = requireReady(result) ?: return finishOperation()
        val currentActivity = activity
        if (currentActivity == null) {
            result.iapError("activityUnavailable", "A foreground Android Activity is required for purchase.")
            finishOperation()
            return
        }
        val productId = call.argument<String>("productId")?.takeIf { it.isNotBlank() }
        if (productId == null) {
            result.iapError("configuration", "productId must not be blank.")
            finishOperation()
            return
        }
        val payload = call.argument<String>("payload") ?: ""
        val generation = lifecycleGeneration
        val listener = IabHelper.OnIabPurchaseFinishedListener { purchaseResult, purchaseInfo ->
            if (isCurrent(generation, billing)) {
                when {
                    MyketErrorMapper.isCancellation(purchaseResult) ->
                        result.success(mapOf("status" to "cancelled"))
                    purchaseResult.isSuccess && purchaseInfo != null ->
                        result.success(mapOf("status" to "completed", "purchase" to purchaseToMap(purchaseInfo)))
                    else -> result.iabResultError(purchaseResult, "Myket purchase failed.")
                }
                finishOperation()
            }
        }
        when (call.argument<String>("type")) {
            TYPE_INAPP -> billing.launchPurchaseFlow(currentActivity, productId, listener, payload)
            TYPE_SUBS -> {
                if (!billing.subscriptionsSupported()) {
                    result.iapError("subscriptionUnavailable", "Myket subscriptions are unavailable.")
                    finishOperation()
                    return
                }
                billing.launchSubscriptionPurchaseFlow(currentActivity, productId, listener, payload)
            }
            else -> {
                result.iapError("configuration", "Unsupported purchase type.")
                finishOperation()
            }
        }
    }

    private fun queryPurchases(call: MethodCall, result: MethodChannel.Result) {
        val billing = requireReady(result) ?: return finishOperation()
        val requestedType = call.argument<String>("type") ?: TYPE_INAPP
        val generation = lifecycleGeneration
        billing.queryInventoryAsync(false) { queryResult, inventory ->
            if (isCurrent(generation, billing)) {
                if (queryResult.isFailure || inventory == null) {
                    result.iabResultError(queryResult, "Myket owned-purchase query failed.")
                } else {
                    result.success(
                        inventory.allPurchases
                            .filterIsInstance<Purchase>()
                            .filter { normalizeType(it.itemType) == requestedType }
                            .map(::purchaseToMap),
                    )
                }
                finishOperation()
            }
        }
    }

    private fun consume(call: MethodCall, result: MethodChannel.Result) {
        val billing = requireReady(result) ?: return finishOperation()
        val rawReceipt = call.argument<String>("rawReceipt")?.takeIf { it.isNotBlank() }
        val signature = call.argument<String>("signature")?.takeIf { it.isNotBlank() }
        if (rawReceipt == null || signature == null) {
            result.iapError("configuration", "rawReceipt and signature are required for Myket consumption.")
            finishOperation()
            return
        }
        val purchase = try {
            Purchase(IabHelper.ITEM_TYPE_INAPP, rawReceipt, signature)
        } catch (throwable: Throwable) {
            result.throwableError("invalidResponse", "Could not reconstruct Myket purchase receipt.", throwable)
            finishOperation()
            return
        }
        val generation = lifecycleGeneration
        billing.consumeAsync(purchase) { _, consumeResult ->
            if (isCurrent(generation, billing)) {
                if (consumeResult.isSuccess) result.success(null)
                else result.iabResultError(consumeResult, "Myket consumption failed.")
                finishOperation()
            }
        }
    }

    private fun withOperation(result: MethodChannel.Result, block: (MethodChannel.Result) -> Unit) {
        if (!operationInProgress.compareAndSet(false, true)) {
            result.iapError("operationInProgress", "Another billing operation is already in progress.")
            return
        }
        try {
            block(result)
        } catch (throwable: Throwable) {
            if (throwable is IllegalStateException) {
                cleanup()
                result.throwableError(
                    "notInitialized",
                    "Myket billing client became unavailable; call initialize() again.",
                    throwable,
                )
            } else {
                result.throwableError("platform", "Unexpected Myket billing failure.", throwable)
                finishOperation()
            }
        }
    }

    private fun requireReady(result: MethodChannel.Result): IabHelper? {
        if (!initialized || helper == null) {
            result.iapError("notInitialized", "Call initialize() before billing operations.")
            return null
        }
        return helper
    }

    private fun finishOperation() {
        operationInProgress.set(false)
    }

    private fun cleanup() {
        lifecycleGeneration++
        runCatching { helper?.dispose() }
        helper = null
        initialized = false
        activePublicKey = null
        initializing.set(false)
        finishOperation()
    }

    private fun isCurrent(generation: Long, expectedHelper: IabHelper): Boolean =
        generation == lifecycleGeneration && helper === expectedHelper

    private fun skuToMap(value: SkuDetails): Map<String, Any?> = mapOf(
        "id" to value.sku,
        "type" to normalizeType(value.type),
        "price" to value.price,
        "title" to value.title,
        "description" to value.description,
    )

    private fun purchaseToMap(value: Purchase): Map<String, Any?> = mapOf(
        "productId" to value.sku,
        "token" to value.token,
        "orderId" to value.orderId,
        "payload" to value.developerPayload,
        "packageName" to value.packageName,
        "state" to value.purchaseState,
        "purchaseTime" to value.purchaseTime,
        "rawReceipt" to value.originalJson,
        "signature" to value.signature,
    )

    private fun normalizeType(value: String): String = when (value.lowercase()) {
        IabHelper.ITEM_TYPE_SUBS -> TYPE_SUBS
        else -> TYPE_INAPP
    }

    private fun MethodChannel.Result.iabResultError(value: IabResult, message: String) {
        error(
            MyketErrorMapper.stableCode(value),
            message,
            mapOf("nativeCode" to value.response, "nativeMessage" to value.message),
        )
    }

    private fun MethodChannel.Result.iapError(code: String, message: String) {
        error(code, message, null)
    }

    private fun MethodChannel.Result.throwableError(code: String, message: String, throwable: Throwable) {
        error(
            code,
            message,
            mapOf(
                "nativeMessage" to throwable.message,
                "nativeExceptionType" to throwable.javaClass.name,
            ),
        )
    }

    private fun isPackageInstalled(context: Context, packageName: String): Boolean = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getPackageInfo(packageName, 0)
        }
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    private companion object {
        const val CHANNEL = "dev.iraniap/iran_iap"
        const val MYKET_PACKAGE = "ir.mservices.market"
        const val TYPE_INAPP = "inapp"
        const val TYPE_SUBS = "subs"
    }
}
