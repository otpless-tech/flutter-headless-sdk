package com.otpless.headlessflutter


import com.otpless.v2.android.sdk.dto.OtplessResponse
import org.json.JSONObject

internal fun convertHeadlessResponseToJson(otplessResponse: OtplessResponse): JSONObject {
    val jsonObject = JSONObject()
    jsonObject.put("responseType", otplessResponse.responseType)
    jsonObject.put("statusCode", otplessResponse.statusCode)
    jsonObject.put("response", otplessResponse.response)
    return jsonObject
}