#include "PlystSearchModule.h"

#include <string>
#include <vector>

namespace facebook::react {

namespace {

PlystSearchText textOf(const std::u16string &value) {
  return {reinterpret_cast<const uint16_t *>(value.data()), value.size()};
}

jsi::Array arrayOf(jsi::Runtime &rt, const uint32_t *values, size_t count) {
  auto result = jsi::Array(rt, count);
  for (size_t i = 0; i < count; i++) {
    result.setValueAtIndex(rt, i, static_cast<double>(values[i]));
  }
  return result;
}

} // namespace

PlystSearchModule::PlystSearchModule(std::shared_ptr<CallInvoker> jsInvoker)
    : NativePlystSearchCxxSpec(std::move(jsInvoker)) {}

// JS 런타임이 다시 만들어질 때 남은 핸들 전체 해제
PlystSearchModule::~PlystSearchModule() {
  for (auto &[handle, entry] : indexes_) {
    plyst_search_free(entry.index);
  }
}

PlystSearchModule::Entry *PlystSearchModule::find(double handle) {
  auto found = indexes_.find(static_cast<uint32_t>(handle));
  return found == indexes_.end() ? nullptr : &found->second;
}

double PlystSearchModule::createIndex(jsi::Runtime &rt) {
  auto index = plyst_search_create();
  if (index == nullptr) {
    return 0;
  }
  auto handle = nextHandle_++;
  indexes_[handle] = {index, 0};
  return handle;
}

void PlystSearchModule::freeIndex(jsi::Runtime &rt, double handle) {
  auto found = indexes_.find(static_cast<uint32_t>(handle));
  if (found == indexes_.end()) {
    return;
  }
  plyst_search_free(found->second.index);
  indexes_.erase(found);
}

bool PlystSearchModule::sync(
    jsi::Runtime &rt,
    double handle,
    jsi::Array order,
    jsi::Array positions,
    jsi::Array fields,
    jsi::Array texts) {
  auto entry = find(handle);
  if (entry == nullptr) {
    return false;
  }
  auto orderCount = order.size(rt);
  auto fieldCount = texts.size(rt);
  if (positions.size(rt) != fieldCount || fields.size(rt) != fieldCount) {
    return false;
  }
  auto builder = plyst_search_sync_begin(orderCount);
  if (builder == nullptr) {
    return false;
  }
  // Hermes 문자열 메모리를 조각째 Rust 버퍼에 이어 붙임
  auto ok = true;
  auto append = [&](const jsi::Value &value) {
    auto receive = [&](bool ascii, const void *data, size_t length) {
      ok = plyst_search_sync_append(builder, data, length, ascii) && ok;
    };
    value.asString(rt).getStringData(rt, receive);
  };
  for (size_t i = 0; ok && i < orderCount; i++) {
    append(order.getValueAtIndex(rt, i));
    ok = ok && plyst_search_sync_id(builder);
  }
  for (size_t i = 0; ok && i < fieldCount; i++) {
    append(texts.getValueAtIndex(rt, i));
    ok = ok && plyst_search_sync_field(
        builder,
        static_cast<uint32_t>(positions.getValueAtIndex(rt, i).asNumber()),
        static_cast<PlystSearchField>(fields.getValueAtIndex(rt, i).asNumber()));
  }
  if (!plyst_search_sync_end(entry->index, builder, ok) || !ok) {
    return false;
  }
  entry->orderCount = orderCount;
  return true;
}

bool PlystSearchModule::prebuild(jsi::Runtime &rt, double handle) {
  auto entry = find(handle);
  return entry != nullptr && plyst_search_prebuild(entry->index);
}

void PlystSearchModule::cancelPrebuild(jsi::Runtime &rt, double handle) {
  if (auto entry = find(handle)) {
    plyst_search_cancel_prebuild(entry->index);
  }
}

std::optional<jsi::Array> PlystSearchModule::filter(jsi::Runtime &rt, double handle, jsi::String query) {
  auto entry = find(handle);
  if (entry == nullptr) {
    return std::nullopt;
  }
  auto value = query.utf16(rt);
  std::vector<uint32_t> out(entry->orderCount);
  size_t count = 0;
  if (!plyst_search_filter(entry->index, textOf(value), out.data(), out.size(), &count)) {
    return std::nullopt;
  }
  return arrayOf(rt, out.data(), count);
}

std::optional<jsi::Object> PlystSearchModule::cardText(
    jsi::Runtime &rt,
    double handle,
    jsi::String id,
    jsi::String name,
    jsi::String body,
    jsi::String query,
    bool isSynced) {
  auto entry = find(handle);
  if (entry == nullptr) {
    return std::nullopt;
  }
  auto idValue = id.utf16(rt);
  auto nameValue = name.utf16(rt);
  auto bodyValue = body.utf16(rt);
  auto queryValue = query.utf16(rt);
  std::vector<uint32_t> nameRanges(nameValue.size() * 2);
  std::vector<uint32_t> bodyRanges(bodyValue.size() * 2);
  size_t namePairs = 0;
  size_t bodyPairs = 0;
  if (!plyst_search_ranges(
          entry->index,
          textOf(idValue),
          0,
          textOf(nameValue),
          isSynced,
          textOf(queryValue),
          nameRanges.data(),
          nameRanges.size(),
          &namePairs) ||
      !plyst_search_ranges(
          entry->index,
          textOf(idValue),
          1,
          textOf(bodyValue),
          isSynced,
          textOf(queryValue),
          bodyRanges.data(),
          bodyRanges.size(),
          &bodyPairs)) {
    return std::nullopt;
  }
  uint32_t excerptStart = 0;
  if (bodyPairs != 0 && !plyst_search_excerpt_start(textOf(bodyValue), bodyRanges[0], &excerptStart)) {
    return std::nullopt;
  }
  auto result = jsi::Object(rt);
  result.setProperty(rt, "nameRanges", arrayOf(rt, nameRanges.data(), namePairs * 2));
  result.setProperty(rt, "bodyRanges", arrayOf(rt, bodyRanges.data(), bodyPairs * 2));
  result.setProperty(rt, "excerptStart", static_cast<double>(excerptStart));
  return result;
}

} // namespace facebook::react
