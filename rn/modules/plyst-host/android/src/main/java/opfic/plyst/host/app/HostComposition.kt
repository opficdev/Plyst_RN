package opfic.plyst.host.app

import android.app.Activity
import android.content.Context
import android.util.Log
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import opfic.plyst.host.adapter.clip.ClipCoreAdapter
import opfic.plyst.host.service.clip.clipboard.ClipboardService
import opfic.plyst.host.service.clip.clipboard.SystemClipboardReader
import opfic.plyst.host.service.clip.clipboard.SystemClipboardWriter
import opfic.plyst.host.service.clip.download.SystemClipImageDownloader
import opfic.plyst.host.service.clip.photolibrary.ClipPhotoLibraryService
import opfic.plyst.host.service.clip.photolibrary.SystemPhotoLibraryWriter
import opfic.plyst.host.service.clip.share.ClipShareService

// 앱 프로세스가 유지되는 동안 공유하는 Service를 만들고 소유
// iOS SceneComposition과 같은 저장 위치 구성
// ShareActivity가 같은 프로세스에서 이 저장소에 바로 쓰므로 공유 수신함과 반입은 없음
class HostComposition(
  context: Context,
  currentActivity: () -> Activity?,
) {
  val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
  val core: ClipCoreAdapter
  val clipboard: ClipboardService
  val photos: ClipPhotoLibraryService
  val shares: ClipShareService

  init {
    // 백업에서 제외되는 위치
    val directory = File(context.noBackupFilesDir, "Plyst")
    core = ClipCoreAdapter(File(directory, "clips.sqlite"), File(directory, "images"))
    clipboard = ClipboardService(core, SystemClipboardReader(context), SystemClipboardWriter(context))
    photos = ClipPhotoLibraryService(core, SystemPhotoLibraryWriter(context, currentActivity))
    shares = ClipShareService(context, core, SystemClipImageDownloader())
  }

  fun makeAdapter() =
    ClipBridgeAdapter(
      core = core,
      clipboard = clipboard,
      photos = photos,
      scope = scope,
    )

  fun startPendingCleanupRecovery() {
    scope.launch {
      try {
        val pending = core.recoverPendingCleanup()
        if (pending.isNotEmpty()) Log.w(TAG, "이미지 정리 보류: ${pending.size}개")
      } catch (error: Exception) {
        Log.e(TAG, "이미지 정리 재시도 실패: ${error.javaClass.simpleName}")
      }
    }
  }

  private companion object {
    const val TAG = "HostComposition"
  }
}
