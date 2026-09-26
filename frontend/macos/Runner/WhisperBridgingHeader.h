#ifndef WhisperBridgingHeader_h
#define WhisperBridgingHeader_h

// whisper.cpp C API declarations for Swift.
// Support both CocoaPods header layouts and local source include layout.
#if __has_include(<whisper_cpp/whisper.h>)
#include <whisper_cpp/whisper.h>
#elif __has_include(<whisper/whisper.h>)
#include <whisper/whisper.h>
#elif __has_include(<whisper.h>)
#include <whisper.h>
#elif __has_include("whisper.cpp/include/whisper.h")
#include "whisper.cpp/include/whisper.h"
#else
#include "whisper.h"
#endif

#endif /* WhisperBridgingHeader_h */
