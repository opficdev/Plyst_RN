package opfic.plyst.host.model

import kotlin.math.roundToLong

// 1970-01-01부터 2001-01-01까지의 초
private const val REFERENCE_DATE_OFFSET = 978_307_200.0

// 저장소 열과 코어가 쓰는 2001-01-01 기준 초
internal val Long.referenceSeconds: Double
  get() = this / 1000.0 - REFERENCE_DATE_OFFSET

internal val Double.epochMilliseconds: Long
  get() = ((this + REFERENCE_DATE_OFFSET) * 1000).roundToLong()

// 코어 경계의 UTF-8 변환은 짝 없는 서로게이트에서 예외를 던지므로 U+FFFD로 치환
// Swift String에는 짝 없는 서로게이트가 없어 iOS에는 없는 경로
internal val String.wellFormed: String
  get() {
    if (none { it.isSurrogate() }) return this
    val result = StringBuilder(length)
    var index = 0
    while (index < length) {
      val scalar = codePointAt(index)
      if (scalar in Char.MIN_SURROGATE.code..Char.MAX_SURROGATE.code) {
        result.append('�')
      } else {
        result.appendCodePoint(scalar)
      }
      index += Character.charCount(scalar)
    }
    return result.toString()
  }
