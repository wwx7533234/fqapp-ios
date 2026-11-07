import Flutter
import UIKit
import UniformTypeIdentifiers

/// Reader-device bridge (`fqapp/reader`): screen brightness sessions, battery
/// status, keep-awake and custom font import.
final class ReaderHost: NSObject, FlutterStreamHandler {
  private let methods: FlutterMethodChannel
  private let events: FlutterEventChannel
  private var sink: FlutterEventSink?
  private var session: String?
  private var originalBrightness: CGFloat?
  private var timer: Timer?

  init(messenger: FlutterBinaryMessenger) {
    methods = FlutterMethodChannel(name: "fqapp/reader", binaryMessenger: messenger)
    events = FlutterEventChannel(name: "fqapp/reader/events", binaryMessenger: messenger)
    super.init()
    methods.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    events.setStreamHandler(self)
    UIDevice.current.isBatteryMonitoringEnabled = true
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    emitStatus()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "keepScreenOn":
      UIApplication.shared.isIdleTimerDisabled = (args["on"] as? Bool) ?? false
      result(true)
    case "pickFont":
      pickFont(result: result)
    case "setImmersive":
      // iOS has no navigation/status bar to hide from the app; the reader uses
      // its SafeArea layout, and Flutter's own chrome handles the rest.
      result(nil)
    default:
      let id = args["session"] as? String ?? ""
      guard !id.isEmpty else {
        result(FlutterError(code: "BAD_SESSION", message: "阅读会话已结束", details: nil))
        return
      }
      switch call.method {
      case "start":
        start(session: id, brightness: args["brightness"], result: result)
      case "setBrightness":
        guard applyBrightness(args["brightness"], result: result) else { return }
      case "suspend":
        restoreBrightness()
        timer?.invalidate()
        timer = nil
        result(nil)
      case "stop":
        restoreBrightness()
        timer?.invalidate()
        timer = nil
        if session == id { session = nil }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func start(session id: String, brightness: Any?, result: @escaping FlutterResult) {
    guard let value = (brightness as? NSNumber)?.doubleValue,
          value.isFinite, value == -1 || (value >= 0.02 && value <= 1) else {
      result(FlutterError(code: "BAD_BRIGHTNESS", message: "亮度值无效", details: nil))
      return
    }
    // Capture the user's brightness once per session. After suspend() the
    // previous value is restored and cleared, so re-entering must capture the
    // current (system/user) brightness again or stop() would leave the reader
    // brightness applied.
    if originalBrightness == nil {
      originalBrightness = UIScreen.main.brightness
    }
    session = id
    if value >= 0 {
      UIScreen.main.brightness = CGFloat(value)
    }
    startTimer()
    result(snapshot())
    emitStatus()
  }

  @discardableResult
  private func applyBrightness(_ raw: Any?, result: @escaping FlutterResult) -> Bool {
    guard let value = (raw as? NSNumber)?.doubleValue,
          value.isFinite, value == -1 || (value >= 0.02 && value <= 1) else {
      result(FlutterError(code: "BAD_BRIGHTNESS", message: "亮度值无效", details: nil))
      return false
    }
    if value >= 0 {
      UIScreen.main.brightness = CGFloat(value)
    } else if let originalBrightness {
      UIScreen.main.brightness = originalBrightness
    }
    result(true)
    emitStatus()
    return true
  }

  private func restoreBrightness() {
    if let originalBrightness {
      UIScreen.main.brightness = originalBrightness
      self.originalBrightness = nil
    }
  }

  private func startTimer() {
    timer?.invalidate()
    let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
      self?.emitStatus()
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  private func snapshot() -> [String: Any] {
    var value: [String: Any] = [
      "timestamp": Int(Date().timeIntervalSince1970 * 1000),
      "charging": isCharging,
    ]
    if UIDevice.current.batteryLevel >= 0 {
      value["battery"] = Int((UIDevice.current.batteryLevel * 100).rounded())
    }
    value["systemBrightness"] = Double(UIScreen.main.brightness)
    return value
  }

  private var isCharging: Bool {
    switch UIDevice.current.batteryState {
    case .charging, .full: return true
    default: return false
    }
  }

  private func emitStatus() {
    guard let session else { return }
    var value = snapshot()
    value["session"] = session
    DispatchQueue.main.async {
      self.sink?(value)
    }
  }

  private func pickFont(result: @escaping FlutterResult) {
    let types: [UTType] = [.font]
    DocumentPickerCoordinator.open(types: types) { urls in
      guard let url = urls.first else {
        result(nil)
        return
      }
      do {
        let support = try FileManager.default.url(
          for: .applicationSupportDirectory,
          in: .userDomainMask,
          appropriateFor: nil,
          create: true
        )
        let directory = support.appendingPathComponent("fonts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: target.path) {
          try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: url, to: target)
        result(["path": target.path, "name": target.deletingPathExtension().lastPathComponent])
      } catch {
        result(FlutterError(code: "font_copy", message: "字体导入失败", details: nil))
      }
    }
  }
}
