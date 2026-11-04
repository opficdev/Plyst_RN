package opfic.plyst.host.service.clip.image

// iOS 저장소와 같은 통일된 타입 식별자와 Android MIME 형식의 대응
object ClipImageContentType {
  private val identifiers =
    mapOf(
      "image/png" to "public.png",
      "image/jpeg" to "public.jpeg",
      "image/gif" to "com.compuserve.gif",
      "image/webp" to "org.webmproject.webp",
      "image/heif" to "public.heif",
      "image/heic" to "public.heic",
      "image/avif" to "public.avif",
      "image/bmp" to "com.microsoft.bmp",
      "image/x-ms-bmp" to "com.microsoft.bmp",
      "image/x-ico" to "com.microsoft.ico",
    )

  // 대응이 없으면 null
  fun identifier(mimeType: String) = identifiers[mimeType.lowercase()]

  fun mimeType(identifier: String) = identifiers.entries.firstOrNull { it.value == identifier }?.key

  fun fileExtension(identifier: String) =
    when (identifier) {
      "public.jpeg" -> "jpg"
      "com.compuserve.gif" -> "gif"
      "org.webmproject.webp" -> "webp"
      "public.heif" -> "heif"
      "public.heic" -> "heic"
      "public.avif" -> "avif"
      "com.microsoft.bmp" -> "bmp"
      "com.microsoft.ico" -> "ico"
      else -> "png"
    }
}
