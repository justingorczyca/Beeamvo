import AVFoundation
import Cocoa
import CoreAudio
import FlutterMacOS

/// Reliable microphone capture for menu-bar / LSUIElement macOS apps.
///
/// The third-party `record_macos` plugin uses `AVCaptureAudioFileOutput` and
/// calls `stopRunning()` immediately after `stopRecording()`. That races the
/// async file finalize callback and frequently leaves a header-only / empty
/// WAV — which surfaces in Dart as "No audio was captured" even when mic
/// permission and device selection are correct.
///
/// This plugin instead:
///  1. Captures via `AVAudioEngine` input tap
///  2. Converts to mono 16 kHz PCM-16 in memory
///  3. Returns the bytes only after the engine has fully stopped
final class MacAudioCapturePlugin: NSObject, FlutterPlugin {
  private static let channelName = "com.beeamvo/mac_audio_capture"

  private var engine: AVAudioEngine?
  private var converter: AVAudioConverter?
  private var pcmBuffer = Data()
  private let lock = NSLock()
  private var isRecording = false
  private var preferredDeviceUID: String?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger
    )
    let instance = MacAudioCapturePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "hasPermission":
      handleHasPermission(result: result)
    case "listInputDevices":
      handleListDevices(result: result)
    case "start":
      handleStart(call, result: result)
    case "stop":
      handleStop(result: result)
    case "isRecording":
      result(isRecording)
    case "cancel":
      handleCancel(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Permission

  private func handleHasPermission(result: @escaping FlutterResult) {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      result(true)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        DispatchQueue.main.async { result(granted) }
      }
    default:
      result(false)
    }
  }

  // MARK: - Devices

  private func handleListDevices(result: @escaping FlutterResult) {
    let devices = Self.discoverInputDevices().map { device -> [String: Any] in
      [
        "id": device.uniqueID,
        "label": device.localizedName,
      ]
    }
    result(devices)
  }

  private static func discoverInputDevices() -> [AVCaptureDevice] {
    var types: [AVCaptureDevice.DeviceType] = [.builtInMicrophone, .externalUnknown]
    if #available(macOS 14.0, *) {
      types.append(.microphone)
    }
    let session = AVCaptureDevice.DiscoverySession(
      deviceTypes: types,
      mediaType: .audio,
      position: .unspecified
    )
    return session.devices
  }

  // MARK: - Start / Stop

  private func handleStart(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if isRecording {
      result(
        FlutterError(
          code: "already_recording",
          message: "Recording is already in progress",
          details: nil
        )
      )
      return
    }

    let args = call.arguments as? [String: Any]
    preferredDeviceUID = args?["deviceId"] as? String

    // Permission must already be granted (Dart preflight), but re-check.
    let status = AVCaptureDevice.authorizationStatus(for: .audio)
    guard status == .authorized else {
      result(
        FlutterError(
          code: "permission_denied",
          message: "Microphone permission is not granted",
          details: nil
        )
      )
      return
    }

    do {
      try startEngine(deviceUID: preferredDeviceUID)
      result(true)
    } catch {
      NSLog("[MacAudioCapture] start failed: \(error)")
      teardownEngine()
      result(
        FlutterError(
          code: "start_failed",
          message: "Failed to start microphone: \(error.localizedDescription)",
          details: String(describing: error)
        )
      )
    }
  }

  private func handleStop(result: @escaping FlutterResult) {
    let data = stopEngineAndTakePcm()
    NSLog("[MacAudioCapture] stop → \(data.count) PCM bytes")
    result(FlutterStandardTypedData(bytes: data))
  }

  private func handleCancel(result: @escaping FlutterResult) {
    _ = stopEngineAndTakePcm()
    result(nil)
  }

  // MARK: - Engine

  private func startEngine(deviceUID: String?) throws {
    let newEngine = AVAudioEngine()
    let input = newEngine.inputNode

    // Select a specific Core Audio device when the user picked one.
    if let uid = deviceUID, !uid.isEmpty {
      if let deviceID = Self.audioDeviceID(forUID: uid) {
        do {
          try input.auAudioUnit.setDeviceID(deviceID)
          NSLog("[MacAudioCapture] using device uid=\(uid) id=\(deviceID)")
        } catch {
          NSLog(
            "[MacAudioCapture] setDeviceID failed for \(uid): \(error). Falling back to system default."
          )
        }
      } else {
        NSLog("[MacAudioCapture] unknown device uid=\(uid); using system default")
      }
    }

    // Prepare first so the hardware format is valid (sampleRate > 0).
    newEngine.prepare()

    var srcFormat = input.inputFormat(forBus: 0)
    if srcFormat.sampleRate <= 0 || srcFormat.channelCount == 0 {
      // Some devices report an invalid format until the engine is briefly started.
      try newEngine.start()
      srcFormat = input.inputFormat(forBus: 0)
      newEngine.stop()
      newEngine.reset()
      newEngine.prepare()
      srcFormat = input.inputFormat(forBus: 0)
    }

    guard srcFormat.sampleRate > 0, srcFormat.channelCount > 0 else {
      throw NSError(
        domain: "MacAudioCapture",
        code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Microphone input format is invalid (rate=\(srcFormat.sampleRate), ch=\(srcFormat.channelCount)).",
        ]
      )
    }

    guard
      let dstFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
      )
    else {
      throw NSError(
        domain: "MacAudioCapture",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Could not create 16 kHz mono PCM format."]
      )
    }

    guard let conv = AVAudioConverter(from: srcFormat, to: dstFormat) else {
      throw NSError(
        domain: "MacAudioCapture",
        code: 3,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Cannot convert mic format \(srcFormat.sampleRate)Hz/\(srcFormat.channelCount)ch → 16kHz mono.",
        ]
      )
    }

    lock.lock()
    pcmBuffer = Data()
    converter = conv
    lock.unlock()

    let bus: AVAudioNodeBus = 0
    let bufferSize: AVAudioFrameCount = 4096

    input.installTap(onBus: bus, bufferSize: bufferSize, format: srcFormat) {
      [weak self] buffer, _ in
      self?.appendConverted(buffer: buffer, dstFormat: dstFormat)
    }

    try newEngine.start()
    engine = newEngine
    isRecording = true
    NSLog(
      "[MacAudioCapture] recording started src=\(srcFormat.sampleRate)Hz/\(srcFormat.channelCount)ch"
    )
  }

  private func appendConverted(buffer: AVAudioPCMBuffer, dstFormat: AVAudioFormat) {
    lock.lock()
    let conv = converter
    lock.unlock()
    guard let conv else { return }

    let ratio = dstFormat.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
    guard
      let outBuffer = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: max(capacity, 1))
    else {
      return
    }

    var error: NSError?
    var consumed = false
    let status = conv.convert(to: outBuffer, error: &error) { _, outStatus in
      if consumed {
        outStatus.pointee = .noDataNow
        return nil
      }
      consumed = true
      outStatus.pointee = .haveData
      return buffer
    }

    if status == .error || error != nil {
      return
    }
    guard outBuffer.frameLength > 0, let channels = outBuffer.int16ChannelData else {
      return
    }

    let frameCount = Int(outBuffer.frameLength)
    let byteCount = frameCount * MemoryLayout<Int16>.size
    let bytes = Data(bytes: channels[0], count: byteCount)

    lock.lock()
    pcmBuffer.append(bytes)
    lock.unlock()
  }

  private func stopEngineAndTakePcm() -> Data {
    isRecording = false
    if let eng = engine {
      eng.inputNode.removeTap(onBus: 0)
      if eng.isRunning {
        eng.stop()
      }
    }
    teardownEngine()

    lock.lock()
    let data = pcmBuffer
    pcmBuffer = Data()
    converter = nil
    lock.unlock()
    return data
  }

  private func teardownEngine() {
    engine = nil
    isRecording = false
  }

  // MARK: - Core Audio device UID → AudioDeviceID

  private static func audioDeviceID(forUID uid: String) -> AudioDeviceID? {
    var propertySize: UInt32 = 0
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )

    guard
      AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &propertySize
      ) == noErr
    else {
      return nil
    }

    let count = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
    var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &propertySize,
        &deviceIDs
      ) == noErr
    else {
      return nil
    }

    for deviceID in deviceIDs {
      if String(deviceID) == uid {
        return deviceID
      }

      var uidSize = UInt32(MemoryLayout<CFString?>.size)
      var uidAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceUID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
      )
      var deviceUID: Unmanaged<CFString>?
      let status = AudioObjectGetPropertyData(
        deviceID,
        &uidAddress,
        0,
        nil,
        &uidSize,
        &deviceUID
      )
      if status == noErr, let value = deviceUID?.takeRetainedValue() as String?, value == uid {
        // Confirm it has input channels.
        if inputChannelCount(deviceID: deviceID) > 0 {
          return deviceID
        }
      }
    }
    return nil
  }

  private static func inputChannelCount(deviceID: AudioDeviceID) -> Int {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreamConfiguration,
      mScope: kAudioDevicePropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0
    else {
      return 0
    }
    let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
    defer { bufferList.deallocate() }
    guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, bufferList) == noErr else {
      return 0
    }
    return UnsafeMutableAudioBufferListPointer(bufferList).reduce(0) {
      $0 + Int($1.mNumberChannels)
    }
  }
}
