package opfic.plyst.host.app

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Typeface
import android.os.Build
import android.util.TypedValue
import android.view.Gravity
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.content.ContextCompat

// 저장소를 열지 못했을 때 iOS StartupFailureViewController와 같은 문구와 다시 시도 버튼
@SuppressLint("ViewConstructor", "DiscouragedApi")
class StartupFailureView(
  context: Context,
  onRetry: () -> Unit,
) : FrameLayout(context) {
  init {
    setBackgroundColor(color("HomeCanvas"))
    val title =
      TextView(context).apply {
        text = "기록을 열지 못했습니다"
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 21f)
        typeface = Typeface.DEFAULT_BOLD
        setTextColor(color("HomePrimaryText"))
        gravity = Gravity.CENTER
      }
    val button =
      Button(context).apply {
        text = "다시 시도"
        isAllCaps = false
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
        typeface =
          if (Build.VERSION_CODES.P <= Build.VERSION.SDK_INT) {
            Typeface.create(Typeface.DEFAULT, 600, false)
          } else {
            Typeface.DEFAULT_BOLD
          }
        background = null
        setOnClickListener { onRetry() }
      }
    val stack =
      LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER_HORIZONTAL
        addView(title)
        addView(
          button,
          LinearLayout.LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT).apply { topMargin = dp(20) },
        )
      }
    addView(
      stack,
      LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT, Gravity.CENTER).apply {
        leftMargin = dp(32)
        rightMargin = dp(32)
      },
    )
  }

  private fun color(name: String): Int {
    val id = resources.getIdentifier(name, "color", context.packageName)
    return if (id == 0) 0 else ContextCompat.getColor(context, id)
  }

  private fun dp(value: Int) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value.toFloat(), resources.displayMetrics).toInt()
}
