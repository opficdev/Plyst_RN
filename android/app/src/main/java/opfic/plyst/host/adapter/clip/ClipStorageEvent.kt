package opfic.plyst.host.adapter.clip

import java.util.UUID
import opfic.plyst.host.model.Clip

sealed interface ClipStorageEvent {
  data class Inserted(val clip: Clip) : ClipStorageEvent

  data class Updated(val clip: Clip) : ClipStorageEvent

  data class Deleted(val id: UUID) : ClipStorageEvent
}
