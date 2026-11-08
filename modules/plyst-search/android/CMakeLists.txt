# C++ 모듈과 앱이 제공하는 core 공유 라이브러리
cmake_minimum_required(VERSION 3.13)
project(plyst_search)

# android/plyst-core가 Prefab으로 공개하는 libplyst_core.so와 C ABI 헤더
find_package(plyst-core REQUIRED CONFIG)

add_library(plyst_search STATIC ${CMAKE_CURRENT_SOURCE_DIR}/../cpp/PlystSearchModule.cpp)
target_include_directories(plyst_search PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/../cpp)
target_compile_features(plyst_search PRIVATE cxx_std_20)
target_link_libraries(plyst_search jsi reactnative react_codegen_PlystSearchSpec plyst-core::plyst_core log)
