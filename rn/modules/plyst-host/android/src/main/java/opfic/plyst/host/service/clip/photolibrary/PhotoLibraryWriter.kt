package opfic.plyst.host.service.clip.photolibrary

enum class PhotoLibraryAuthorization {
  AUTHORIZED,
  DENIED,
  RESTRICTED,
}

interface PhotoLibraryWriter {
  suspend fun requestAddAuthorization(): PhotoLibraryAuthorization

  suspend fun write(
    data: ByteArray,
    contentType: String,
  )
}
