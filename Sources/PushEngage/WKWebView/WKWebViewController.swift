//
//  WKWebView.swift
//  PushEngage
//
//  Created by Abhishek on 11/03/21.
//

import UIKit
import WebKit

class WKWebViewController: UIViewController {
    
    private lazy var back: UIButton = {
       let back = UIButton()
        back.translatesAutoresizingMaskIntoConstraints = false
        back.setTitle("back", for: .normal)
        back.setTitleColor(.systemBlue, for: .normal)
        back.addTarget(self, action: #selector(backAction(_:)), for: .touchUpInside)
        return back
    }()
    
    private lazy var nextButton: UIButton = {
        let next = UIButton()
        next.translatesAutoresizingMaskIntoConstraints = false
        next.setTitle("next", for: .normal)
        next.setTitleColor(.systemBlue, for: .normal)
        next.addTarget(self, action: #selector(nextAction(_:)), for: .touchUpInside)
        return next
    }()
    
    private lazy var stackview: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [back, nextButton])
        stackView.alignment = .center
        stackView.axis = .horizontal
        stackView.spacing = 10
        stackView.distribution = .equalSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private lazy var webView: WKWebView = {
        let preferences = WKPreferences()
        preferences.javaScriptEnabled = true
        let configuration = WKWebViewConfiguration()
        configuration.preferences = preferences
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        return webView
    }()
    
    private let url: URL
    
    init(url: URL, title: String) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
        self.title = title
        webView.load(URLRequest(url: self.url))
        webView.allowsBackForwardNavigationGestures = true
        configurationButtons()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        view.backgroundColor = .white
        view.addSubview(webView)
        view.addSubview(stackview)
       
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        NSLayoutConstraint.activate([stackview.topAnchor.constraint(equalTo: view.topAnchor, constant: 50),
                                     stackview.heightAnchor.constraint(equalToConstant: 100),
                                     stackview.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
                                     stackview.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
                                     webView.topAnchor.constraint(equalTo: stackview.bottomAnchor, constant: 5),
                                     webView.widthAnchor.constraint(equalTo: view.widthAnchor),
                                     webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
    }
    
    private func configurationButtons() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Done",
                                                           style: .done,
                                                           target: self,
                                                           action: #selector(dismissWebview))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh,
                                                            target: self,
                                                            action: #selector(reloadURL))
    }
    
    @objc private func dismissWebview() {
        dismiss(animated: true, completion: nil)
    }
    
    @objc private func reloadURL() {
        webView.load(URLRequest(url: self.url))
    }
}

extension WKWebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.webView.evaluateJavaScript("document.title") { [weak self] (result, _) -> Void in
            self?.navigationItem.title = result as? String
        }
    }
    
    static func isAllowedNavigationURL(_ url: URL?) -> Bool {
        guard let scheme = url?.scheme?.lowercased() else { return false }
        // "about" is required for the empty-document bootstrap of scripted iframes.
        return scheme == "http" || scheme == "https" || scheme == "about"
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(Self.isAllowedNavigationURL(navigationAction.request.url) ? .allow : .cancel)
    }
}

extension WKWebViewController {
    @objc func backAction(_ sender: UIButton) {
        if webView.canGoBack {
            webView.goBack()
        }
    }
    
    @objc func nextAction(_ sender: UIButton) {
        if webView.canGoForward {
            webView.goForward()
        }
    }
}
