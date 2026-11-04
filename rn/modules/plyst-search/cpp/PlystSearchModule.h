#pragma once

#if __has_include(<ReactCodegen/PlystSearchSpecJSI.h>)
#include <ReactCodegen/PlystSearchSpecJSI.h>
#else
#include <PlystSearchSpecJSI.h>
#endif

#include <memory>
#include <optional>
#include <unordered_map>

#include "plyst_search.h"

namespace facebook::react {

// JS 문자열을 UTF-16 그대로 Rust 인덱스에 넘기는 동기 모듈
// 핸들 표는 JS 스레드에서만 접근하므로 잠금 없음
class PlystSearchModule : public NativePlystSearchCxxSpec<PlystSearchModule> {
 public:
  static constexpr const char *kModuleName = "PlystSearch";

  explicit PlystSearchModule(std::shared_ptr<CallInvoker> jsInvoker);
  ~PlystSearchModule() override;

  double createIndex(jsi::Runtime &rt);
  void freeIndex(jsi::Runtime &rt, double handle);
  bool sync(
      jsi::Runtime &rt,
      double handle,
      jsi::Array order,
      jsi::Array positions,
      jsi::Array fields,
      jsi::Array texts);
  bool prebuild(jsi::Runtime &rt, double handle);
  void cancelPrebuild(jsi::Runtime &rt, double handle);
  std::optional<jsi::Array> filter(jsi::Runtime &rt, double handle, jsi::String query);
  std::optional<jsi::Object> cardText(
      jsi::Runtime &rt,
      double handle,
      jsi::String id,
      jsi::String name,
      jsi::String body,
      jsi::String query,
      bool isSynced);

 private:
  // 마지막 sync의 order 수는 filter 출력 용량
  struct Entry {
    PlystSearchIndex *index;
    size_t orderCount;
  };

  Entry *find(double handle);

  std::unordered_map<uint32_t, Entry> indexes_;
  uint32_t nextHandle_ = 1;
};

} // namespace facebook::react
