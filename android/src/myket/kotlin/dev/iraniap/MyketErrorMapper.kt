package dev.iraniap

import ir.myket.billingclient.IabHelper
import ir.myket.billingclient.util.IabResult

internal object MyketErrorMapper {
    fun stableCode(result: IabResult): String = when (result.response) {
        IabHelper.BILLING_RESPONSE_RESULT_USER_CANCELED,
        IabHelper.IABHELPER_USER_CANCELLED -> "userCancelled"
        IabHelper.BILLING_RESPONSE_RESULT_BILLING_UNAVAILABLE -> "serviceUnavailable"
        IabHelper.BILLING_RESPONSE_RESULT_ITEM_UNAVAILABLE -> "itemUnavailable"
        IabHelper.BILLING_RESPONSE_RESULT_DEVELOPER_ERROR -> "developerError"
        IabHelper.BILLING_RESPONSE_RESULT_ITEM_ALREADY_OWNED -> "itemAlreadyOwned"
        IabHelper.BILLING_RESPONSE_RESULT_ITEM_NOT_OWNED -> "itemNotOwned"
        IabHelper.IABHELPER_REMOTE_EXCEPTION -> "serviceUnavailable"
        IabHelper.IABHELPER_BAD_RESPONSE,
        IabHelper.IABHELPER_UNKNOWN_PURCHASE_RESPONSE,
        IabHelper.IABHELPER_MISSING_TOKEN -> "invalidResponse"
        IabHelper.IABHELPER_VERIFICATION_FAILED -> "verificationFailed"
        IabHelper.IABHELPER_SUBSCRIPTIONS_NOT_AVAILABLE -> "subscriptionUnavailable"
        IabHelper.IABHELPER_INVALID_CONSUMPTION -> "configuration"
        else -> "platform"
    }

    fun isCancellation(result: IabResult): Boolean =
        result.response == IabHelper.BILLING_RESPONSE_RESULT_USER_CANCELED ||
            result.response == IabHelper.IABHELPER_USER_CANCELLED
}
