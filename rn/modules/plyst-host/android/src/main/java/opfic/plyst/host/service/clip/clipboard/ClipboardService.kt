package opfic.plyst.host.service.clip.clipboard

import java.util.UUID
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import opfic.plyst.core.ClipboardWriter
import opfic.plyst.host.adapter.clip.ClipCoreAdapter
import opfic.plyst.host.adapter.clip.ClipboardCopyResult
import opfic.plyst.host.adapter.clip.ClipboardSaveResult

// 사용자 요청에 따라 클립을 저장하거나 다시 복사
// 구성 시에는 클립보드에 접근하지 않음
// 순서와 결과 판정은 코어의 ClipboardOperations가 맡고 이 타입은 읽기, 플랫폼 클립보드 직렬화, 쓰기 구현 보유를 담당
class ClipboardService(
  private val core: ClipCoreAdapter,
  private val reader: ClipboardReader,
  private val writer: ClipboardWriter,
) {
  // 저장과 복사 작업 전체를 요청 순서대로 처리
  private val mutex = Mutex()

  // 저장소 오류와 CancellationException은 그대로 전파
  suspend fun saveCurrentClipboard(): ClipboardSaveResult =
    mutex.withLock {
      when (val result = reader.read()) {
        is ClipboardReadResult.Text -> core.saveClipboardText(result.text)
        is ClipboardReadResult.Image -> core.saveClipboardImage(result.data)
        ClipboardReadResult.Empty -> ClipboardSaveResult.Empty
        ClipboardReadResult.Unsupported -> ClipboardSaveResult.Unsupported
        ClipboardReadResult.AccessFailed -> ClipboardSaveResult.AccessFailed
      }
    }

  // 쓰기 전 오류는 전파
  // 쓰기가 확인된 이후의 사용 시각 저장 실패는 부분 성공으로 반환
  suspend fun copy(id: UUID): ClipboardCopyResult = mutex.withLock { core.copy(id, writer) }
}
