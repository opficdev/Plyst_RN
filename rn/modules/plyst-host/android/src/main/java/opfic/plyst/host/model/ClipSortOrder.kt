package opfic.plyst.host.model

enum class ClipSortOrder {
  CREATED_AT;

  // 생성 시각의 내림차순으로 정렬
  // 생성 시각이 같으면 대문자 식별자 문자열의 오름차순으로 순서를 결정
  fun sorted(clips: List<Clip>): List<Clip> =
    clips.sortedWith(
      compareByDescending<Clip> { it.createdAt }.thenBy { it.id.toString().uppercase() },
    )
}
