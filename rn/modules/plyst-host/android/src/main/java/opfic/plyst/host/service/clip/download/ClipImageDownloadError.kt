package opfic.plyst.host.service.clip.download

// 요청 URL이나 응답 내용을 포함하지 않는 오류
sealed class ClipImageDownloadError : Exception() {
  data object UnsupportedURL : ClipImageDownloadError()

  data object InvalidResponse : ClipImageDownloadError()

  data object NotImage : ClipImageDownloadError()

  data object TooLarge : ClipImageDownloadError()

  data object RequestFailed : ClipImageDownloadError()
}
