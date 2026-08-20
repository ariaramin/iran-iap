package dev.iraniap

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal fun openPaymentUrl(
    activity: Activity?,
    call: MethodCall,
    result: MethodChannel.Result,
) {
    if (activity == null) {
        result.error(
            "activityUnavailable",
            "A foreground Android Activity is required to open a payment URL.",
            null,
        )
        return
    }
    val paymentUrl = call.argument<String>("paymentUrl")?.trim()
    val paymentUri = paymentUrl?.let(Uri::parse)
    if (
        paymentUrl.isNullOrEmpty() ||
        paymentUri == null ||
        paymentUri.scheme?.lowercase() != "https" ||
        paymentUri.host.isNullOrEmpty() ||
        !paymentUri.userInfo.isNullOrEmpty()
    ) {
        result.error(
            "configuration",
            "paymentUrl must be an HTTPS URL without embedded credentials.",
            null,
        )
        return
    }
    val intent = Intent(Intent.ACTION_VIEW, paymentUri)
        .addCategory(Intent.CATEGORY_BROWSABLE)
    if (intent.resolveActivity(activity.packageManager) == null) {
        result.error(
            "featureUnavailable",
            "No Android application can open the payment URL.",
            null,
        )
        return
    }
    runCatching { activity.startActivity(intent) }.fold(
        onSuccess = { result.success(null) },
        onFailure = {
            result.error("platform", "Could not open the payment URL.", null)
        },
    )
}
