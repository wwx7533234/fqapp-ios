import Flutter
import UIKit

/// Registers the application-level platform channels that the Android build
/// provides through its own Flutter plugins. The Dart side treats every one of
/// these channels as optional except the native player, so registration must
/// never throw on launch.
final class FqappPlugin: NSObject {
  private static var retained: [FqappPlugin] = []

  private let messenger: FlutterBinaryMessenger
  private let textures: FlutterTextureRegistry
  private var channels: [FlutterMethodChannel] = []
  private var playerHost: PlayerHost?
  private var readerHost: ReaderHost?
  private var ttsHost: TtsHost?
  private var filesHost: FilesHost?

  init(messenger: FlutterBinaryMessenger, textures: FlutterTextureRegistry) {
    self.messenger = messenger
    self.textures = textures
  }

  static func register(with registrar: FlutterApplicationRegistrar) {
    let plugin = FqappPlugin(
      messenger: registrar.messenger(),
      textures: registrar.textures()
    )
    plugin.install()
    retained.append(plugin)
  }

  private func install() {
    playerHost = PlayerHost(messenger: messenger, textures: textures)
    readerHost = ReaderHost(messenger: messenger)
    ttsHost = TtsHost(messenger: messenger)
    filesHost = FilesHost(messenger: messenger)
    installMiscChannels()
  }

  private func channel(_ name: String, _ handler: @escaping FlutterMethodCallHandler) {
    let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    channel.setMethodCallHandler(handler)
    channels.append(channel)
  }

  private func installMiscChannels() {
    // E-ink full refresh is a Hisense-specific Android API; iOS reports
    // unsupported so the reader skips it without an error path.
    channel("fqapp/eink-refresh") { call, result in
      switch call.method {
      case "isSupported": result(false)
      case "refresh": result(false)
      default: result(FlutterMethodNotImplemented)
      }
    }

    // Volume-key page turning: iOS cannot intercept the hardware volume keys
    // without also letting the system change the volume, so this is a no-op.
    channel("fqapp/volume-key") { call, result in
      if call.method == "setEnabled" { result(nil) } else { result(FlutterMethodNotImplemented) }
    }

    channel("fqapp/share") { [weak self] call, result in
      guard call.method == "shareText", let self else {
        result(FlutterMethodNotImplemented)
        return
      }
      let args = call.arguments as? [String: Any] ?? [:]
      let title = args["title"] as? String ?? ""
      let text = args["text"] as? String ?? ""
      self.presentActivity(items: [text], title: title) { ok in
        result(ok)
      }
    }
  }

  private func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
      ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    var controller = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
    while let presented = controller?.presentedViewController {
      controller = presented
    }
    return controller
  }

  private func presentActivity(items: [Any], title: String, completion: @escaping (Bool) -> Void) {
    DispatchQueue.main.async {
      guard let presenter = self.topViewController() else {
        completion(false)
        return
      }
      let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
      if let popover = controller.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(
          x: presenter.view.bounds.midX,
          y: presenter.view.bounds.midY,
          width: 0,
          height: 0
        )
        popover.permittedArrowDirections = []
      }
      presenter.present(controller, animated: true) {
        completion(true)
      }
    }
  }
}
