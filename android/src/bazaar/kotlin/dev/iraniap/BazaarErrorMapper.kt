package dev.iraniap

/** Maps Poolakey exceptions to the stable Dart error taxonomy. */
internal object BazaarErrorMapper {
    fun stableCode(throwable: Throwable): String = when (throwable.javaClass.simpleName) {
        "BazaarNotFoundException" -> "storeNotInstalled"
        "BazaarNotSupportedException",
        "IAPNotSupportedException" -> "storeUnsupported"
        "SubsNotSupportedException" -> "subscriptionUnavailable"
        "DynamicPriceNotSupportedException" -> "featureUnavailable"
        "PurchaseHijackedException" -> "verificationFailed"
        "ResultNotOkayException" -> "invalidResponse"
        "DisconnectException" -> "notInitialized"
        "ConsumeFailedException" -> "platform"
        else -> "platform"
    }
}
