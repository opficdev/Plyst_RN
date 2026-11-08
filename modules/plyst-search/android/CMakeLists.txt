# C++ 모듈과 Rust 정적 라이브러리
cmake_minimum_required(VERSION 3.13)
project(plyst_search)

if(ANDROID_ABI STREQUAL "arm64-v8a")
  set(RUST_TARGET aarch64-linux-android)
elseif(ANDROID_ABI STREQUAL "armeabi-v7a")
  set(RUST_TARGET armv7-linux-androideabi)
elseif(ANDROID_ABI STREQUAL "x86_64")
  set(RUST_TARGET x86_64-linux-android)
elseif(ANDROID_ABI STREQUAL "x86")
  set(RUST_TARGET i686-linux-android)
else()
  message(FATAL_ERROR "plyst-search가 지원하지 않는 ABI: ${ANDROID_ABI}")
endif()

# .mise.toml의 Rust 버전을 쓰도록 mise가 있으면 mise로 실행
find_program(MISE_PROGRAM mise HINTS /opt/homebrew/bin /usr/local/bin $ENV{HOME}/.local/bin)
if(MISE_PROGRAM)
  set(CARGO_COMMAND ${MISE_PROGRAM} exec -- cargo)
else()
  find_program(CARGO_PROGRAM cargo HINTS $ENV{HOME}/.cargo/bin REQUIRED)
  set(CARGO_COMMAND ${CARGO_PROGRAM})
endif()

set(RUST_CRATE ${CMAKE_CURRENT_SOURCE_DIR}/../rust)
set(RUST_TARGET_DIR ${CMAKE_CURRENT_BINARY_DIR}/rust)
set(RUST_LIBRARY ${RUST_TARGET_DIR}/${RUST_TARGET}/release/libplyst_search_core.a)
file(GLOB RUST_SOURCES CONFIGURE_DEPENDS ${RUST_CRATE}/src/*.rs)

add_custom_command(
  OUTPUT ${RUST_LIBRARY}
  COMMAND ${CARGO_COMMAND} build --release --locked --target ${RUST_TARGET} --target-dir ${RUST_TARGET_DIR}
  WORKING_DIRECTORY ${RUST_CRATE}
  DEPENDS ${RUST_SOURCES} ${RUST_CRATE}/Cargo.toml ${RUST_CRATE}/Cargo.lock
  VERBATIM
)
add_custom_target(plyst_search_rust DEPENDS ${RUST_LIBRARY})

add_library(plyst_search_core STATIC IMPORTED)
set_target_properties(plyst_search_core PROPERTIES IMPORTED_LOCATION ${RUST_LIBRARY})
add_dependencies(plyst_search_core plyst_search_rust)

add_library(plyst_search STATIC ${CMAKE_CURRENT_SOURCE_DIR}/../cpp/PlystSearchModule.cpp)
target_include_directories(plyst_search PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/../cpp)
target_compile_features(plyst_search PRIVATE cxx_std_20)
target_link_libraries(plyst_search jsi reactnative react_codegen_PlystSearchSpec plyst_search_core log dl m)
