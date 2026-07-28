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
import com.otpless.v2.android.sdk.session.OtplessSessionManager
import com.otpless.v2.android.sdk.session.OtplessSessionState
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
                        val providerInfo = mapOf(
                            "error" to "truecaller_init_failed",
                            "errorMessage" to (ex.message ?: "Something went wrong on truecaller init")
                        )
                        OtplessSDK.userAuthEvent(AuthEvent.AUTH_FAILED, false, ProviderType.OTPLESS, providerInfo)
                        false
                    }
                    result.success(isInit)
                }
            }

            "isSdkReady" -> {
                result.success(OtplessSDK.isSdkReady)
            }

            "startOnetap" -> {
                startOnetap(call.parseJsonArg(), result)
            }

            "startInBackground" -> {
                result.success(null)
                startInBackground(call.parseJsonArg())
            }

            "setMfaEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                OtplessSDK.isMfaEnabled = enabled
                result.success(null)
            }

            "initSession" -> {
                val appId = call.argument<String>("appId")
                if (appId.isNullOrEmpty()) {
                    result.error("0", "appId is required for initSession", null)
                    return
                }
                val mActivity = activity.get() ?: return run {
                    result.error("0", "initSession called before activity is attached", null)
                }
                mActivity.lifecycleScope.launch(Dispatchers.IO) {
                    OtplessSessionManager.init(context, appId)
                    result.success(null)
                }
            }

            "getActiveSession" -> {
                val mActivity = activity.get() ?: return run {
                    result.success(mapOf("isActive" to false))
                }
                mActivity.lifecycleScope.launch(Dispatchers.IO) {
                    val state = OtplessSessionManager.getActiveSession()
                    val map: Map<String, Any?> = when (state) {
                        is OtplessSessionState.Active -> mapOf("isActive" to true, "jwtToken" to state.jwtToken)
                        is OtplessSessionState.Inactive -> mapOf("isActive" to false)
                    }
                    result.success(map)
                }
            }

            "logoutSession" -> {
                val mActivity = activity.get() ?: return run { result.success(null) }
                mActivity.lifecycleScope.launch(Dispatchers.IO) {
                    OtplessSessionManager.logout()
                    result.success(null)
                }
            }

            "checkSimBindingStatus" -> {
                val mActivity = activity.get() ?: return run { result.success(false) }
                mActivity.lifecycleScope.launch(Dispatchers.IO) {
                    result.success(OtplessSDK.checkSimBindingStatus(context))
                }
            }

            "clearSimBinding" -> {
                val mActivity = activity.get() ?: return run { result.success(null) }
                mActivity.lifecycleScope.launch(Dispatchers.IO) {
                    OtplessSDK.clearSimBinding(context)
                    result.success(null)
                }
            }

            "setSimBindingEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                OtplessSDK.isSimBindingEnabled = enabled
                result.success(null)
            }

            "closeDialogIfOpen" -> {
                OtplessSDK.closeDialogIfOpen()
                result.success(null)
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
        val isOtpVerification = json.optString("otp").isNotEmpty()
        if (!isOtpVerification) {
            otplessJob?.cancel()
        }
        val newJob = fa.lifecycleScope.launch(Dispatchers.IO) {
            OtplessSDK.start(request = request, this@OtplessFlutterHeadless::onOtplessResponseCallback)
        }
        if (!isOtpVerification) {
            otplessJob = newJob
        }
    }

    private fun startInBackground(json: JSONObject) {
        val fa = activity.get() ?: return
        val request = parseJsonToOtplessRequest(json)
        otplessJob?.cancel()
        otplessJob = fa.lifecycleScope.launch(Dispatchers.IO) {
            OtplessSDK.startInBackground(request = request, this@OtplessFlutterHeadless::onOtplessResponseCallback)
        }
    }

    private fun startOnetap(json: JSONObject, result: Result) {
        otplessJob?.cancel()
        val fa = activity.get() ?: return run { result.success(false) }
        otplessJob = fa.lifecycleScope.launch(Dispatchers.IO) {
            val config = parseToOtplessAuthConfig(json)
            result.success(OtplessSDK.start(config))
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
        activity.get()?.let { activity ->
            activity.lifecycleScope.launch(Dispatchers.IO) {
                OtplessSDK.onNewIntent(intent)
            }
        }
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
