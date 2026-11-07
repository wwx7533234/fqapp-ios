import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Audiobook/short-drama playback and system read-aloud continue in the
    // background through the audio session declared in Info.plist
    // (UIBackgroundModes). Selecting the category early also keeps the first
    // AVPlayer from starting in the ambient category.
    do {
      try AVAudioSession.sharedInstance().setCategory(
        .playback,
        mode: .moviePlayback,
        options: [.allowAirPlay, .allowBluetoothA2DP]
      )
    } catch {
      // A failed category selection must not block launch; foreground playback
      // still works with the default session.
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    FqappPlugin.register(with: engineBridge.applicationRegistrar)
  }
}
