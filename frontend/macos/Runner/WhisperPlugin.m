#import "WhisperPlugin.h"
#if __has_include(<whisper_cpp/whisper.h>)
#import <whisper_cpp/whisper.h>
#elif __has_include(<whisper/whisper.h>)
#import <whisper/whisper.h>
#elif __has_include(<whisper.h>)
#import <whisper.h>
#else
#import "whisper.cpp/include/whisper.h"
#endif
#import <pthread.h>
#import <math.h>
#import <sys/sysctl.h>

static int whisper_physical_core_count(void) {
    int cores = 0;
    size_t size = sizeof(cores);
    if (sysctlbyname("hw.physicalcpu", &cores, &size, NULL, 0) == 0 && cores > 0) {
        return cores;
    }
    return (int)[[NSProcessInfo processInfo] activeProcessorCount];
}

static bool whisper_abort_callback(void *user_data);

@interface WhisperPlugin ()
@property (nonatomic, assign) struct whisper_context *ctx;
@property (nonatomic, assign) int nThreads;
@property (nonatomic, assign) BOOL busy;
@property (atomic, assign) BOOL cancelRequested;
@property (nonatomic, strong) NSLock *contextLock;
@end

@implementation WhisperPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FlutterMethodChannel* channel = [FlutterMethodChannel
        methodChannelWithName:@"com.beeamvo/whisper"
        binaryMessenger:[registrar messenger]];

    WhisperPlugin* instance = [[WhisperPlugin alloc] init];
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _contextLock = [[NSLock alloc] init];
        _busy = NO;
        _cancelRequested = NO;
    }
    return self;
}

- (void)dealloc {
    [self freeContext];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([call.method isEqualToString:@"init"]) {
        [self handleInit:call result:result];
    } else if ([call.method isEqualToString:@"transcribeRaw"]) {
        [self handleTranscribeRaw:call result:result];
    } else if ([call.method isEqualToString:@"cancel"]) {
        self.cancelRequested = YES;
        result(@YES);
    } else if ([call.method isEqualToString:@"cleanup"]) {
        [self freeContext];
        result(nil);
    } else {
        result(FlutterMethodNotImplemented);
    }
}

- (void)handleInit:(FlutterMethodCall*)call result:(FlutterResult)result {
    NSDictionary *args = call.arguments;
    NSString *modelPath = args[@"modelPath"];
    NSNumber *threads = args[@"threads"] ?: @0;

    if (!modelPath) {
        result([FlutterError errorWithCode:@"invalid_args" message:@"Missing modelPath" details:nil]);
        return;
    }

    NSLog(@"[Whisper] Init with model: %@", modelPath);
    BOOL ok = [self initializeContext:modelPath threads:[threads intValue]];
    NSLog(ok ? @"[Whisper] Init OK" : @"[Whisper] Init FAILED");
    result(@(ok));
}

- (void)handleTranscribeRaw:(FlutterMethodCall*)call result:(FlutterResult)result {
    NSDictionary *args = call.arguments;

    [self.contextLock lock];
    if (self.busy) {
        [self.contextLock unlock];
        result([FlutterError errorWithCode:@"busy" message:@"Transcription already in progress" details:nil]);
        return;
    }
    self.busy = YES;
    self.cancelRequested = NO;
    [self.contextLock unlock];

    FlutterStandardTypedData *pcmData = args[@"pcmBytes"];
    if (!pcmData) {
        [self.contextLock lock];
        self.busy = NO;
        [self.contextLock unlock];
        result([FlutterError errorWithCode:@"invalid_args" message:@"Missing pcmBytes" details:nil]);
        return;
    }

    NSInteger sampleRate = [args[@"sampleRate"] integerValue] ?: 16000;
    NSInteger channels = [args[@"channels"] integerValue] ?: 1;
    NSString *language = args[@"language"] ?: @"auto";
    if (channels <= 0) {
        [self.contextLock lock];
        self.busy = NO;
        [self.contextLock unlock];
        result([FlutterError errorWithCode:@"invalid_args" message:@"channels must be > 0" details:nil]);
        return;
    }

    [self.contextLock lock];
    if (!self.ctx) {
        self.busy = NO;
        [self.contextLock unlock];
        NSLog(@"[Whisper] TranscribeRaw: context is null!");
        result([FlutterError errorWithCode:@"not_initialized" message:@"Whisper context not initialized" details:nil]);
        return;
    }
    [self.contextLock unlock];

    // Convert PCM-16LE to float32 samples
    NSData *data = pcmData.data;
    const int16_t *int16Ptr = (const int16_t *)[data bytes];
    size_t sampleCount = data.length / (2 * (size_t)channels);

    // Fast path: convert directly to contiguous float buffer (first channel only).
    float *samplesArray = malloc(sampleCount * sizeof(float));
    if (samplesArray == NULL) {
        [self.contextLock lock];
        self.busy = NO;
        [self.contextLock unlock];
        result([FlutterError errorWithCode:@"alloc_failed" message:@"Failed to allocate audio buffer" details:nil]);
        return;
    }
    for (size_t i = 0; i < sampleCount; i++) {
        samplesArray[i] = (float)int16Ptr[i * (size_t)channels] / 32768.0f;
    }

    NSLog(@"[Whisper] Transcribing %zu samples, lang=%@", sampleCount, language);

    NSString *transcription = [self transcribePcm:samplesArray
                                            count:(int)sampleCount
                                       sampleRate:(int)sampleRate
                                         language:language];

    free(samplesArray);

    NSLog(@"[Whisper] Transcription completed, characters=%lu", (unsigned long)[transcription length]);

    [self.contextLock lock];
    self.busy = NO;
    [self.contextLock unlock];
    result(transcription);
}

