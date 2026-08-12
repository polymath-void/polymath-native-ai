cmake_minimum_required(VERSION 3.18)
project(native_ai_engine VERSION 1.0.0 LANGUAGES CXX C)

# Set C++ Standard
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Export compile commands for IDEs / Language Servers
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Option Flags
option(ENABLE_NEON "Enable ARM NEON SIMD optimizations" ON)
option(ENABLE_STATIC "Statically link target binary for /system/bin portability" OFF)
option(BUILD_RUST_BRIDGE "Include Rust bridge bindings" OFF)

# Optimization Flags
if(CMAKE_BUILD_TYPE STREQUAL "Release" OR NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Choose the type of build." FORCE)
    add_compile_options(-O3 -ffast-math -funroll-loops)
endif()

# Platform and SIMD Flags
if(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64" OR ANDROID_ABI STREQUAL "arm64-v8a")
    message(STATUS "Configuring for ARM64 Architecture")
    if(ENABLE_NEON)
        add_compile_options(-march=armv8-a+fp+simd)
        add_definitions(-DENABLE_NEON=1)
    endif()
endif()

# Android NDK Specific Setup
if(ANDROID OR DEFINED ANDROID_ABI)
    message(STATUS "Building with Android NDK for ABI: ${ANDROID_ABI}")
    add_definitions(-D__ANDROID__=1)
    find_library(ANDROID_LOG_LIB log)
    set(EXTRA_LIBS ${ANDROID_LOG_LIB})
else()
    set(EXTRA_LIBS "")
endif()

# Static Linking Configuration
if(ENABLE_STATIC)
    message(STATUS "Configuring static binary build for /system/bin")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -static")
endif()

# Include Directories
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

# Source Files
set(SOURCES
    src/main.cpp
    src/ai_engine.cpp
    src/model_loader.cpp
)

# Executable Target
add_executable(native_ai_engine ${SOURCES})

# Target Compiler Features and Libraries
target_link_libraries(native_ai_engine PRIVATE pthread ${CMAKE_DL_LIBS} ${EXTRA_LIBS})

# Installation rule for Android /system/bin target
install(TARGETS native_ai_engine DESTINATION bin)
