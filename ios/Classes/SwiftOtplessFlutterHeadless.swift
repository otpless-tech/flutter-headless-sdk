import Flutter
import UIKit
import OtplessBM


public class SwiftOtplessFlutterHeadless: NSObject, FlutterPlugin {
    
    private var otplessTask: Task<Void, Never>? = nil
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "otpless_headless_flutter", binaryMessenger: registrar.messenger())
        let instance = SwiftOtplessFlutterHeadless()
        registrar.addMethodCallDelegate(instance, channel: channel)
        ChannelManager.shared.setMethodChannel(channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "start":
            let args = call.arguments as! [String: Any]
            let jsonString = args["arg"] as! String
            let data = jsonString.data(using: .utf8)!
            let arguments: [String: String] = try! JSONSerialization.jsonObject(with: data, options: []) as! [String: String]
            start(withDict: arguments)
            return
        case "initialize":
            guard let viewController = UIApplication.shared.delegate?.window??.rootViewController else {return}
            let args = call.arguments as! [String: Any]
            let appId = args["appId"] as! String
            Otpless.shared.initialise(withAppId: appId, vc: viewController)
            return
        case "setResponseCallback":
            Otpless.shared.setResponseDelegate(self)
            return
        case "commitResponse":
            Otpless.shared.commitOtplessResponse(convertDictionaryToOtplessResponse(call.arguments as? [String: Any]))
            return
        case "cleanup":
            cleanup()
        case "setDevLogging":
            let args = call.arguments as! [String: Any]
            if let isEnabled = args["isEnabled"] as? Bool, isEnabled {
                Otpless.shared.setLoggerDelegate(self)
            }
            break;
        default:
            return
        }
    }
    
    private func start(withDict dict: [String: String]) {
        let otplessRequest = createOtplessRequest(args: dict)
        
        let isOtpVerification = dict["otp"]?.isEmpty == false
        
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
    
    private func createOtplessRequest(args: [String: String]) -> OtplessRequest {
        let otplessRequest = OtplessRequest()
        
        if let phone = args["phone"],
           let countryCode = args["countryCode"] {
            otplessRequest.set(phoneNumber: phone, withCountryCode: countryCode)
        } else if let email = args["email"] {
            otplessRequest.set(email: email)
        } else if let channelType = args["channelType"] {
            otplessRequest.set(channelType: OtplessChannelType.fromString(channelType.uppercased()))
        }
        
        if let otp = args["otp"] {
            otplessRequest.set(otp: otp)
        }
        
        if let deliveryChannel = args["deliveryChannel"] {
            otplessRequest.set(deliveryChannelForTransaction: deliveryChannel.uppercased())
        }
        
        if let otpLength = args["otpLength"] {
            otplessRequest.set(otpLength: otpLength)
        }
        
        if let expiry = args["expiry"] {
            otplessRequest.set(otpExpiry: expiry)
        }
        
        if let tid = args["tid"] {
            otplessRequest.set(tid: tid)
        }
        
        return otplessRequest
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


