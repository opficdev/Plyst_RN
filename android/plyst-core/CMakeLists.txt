# Rust 정적 라이브러리를 JNA가 읽는 공유 라이브러리로 묶음
cmake_minimum_required(VERSION 3.13)
project(plyst_core C)

if(ANDROID_ABI STREQUAL "arm64-v8a")
  set(RUST_TARGET aarch64-linux-android)
elseif(ANDROID_ABI STREQUAL "armeabi-v7a")
  set(RUST_TARGET armv7-linux-androideabi)
elseif(ANDROID_ABI STREQUAL "x86_64")
  set(RUST_TARGET x86_64-linux-android)
elseif(ANDROID_ABI STREQUAL "x86")
  set(RUST_TARGET i686-linux-android)
else()
  message(FATAL_ERROR "plyst-core가 지원하지 않는 ABI: ${ANDROID_ABI}")
endif()

# .mise.toml의 Rust 버전을 쓰도록 mise가 있으면 mise로 실행
find_program(MISE_PROGRAM mise HINTS /opt/homebrew/bin /usr/local/bin $ENV{HOME}/.local/bin)
if(MISE_PROGRAM)
  set(CARGO_COMMAND ${MISE_PROGRAM} exec -- cargo)
else()
  find_program(CARGO_PROGRAM cargo HINTS $ENV{HOME}/.cargo/bin REQUIRED)
  set(CARGO_COMMAND ${CARGO_PROGRAM})
endif()

string(REPLACE "-" "_" RUST_TARGET_ENV ${RUST_TARGET})

set(RUST_CRATE ${CMAKE_CURRENT_SOURCE_DIR}/../../core)
set(RUST_TARGET_DIR ${CMAKE_CURRENT_BINARY_DIR}/rust)
set(RUST_LIBRARY ${RUST_TARGET_DIR}/${RUST_TARGET}/release/libplyst_core.a)
file(GLOB_RECURSE RUST_SOURCES CONFIGURE_DEPENDS ${RUST_CRATE}/src/*.rs)

add_custom_command(
  OUTPUT ${RUST_LIBRARY}
  # rusqlite의 번들 SQLite를 NDK 컴파일러로 빌드
  COMMAND ${CMAKE_COMMAND} -E env
    CC_${RUST_TARGET_ENV}=${CMAKE_C_COMPILER}
    AR_${RUST_TARGET_ENV}=${CMAKE_AR}
    CFLAGS_${RUST_TARGET_ENV}=--target=${CMAKE_C_COMPILER_TARGET}
    ${CARGO_COMMAND} build --release --locked --target ${RUST_TARGET} --target-dir ${RUST_TARGET_DIR}
  WORKING_DIRECTORY ${RUST_CRATE}
  DEPENDS ${RUST_SOURCES} ${RUST_CRATE}/Cargo.toml ${RUST_CRATE}/Cargo.lock ${RUST_CRATE}/.cargo/config.toml
  VERBATIM
)
add_custom_target(plyst_core_rust DEPENDS ${RUST_LIBRARY})

add_library(plyst_core SHARED src/main/c/plyst_core_stub.c)
add_dependencies(plyst_core plyst_core_rust)
# 정적 라이브러리가 바뀌면 다시 링크
set_target_properties(plyst_core PROPERTIES LINK_DEPENDS ${RUST_LIBRARY})
target_link_options(plyst_core PRIVATE -Wl,--whole-archive ${RUST_LIBRARY} -Wl,--no-whole-archive -Wl,-z,max-page-size=16384)
target_link_libraries(plyst_core log dl m)
