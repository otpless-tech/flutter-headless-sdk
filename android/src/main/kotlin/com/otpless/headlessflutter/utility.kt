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
import com.otpless.v2.android.sdk.dto.AuthEvent
import com.otpless.v2.android.sdk.dto.OtplessChannelType
import com.otpless.v2.android.sdk.dto.OtplessRequest
import com.otpless.v2.android.sdk.dto.OtplessResponse
import com.otpless.v2.android.sdk.dto.ResponseTypes
import com.otpless.v2.android.sdk.view.models.OtplessAuthConfig
import io.flutter.plugin.common.MethodCall
import org.json.JSONObject
import java.util.Locale

private const val Tag = "OtplessFlutterHeadless"

/// parse json request into OtplessRequest model class
/// json serialization is not used because of enum parsing (channel) and conversion
internal fun parseJsonToOtplessRequest(json: JSONObject): OtplessRequest {
    val otplessRequest = OtplessRequest()
    // check for phone
    val phone = json.optString("phone")
    if (phone.isNotEmpty()) {
        val countryCode = json.getString("countryCode")
        otplessRequest.setPhoneNumber(number = phone, countryCode = countryCode)
        val otp = json.optString("otp")
        if (otp.isNotEmpty()) {
            otplessRequest.setOtp(otp)
        }
    } else {
        // check for email
        val email = json.optString("email")
        // check for otp in case of phone and email
        if (email.isNotEmpty()) {
            otplessRequest.setEmail(email)
            val otp = json.optString("otp")
            if (otp.isNotEmpty()) {
                otplessRequest.setOtp(otp)
            }
        } else {
            // check for channel type
            val channelType = json.getString("channelType")
            otplessRequest.setChannelType(OtplessChannelType.values().first { it.channelTypeName == channelType })
        }
    }
    json.optString("otpLength").let {
        otplessRequest.setOtpLength(it)
    }
    json.optString("expiry").let {
        otplessRequest.setExpiry(it)
    }

    json.optString("tid").let {
        otplessRequest.setTemplateId(it)
    }

    val dChannelStr: String = json.optString("deliveryChannel")
    otplessRequest.setDeliveryChannel(dChannelStr)
    return otplessRequest
}

internal fun parseToOtplessAuthConfig(json: JSONObject): OtplessAuthConfig {
    val isForeground = json.optBoolean("isForeground", false)
    return OtplessAuthConfig(isForeground, json.optString("otp"), json.optString("tid").takeIf { it.isNotEmpty() })
}

/// convert response map object into otpless response
internal fun convertMapToOtplessResponse(response: Map<String, Any>): OtplessResponse? {
    if (response.isEmpty()) return null
    try {
        val responseType = response["responseType"].toString()
        val responseJson = JSONObject(response["response"] as Map<String, Any>)
        val statusCode = response["statusCode"].toString().softParseStatusCode()
        return OtplessResponse(ResponseTypes.valueOf(responseType), responseJson, statusCode)
    } catch (_: Exception) {
        return null
    }
}

private fun String.softParseStatusCode(): Int {
    if (this.isEmpty()) return -1000
    return try {
        this.toInt()
    } catch (e: NumberFormatException) {
        -1000
    }
}

/// convert otpless response object into json object
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

/// dart enum style is lowerCamelCase and kotlin enum style is UPPER_SNAKE_CASE
/// but alpha strings in both kind of enums are same in order typical for truecaller
/// this method convert string dart enum type into kotlin enum type
/// e.g. openId to OPEN_ID
fun String.fromDartEnumStyleToKotlin(): String {
    return replace(Regex("([a-z])([A-Z])"), "$1_$2").uppercase()
}

/// convert dart kind to enum class into equivalent kotlin class
inline fun <reified T : Enum<T>> safeEnumValueOf(name: String?): T? {
    val kotlinKindName = name?.fromDartEnumStyleToKotlin() ?: return null
    return try {
        enumValueOf<T>(kotlinKindName)
    } catch (ignore: Exception) {
        null
    }
}

/// parse OtplessTruecallerRequest and List<OTScope> form Method Call
/// and return them as pair
internal fun parseOtplessTruecallerRequest(call: MethodCall): Pair<OtplessTruecallerRequest, List<OTScope>> {
    val dartRequest = call.argument<Map<String, Any>>("request") ?: return run {
        Pair(OtplessTruecallerRequest(), listOf(OTScope.PHONE, OTScope.OPEN_ID, OTScope.PROFILE))
    }
    val trueCallerConfig: OtplessTruecallerRequest = dartRequest["config"]?.let {
        if (it is Map<*, Any?>) {
            val map =
                it.mapNotNull { (key, value) -> if (key is String && value != null) key to value else null }
                    .toMap()
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

/// convert map truecaller object into OtplessTruecallerRequest object
internal fun parseTrueCallerConfig(map: Map<String, Any>): OtplessTruecallerRequest {
    return OtplessTruecallerRequest(
        footerType = (map["footerType"] as? String)?.let { safeEnumValueOf<OTFooterType>(it) },
        shape = (map["shape"] as? String)?.let { safeEnumValueOf<OTButtonShape>(it) },
        verifyOption = (map["verifyOption"] as? String)?.let { safeEnumValueOf<OTVerifyOption>(it) },
        heading = (map["heading"] as? String)?.let { safeEnumValueOf<OTHeadingConsent>(it) },
        loginPrefixText = (map["loginPrefixText"] as? String)?.let {
            safeEnumValueOf<OTLoginPrefixText>(
                it
            )
        },
        ctaText = (map["ctaText"] as? String)?.let { safeEnumValueOf<OTCtaText>(it) },
        locale = (map["locale"] as? String)?.let { parseLocale(it) },
        buttonColor = (map["buttonColor"] as? String)?.let { parseHexColor(it) },
        buttonTextColor = (map["buttonTextColor"] as? String)?.let { parseHexColor(it) },
    )
}

/// convert hex string code into int
///@param hex  eg #ddeeaa
internal fun parseHexColor(hex: String) = try {
    Color.parseColor(hex)
} catch (ex: Exception) {
    null
}

/// convert locale string en-US or en_US into locale
internal fun parseLocale(str: String): Locale? = try {
    // locale can be send with dash(-) and underscore(_)
    val list = str.split("-", "_")
    if (list.size == 2) {
        Locale(list[0], list[1])
    } else {
        null
    }
} catch (ex: Exception) {
    null
}

/// parse arg key (json string) from method call into json object
internal fun MethodCall.parseJsonArg(): JSONObject {
    val jsonString = this.argument<String>("arg")
    val jsonObject = if (jsonString != null) {
        try {
            Log.d(Tag, "arg: $jsonString")
            JSONObject(jsonString)
        } catch (ex: Exception) {
            Log.d(Tag, "wrong json object is passed. error ${ex.message}")
            ex.printStackTrace()
            null
        }
    } else {
        Log.d(Tag, "No json object is passed.")
        null
    }
    if (jsonObject == null) {
        throw Exception("json argument not provided")
    }
    return jsonObject
}
