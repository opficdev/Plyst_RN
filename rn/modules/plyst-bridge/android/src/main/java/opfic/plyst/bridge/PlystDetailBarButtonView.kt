package opfic.plyst.bridge

import android.annotation.SuppressLint
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.os.Build
import android.text.TextPaint
import android.util.TypedValue
import android.view.MotionEvent
import android.view.View
import androidx.core.content.ContextCompat
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.ReactContext
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.UIManagerHelper
import com.facebook.react.uimanager.events.Event

// 상세 화면 상단 바의 원형 아이콘 버튼과 캡슐형 텍스트 버튼
// iOS 26 미만 DetailBarButton의 테두리가 있는 평면 모양
// 색과 아이콘은 앱 리소스를 이름으로 참조하므로 앱에 같은 이름의 color와 sf_ drawable이 있어야 함
@SuppressLint("ViewConstructor")
class PlystDetailBarButtonView(context: ThemedReactContext) : View(context) {
  private var icon: String? = null
  private var title: String? = null
  private var iconDrawable: Drawable? = null
  private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
  private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
  private val text =
    TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
      textSize = dp(15f)
      typeface =
        if (Build.VERSION_CODES.P <= Build.VERSION.SDK_INT) {
          Typeface.create(Typeface.DEFAULT, 600, false)
        } else {
          Typeface.DEFAULT_BOLD
        }
    }
  private val capsule = RectF()

  fun setIcon(icon: String?) {
    this.icon = icon?.takeIf { it.isNotEmpty() }
    iconDrawable =
      this.icon?.let { name ->
        // iOS 버튼과 같은 semibold 굵기의 drawable
        val id = resources.getIdentifier("sf_${name.replace('.', '_')}_w600", "drawable", context.packageName)
        if (id == 0) null else ContextCompat.getDrawable(context, id)?.mutate()
      }
    invalidate()
  }

  fun setTitle(title: String?) {
    this.title = title?.takeIf { it.isNotEmpty() }
    invalidate()
  }

  override fun setEnabled(enabled: Boolean) {
    super.setEnabled(enabled)
    invalidate()
  }

  override fun onDraw(canvas: Canvas) {
    if (icon == null && title == null) return
    val side = dp(SIDE)
    val width = if (icon != null) side else text.measureText(title) + dp(TITLE_INSET) * 2
    // 버튼은 자기 크기를 유지하므로 Fabric 상자의 중앙에 둠
    capsule.set(
      (this.width - width) / 2,
      (height - side) / 2,
      (this.width + width) / 2,
      (height + side) / 2,
    )
    val half = dp(1f) / 2
    capsule.inset(half, half)
    val radius = capsule.height() / 2
    fill.color = color("HomeCard")
    stroke.color = color("HomeOutline")
    stroke.strokeWidth = dp(1f)
    canvas.drawRoundRect(capsule, radius, radius, fill)
    canvas.drawRoundRect(capsule, radius, radius, stroke)
    val foreground = color(if (isEnabled) "HomePrimaryText" else "HomePlaceholder")
    val drawable = iconDrawable
    if (drawable != null) {
      // drawable 고유 크기는 SF Symbols 20pt 이미지 크기라 15pt 이미지 크기로 줄임
      val scale = ICON_POINT_SIZE / DRAWABLE_POINT_SIZE
      val iconWidth = drawable.intrinsicWidth * scale
      val iconHeight = drawable.intrinsicHeight * scale
      val left = (capsule.centerX() - iconWidth / 2).toInt()
      val top = (capsule.centerY() - iconHeight / 2).toInt()
      drawable.setBounds(left, top, left + iconWidth.toInt(), top + iconHeight.toInt())
      drawable.setTint(foreground)
      drawable.alpha = if (isPressed) PRESSED_ALPHA else 255
      drawable.draw(canvas)
      return
    }
    val title = title ?: return
    text.color = foreground
    if (isPressed) text.alpha = PRESSED_ALPHA
    val baseline = capsule.centerY() - (text.descent() + text.ascent()) / 2
    canvas.drawText(title, capsule.centerX() - text.measureText(title) / 2, baseline, text)
  }

  @SuppressLint("ClickableViewAccessibility")
  override fun onTouchEvent(event: MotionEvent): Boolean {
    if (!isEnabled) return false
    when (event.actionMasked) {
      MotionEvent.ACTION_DOWN -> isPressed = true
      MotionEvent.ACTION_MOVE -> isPressed = 0 <= event.x && event.x <= width && 0 <= event.y && event.y <= height
      MotionEvent.ACTION_UP -> {
        if (isPressed) emitPress()
        isPressed = false
      }
      MotionEvent.ACTION_CANCEL -> isPressed = false
    }
    return true
  }

  override fun drawableStateChanged() {
    super.drawableStateChanged()
    invalidate()
  }

  private fun color(name: String): Int {
    val id = resources.getIdentifier(name, "color", context.packageName)
    return if (id == 0) text.color else ContextCompat.getColor(context, id)
  }

  private fun dp(value: Float) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value, resources.displayMetrics)

  private fun emitPress() {
    val context = context as ReactContext
    val surfaceID = UIManagerHelper.getSurfaceId(this)
    UIManagerHelper.getEventDispatcherForReactTag(context, id)?.dispatchEvent(PressEvent(surfaceID, id))
  }

  private class PressEvent(
    surfaceID: Int,
    viewID: Int,
  ) : Event<PressEvent>(surfaceID, viewID) {
    override fun getEventName() = EVENT_NAME

    override fun getEventData() = Arguments.createMap()
  }

  companion object {
    const val EVENT_NAME = "topPress"

    // iOS 26 미만 DetailBarButton.makeLayout()의 한 변
    private const val SIDE = 40f
    private const val TITLE_INSET = 16f
    private const val ICON_POINT_SIZE = 15f
    private const val DRAWABLE_POINT_SIZE = 20f

    // UIButton.Configuration.plain()이 눌렸을 때 낮추는 전경 불투명도와 비슷한 값
    private const val PRESSED_ALPHA = 128
  }
}
