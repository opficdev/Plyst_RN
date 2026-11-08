// rust/src/lib.rs가 내보내는 C ABI
// 포인터는 호출하는 동안만 유효

#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct PlystSearchIndex PlystSearchIndex;
typedef struct PlystSearchSyncBuilder PlystSearchSyncBuilder;

// UTF-16 코드 단위 배열
typedef struct {
  const uint16_t *data;
  size_t length;
} PlystSearchText;

// 0 이름, 1 본문, 2 시간 0, 3 시간 1
typedef uint8_t PlystSearchField;

PlystSearchIndex *plyst_search_create(void);
void plyst_search_free(PlystSearchIndex *index);
// sync 한 번 동안 JS 문자열 조각을 복사 없이 넘김
// 텍스트마다 append로 이어 붙인 뒤 id(order 순서)나 field로 확정
PlystSearchSyncBuilder *plyst_search_sync_begin(size_t order_count);
// ascii면 data는 length개의 바이트
// 아니면 UTF-16 단위
bool plyst_search_sync_append(
    PlystSearchSyncBuilder *builder,
    const void *data,
    size_t length,
    bool ascii);
bool plyst_search_sync_id(PlystSearchSyncBuilder *builder);
bool plyst_search_sync_field(
    PlystSearchSyncBuilder *builder,
    uint32_t position,
    PlystSearchField field);
// builder를 해제하고 commit이 true면 order에 없는 클립을 지우며 표에 반영
bool plyst_search_sync_end(
    PlystSearchIndex *index,
    PlystSearchSyncBuilder *builder,
    bool commit);
bool plyst_search_prebuild(PlystSearchIndex *index);
void plyst_search_cancel_prebuild(PlystSearchIndex *index);
// out 용량은 마지막 sync의 order_count 이상
bool plyst_search_filter(
    PlystSearchIndex *index,
    PlystSearchText query,
    uint32_t *out,
    size_t capacity,
    size_t *out_count);
// [location, length] 쌍
// out 용량은 text.length * 2 이상
// stored는 text가 마지막 sync로 보낸 값과 같을 때 true
bool plyst_search_ranges(
    PlystSearchIndex *index,
    PlystSearchText id,
    PlystSearchField field,
    PlystSearchText text,
    bool stored,
    PlystSearchText query,
    uint32_t *out,
    size_t capacity,
    size_t *pair_count);
bool plyst_search_excerpt_start(
    PlystSearchText body,
    uint32_t location,
    uint32_t *start);

#ifdef __cplusplus
}
#endif
