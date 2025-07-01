package com.otpless.headlessflutter


import android.graphics.Color
import android.util.Log
import com.otpless.longclaw.tc.OTButtonShape
import com.otpless.longclaw.tc.OTCtaText
import com.otpless.longclaw.tc.OTFooterType
import com.otpless.longclaw.tc.OTHeadingConsent
import com.otpless.longclaw.tc.OTLoginPrefixText
import com.otpless.longclaw.tc.OTScope
import com.otpless.longclaw.tc.OTVerifyOption
import com.otpless.longclaw.tc.OtplessTruecallerRequest
import com.otpless.v2.android.sdk.dto.OtplessResponse
import io.flutter.plugin.common.MethodCall
import org.json.JSONObject
import java.util.Locale

internal fun convertHeadlessResponseToJson(otplessResponse: OtplessResponse): JSONObject {
    val jsonObject = JSONObject()
    jsonObject.put("responseType", otplessResponse.responseType)
    jsonObject.put("statusCode", otplessResponse.statusCode)
    jsonObject.put("response", otplessResponse.response)
    return jsonObject
}

internal fun debugLog(message: String) {
    Log.d("HeadlessFlutter", message)
}

fun String.fromDartEnumStyleToKotlin(): String {
    return replace(Regex("([a-z])([A-Z])"), "$1_$2").uppercase()
}

inline fun <reified T : Enum<T>> safeEnumValueOf(name: String?): T? {
    val kotlinKindName = name?.fromDartEnumStyleToKotlin() ?: return null
    return try {
        enumValueOf<T>(kotlinKindName)
    } catch (ignore: Exception) {
        null
    }
}


internal fun parseOtplessTruecallerRequest(call: MethodCall): Pair<OtplessTruecallerRequest, List<OTScope>> {
    val dartRequest = call.argument<Map<String, Any>>("request") ?: return run {
        Pair(OtplessTruecallerRequest(), listOf(OTScope.PHONE, OTScope.OPEN_ID, OTScope.PROFILE))
    }
    val trueCallerConfig: OtplessTruecallerRequest = dartRequest["config"]?.let {
        if (it is Map<*, Any?>) {
            val map = it.mapNotNull { (key, value) -> if (key is String && value != null) key to value else null }.toMap()
            parseTrueCallerConfig(map)
        } else OtplessTruecallerRequest()
    } ?: OtplessTruecallerRequest()
    val scopes: List<OTScope> = dartRequest["scopes"]?.let {
        if (it is List<*>) {
            val sc = mutableListOf<OTScope>()
            for (each in it) {
                if (each !is String) continue
                val scope = safeEnumValueOf<OTScope>(each) ?: continue
                sc.add(scope)
            }
            sc
        } else {
            listOf(OTScope.PHONE, OTScope.OPEN_ID, OTScope.PROFILE)
        }
    } ?: listOf(OTScope.PHONE, OTScope.OPEN_ID, OTScope.PROFILE)
    return Pair(trueCallerConfig, scopes)
}

fun parseTrueCallerConfig(map: Map<String, Any>): OtplessTruecallerRequest {
    return OtplessTruecallerRequest(
        footerType = (map["footerType"] as? String)?.let { safeEnumValueOf<OTFooterType>(it) },
        shape = (map["shape"] as? String)?.let { safeEnumValueOf<OTButtonShape>(it) },
        verifyOption = (map["verifyOption"] as? String)?.let { safeEnumValueOf<OTVerifyOption>(it) },
        heading = (map["heading"] as? String)?.let { safeEnumValueOf<OTHeadingConsent>(it) },
        loginPrefixText = (map["loginPrefixText"] as? String)?.let { safeEnumValueOf<OTLoginPrefixText>(it) },
        ctaText = (map["ctaText"] as? String)?.let { safeEnumValueOf<OTCtaText>(it) },
        locale = (map["locale"] as? String)?.let { parseLocale(it) },
        buttonColor = (map["buttonColor"] as? String)?.let { parseHexColor(it) },
        buttonTextColor = (map["buttonTextColor"] as? String)?.let { parseHexColor(it) },
    ).also {
        debugLog("converting: $it")
    }
}

internal fun parseHexColor(hex: String) = try {
    Color.parseColor(hex)
} catch (ex: Exception) {
    null
}

internal fun parseLocale(str: String): Locale? = try {
    val list = str.split("-")
    Locale(list[0], list[1])
} catch (ex: Exception) {
    null
}