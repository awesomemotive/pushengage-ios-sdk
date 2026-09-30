//
//  Utility+App.swift
//  PushEngage
//

import UIKit
import PushEngageExtension

extension Utility {

    /// The current key window, via the scene-based lookup.
    static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    static func loadWKWebView(with url: URL?) {
        if let link = url {
            DispatchQueue.main.async {
                let wkWebView = WKWebViewController(url: link, title: Utility.getApplicationName)
                let nav = UINavigationController(rootViewController: wkWebView)
                keyWindow?.rootViewController?.present(nav, animated: true, completion: nil)
            }
        }
    }

    static func loadWithSafari(url: URL?) {
        guard let link = url else {
            return
        }
        DispatchQueue.main.async {
            if UIApplication.shared.canOpenURL(link) {
                UIApplication.shared.open(link) { (reponse) in
                    PELogger.info(className: String(describing: Utility.self),
                                  message: reponse.description)
                }
            }
        }
    }
}
