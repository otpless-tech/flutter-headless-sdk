package com.otpless.headlessflutter

import android.content.Context
import android.content.Intent
import androidx.fragment.app.FragmentActivity
import com.otpless.longclaw.tc.OTScopeRequest
import com.otpless.v2.android.sdk.dto.OtplessResponse
import com.otpless.v2.android.sdk.main.OtplessSDK
import com.otpless.v2.android.sdk.utils.OtplessUtils
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener
import io.flutter.plugin.common.PluginRegistry.NewIntentListener
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.lang.ref.WeakReference


/** OtplessFlutterHeadless */
class OtplessFlutterHeadless : FlutterPlugin, MethodCallHandler, ActivityAware, ActivityResultListener, NewIntentListener {
    /// The MethodChannel that will the communication between Flutter and native Android
    ///
    /// This local reference serves to register the plugin with the Flutter Engine and unregister it
    /// when the Flutter Engine is detached from the Activity
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private lateinit var activity: WeakReference<FragmentActivity>
    private var otplessJob: Job? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "otpless_headless_flutter")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
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
                start(call.parseJsonArg())
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

            "setDevLogging" -> {
                val isEnabled = call.argument<Boolean>("isEnabled") ?: false
                debugLog("setting dev logging $isEnabled")
                OtplessSDK.devLogging = isEnabled
            }

            "initTrueCaller" -> {
                val activityContext = activity.get() ?: return kotlin.run { result.success(false) }
                val request = parseOtplessTruecallerRequest(call)
                val isInit = OtplessSDK.initTrueCaller(activityContext, request.first) {
                    OTScopeRequest.ActivityRequest(activityContext, request.second)
                }
                result.success(isInit)
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    private fun onOtplessResponseCallback(otplessResponse: OtplessResponse) {
        channel.invokeMethod("otpless_callback_event", convertHeadlessResponseToJson(otplessResponse).toString())
    }

    private fun start(json: JSONObject) {
        val request = parseJsonToOtplessRequest(json)
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

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = WeakReference(binding.activity as FragmentActivity)
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

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        OtplessSDK.onActivityResult(requestCode, resultCode, data)
        return true
    }
}
