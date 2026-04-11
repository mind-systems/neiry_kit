cmake_minimum_required(VERSION 3.18)
project(neiry_jni)

set(CAPSULE_LIBS "${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/arm64-v8a")
set(CAPSULE_HEADERS "${CMAKE_CURRENT_SOURCE_DIR}/../../../../official/iOS/CapsuleClient.framework/Headers")

add_library(neiry_jni SHARED
    jni_bridge.cpp
    jni_device_locator.cpp
    jni_device.cpp
    jni_nfb.cpp
    jni_nfb_calibrator.cpp
    jni_emotions.cpp
    jni_physio.cpp
    jni_cardio.cpp
)

target_include_directories(neiry_jni PRIVATE ${CAPSULE_HEADERS})

target_link_libraries(neiry_jni
    ${CAPSULE_LIBS}/libCapsuleClient.so
    android
    log
)
