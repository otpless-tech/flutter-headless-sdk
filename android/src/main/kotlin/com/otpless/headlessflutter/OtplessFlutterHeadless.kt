package com.otpless.headlessflutter

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.lifecycleScope
import com.otpless.longclaw.tc.OTScopeRequest
import com.otpless.v2.android.sdk.dto.AuthEvent
import com.otpless.v2.android.sdk.dto.OtplessResponse
import com.otpless.v2.android.sdk.dto.ProviderType
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
                result.success(null)
                start(call.parseJsonArg())
            }

            "initialize" -> {
                val appId = call.argument<String>("appId") ?: ""
                val loginUri = call.argument<String>("loginUri")

                val mActivity = activity.get() ?: return run {
                    result.error("0", "init called before activity is attached", null)
                }
                result.success(null)
                mActivity.lifecycleScope.launch(Dispatchers.IO) {
                    OtplessSDK.initialize(appId = appId, activity = mActivity, loginUri = loginUri, this@OtplessFlutterHeadless::onOtplessResponseCallback)
                }
            }

            "setResponseCallback" -> {
                result.success(null)
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
                activityContext.lifecycleScope.launch(Dispatchers.IO) {
                    val request = parseOtplessTruecallerRequest(call)
                    val isInit = try {
                        OtplessSDK.initTrueCaller(activityContext, request.first) {
                            OTScopeRequest.ActivityRequest(activityContext, request.second)
                        }
                    } catch (ex: Exception) {
                        // log the exception to event
                        OtplessSDK.userAuthEvent(
                            AuthEvent.AUTH_FAILED, false,
                            ProviderType.OTPLESS, mapOf(
                                "error" to "truecaller_init_failed",
                                "errorMessage" to (ex.message ?: "Something went wrong on truecaller init")
                            )
                        )
                        false
                    }
                    result.success(isInit)
                }
            }

            "isSdkReady" -> {
                result.success(OtplessSDK.isSdkReady)
            }

            "startBackground" -> {
                startBackground(call.parseJsonArg(), result)
            }

            "closeDialogIfOpen" -> {
                OtplessSDK.closeDialogIfOpen()
            }

            "userAuthEvent" -> sendUserAuthEvent(call, result)

            else -> {
                result.notImplemented()
            }
        }
    }

    private fun onOtplessResponseCallback(otplessResponse: OtplessResponse) {
        channel.invokeMethod("otpless_callback_event", convertHeadlessResponseToJson(otplessResponse).toString())
    }

    private fun start(json: JSONObject) {
        val fa = activity.get() ?: return
        val request = parseJsonToOtplessRequest(json)
        if (request.hasOtp()) {
            otplessJob = fa.lifecycleScope.launch(Dispatchers.IO) {
                OtplessSDK.start(request = request, this@OtplessFlutterHeadless::onOtplessResponseCallback)
            }
        } else {
            otplessJob?.cancel()
            otplessJob = fa.lifecycleScope.launch(Dispatchers.IO) {
                OtplessSDK.start(request = request, this@OtplessFlutterHeadless::onOtplessResponseCallback)
            }
        }
    }

    private fun startBackground(json: JSONObject, result: Result) {
        otplessJob?.cancel()
        activity.get()?.let { activity ->
            otplessJob = activity.lifecycleScope.launch(Dispatchers.IO) {
                result.success(OtplessSDK.start(parseToOtplessAuthConfig(json)))
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

    private fun sendUserAuthEvent(call: MethodCall, result: Result) {
        val event = safeEnumValueOf<AuthEvent>(call.argument<String>("event"))
        val fallback = call.argument<Boolean>("fallback")
        val providerType = safeEnumValueOf<ProviderType>(call.argument<String>("providerType"))
        if (event == null || fallback == null || providerType == null) {
            result.success(false)
            return
        }
        val providerInfo: Map<String, String> = call.argument<String>("providerInfo")?.let { str ->
            val json = try {
                JSONObject(str)
            } catch (_: Exception) {
                JSONObject()
            }
            val info = mutableMapOf<String, String>()
            val keySet = json.keys()
            for (key in keySet) {
                val value = json.optString(key)
                if (value.isEmpty()) continue
                info[key] = value
            }
            info
        } ?: emptyMap()
        OtplessSDK.userAuthEvent(event, fallback, providerType, providerInfo)
        result.success(true)
    }
}
