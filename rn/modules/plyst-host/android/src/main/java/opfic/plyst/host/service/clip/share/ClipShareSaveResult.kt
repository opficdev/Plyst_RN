package opfic.plyst.host.service.clip.share

import opfic.plyst.host.model.Clip

sealed interface ClipShareSaveResult {
  data class Saved(val clip: Clip) : ClipShareSaveResult

  // 지원하는 첨부가 없거나 공백뿐인 텍스트
  // 기록을 남기지 않음
  data object Empty : ClipShareSaveResult

  // 지원하는 첨부에서 값을 읽지 못했음
  // 기록을 남기지 않음
  data object LoadFailed : ClipShareSaveResult
}
