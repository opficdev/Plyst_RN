package opfic.plyst.host.model

import opfic.plyst.core.ClipSortOrderValue

enum class ClipSortOrder {
  // 생성 시각의 내림차순으로 정렬
  // 생성 시각이 같으면 대문자 식별자 문자열의 오름차순으로 순서를 결정
  CREATED_AT,
}

internal val ClipSortOrder.coreValue: ClipSortOrderValue
  get() =
    when (this) {
      ClipSortOrder.CREATED_AT -> ClipSortOrderValue.CREATED_AT
    }
