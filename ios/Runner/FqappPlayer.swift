import AVFoundation
import Flutter
import MediaPlayer
import UIKit

/// iOS host for the Dart `NativePlayer` wrapper.
///
/// Android uses ExoPlayer plus a CENC data source. On iOS the CENC payload is
/// prepared into a plaintext local file by the Rust core (see
/// `rust/src/api/media_cache.rs`), so this host only has to run AVPlayer and
/// project its frames into a Flutter texture. The channel/event contract is
/// byte-for-byte the one the Dart side already implements.
final class PlayerHost: NSObject, FlutterStreamHandler {
  private let messenger: FlutterBinaryMessenger
  private let textures: FlutterTextureRegistry
  private let methods: FlutterMethodChannel
  private let events: FlutterEventChannel
  private var sink: FlutterEventSink?
  private var players: [Int: PlayerInstance] = [:]
  private var nextId = 1

  init(messenger: FlutterBinaryMessenger, textures: FlutterTextureRegistry) {
    self.messenger = messenger
    self.textures = textures
    methods = FlutterMethodChannel(
      name: "fqapp/native_player",
      binaryMessenger: messenger
    )
    events = FlutterEventChannel(
      name: "fqapp/native_player/events",
      binaryMessenger: messenger
    )
    super.init()
    methods.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    events.setStreamHandler(self)
    RemoteCommands.shared.onAction = { [weak self] action in
      self?.dispatchRemote(action)
    }
    RemoteCommands.shared.onNoisy = { [weak self] in
      self?.pauseAll()
      self?.methods.invokeMethod("onAudioBecomingNoisy", arguments: nil)
    }
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

  private func dispatchRemote(_ action: String) {
    methods.invokeMethod("onNotificationAction", arguments: ["action": action])
  }

  private func pauseAll() {
    for player in players.values {
      player.pause()
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "create":
      let url = args["cdnUrl"] as? String ?? ""
      let key = args["keyHex"] as? String ?? ""
      create(url: url, key: key, result: result)
    case "play":
      withPlayer(args, result) { $0.play() }
    case "pause":
      withPlayer(args, result) { $0.pause() }
    case "seek":
      withPlayer(args, result) { $0.seek(toMilliseconds: (args["positionMs"] as? NSNumber)?.int64Value ?? 0) }
    case "setVolume":
      withPlayer(args, result) { $0.setVolume(Float((args["volume"] as? NSNumber)?.doubleValue ?? 1)) }
    case "setRate":
      withPlayer(args, result) { $0.setRate(Float((args["rate"] as? NSNumber)?.doubleValue ?? 1)) }
    case "dispose":
      guard let id = (args["id"] as? NSNumber)?.intValue else {
        result(FlutterError(code: "bad_args", message: "缺少播放器 id", details: nil))
        return
      }
      if let player = players.removeValue(forKey: id) {
        player.dispose()
      }
      result(nil)
    case "setKeepScreenOn":
      UIApplication.shared.isIdleTimerDisabled = (args["on"] as? Bool) ?? false
      result(nil)
    case "startListenForeground":
      RemoteCommands.shared.start(
        title: args["title"] as? String ?? "",
        episode: args["episode"] as? String ?? "",
        playing: (args["playing"] as? Bool) ?? true,
        hasPrev: (args["hasPrev"] as? Bool) ?? true,
        hasNext: (args["hasNext"] as? Bool) ?? true,
        positionMs: (args["positionMs"] as? NSNumber)?.doubleValue ?? 0,
        durationMs: (args["durationMs"] as? NSNumber)?.doubleValue ?? 0,
        speed: (args["speed"] as? NSNumber)?.doubleValue ?? 1
      )
      result(nil)
    case "stopListenForeground":
      RemoteCommands.shared.stop()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func withPlayer(
    _ args: [String: Any],
    _ result: @escaping FlutterResult,
    _ body: (PlayerInstance) -> Void
  ) {
    guard let id = (args["id"] as? NSNumber)?.intValue, let player = players[id] else {
      result(FlutterError(code: "no_player", message: "播放器不存在", details: nil))
      return
    }
    body(player)
    result(nil)
  }

  private func create(url: String, key: String, result: @escaping FlutterResult) {
    guard !url.isEmpty else {
      result(FlutterError(code: "bad_url", message: "媒体地址为空", details: nil))
      return
    }
    let id = nextId
    nextId += 1
    guard let player = PlayerInstance(
      id: id,
      url: url,
      textures: textures,
      emit: { [weak self] event in self?.emit(event) }
    ) else {
      result(FlutterError(code: "create_failed", message: "无法创建播放器", details: nil))
      return
    }
    players[id] = player
    result(["playerId": id])
  }

  private final class RemoteCommands {
    static let shared = RemoteCommands()
    var onAction: ((String) -> Void)?
    var onNoisy: (() -> Void)?
    private var configured = false

    func configure() {
      guard !configured else { return }
      configured = true
      let center = MPRemoteCommandCenter.shared()
      center.playCommand.addTarget { [weak self] _ in
        self?.onAction?("playPause")
        return .success
      }
      center.pauseCommand.addTarget { [weak self] _ in
        self?.onAction?("playPause")
        return .success
      }
      center.togglePlayPauseCommand.addTarget { [weak self] _ in
        self?.onAction?("playPause")
        return .success
      }
      center.nextTrackCommand.addTarget { [weak self] _ in
        self?.onAction?("next")
        return .success
      }
      center.previousTrackCommand.addTarget { [weak self] _ in
        self?.onAction?("prev")
        return .success
      }
      center.stopCommand.addTarget { [weak self] _ in
        self?.onAction?("stop")
        return .success
      }
      NotificationCenter.default.addObserver(
        forName: AVAudioSession.interruptionNotification,
        object: nil,
        queue: .main
      ) { [weak self] notification in
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began {
          self?.onNoisy?()
        } else if let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt {
          let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
          if options.contains(.shouldResume) {
            // The Dart session decides whether to resume; exposing a play
            // action keeps it in charge instead of starting audio behind its
            // back.
            self?.onAction?("playPause")
          }
        }
      }
      NotificationCenter.default.addObserver(
        forName: AVAudioSession.routeChangeNotification,
        object: nil,
        queue: .main
      ) { [weak self] notification in
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        if reason == .oldDeviceUnavailable {
          self?.onNoisy?()
        }
      }
    }

    func start(
      title: String,
      episode: String,
      playing: Bool,
      hasPrev: Bool,
      hasNext: Bool,
      positionMs: Double,
      durationMs: Double,
      speed: Double
    ) {
      configure()
      let center = MPRemoteCommandCenter.shared()
      center.playCommand.isEnabled = true
      center.pauseCommand.isEnabled = true
      center.togglePlayPauseCommand.isEnabled = true
      center.nextTrackCommand.isEnabled = hasNext
      center.previousTrackCommand.isEnabled = hasPrev
      center.stopCommand.isEnabled = true
      var info: [String: Any] = [
        MPMediaItemPropertyTitle: title,
        MPMediaItemPropertyAlbumTitle: episode,
        MPNowPlayingInfoPropertyPlaybackRate: playing ? speed : 0,
        MPNowPlayingInfoPropertyElapsedPlaybackTime: positionMs / 1000.0,
        MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
      ]
      if durationMs > 0 {
        info[MPMediaItemPropertyPlaybackDuration] = durationMs / 1000.0
      }
      MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func stop() {
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
      MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled = false
      MPRemoteCommandCenter.shared().previousTrackCommand.isEnabled = false
    }
  }
}

/// One AVPlayer plus its Flutter texture, matching one Dart [NativePlayer].
private final class PlayerInstance: NSObject {
  let id: Int
  private let textures: FlutterTextureRegistry
  private let emit: ([String: Any]) -> Void
  private let player: AVPlayer
  private let item: AVPlayerItem
  private let videoOutput: AVPlayerItemVideoOutput
  private let texture: PlayerTexture
  private var textureId: Int64 = 0
  private var displayLink: CADisplayLink?
  private var timeObserver: Any?
  private var statusObservation: NSKeyValueObservation?
  private var timeControlObservation: NSKeyValueObservation?
  private var durationObservation: NSKeyValueObservation?
  private var endObserver: NSObjectProtocol?
  private var failureObserver: NSObjectProtocol?
  private var playWhenReady = false
  private var desiredRate: Float = 1
  private var lastPositionMs: Int64 = 0
  private var lastDurationMs: Int64 = 0
  private var sentFirstFrame = false
  private var reportedSize = CGSize.zero
  private var disposed = false

  init?(
    id: Int,
    url: String,
    textures: FlutterTextureRegistry,
    emit: @escaping ([String: Any]) -> Void
  ) {
    guard let resolved = Self.resolveURL(url) else { return nil }
    self.id = id
    self.textures = textures
    self.emit = emit
    player = AVPlayer()
    let asset = AVURLAsset(
      url: resolved,
      options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
    )
    item = AVPlayerItem(asset: asset)
    videoOutput = AVPlayerItemVideoOutput(
      pixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
      ]
    )
    texture = PlayerTexture()
    super.init()
    textureId = textures.register(texture)
    texture.output = videoOutput
    texture.onFrame = { [weak self] in
      guard let self, !self.sentFirstFrame else { return }
      self.sentFirstFrame = true
      self.emit(["type": "firstFrame", "playerId": self.id, "value": true])
    }
    item.add(videoOutput)
    item.audioTimePitchAlgorithm = .timeDomain
    player.replaceCurrentItem(with: item)
    player.actionAtItemEnd = .pause
    player.automaticallyWaitsToMinimizeStalling = true

    emit(["type": "created", "playerId": id, "value": textureId])
    observe()
    startDisplayLink()
    emitSizeIfReady()
  }

  private static func resolveURL(_ raw: String) -> URL? {
    if raw.hasPrefix("file://") {
      return URL(string: raw)
    }
    if raw.hasPrefix("/") {
      return URL(fileURLWithPath: raw)
    }
    return URL(string: raw)
  }

  private func observe() {
    statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
      guard let self else { return }
      switch item.status {
      case .readyToPlay:
        self.emitDuration()
        self.emitSizeIfReady()
        self.emitBuffering(self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate)
      case .failed:
        self.emitFailure(item.error)
      default:
        break
      }
    }
    timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
      guard let self else { return }
      switch player.timeControlStatus {
      case .playing:
        self.emit(["type": "playing", "playerId": self.id, "value": true])
        self.emit(["type": "buffering", "playerId": self.id, "value": false])
        AudioSession.activate()
      case .waitingToPlayAtSpecifiedRate:
        self.emit(["type": "playing", "playerId": self.id, "value": false])
        self.emit(["type": "buffering", "playerId": self.id, "value": true])
      case .paused:
        self.emit(["type": "playing", "playerId": self.id, "value": false])
        self.emit(["type": "buffering", "playerId": self.id, "value": false])
      @unknown default:
        break
      }
    }
    durationObservation = item.observe(\.duration, options: [.new]) { [weak self] _, _ in
      self?.emitDuration()
    }
    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
      queue: .main
    ) { [weak self] time in
      guard let self else { return }
      let ms = Int64((time.seconds.isFinite ? time.seconds : 0) * 1000)
      if ms != self.lastPositionMs {
        self.lastPositionMs = ms
        self.emit(["type": "position", "playerId": self.id, "value": ms])
      }
      self.emitDuration()
      self.emitSizeIfReady()
    }
    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: item,
      queue: .main
    ) { [weak self] _ in
      guard let self, !self.disposed else { return }
      self.playWhenReady = false
      self.emit(["type": "playWhenReady", "playerId": self.id, "value": false])
      self.emit(["type": "completed", "playerId": self.id, "value": true])
      self.emit(["type": "playing", "playerId": self.id, "value": false])
    }
    failureObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemFailedToPlayToEndTime,
      object: item,
      queue: .main
    ) { [weak self] notification in
      self?.emitFailure(notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)
    }
  }

  private func emitDuration() {
    let duration = item.duration
    guard duration.isNumeric, duration.seconds.isFinite else { return }
    let ms = Int64(duration.seconds * 1000)
    guard ms > 0, ms != lastDurationMs else { return }
    lastDurationMs = ms
    emit(["type": "duration", "playerId": id, "value": ms])
  }

  private func emitSizeIfReady() {
    guard item.status == .readyToPlay else { return }
    let tracks = item.asset.tracks(withMediaType: .video)
    guard let track = tracks.first else { return }
    let natural = track.naturalSize
    guard natural.width > 0, natural.height > 0 else { return }
    let degrees = Self.rotationDegrees(track.preferredTransform)
    if natural == reportedSize {
      return
    }
    reportedSize = natural
    emit([
      "type": "videoSize",
      "playerId": id,
      "width": natural.width,
      "height": natural.height,
      "rotationCorrection": degrees,
      "formatRotation": degrees,
      "handlesCropAndRotation": false,
    ])
  }

  private static func rotationDegrees(_ transform: CGAffineTransform) -> Int {
    let angle = atan2(transform.b, transform.a) * 180 / .pi
    let rounded = Int(angle.rounded())
    switch rounded {
    case 90, -270: return 90
    case 180, -180: return 180
    case 270, -90: return 270
    default: return 0
    }
  }

  private func emitBuffering(_ value: Bool) {
    emit(["type": "buffering", "playerId": id, "value": value])
  }

  private func emitFailure(_ error: Error?) {
    guard !disposed else { return }
    let nsError = error as NSError?
    let message = nsError?.localizedDescription ?? "播放失败"
    emit([
      "type": "error",
      "playerId": id,
      "value": [
        "message": message,
        "errorCode": nsError?.code ?? -1,
        "httpStatusCode": Self.httpStatus(from: nsError),
      ],
    ])
  }

  private static func httpStatus(from error: NSError?) -> Int? {
    guard let error else { return nil }
    if let code = error.userInfo["HTTPStatus"] as? Int { return code }
    if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
      return httpStatus(from: underlying)
    }
    return nil
  }

  private func startDisplayLink() {
    let link = CADisplayLink(target: self, selector: #selector(displayTick))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 60, preferred: 30)
    link.add(to: .main, forMode: .common)
    displayLink = link
  }

  @objc private func displayTick(_ link: CADisplayLink) {
    guard item.status == .readyToPlay else { return }
    let hostTime = CACurrentMediaTime()
    let itemTime = videoOutput.itemTime(forHostTime: hostTime)
    guard videoOutput.hasNewPixelBuffer(forItemTime: itemTime),
          let buffer = videoOutput.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) else {
      return
    }
    texture.enqueue(buffer)
    textures.textureFrameAvailable(textureId)
  }

  func play() {
    guard !disposed else { return }
    playWhenReady = true
    AudioSession.activate()
    player.play()
    if desiredRate != 1 {
      player.rate = desiredRate
    }
    emit(["type": "playWhenReady", "playerId": id, "value": true])
  }

  func pause() {
    guard !disposed else { return }
    playWhenReady = false
    player.pause()
    emit(["type": "playWhenReady", "playerId": id, "value": false])
  }

  func seek(toMilliseconds ms: Int64) {
    guard !disposed else { return }
    let time = CMTime(value: CMTimeValue(max(0, ms)), timescale: 1000)
    player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
      guard let self else { return }
      self.lastPositionMs = max(0, ms)
      self.emit(["type": "position", "playerId": self.id, "value": self.lastPositionMs])
      self.emit(["type": "completed", "playerId": self.id, "value": false])
    }
  }

  func setVolume(_ volume: Float) {
    player.volume = max(0, min(1, volume))
  }

  func setRate(_ rate: Float) {
    desiredRate = max(0.25, min(3, rate))
    if playWhenReady {
      player.rate = desiredRate
    }
  }

  func dispose() {
    guard !disposed else { return }
    disposed = true
    displayLink?.invalidate()
    displayLink = nil
    if let timeObserver {
      player.removeTimeObserver(timeObserver)
      self.timeObserver = nil
    }
    statusObservation?.invalidate()
    timeControlObservation?.invalidate()
    durationObservation?.invalidate()
    if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
    endObserver = nil
    failureObserver = nil
    player.pause()
    player.replaceCurrentItem(with: nil)
    item.remove(videoOutput)
    textures.unregisterTexture(textureId)
  }
}

private final class PlayerTexture: NSObject, FlutterTexture {
  private let lock = NSLock()
  private var latest: CVPixelBuffer?
  var output: AVPlayerItemVideoOutput?
  var onFrame: (() -> Void)?

  func enqueue(_ buffer: CVPixelBuffer) {
    lock.lock()
    latest = buffer
    lock.unlock()
    onFrame?()
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    lock.lock()
    guard let buffer = latest else {
      lock.unlock()
      return nil
    }
    lock.unlock()
    return Unmanaged.passRetained(buffer)
  }
}

private enum AudioSession {
  static func activate() {
    do {
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      // Playback still proceeds in the foreground with the default session.
    }
  }
}
