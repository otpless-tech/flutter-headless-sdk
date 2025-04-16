package com.otpless.headlessflutter

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.annotation.NonNull
import com.otpless.v2.android.sdk.dto.OtplessChannelType
import com.otpless.v2.android.sdk.dto.OtplessRequest
import com.otpless.v2.android.sdk.dto.OtplessResponse
import com.otpless.v2.android.sdk.dto.ResponseTypes
import com.otpless.v2.android.sdk.main.OtplessSDK
import com.otpless.v2.android.sdk.utils.OtplessUtils
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener
import io.flutter.plugin.common.PluginRegistry.NewIntentListener
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.lang.ref.WeakReference
import io.flutter.plugin.common.MethodChannel.Result



/** OtplessFlutterHeadless */
class OtplessFlutterHeadless: FlutterPlugin, MethodCallHandler, ActivityAware, ActivityResultListener, NewIntentListener {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var channel : MethodChannel
  private lateinit var context: Context
  private lateinit var activity: WeakReference<Activity>
  private var otplessJob: Job? = null

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "otpless_headless_flutter")
    channel.setMethodCallHandler(this)
    context = flutterPluginBinding.applicationContext
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    // safe check
    fun parseJsonArg(): JSONObject {
      val jsonString = call.argument<String>("arg")
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
    when (call.method) {
      "isWhatsAppInstalled" -> {
        activity.get()?.let {
          result.success(OtplessUtils.isWhatsAppInstalled(it))
        } ?: kotlin.run {
          result.success(false)
        }
      }

      "start" -> {
        result.success("")
        start(parseJsonArg())
      }

      "initialize" -> {
        val appId = call.argument<String>("appId") ?: ""
        val loginUri = call.argument<String>("loginUri")
        result.success("")
        val mActivity = activity.get() ?: return
        OtplessSDK.initialize(appId = appId, activity = mActivity, loginUri = loginUri)
      }

      "setResponseCallback" -> {
        result.success("")
        OtplessSDK.setResponseCallback(this::onOtplessResponseCallback)
      }

      "commitResponse" -> {
        val response = call.argument<Map<String, Any>>("response") ?: emptyMap()
        val otplessResponse = convertMapToOtplessResponse(response)
        OtplessSDK.commit(otplessResponse)
      }

      "cleanup" -> {
        otplessJob?.cancel()
        OtplessSDK.cleanup()
      }

      else -> {
        result.notImplemented()
      }
    }
  }

  private fun convertMapToOtplessResponse(response: Map<String, Any>): OtplessResponse? {
    if (response.isEmpty()) return null
    try {
      val responseType = response["responseType"].toString()
      val responseJson =  JSONObject(response["response"] as Map<String, Any>)
      val statusCode = response["statusCode"].toString().softParseStatusCode()

      return OtplessResponse(
        ResponseTypes.valueOf(responseType),
        responseJson,
       statusCode
      )
    } catch (_: Exception) {
      return null
    }
  }

  private fun onOtplessResponseCallback(otplessResponse: OtplessResponse) {
    channel.invokeMethod("otpless_callback_event", convertHeadlessResponseToJson(otplessResponse).toString())
  }

  private fun start(json: JSONObject) {
    val request = parseRequest(json)

    if (request.hasOtp()) {
      otplessJob = CoroutineScope(Dispatchers.IO).launch {
        OtplessSDK.start(request = request, this@OtplessFlutterHeadless::onOtplessResponseCallback)
      }
    } else {
      otplessJob?.cancel()
      otplessJob = CoroutineScope(Dispatchers.IO).launch {
        OtplessSDK.start(request = request, this@OtplessFlutterHeadless::onOtplessResponseCallback)
      }
    }
  }

  private fun parseRequest(json: JSONObject): OtplessRequest {
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
        otplessRequest.setChannelType(OtplessChannelType.valueOf(channelType))
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

  private fun String.softParseStatusCode() : Int {
    if (this.isEmpty()) return -1000
    return try {
      this.toInt()
    } catch (e: NumberFormatException) {
      -1000
    }
  }


  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = WeakReference(binding.activity)
    binding.addActivityResultListener(this)
    binding.addOnNewIntentListener(this)
  }

  override fun onNewIntent(intent: Intent): Boolean {
    OtplessSDK.onNewIntentAsync(intent)
    return true
  }

  override fun onDetachedFromActivityForConfigChanges() {
    return
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    return
  }

  override fun onDetachedFromActivity() {
    return
  }

  companion object {
    private const val Tag = "OtplessFlutterHeadless"
  }

  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
    OtplessSDK.onActivityResult(requestCode, resultCode, data)
    return true
  }

}
