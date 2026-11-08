package opfic.plyst.host.feature.share

import android.annotation.SuppressLint
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.core.content.ContextCompat

// iOS ShareStatusView와 같은 문구, 크기, 간격을 위쪽 모서리가 둥근 시트에 표시
// 앱 색과 아이콘은 호스트 패키지에 없어 이름으로 읽음
// 글자는 iOS 고정 크기처럼 글꼴 크기 설정을 따르지 않음
@SuppressLint("ViewConstructor", "DiscouragedApi")
class ShareStatusView(
  context: Context,
  onRetry: () -> Unit,
  onCancel: () -> Unit,
) : FrameLayout(context) {
  private val checkmark =
    ImageView(context).apply {
      setImageResource(resources.getIdentifier("sf_checkmark_circle_fill", "drawable", context.packageName))
      imageTintList = ColorStateList.valueOf(color("HomeShareSuccess"))
    }
  private val indicator =
    ProgressBar(context).apply {
      indeterminateTintList = ColorStateList.valueOf(color("HomeSecondaryText"))
    }
  private val title =
    TextView(context).apply {
      setTextSize(TypedValue.COMPLEX_UNIT_DIP, 21f)
      typeface = Typeface.DEFAULT_BOLD
      setTextColor(color("HomePrimaryText"))
      gravity = Gravity.CENTER
    }
  private val retryButton = button("다시 시도", onRetry)
  private val cancelButton = button("취소", onCancel)

  init {
    background =
      GradientDrawable().apply {
        setColor(color("HomeCard"))
        val radius = dp(SHEET_CORNER_RADIUS).toFloat()
        cornerRadii = floatArrayOf(radius, radius, radius, radius, 0f, 0f, 0f, 0f)
      }
    val stack =
      LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER_HORIZONTAL
        // 숨긴 요소는 간격을 차지하지 않음
        dividerDrawable =
          GradientDrawable().apply {
            setColor(Color.TRANSPARENT)
            setSize(0, dp(20))
          }
        showDividers = LinearLayout.SHOW_DIVIDER_MIDDLE
        addView(checkmark, LinearLayout.LayoutParams(dp(CHECKMARK_WIDTH), dp(CHECKMARK_HEIGHT)))
        addView(indicator, LinearLayout.LayoutParams(dp(INDICATOR_SIDE), dp(INDICATOR_SIDE)))
        // 기본 폭은 match_parent라 글자가 바뀌어도 다시 측정되지 않아 내용 크기로 지정
        listOf(title, retryButton, cancelButton).forEach {
          addView(it, LinearLayout.LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT))
        }
      }
    addView(
      stack,
      LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT, Gravity.CENTER).apply {
        leftMargin = dp(32)
        rightMargin = dp(32)
      },
    )
  }

  fun setStatus(status: ShareStatus) {
    checkmark.visibility = visibleIf(status == ShareStatus.COMPLETED)
    indicator.visibility = visibleIf(status == ShareStatus.SAVING)
    title.text =
      when (status) {
        ShareStatus.SAVING -> "저장 중"
        ShareStatus.COMPLETED -> "저장했습니다"
        ShareStatus.FAILED -> "저장하지 못했습니다"
      }
    retryButton.visibility = visibleIf(status == ShareStatus.FAILED)
    cancelButton.visibility = visibleIf(status != ShareStatus.COMPLETED)
    cancelButton.text = if (status == ShareStatus.FAILED) "닫기" else "취소"
  }

  private fun button(
    text: String,
    onClick: () -> Unit,
  ) = Button(context).apply {
    this.text = text
    isAllCaps = false
    setTextSize(TypedValue.COMPLEX_UNIT_DIP, 17f)
    typeface =
      if (Build.VERSION_CODES.P <= Build.VERSION.SDK_INT) {
        Typeface.create(Typeface.DEFAULT, 600, false)
      } else {
        Typeface.DEFAULT_BOLD
      }
    setTextColor(color("plyst_text_accent"))
    background = null
    minHeight = 0
    minimumHeight = 0
    minWidth = 0
    minimumWidth = 0
    setPadding(dp(8), dp(6), dp(8), dp(6))
    setOnClickListener { onClick() }
  }

  private fun visibleIf(isVisible: Boolean) = if (isVisible) View.VISIBLE else View.GONE

  private fun color(name: String): Int {
    val id = resources.getIdentifier(name, "color", context.packageName)
    return if (id == 0) 0 else ContextCompat.getColor(context, id)
  }

  private fun dp(value: Int) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value.toFloat(), resources.displayMetrics).toInt()

  private companion object {
    const val SHEET_CORNER_RADIUS = 38

    // 44pt checkmark.circle.fill의 SF 이미지 영역
    const val CHECKMARK_WIDTH = 52
    const val CHECKMARK_HEIGHT = 50

    // UIActivityIndicatorView medium 크기
    const val INDICATOR_SIDE = 20
  }
}
