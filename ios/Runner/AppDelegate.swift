import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let didFinish = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    // flutter_local_notifications: deliver notification taps to the plugin.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate

    // Microphone permission channel — flutter_audio_capture doesn't request it,
    // so the recorder asks through here before starting capture.
    if let controller = window?.rootViewController as? FlutterViewController {
      let micChannel = FlutterMethodChannel(
        name: "metro_sound/mic", binaryMessenger: controller.binaryMessenger)
      micChannel.setMethodCallHandler { call, result in
        guard call.method == "requestPermission" else {
          result(FlutterMethodNotImplemented)
          return
        }
        if #available(iOS 17.0, *) {
          AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async { result(granted) }
          }
        } else {
          AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async { result(granted) }
          }
        }
      }

      // Build-environment channel. The App Store receipt is named
      // "sandboxReceipt" for TestFlight (and Xcode) installs and "receipt" for
      // production App Store installs, so this reliably distinguishes a tester
      // build from a paying customer's copy of the same binary. Used to gate the
      // TestFlight-only Pro bypass; it fails closed (false) when no receipt is
      // present, so production never accidentally reports as a test build.
      let envChannel = FlutterMethodChannel(
        name: "metro_sound/build_env", binaryMessenger: controller.binaryMessenger)
      envChannel.setMethodCallHandler { call, result in
        guard call.method == "isSandbox" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let name = Bundle.main.appStoreReceiptURL?.lastPathComponent
        result(name == "sandboxReceipt")
      }
    }
    return didFinish
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
