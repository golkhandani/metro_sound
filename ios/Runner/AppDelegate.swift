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
    }
    return didFinish
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
