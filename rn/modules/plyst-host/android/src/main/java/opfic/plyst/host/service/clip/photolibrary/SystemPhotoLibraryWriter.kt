package opfic.plyst.host.service.clip.photolibrary

import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.ContextCompat
import com.facebook.react.modules.core.PermissionAwareActivity
import java.io.IOException
import java.util.UUID
import kotlin.coroutines.resume
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import opfic.plyst.host.service.clip.image.ClipImageContentType

// Android 10부터는 권한 없이 사진 모음에 추가하고 그보다 낮으면 iOS처럼 저장할 때 권한을 요청
class SystemPhotoLibraryWriter(
  private val context: Context,
  private val currentActivity: () -> Activity?,
) : PhotoLibraryWriter {
  override suspend fun requestAddAuthorization(): PhotoLibraryAuthorization {
    if (Build.VERSION_CODES.Q <= Build.VERSION.SDK_INT || isGranted()) return PhotoLibraryAuthorization.AUTHORIZED
    return withContext(Dispatchers.Main) {
      val activity = currentActivity() as? PermissionAwareActivity ?: return@withContext PhotoLibraryAuthorization.DENIED
      suspendCancellableCoroutine { continuation ->
        activity.requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), REQUEST_CODE) { code, _, results ->
          if (code != REQUEST_CODE) return@requestPermissions false
          val isGranted = results.firstOrNull() == PackageManager.PERMISSION_GRANTED
          if (continuation.isActive) {
            continuation.resume(if (isGranted) PhotoLibraryAuthorization.AUTHORIZED else PhotoLibraryAuthorization.DENIED)
          }
          true
        }
      }
    }
  }

  override suspend fun write(
    data: ByteArray,
    contentType: String,
  ) = withContext(Dispatchers.IO) {
    val resolver = context.contentResolver
    val extension = ClipImageContentType.fileExtension(contentType)
    val values =
      ContentValues().apply {
        put(MediaStore.Images.Media.DISPLAY_NAME, "Plyst-${UUID.randomUUID()}.$extension")
        put(MediaStore.Images.Media.MIME_TYPE, ClipImageContentType.mimeType(contentType) ?: "image/png")
        if (Build.VERSION_CODES.Q <= Build.VERSION.SDK_INT) {
          put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/Plyst")
          put(MediaStore.Images.Media.IS_PENDING, 1)
        }
      }
    val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: throw IOException()
    try {
      resolver.openOutputStream(uri)?.use { it.write(data) } ?: throw IOException()
      if (Build.VERSION_CODES.Q <= Build.VERSION.SDK_INT) {
        resolver.update(uri, ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }, null, null)
      }
    } catch (error: Exception) {
      resolver.delete(uri, null, null)
      throw error
    }
    Unit
  }

  private fun isGranted() =
    ContextCompat.checkSelfPermission(context, Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED

  private companion object {
    const val REQUEST_CODE = 0x5079
  }
}
