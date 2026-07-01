Pod::Spec.new do |s|
  ggml_version       = '0.9.8'
  ggml_commit        = 'unknown'

  s.name             = 'whisper.cpp'
  s.version          = '1.8.4'
  s.summary          = 'Port of OpenAI Whisper in C/C++'
  s.description      = <<-DESC
  High-performance inference of OpenAI's Whisper automatic speech recognition model using C/C++
                       DESC
  s.homepage         = 'https://github.com/ggml-org/whisper.cpp'
  s.license          = { :type => 'MIT', :file => 'Runner/whisper.cpp/LICENSE' }
  s.author           = { 'Georgi Gerganov' => 'ggerganov@gmail.com' }
  s.source           = { :git => 'https://github.com/ggml-org/whisper.cpp.git', :commit => '9386f239401074690479731c1e41683fbbeac557' }

  s.platform         = :osx, '11.0'

  s.source_files     = 'Runner/whisper.cpp/include/**/*.h',
                       'Runner/whisper.cpp/src/**/*.h',
                       'Runner/whisper.cpp/src/whisper.cpp',
                       'Runner/whisper.cpp/src/coreml/*.{m,mm}',
                       'Runner/whisper.cpp/ggml/include/**/*.h',
                       'Runner/whisper.cpp/ggml/src/ggml.c',
                       'Runner/whisper.cpp/ggml/src/ggml.cpp',
                       'Runner/whisper.cpp/ggml/src/gguf.cpp',
                       'Runner/whisper.cpp/ggml/src/ggml-alloc.c',
                       'Runner/whisper.cpp/ggml/src/ggml-backend.cpp',
                       'Runner/whisper.cpp/ggml/src/ggml-backend-dl.cpp',
                       'Runner/whisper.cpp/ggml/src/ggml-backend-reg.cpp',
                       'Runner/whisper.cpp/ggml/src/ggml-opt.cpp',
                       'Runner/whisper.cpp/ggml/src/ggml-threading.cpp',
                       'Runner/whisper.cpp/ggml/src/ggml-quants.c',
                       'Runner/whisper.cpp/ggml/src/ggml-cpu/ggml-cpu.c',
                       'Runner/whisper.cpp/ggml/src/ggml-cpu/ggml-cpu.cpp',
                       'Runner/whisper.cpp/ggml/src/ggml-cpu/repack.cpp',
                       'Runner/whisper.cpp/ggml/src/ggml-cpu/hbm.cpp',
                       'Runner/whisper.cpp/ggml/src/ggml-cpu/quants.c',
                       'Runner/whisper.cpp/ggml/src/ggml-cpu/traits.cpp',
                       'Runner/whisper.cpp/ggml/src/ggml-cpu/binary-ops.cpp',
                       'Runner/whisper.cpp/ggml/src/ggml-cpu/unary-ops.cpp',
                       'Runner/whisper.cpp/ggml/src/ggml-cpu/vec.cpp',
                       'Runner/whisper.cpp/ggml/src/ggml-cpu/ops.cpp',
                       'Runner/whisper.cpp/ggml/src/ggml-cpu/ggml-cpu-arm-quants.c',
                       'Runner/whisper.cpp/ggml/src/ggml-cpu/ggml-cpu-arm-repack.cpp',
                       'Runner/whisper.cpp/ggml/src/ggml-cpu/ggml-cpu-x86-quants.c',
                       'Runner/whisper.cpp/ggml/src/ggml-cpu/ggml-cpu-x86-repack.cpp',
                       'Runner/whisper.cpp/ggml/src/ggml-blas/ggml-blas.cpp',
                       'Runner/whisper.cpp/ggml/src/ggml-metal/ggml-metal.cpp',
                       'Runner/whisper.cpp/ggml/src/ggml-metal/ggml-metal-device.m',
                       'Runner/whisper.cpp/ggml/src/ggml-metal/ggml-metal-device.cpp',
                       'Runner/whisper.cpp/ggml/src/ggml-metal/ggml-metal-common.cpp',
                       'Runner/whisper.cpp/ggml/src/ggml-metal/ggml-metal-context.m',
                       'Runner/whisper.cpp/ggml/src/ggml-metal/ggml-metal-ops.cpp'
  s.resources        = ['Runner/whisper.cpp/ggml/src/ggml-metal/ggml-metal.metal',
                        'Runner/whisper.cpp/ggml/src/ggml-metal/ggml-metal-impl.h',
                        'Runner/whisper.cpp/ggml/src/ggml-common.h']
  s.public_header_files = 'Runner/whisper.cpp/include/whisper.h',
                          'Runner/whisper.cpp/ggml/include/ggml.h',
                          'Runner/whisper.cpp/ggml/include/ggml-alloc.h',
                          'Runner/whisper.cpp/ggml/include/ggml-cpu.h',
                          'Runner/whisper.cpp/ggml/include/ggml-backend.h'
  
  # Frameworks for macOS GPU / ANE support and CPU fallback
  s.frameworks       = 'Foundation', 'Metal', 'MetalKit', 'Accelerate', 'CoreML'

  s.pod_target_xcconfig = {
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/Runner/whisper.cpp" "${PODS_TARGET_SRCROOT}/Runner/whisper.cpp/include" "${PODS_TARGET_SRCROOT}/Runner/whisper.cpp/src" "${PODS_TARGET_SRCROOT}/Runner/whisper.cpp/src/coreml" "${PODS_TARGET_SRCROOT}/Runner/whisper.cpp/ggml/include" "${PODS_TARGET_SRCROOT}/Runner/whisper.cpp/ggml/src" "${PODS_TARGET_SRCROOT}/Runner/whisper.cpp/ggml/src/ggml-cpu" "${PODS_TARGET_SRCROOT}/Runner/whisper.cpp/ggml/src/ggml-blas" "${PODS_TARGET_SRCROOT}/Runner/whisper.cpp/ggml/src/ggml-metal" "$(inherited)"',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'GCC_PREPROCESSOR_DEFINITIONS' => "$(inherited) WHISPER_VERSION=\\\"#{s.version}\\\" GGML_VERSION=\\\"#{ggml_version}\\\" GGML_COMMIT=\\\"#{ggml_commit}\\\""
  }

  s.requires_arc = ['Runner/whisper.cpp/src/coreml/*.m', 'Runner/whisper.cpp/src/coreml/*.mm']

  # Preserve the static library
  s.static_framework = true

  # Mirror the upstream macOS build: CPU + BLAS + Metal by default, with
  # Core ML enabled when a matching *-encoder.mlmodelc is present.
  s.compiler_flags = '-Wno-unused-function -Wno-unused-variable -DGGML_USE_CPU -DGGML_USE_BLAS -DGGML_USE_METAL -DGGML_USE_ACCELERATE -DGGML_BLAS_USE_ACCELERATE -DGGML_METAL_NDEBUG -DACCELERATE_NEW_LAPACK -DACCELERATE_LAPACK_ILP64 -DWHISPER_USE_COREML -DWHISPER_COREML_ALLOW_FALLBACK'
end
