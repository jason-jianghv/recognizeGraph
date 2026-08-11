import Flutter
import Network
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var localNetworkBrowser: NWBrowser?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 尽早用 Bonjour 浏览触发「本地网络」系统弹窗（Dart HTTP 不会触发）
    triggerLocalNetworkPrompt()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "com.shitu/local_network",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "probe" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let args = call.arguments as? [String: Any],
        let urlString = args["url"] as? String,
        let url = URL(string: urlString)
      else {
        result(
          FlutterError(code: "bad_args", message: "url required", details: nil)
        )
        return
      }
      self?.probeWithURLSession(url: url, result: result)
    }
  }

  /// NWBrowser 会可靠触发本地网络权限弹窗（需 Info.plist 含 NSBonjourServices）
  private func triggerLocalNetworkPrompt() {
    let params = NWParameters()
    params.includePeerToPeer = true
    let browser = NWBrowser(for: .bonjour(type: "_http._tcp", domain: nil), using: params)
    browser.stateUpdateHandler = { state in
      NSLog("[ShituLocalNetwork] browser state: \(String(describing: state))")
    }
    browser.start(queue: .main)
    localNetworkBrowser = browser
    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
      self?.localNetworkBrowser?.cancel()
      self?.localNetworkBrowser = nil
    }
  }

  /// URLSession + waitsForConnectivity：授权前会等待用户点「允许」，不会像 Dart 立刻 errno=65
  private func probeWithURLSession(url: URL, result: @escaping FlutterResult) {
    triggerLocalNetworkPrompt()

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 45

    let config = URLSessionConfiguration.ephemeral
    config.waitsForConnectivity = true
    config.timeoutIntervalForResource = 45

    let task = URLSession(configuration: config).dataTask(with: request) { data, response, error in
      if let error = error as NSError? {
        NSLog("[ShituLocalNetwork] probe failed: \(error)")
        result(
          FlutterError(
            code: "probe_failed",
            message: error.localizedDescription,
            details: "domain=\(error.domain) code=\(error.code)"
          )
        )
        return
      }
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
      NSLog("[ShituLocalNetwork] probe ok status=\(status) body=\(body)")
      result(["statusCode": status, "body": body])
    }
    task.resume()
  }
}
