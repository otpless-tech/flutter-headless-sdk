//
//  SceneDelegate.swift
//  Runner
//
//  Created by digvijay singh on 19/06/26.
//

import UIKit
import OtplessBM

@available(iOS 13.0, *)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        print("[OtplessExample] SceneDelegate.scene(willConnectTo:) — SceneDelegate is wired in")
        guard let _ = (scene as? UIWindowScene) else { return }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        print("[OtplessExample] SceneDelegate.scene(openURLContexts:) urls=\(URLContexts.map { $0.url })")
        guard let url = URLContexts.first?.url else { return }
        guard Otpless.shared.isOtplessDeeplink(url: url) else { return }
        Task { await Otpless.shared.handleDeeplink(url) }
    }
}


