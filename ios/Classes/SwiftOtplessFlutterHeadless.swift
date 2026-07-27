import Flutter
import UIKit
import OtplessBM


public class SwiftOtplessFlutterHeadless: NSObject, FlutterPlugin {
    
    private var otplessTask: Task<Void, Never>? = nil
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "otpless_headless_flutter", binaryMessenger: registrar.messenger())
        let instance = SwiftOtplessFlutterHeadless()
        registrar.addMethodCallDelegate(instance, channel: channel)
        Task { @MainActor in
            ChannelManager.shared.setMethodChannel(channel)
        }
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        Task { @MainActor [weak self] in
            guard let self = self else {return}
            self.handleOnMainThread(call, result: result)
        }
    }
    
    @MainActor
    private func handleOnMainThread(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "start":
            let args = call.arguments as! [String: Any]
            let jsonString = args["arg"] as! String
            let data = jsonString.data(using: .utf8)!
            let arguments = (try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]) ?? [:]
            start(withDict: arguments)
            result(nil)
        case "initialize":
            let args = call.arguments as! [String: Any]
            let appId = args["appId"] as! String
            guard let viewController = Self.rootViewController() else {
                result(nil)
                return
            }
            Otpless.shared.initialise(withAppId: appId, vc: viewController)
            result(nil)
        case "setResponseCallback":
            Otpless.shared.setResponseDelegate(self)
            result(nil)
        case "commitResponse":
            Otpless.shared.commitOtplessResponse(convertDictionaryToOtplessResponse(call.arguments as? [String: Any]))
            result(nil)
        case "cleanup":
            cleanup()
            result(nil)
        case "setDevLogging":
            let args = call.arguments as! [String: Any]
            if let isEnabled = args["isEnabled"] as? Bool, isEnabled {
                Otpless.shared.setLoggerDelegate(self)
            }
            result(nil)
        case "isSdkReady":
            result(Otpless.shared.isSdkReady())
        case "setDeviceFingerprintMode":
            let args = call.arguments as! [String: Any]
            let modeStr = (args["mode"] as? String)?.uppercased() ?? "NONE"
            let mode: DeviceFingerprintMode
            switch modeStr {
            case "ASYNC": mode = .ASYNC
            case "SYNC":  mode = .SYNC
            default:      mode = .NONE
            }
            Otpless.shared.setDeviceFingerprintMode(mode)
            result(nil)
        case "setMfaEnabled":
            let args = call.arguments as! [String: Any]
            let enabled = (args["enabled"] as? Bool) ?? false
            Otpless.shared.setMfaEnabled(enabled)
            result(nil)
        case "initSession":
            let args = call.arguments as! [String: Any]
            let appId = args["appId"] as? String ?? ""
            Task {
                await OtplessSessionManager.shared.initialize(appId: appId)
                DispatchQueue.main.async { result(nil) }
            }
        case "getActiveSession":
            Task {
                let state = await OtplessSessionManager.shared.getActiveSession()
                let map: [String: Any?]
                switch state {
                case .active(let jwt): map = ["isActive": true, "jwtToken": jwt]
                case .inactive:        map = ["isActive": false]
                }
                DispatchQueue.main.async { result(map) }
            }
        case "logoutSession":
            Task {
                await OtplessSessionManager.shared.logout()
                DispatchQueue.main.async { result(nil) }
            }
        case "startOnetap":
            let args = call.arguments as! [String: Any]
            let jsonString = args["arg"] as! String
            guard let data = jsonString.data(using: .utf8),
                  let dict = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] else {
                result(false)
                return
            }
            guard let rootVC = Self.rootViewController() else {
                result(false)
                return
            }
            let isForeground = (dict["isForeground"] as? Bool) ?? false
            let otp = dict["otp"] as? String
            let tid = dict["tid"] as? String
            let config = OtplessAuthCofig(isForeground: isForeground, otp: otp, tid: tid)
            Task { @MainActor in
                let ok = await Otpless.shared.startAuth(parent: rootVC, config: config)
                DispatchQueue.main.async { result(ok) }
            }
        case "isWhatsAppInstalled":
            result(false)
        case "initTrueCaller":
            result(false)
        case "startInBackground":
            result(nil)
        case "userAuthEvent":
            let args = (call.arguments as? [String: Any]) ?? [:]
            let eventStr = (args["event"] as? String)?.lowercased() ?? ""
            let fallback = (args["fallback"] as? Bool) ?? false
            let providerTypeStr = (args["providerType"] as? String)?.lowercased() ?? ""
            let event: AuthEvent
            switch eventStr {
            case "authinitiated": event = .AUTH_INITIATED
            case "authsuccess":   event = .AUTH_SUCCESS
            case "authfailed":    event = .AUTH_FAILED
            default:
                result(false)
                return
            }
            let providerType: ProviderType = (providerTypeStr == "otpless") ? .OTPLESS : .CLIENT
            var providerInfo: [String: String] = [:]
            if let raw = args["providerInfo"] as? String,
               let data = raw.data(using: .utf8),
               let dict = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] {
                for (k, v) in dict { providerInfo[k] = "\(v)" }
            }
            Otpless.shared.userAuthEvent(event: event, fallback: fallback, providerType: providerType, providerInfo: providerInfo)
            result(true)
        case "checkSimBindingStatus":
            result(false)
        case "clearSimBinding":
            result(nil)
        case "setSimBindingEnabled":
            result(nil)
        case "closeDialogIfOpen":
            result(nil)
        default:
            return
        }
    }
    
    private func start(withDict dict: [String: Any]) {
        let otplessRequest = createOtplessRequest(args: dict)

        let isOtpVerification = (dict["otp"] as? String)?.isEmpty == false

        if !isOtpVerification {
            // Cancel the existing task if it's not an OTP verification request
            otplessTask?.cancel()
        }

        let newTask = Task(priority: .userInitiated) {
            await Otpless.shared.start(withRequest: otplessRequest)
        }

        if !isOtpVerification {
            otplessTask = newTask
        }
    }
    
    private func convertDictionaryToOtplessResponse(_ dict: [String: Any]?) -> OtplessResponse {
        return OtplessResponse(
            responseType: ResponseTypes(rawValue: dict?["responseType"] as? String ?? "") ?? .FAILED,
            response: dict?["response"] as? [String: Any],
            statusCode: dict?["statusCode"] as? Int ?? -25000
        )
    }
    
    private func cleanup() {
        Otpless.shared.cleanup()
        otplessTask?.cancel()
        otplessTask = nil
    }
    
    private func createOtplessRequest(args: [String: Any]) -> OtplessRequest {
        let otplessRequest = OtplessRequest()

        if let phone = args["phone"] as? String, !phone.isEmpty,
           let countryCode = args["countryCode"] as? String {
            otplessRequest.set(phoneNumber: phone, withCountryCode: countryCode)
        } else if let email = args["email"] as? String, !email.isEmpty {
            otplessRequest.set(email: email)
        } else if let channelType = args["channelType"] as? String, !channelType.isEmpty {
            otplessRequest.set(channelType: OtplessChannelType.fromString(channelType.uppercased()))
        }

        if let otp = args["otp"] as? String, !otp.isEmpty { otplessRequest.set(otp: otp) }
        if let code = args["code"] as? String, !code.isEmpty { otplessRequest.set(code: code) }
        if let deliveryChannel = args["deliveryChannel"] as? String, !deliveryChannel.isEmpty {
            otplessRequest.set(deliveryChannelForTransaction: deliveryChannel.uppercased())
        }
        if let otpLength = args["otpLength"] as? String, !otpLength.isEmpty { otplessRequest.set(otpLength: otpLength) }
        if let expiry = args["expiry"] as? String, !expiry.isEmpty { otplessRequest.set(otpExpiry: expiry) }
        if let tid = args["tid"] as? String, !tid.isEmpty { otplessRequest.set(tid: tid) }
        if let requestId = args["requestId"] as? String, !requestId.isEmpty { otplessRequest.set(fromBackend: requestId) }

        if let extras = args["extras"] as? [String: String], !extras.isEmpty {
            otplessRequest.set(extras: extras)
        }

        if let modeStr = (args["deviceFingerprintMode"] as? String)?.uppercased() {
            switch modeStr {
            case "ASYNC": otplessRequest.set(deviceFingerprintMode: .ASYNC)
            case "SYNC":  otplessRequest.set(deviceFingerprintMode: .SYNC)
            case "NONE":  otplessRequest.set(deviceFingerprintMode: .NONE)
            default: break
            }
        }

        return otplessRequest
    }
    
    @MainActor
    private static func rootViewController() -> UIViewController? {
        // SceneDelegate apps (iOS 13+)
        if let vc = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?.rootViewController {
            return vc
        }

        // AppDelegate-only apps (legacy / no SceneDelegate)
        if let vc = (UIApplication.shared.delegate as? FlutterAppDelegate)?.window?.rootViewController {
            return vc
        }
        return UIApplication.shared.delegate?.window??.rootViewController
    }

    static func filterParamsCondition(_ call: FlutterMethodCall, on onHaving: ([String: Any]) -> Void, off onNotHaving: () -> Void) {
        if let args = call.arguments as? [String: Any] {
            if let jsonString = args["arg"] as? String {
                if let params = convertToDictionary(text: jsonString) {
                    onHaving(params)
                    return
                }
            }
        }
        onNotHaving()
    }
    
    static func convertToDictionary(text: String) -> [String: Any]? {
        if let data = text.data(using: .utf8) {
            do {
                return try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            } catch {
                print(error.localizedDescription)
            }
        }
        return nil
    }
}

extension SwiftOtplessFlutterHeadless: OtplessResponseDelegate {
    public func onResponse(_ response: OtplessBM.OtplessResponse) {
        let flutterResponse: [String: Any?] = [
            "statusCode": response.statusCode,
            "responseType": response.responseType.rawValue,
            "response": response.response
        ]
        let jsonData = try? JSONSerialization.data(withJSONObject: flutterResponse, options: [])
        guard let jsonData else {
            print("Failed to parse JSON data")
            return
        }
        ChannelManager.shared.invokeMethod(method: "otpless_callback_event", arguments: String(data: jsonData, encoding: .utf8))
    }
}

extension SwiftOtplessFlutterHeadless: OtplessLoggerDelegate {
    public func log(message: String, type: OtplessBM.LogType) {
        print("Otpless Log of type : \(type)\n\n\(message)")
    }
}

@MainActor
class ChannelManager {
    static let shared = ChannelManager()
    
    private var methodChannel: FlutterMethodChannel?
    
    private init() {}
    
    func setMethodChannel(_ channel: FlutterMethodChannel) {
        methodChannel = channel
    }
    
    func invokeMethod(method: String, arguments: Any?) {
        methodChannel?.invokeMethod(method, arguments: arguments)
    }
}


