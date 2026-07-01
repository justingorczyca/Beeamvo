cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# ============================================================================
# whisper.cpp integration via FetchContent
# ============================================================================
include(FetchContent)

find_package(CUDAToolkit QUIET)
if(CUDAToolkit_FOUND)
  message(STATUS "CUDA toolkit detected, enabling whisper.cpp CUDA backend")
  set(GGML_CUDA ON CACHE BOOL "Enable ggml CUDA backend" FORCE)
else()
  message(STATUS "CUDA toolkit not detected, building whisper.cpp without CUDA")
endif()

message(STATUS "Fetching whisper.cpp from GitHub...")
FetchContent_Declare(
  whisper
  GIT_REPOSITORY https://github.com/ggml-org/whisper.cpp.git
  GIT_TAG        9386f239401074690479731c1e41683fbbeac557 # v1.8.4
)

# Disable unnecessary targets in whisper to speed up build
set(WHISPER_BUILD_TESTS OFF CACHE BOOL "Disable whisper tests" FORCE)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "Disable whisper examples" FORCE)
set(WHISPER_BUILD_SERVER OFF CACHE BOOL "Disable whisper server" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build static library" FORCE)
set(WHISPER_BUILD_SHARED_LIB OFF CACHE BOOL "Disable shared library" FORCE)

FetchContent_GetProperties(whisper)
if(NOT whisper_POPULATED)
  FetchContent_Populate(whisper)
  add_subdirectory(${whisper_SOURCE_DIR} ${whisper_BINARY_DIR} EXCLUDE_FROM_ALL)
endif()

# ============================================================================
# Application target
# ============================================================================
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "whisper_plugin.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

apply_standard_settings(${BINARY_NAME})

target_compile_definitions(${BINARY_NAME} PRIVATE "APPLICATION_ID=\"com.beeamvo.app\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

if(CUDAToolkit_FOUND)
  target_compile_definitions(${BINARY_NAME} PRIVATE "GGML_USE_CUDA")
endif()

target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${BINARY_NAME} PRIVATE whisper)
target_link_libraries(${BINARY_NAME} PRIVATE pthread)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
target_include_directories(${BINARY_NAME} PRIVATE "${whisper_SOURCE_DIR}")
target_include_directories(${BINARY_NAME} PRIVATE "${whisper_SOURCE_DIR}/include")
target_include_directories(${BINARY_NAME} PRIVATE "${whisper_SOURCE_DIR}/ggml/include")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# Copy model file to output directory if it exists
set(MODEL_SOURCE "${CMAKE_SOURCE_DIR}/../../../ggml-tiny.bin")
if(EXISTS ${MODEL_SOURCE})
  add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
    ${MODEL_SOURCE}
    $<TARGET_FILE_DIR:${BINARY_NAME}>/ggml-tiny.bin)
  message(STATUS "Will copy ggml-tiny.bin to output directory")
endif()
