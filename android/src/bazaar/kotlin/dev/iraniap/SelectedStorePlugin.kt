package dev.iraniap

import androidx.activity.result.ActivityResultRegistryOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import ir.cafebazaar.poolakey.Connection
import ir.cafebazaar.poolakey.Payment
import ir.cafebazaar.poolakey.config.PaymentConfiguration
import ir.cafebazaar.poolakey.config.SecurityCheck
import ir.cafebazaar.poolakey.entity.PurchaseInfo
import ir.cafebazaar.poolakey.entity.PurchaseState
import ir.cafebazaar.poolakey.entity.SkuDetails
import ir.cafebazaar.poolakey.request.PurchaseRequest
import java.util.concurrent.atomic.AtomicBoolean

internal class SelectedStorePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private var applicationContext: android.content.Context? = null
    private var activity: android.app.Activity? = null
    private var payment: Payment? = null
    private var connection: Connection? = null
    private var initialized = false
    private var activeConfig: NativeConfig? = null
    private val operationInProgress = AtomicBoolean(false)
    private val initializing = AtomicBoolean(false)
    @Volatile private var activeOperationResult: MethodChannel.Result? = null
    @Volatile private var lifecycleGeneration = 0L

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        cleanup()
        channel.setMethodCallHandler(null)
        applicationContext = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
        val currentPayment = payment
        if (operationInProgress.get() && currentPayment != null) {
            invalidatePayment(currentPayment, notifyActiveOperation = true)
        }
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "selectedStore" -> result.success("bazaar")
            "initialize" -> try {
                initialize(call, result)
            } catch (throwable: Throwable) {
                cleanup()
                result.throwableError("Unexpected Bazaar initialization failure.", throwable)
            }
            "queryProducts" -> withOperation(result) { queryProducts(call, it) }
            "purchase" -> withOperation(result) { purchase(call, it) }
            "queryPurchases" -> withOperation(result) { queryPurchases(call, it) }
            "consume" -> withOperation(result) { consume(call, it) }
            "dispose" -> {
                if (initializing.get() || operationInProgress.get()) {
                    result.iapError(
                        "operationInProgress",
                        "Cannot dispose Bazaar billing while an operation is in progress.",
                    )
                } else {
                    cleanup()
                    result.success(null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun initialize(call: MethodCall, result: MethodChannel.Result) {
        val securityMode = call.argument<String>("securityMode") ?: "serverVerification"
        val rsaPublicKey = call.argument<String>("rsaPublicKey")?.takeIf { it.isNotBlank() }
        val supportSubscriptions = call.argument<Boolean>("supportSubscriptions") ?: true
        val requestedConfig = NativeConfig(securityMode, rsaPublicKey, supportSubscriptions)
        if (initialized) {
            if (activeConfig != requestedConfig) {
                result.iapError("configuration", "Bazaar billing is already initialized with different configuration.")
            } else {
                result.success(
                    mapOf(
                        "supportsSubscriptions" to activeConfig!!.supportSubscriptions,
                        "supportsConsumption" to true,
                        "supportsDynamicPricing" to true,
                    ),
                )
            }
            return
        }
        val context = applicationContext ?: run {
            result.iapError("platform", "Plugin is not attached to an Android context.")
            return
        }
        val securityCheck = when (securityMode) {
            "serverVerification" -> SecurityCheck.Disable
            "localVerification" -> {
                if (rsaPublicKey == null) {
                    result.iapError("configuration", "rsaPublicKey is required for local verification.")
                    return
                }
                SecurityCheck.Enable(rsaPublicKey)
            }
            else -> {
                result.iapError("configuration", "Unknown Bazaar security mode: $securityMode")
                return
            }
        }
        if (!initializing.compareAndSet(false, true)) {
            result.iapError("operationInProgress", "Bazaar billing initialization is already in progress.")
            return
        }
        val generation = lifecycleGeneration
        val newPayment = Payment(
            context,
            PaymentConfiguration(
                localSecurityCheck = securityCheck,
                shouldSupportSubscription = supportSubscriptions,
            ),
        )
        payment = newPayment
        val completed = AtomicBoolean(false)
        val newConnection = newPayment.connect {
            connectionSucceed {
                if (isCurrent(generation, newPayment)) {
                    initialized = true
                    activeConfig = requestedConfig
                    initializing.set(false)
                    if (completed.compareAndSet(false, true)) {
                        result.success(
                            mapOf(
                                "supportsSubscriptions" to supportSubscriptions,
                                "supportsConsumption" to true,
                                "supportsDynamicPricing" to true,
                            ),
                        )
                    }
                }
            }
            connectionFailed { throwable ->
                if (isCurrent(generation, newPayment)) {
                    if (completed.compareAndSet(false, true)) {
                        result.throwableError(
                            BazaarErrorMapper.stableCode(throwable),
                            "Could not connect to Bazaar billing.",
                            throwable,
                        )
                    }
                    invalidatePayment(newPayment, notifyActiveOperation = false)
                }
            }
            disconnected {
                if (isCurrent(generation, newPayment)) {
                    if (initializing.get() && completed.compareAndSet(false, true)) {
                        result.iapError("serviceUnavailable", "Bazaar billing disconnected during initialization.")
                    }
                    invalidatePayment(newPayment, notifyActiveOperation = true)
                }
            }
        }
        if (isCurrent(generation, newPayment)) {
            connection = newConnection
        } else {
            runCatching { newConnection.disconnect() }
        }
    }

    private fun queryProducts(call: MethodCall, result: MethodChannel.Result) {
        val billing = requireReady(result) ?: return finishOperation()
        val ids = call.argument<List<String>>("productIds").orEmpty()
        val type = call.argument<String>("type")
        val generation = lifecycleGeneration
        val callback: ir.cafebazaar.poolakey.callback.GetSkuDetailsCallback.() -> Unit = {
            getSkuDetailsSucceed { details ->
                if (isCurrent(generation, billing)) {
                    result.success(details.map(::skuToMap))
                    finishOperation()
                }
            }
            getSkuDetailsFailed { throwable ->
                if (isCurrent(generation, billing)) {
                    result.throwableError("Bazaar product query failed.", throwable)
                    finishOperation()
                }
            }
        }
        when (type) {
            TYPE_INAPP -> billing.getInAppSkuDetails(ids, callback)
            TYPE_SUBS -> billing.getSubscriptionSkuDetails(ids, callback)
            else -> {
                result.iapError("configuration", "Unsupported product type: $type")
                finishOperation()
            }
        }
    }

    private fun purchase(call: MethodCall, result: MethodChannel.Result) {
        val billing = requireReady(result) ?: return finishOperation()
        val registryOwner = activity as? ActivityResultRegistryOwner
        if (registryOwner == null) {
            result.iapError(
                "activityUnavailable",
                "Bazaar purchases require an ActivityResultRegistryOwner. " +
                    "Use FlutterFragmentActivity or another compatible host activity.",
            )
            finishOperation()
            return
        }
        val productId = call.argument<String>("productId")?.takeIf { it.isNotBlank() }
        if (productId == null) {
            result.iapError("configuration", "productId must not be blank.")
            finishOperation()
            return
        }
        val generation = lifecycleGeneration
        val request = PurchaseRequest(
            productId = productId,
            payload = call.argument<String>("payload"),
            dynamicPriceToken = call.argument<String>("dynamicPriceToken"),
        )
        val callback: ir.cafebazaar.poolakey.callback.PurchaseCallback.() -> Unit = {
            purchaseSucceed { info ->
                if (isCurrent(generation, billing)) {
                    result.success(mapOf("status" to "completed", "purchase" to purchaseToMap(info)))
                    finishOperation()
                }
            }
            purchaseCanceled {
                if (isCurrent(generation, billing)) {
                    result.success(mapOf("status" to "cancelled"))
                    finishOperation()
                }
            }
            purchaseFailed { throwable ->
                if (isCurrent(generation, billing)) {
                    result.throwableError("Bazaar purchase failed.", throwable)
                    finishOperation()
                }
            }
            failedToBeginFlow { throwable ->
                if (isCurrent(generation, billing)) {
                    result.throwableError("Bazaar purchase flow could not begin.", throwable)
                    finishOperation()
                }
            }
        }
        when (call.argument<String>("type")) {
            TYPE_INAPP -> billing.purchaseProduct(registryOwner.activityResultRegistry, request, callback)
            TYPE_SUBS -> billing.subscribeProduct(registryOwner.activityResultRegistry, request, callback)
            else -> {
                result.iapError("configuration", "Unsupported purchase type.")
                finishOperation()
            }
        }
    }

    private fun queryPurchases(call: MethodCall, result: MethodChannel.Result) {
        val billing = requireReady(result) ?: return finishOperation()
        val generation = lifecycleGeneration
        val callback: ir.cafebazaar.poolakey.callback.PurchaseQueryCallback.() -> Unit = {
            querySucceed { purchases ->
                if (isCurrent(generation, billing)) {
                    result.success(purchases.map(::purchaseToMap))
                    finishOperation()
                }
            }
            queryFailed { throwable ->
                if (isCurrent(generation, billing)) {
                    result.throwableError("Bazaar owned-purchase query failed.", throwable)
                    finishOperation()
                }
            }
        }
        when (call.argument<String>("type")) {
            TYPE_INAPP -> billing.getPurchasedProducts(callback)
            TYPE_SUBS -> billing.getSubscribedProducts(callback)
            else -> {
                result.iapError("configuration", "Unsupported purchase type.")
                finishOperation()
            }
        }
    }

    private fun consume(call: MethodCall, result: MethodChannel.Result) {
        val billing = requireReady(result) ?: return finishOperation()
        val token = call.argument<String>("token")?.takeIf { it.isNotBlank() }
        if (token == null) {
            result.iapError("configuration", "Purchase token must not be blank.")
            finishOperation()
            return
        }
        val generation = lifecycleGeneration
        billing.consumeProduct(token) {
            consumeSucceed {
                if (isCurrent(generation, billing)) {
                    result.success(null)
                    finishOperation()
                }
            }
            consumeFailed { throwable ->
                if (isCurrent(generation, billing)) {
                    result.throwableError("Bazaar consumption failed.", throwable)
                    finishOperation()
                }
            }
        }
    }

    private fun withOperation(result: MethodChannel.Result, block: (MethodChannel.Result) -> Unit) {
        if (!operationInProgress.compareAndSet(false, true)) {
            result.iapError("operationInProgress", "Another billing operation is already in progress.")
            return
        }
        activeOperationResult = result
        try {
            block(result)
        } catch (throwable: Throwable) {
            val stableCode = BazaarErrorMapper.stableCode(throwable)
            if (stableCode == "notInitialized") {
                cleanup()
            } else {
                finishOperation()
            }
            result.throwableError(stableCode, "Unexpected Bazaar billing failure.", throwable)
        }
    }

    private fun requireReady(result: MethodChannel.Result): Payment? {
        if (!initialized || payment == null) {
            result.iapError("notInitialized", "Call initialize() before billing operations.")
            return null
        }
        return payment
    }

    private fun finishOperation() {
        activeOperationResult = null
        operationInProgress.set(false)
    }

    private fun isCurrent(generation: Long, expectedPayment: Payment): Boolean =
        generation == lifecycleGeneration && payment === expectedPayment

    private fun invalidatePayment(expectedPayment: Payment, notifyActiveOperation: Boolean) {
        if (payment !== expectedPayment) return

        lifecycleGeneration++
        val oldConnection = connection
        connection = null
        payment = null
        initialized = false
        activeConfig = null
        initializing.set(false)

        val pendingResult = activeOperationResult
        finishOperation()
        runCatching { oldConnection?.disconnect() }

        if (notifyActiveOperation) {
            pendingResult?.iapError(
                "notInitialized",
                "Bazaar billing disconnected; call initialize() again before retrying the operation.",
            )
        }
    }

    private fun cleanup() {
        lifecycleGeneration++
        val oldConnection = connection
        connection = null
        payment = null
        initialized = false
        activeConfig = null
        initializing.set(false)
        finishOperation()
        runCatching { oldConnection?.disconnect() }
    }

    private fun skuToMap(value: SkuDetails): Map<String, Any?> = mapOf(
        "id" to value.sku,
        "type" to normalizeType(value.type),
        "price" to value.price,
        "title" to value.title,
        "description" to value.description,
    )

    private fun purchaseToMap(value: PurchaseInfo): Map<String, Any?> = mapOf(
        "productId" to value.productId,
        "token" to value.purchaseToken,
        "orderId" to value.orderId,
        "payload" to value.payload,
        "packageName" to value.packageName,
        "state" to if (value.purchaseState == PurchaseState.PURCHASED) "purchased" else "refunded",
        "purchaseTime" to value.purchaseTime,
        "rawReceipt" to value.originalJson,
        "signature" to value.dataSignature,
    )

    private fun normalizeType(value: String): String = when (value.lowercase()) {
        "subs", "subscription" -> TYPE_SUBS
        else -> TYPE_INAPP
    }

    private fun MethodChannel.Result.iapError(code: String, message: String, details: Map<String, Any?>? = null) {
        error(code, message, details)
    }

    private fun MethodChannel.Result.throwableError(message: String, throwable: Throwable) {
        throwableError(BazaarErrorMapper.stableCode(throwable), message, throwable)
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

    private data class NativeConfig(
        val securityMode: String,
        val rsaPublicKey: String?,
        val supportSubscriptions: Boolean,
    )

    private companion object {
        const val CHANNEL = "dev.iraniap/iran_iap"
        const val TYPE_INAPP = "inapp"
        const val TYPE_SUBS = "subs"
    }
}
