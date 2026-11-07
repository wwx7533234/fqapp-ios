import AVFoundation
import Flutter
import UIKit

/// System read-aloud (`fqapp/system_tts`) backed by AVSpeechSynthesizer.
///
/// The Dart session requests a maximum utterance size, speaks one sentence at a
/// time, and advances on `done`. AVSpeechSynthesizer has no equivalent of
/// Android's installed-engine list, so a single "system voice" entry is
/// reported and Chinese is selected explicitly.
final class TtsHost: NSObject, FlutterStreamHandler, AVSpeechSynthesizerDelegate {
  private let methods: FlutterMethodChannel
  private let events: FlutterEventChannel
  private let synthesizer = AVSpeechSynthesizer()
  private var sink: FlutterEventSink?
  private var activeId: String?
  private var speechRate: Float = 0.5
  private var rateMultiplier: Float = 1

  static let maxUtteranceLength = 300

  init(messenger: FlutterBinaryMessenger) {
    methods = FlutterMethodChannel(name: "fqapp/system_tts", binaryMessenger: messenger)
    events = FlutterEventChannel(name: "fqapp/system_tts_events", binaryMessenger: messenger)
    super.init()
    synthesizer.delegate = self
    methods.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    events.setStreamHandler(self)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  private func emit(_ event: [String: Any]) {
    DispatchQueue.main.async {
      self.sink?(event)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "engines":
      result([
        "engines": [["package": "ios.system", "label": "系统语音"]],
        "defaultEngine": "ios.system",
      ])
    case "initialize":
      initialize(args, result: result)
    case "speak":
      speak(args, result: result)
    case "stop":
      stop(emitInterrupted: false)
      result(nil)
    case "shutdown":
      stop(emitInterrupted: false)
      result(nil)
    case "settings":
      if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func initialize(_ args: [String: Any], result: @escaping FlutterResult) {
    guard AVSpeechSynthesisVoice(language: "zh-CN") != nil else {
      result(FlutterError(code: "language_missing", message: "系统未提供中文语音", details: nil))
      return
    }
    let rate = (args["rate"] as? NSNumber)?.floatValue ?? 1
    rateMultiplier = max(0.5, min(2, rate))
    speechRate = AVSpeechUtteranceDefaultSpeechRate * rateMultiplier
    do {
      try AVAudioSession.sharedInstance().setCategory(
        .playback,
        mode: .spokenAudio,
        options: [.duckOthers, .allowBluetoothA2DP]
      )
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      result(FlutterError(code: "audio_session", message: "无法启用朗读音频", details: nil))
      return
    }
    result(Self.maxUtteranceLength)
  }

  private func speak(_ args: [String: Any], result: @escaping FlutterResult) {
    let text = args["text"] as? String ?? ""
    let id = args["id"] as? String ?? ""
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      result(FlutterError(code: "invalid_text", message: "朗读片段为空", details: nil))
      return
    }
    guard text.utf16.count <= Self.maxUtteranceLength else {
      result(FlutterError(code: "invalid_text", message: "朗读片段过长", details: nil))
      return
    }
    guard !id.isEmpty else {
      result(FlutterError(code: "invalid_text", message: "朗读片段缺少标识", details: nil))
      return
    }
    if synthesizer.isSpeaking {
      synthesizer.stopSpeaking(at: .immediate)
    }
    activeId = id
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice =
      AVSpeechSynthesisVoice(language: "zh-CN")
      ?? AVSpeechSynthesisVoice(language: "zh-TW")
      ?? AVSpeechSynthesisVoice(language: "zh-HK")
    utterance.rate = max(0.1, min(1, speechRate))
    utterance.prefersAssistiveTechnologySettings = false
    synthesizer.speak(utterance)
    result(nil)
  }

  private func stop(emitInterrupted: Bool) {
    let id = activeId
    activeId = nil
    if synthesizer.isSpeaking || synthesizer.isPaused {
      synthesizer.stopSpeaking(at: .immediate)
    }
    if emitInterrupted, let id {
      emit(["type": "interrupted", "id": id, "start": 0])
    }
  }

  func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    willSpeakRangeOfSpeechString characterRange: NSRange,
    utterance: AVSpeechUtterance
  ) {
    guard let id = activeId else { return }
    emit(["type": "range", "id": id, "start": characterRange.location])
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    guard let id = activeId else { return }
    activeId = nil
    emit(["type": "done", "id": id, "start": 0])
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    guard let id = activeId else { return }
    activeId = nil
    emit(["type": "interrupted", "id": id, "start": 0])
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
    // Nothing to report: Dart drives pause through `stop`, not the engine.
  }
}
