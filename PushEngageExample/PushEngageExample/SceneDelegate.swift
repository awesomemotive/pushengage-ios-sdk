//
//  SceneDelegate.swift
//  PushEngageExample
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UINavigationController(rootViewController: makeRootViewController())
        window.makeKeyAndVisible()
        self.window = window
    }

    private func makeRootViewController() -> UIViewController {
        if DemoPrefs.shared.isConfigured {
            return HomeViewController()
        }
        let settings = SettingsViewController()
        settings.isInitialSetup = true
        return settings
    }
}
