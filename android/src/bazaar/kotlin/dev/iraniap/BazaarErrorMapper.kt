package dev.iraniap

import ir.cafebazaar.poolakey.exception.BazaarNotFoundException
import ir.cafebazaar.poolakey.exception.BazaarNotSupportedException
import ir.cafebazaar.poolakey.exception.ConsumeFailedException
import ir.cafebazaar.poolakey.exception.DisconnectException
import ir.cafebazaar.poolakey.exception.DynamicPriceNotSupportedException
import ir.cafebazaar.poolakey.exception.IAPNotSupportedException
import ir.cafebazaar.poolakey.exception.PurchaseHijackedException
import ir.cafebazaar.poolakey.exception.ResultNotOkayException
import ir.cafebazaar.poolakey.exception.SubsNotSupportedException

/** Maps Poolakey exceptions to the stable Dart error taxonomy. */
internal object BazaarErrorMapper {
    fun stableCode(throwable: Throwable): String = when (throwable) {
        is BazaarNotFoundException -> "storeNotInstalled"
        is BazaarNotSupportedException,
        is IAPNotSupportedException -> "storeUnsupported"
        is SubsNotSupportedException -> "subscriptionUnavailable"
        is DynamicPriceNotSupportedException -> "featureUnavailable"
        is PurchaseHijackedException -> "verificationFailed"
        is ResultNotOkayException -> "invalidResponse"
        is DisconnectException -> "notInitialized"
        is ConsumeFailedException -> "platform"
        else -> "platform"
    }
}