- (BOOL)initializeContext:(NSString *)modelPath threads:(int)threads {
    [self.contextLock lock];

    if (self.ctx) {
        NSLog(@"[Whisper] Already initialized, reusing context");
        [self.contextLock unlock];
        return YES;
    }

    const int hw = whisper_physical_core_count();
    self.nThreads = threads > 0 ? MIN(threads, hw) : hw;
    self.nThreads = MAX(1, self.nThreads);
    NSLog(@"[Whisper] Using %d threads", self.nThreads);

    struct whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu = true;
    cparams.flash_attn = true;
    cparams.gpu_device = 0;

    NSLog(@"[Whisper] Loading model from: %@", modelPath);
    self.ctx = whisper_init_from_file_with_params([modelPath UTF8String], cparams);

    [self.contextLock unlock];

    if (self.ctx) {
        NSLog(@"[Whisper] Model loaded successfully");
        return YES;
    } else {
        NSLog(@"[Whisper] FAILED to load model!");
        return NO;
    }
}

- (NSString *)transcribePcm:(float *)samples count:(int)count sampleRate:(int)sampleRate language:(NSString *)language {
    [self.contextLock lock];

    if (!self.ctx || count == 0) {
        NSLog(@"[Whisper] TranscribePcm: no context or empty samples");
        [self.contextLock unlock];
        return @"";
    }

    struct whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);

    wparams.n_threads = self.nThreads;
    wparams.language = [language UTF8String];
    wparams.print_progress = false;
    wparams.print_special = false;
    wparams.print_realtime = false;
    wparams.print_timestamps = false;
    wparams.no_timestamps = true;
    wparams.single_segment = true;
    wparams.abort_callback = whisper_abort_callback;
    wparams.abort_callback_user_data = (__bridge void *)self;

    // Reduce encoder context for short clips; avoids paying full 30s encoder cost.
    const float audioSeconds = (sampleRate > 0) ? ((float)count / (float)sampleRate) : ((float)count / 16000.0f);
    if (audioSeconds < 30.0f) {
        int ctxFrames = (int)ceilf(audioSeconds / 30.0f * 1500.0f / 64.0f) * 64;
        wparams.audio_ctx = MAX(512, ctxFrames);
    } else {
        wparams.audio_ctx = 0; // 0 = whisper default full context window
    }
    NSLog(@"[Whisper] audio_ctx=%d for %.2fs audio", wparams.audio_ctx, audioSeconds);

    NSLog(@"[Whisper] Running inference on %d float samples...", count);

    int ret = whisper_full(self.ctx, wparams, samples, count);
    if (ret != 0) {
        NSLog(@"[Whisper] whisper_full returned error: %d", ret);
        [self.contextLock unlock];
        return @"";
    }

    int nSegments = whisper_full_n_segments(self.ctx);
    NSLog(@"[Whisper] Got %d segments", nSegments);

    NSMutableString *result = [NSMutableString string];
    for (int i = 0; i < nSegments; i++) {
        const char *text = whisper_full_get_segment_text(self.ctx, i);
        if (text) {
            if (result.length > 0) {
                [result appendString:@" "];
            }
            [result appendString:[NSString stringWithUTF8String:text]];
        }
    }

    [self.contextLock unlock];

    return [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

static bool whisper_abort_callback(void *user_data) {
    if (user_data == NULL) {
        return false;
    }
    WhisperPlugin *plugin = (__bridge WhisperPlugin *)user_data;
    return plugin.cancelRequested;
}

- (void)freeContext {
    [self.contextLock lock];

    if (self.ctx) {
        whisper_free(self.ctx);
        self.ctx = NULL;
        NSLog(@"[Whisper] Context freed");
    }

    [self.contextLock unlock];
}

@end
