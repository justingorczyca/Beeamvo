import Cocoa
import FlutterMacOS

private func whisperPhysicalCoreCount() -> Int {
    var cores: Int32 = 0
    var size = MemoryLayout<Int32>.size
    let rc = sysctlbyname("hw.physicalcpu", &cores, &size, nil, 0)
    if rc == 0 && cores > 0 {
        return Int(cores)
    }
    return ProcessInfo.processInfo.activeProcessorCount
}

/// WhisperPlugin integrates whisper.cpp for offline speech-to-text on macOS.
/// Uses MethodChannel "com.beeamvo/whisper" for Dart communication.
class WhisperPlugin: NSObject {
    private var channel: FlutterMethodChannel?
    private var whisperContext: OpaquePointer?
    private var nThreads: Int = 0
    private var busy: Bool = false
    private var cancelRequested: Bool = false
    private let contextLock = NSLock()
    private let cancelLock = NSLock()

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.beeamvo/whisper",
            binaryMessenger: registrar.messenger
        )

        let instance = WhisperPlugin()
        instance.channel = channel

        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    deinit {
        freeContext()
    }
}

extension WhisperPlugin: FlutterPlugin {
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "init":
            handleInit(call, result: result)
        case "transcribeRaw":
            handleTranscribeRaw(call, result: result)
        case "cleanup":
            handleCleanup(result: result)
        case "cancel":
            handleCancel(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleInit(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let modelPath = args["modelPath"] as? String else {
            result(FlutterError(code: "invalid_args", message: "Missing modelPath", details: nil))
            return
        }

        let threads = args["threads"] as? Int ?? 0

        NSLog("[Whisper] Init with model: \(modelPath)")
        let ok = initializeContext(modelPath: modelPath, threads: threads)
        NSLog(ok ? "[Whisper] Init OK" : "[Whisper] Init FAILED")
        result(ok)
    }

    private func handleTranscribeRaw(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "invalid_args", message: "Missing arguments", details: nil))
            return
        }

        contextLock.lock()
        if busy {
            contextLock.unlock()
            result(FlutterError(code: "busy", message: "Transcription already in progress", details: nil))
            return
        }
        busy = true
        contextLock.unlock()
        cancelLock.lock()
        cancelRequested = false
        cancelLock.unlock()

        guard let pcmBytes = args["pcmBytes"] as? FlutterStandardTypedData else {
            contextLock.lock()
            busy = false
            contextLock.unlock()
            result(FlutterError(code: "invalid_args", message: "Missing pcmBytes", details: nil))
            return
        }

        let sampleRate = args["sampleRate"] as? Int ?? 16000
        let channels = args["channels"] as? Int ?? 1
        let language = args["language"] as? String ?? "auto"
        if channels <= 0 {
            contextLock.lock()
            busy = false
            contextLock.unlock()
            result(FlutterError(code: "invalid_args", message: "channels must be > 0", details: nil))
            return
        }

        contextLock.lock()
        if whisperContext == nil {
            busy = false
            contextLock.unlock()
            NSLog("[Whisper] TranscribeRaw: context is null!")
            result(FlutterError(code: "not_initialized", message: "Whisper context not initialized", details: nil))
            return
        }
        contextLock.unlock()

        // Convert PCM-16LE to float32 samples
        let data = pcmBytes.data
        let sampleCount = data.count / 2 / channels
        var samples = [Float]()
        samples.reserveCapacity(sampleCount)

        data.withUnsafeBytes { ptr in
            let int16Ptr = ptr.bindMemory(to: Int16.self)
            for i in stride(from: 0, to: min(int16Ptr.count, sampleCount * channels), by: channels) {
                samples.append(Float(int16Ptr[i]) / 32768.0)
            }
        }

        NSLog("[Whisper] Transcribing \(samples.count) samples, sr=\(sampleRate), ch=\(channels), lang=\(language)")

        let text = transcribePcm(samples: samples, sampleRate: sampleRate, language: language)

        NSLog("[Whisper] Transcription completed, characters=\(text.count)")

        contextLock.lock()
        busy = false
        contextLock.unlock()
        result(text)
    }

    private func handleCleanup(result: @escaping FlutterResult) {
        freeContext()
        result(nil)
    }

    private func handleCancel(result: @escaping FlutterResult) {
        cancelLock.lock()
        cancelRequested = true
        cancelLock.unlock()
        result(true)
    }

    private func initializeContext(modelPath: String, threads: Int) -> Bool {
        contextLock.lock()
        defer { contextLock.unlock() }

        if whisperContext != nil {
            NSLog("[Whisper] Already initialized, reusing context")
            return true
        }

        let hw = whisperPhysicalCoreCount()
        nThreads = threads > 0 ? min(threads, hw) : hw
        nThreads = max(1, nThreads)
        NSLog("[Whisper] Using \(nThreads) threads")

        var cparams = whisper_context_default_params()
        cparams.use_gpu = true
        cparams.flash_attn = true
        cparams.gpu_device = 0

        NSLog("[Whisper] Loading model from: \(modelPath)")
        whisperContext = whisper_init_from_file_with_params(modelPath, cparams)

        if whisperContext != nil {
            NSLog("[Whisper] Model loaded successfully")
            return true
        } else {
            NSLog("[Whisper] FAILED to load model!")
            return false
        }
    }

    private func transcribePcm(samples: [Float], sampleRate: Int, language: String) -> String {
        contextLock.lock()
        defer { contextLock.unlock() }

        guard let ctx = whisperContext, !samples.isEmpty else {
            NSLog("[Whisper] TranscribePcm: no context or empty samples")
            return ""
        }

        var wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)

        wparams.n_threads = Int32(max(1, nThreads))
        wparams.print_progress = false
        wparams.print_special = false
        wparams.print_realtime = false
        wparams.print_timestamps = false
        wparams.no_timestamps = true
        wparams.single_segment = true

        // Reduce encoder context for short clips to avoid full 30s encoder cost.
        let sr = sampleRate > 0 ? sampleRate : 16000
        let audioSeconds = Float(samples.count) / Float(sr)
        if audioSeconds < 30 {
            let ctxFrames = Int(ceil(audioSeconds / 30.0 * 1500.0 / 64.0)) * 64
            wparams.audio_ctx = Int32(max(512, ctxFrames))
        } else {
            wparams.audio_ctx = 0 // 0 = default full context window
        }
        NSLog("[Whisper] audio_ctx=\(wparams.audio_ctx) for \(String(format: "%.2f", audioSeconds))s audio")

        wparams.abort_callback_user_data = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        wparams.abort_callback = { userData in
            guard let userData else { return false }
            let plugin = Unmanaged<WhisperPlugin>.fromOpaque(userData).takeUnretainedValue()
            return plugin.shouldAbort()
        }

        NSLog("[Whisper] Running inference on \(samples.count) float samples...")

        // language pointer must remain valid for the duration of whisper_full
        var result = ""
        language.withCString { langPtr in
            wparams.language = langPtr

            let ret = whisper_full(ctx, wparams, samples, Int32(samples.count))
            if ret != 0 {
                if shouldAbort() {
                    NSLog("[Whisper] Transcription cancelled")
                } else {
                    NSLog("[Whisper] whisper_full returned error: \(ret)")
                }
                return
            }

            let nSegments = whisper_full_n_segments(ctx)
            NSLog("[Whisper] Got \(nSegments) segments")

            for i in 0..<nSegments {
                if let text = whisper_full_get_segment_text(ctx, i) {
                    let segmentText = String(cString: text)
                    if !result.isEmpty { result += " " }
                    result += segmentText
                }
            }
        }

        return result.trimmingCharacters(in: .whitespaces)
    }

    private func freeContext() {
        contextLock.lock()
        defer { contextLock.unlock() }

        if let ctx = whisperContext {
            whisper_free(ctx)
            whisperContext = nil
            NSLog("[Whisper] Context freed")
        }
    }

    private func shouldAbort() -> Bool {
        cancelLock.lock()
        defer { cancelLock.unlock() }
        return cancelRequested
    }
}
