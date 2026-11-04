package opfic.plyst.bridge

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.view.animation.PathInterpolator
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.ReactContext
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.UIManagerHelper
import com.facebook.react.uimanager.events.Event
import com.facebook.react.views.view.ReactViewGroup

// 원본 UIKit 검색 화면의 UIView.animate와 같은 길이
private const val TRANSITION_DURATION = 300L

// 자기 알파와 expand의 경우 오른쪽 끝을 고정한 너비만 움직이는 컨테이너
// 색, 테두리, 내용은 React Native가 그림
class PlystSearchTransitionView(context: ThemedReactContext) : ReactViewGroup(context) {
  private var isFadeOut = false
  private var isExpand = false

  // props가 요구하는 상태
  private var requestedIsPresented = false

  // 화면에 반영한 상태
  private var isPresented = false
  private var hasConfigured = false

  // expand가 너비 0으로 접혀 있으면 true
  private var isCollapsed = false

  // Fabric이 정한 펼친 frame
  private var finalLeft = 0
  private var finalTop = 0
  private var finalRight = 0
  private var finalBottom = 0
  private var animator: ValueAnimator? = null

  // expand 애니메이션이 마지막으로 정한 왼쪽 끝
  private var animatingLeft: Int? = null

  // 새 전환이나 재활용 전에 시작한 애니메이션의 완료 신호를 버리기 위한 번호
  private var generation = 0

  fun setEffect(effect: String?) {
    // 알 수 없는 effect는 fadeIn으로 다룸
    isFadeOut = effect == "fadeOut"
    isExpand = effect == "expand"
  }

  fun setRequestedIsPresented(isPresented: Boolean) {
    requestedIsPresented = isPresented
  }

  // Fabric은 props를 바꿀 때 opacity를 prop 값으로 되돌릴 수 있어 상태가 정한 알파를 다시 넣음
  fun finalizeUpdates() {
    if (!hasConfigured) {
      hasConfigured = true
      isPresented = requestedIsPresented
      alpha = restingAlpha(isPresented)
      return
    }
    if (isPresented != requestedIsPresented) {
      transition(requestedIsPresented)
      return
    }
    if (animator == null) alpha = restingAlpha(isPresented)
  }

  // Fabric이 frame을 바꾸면 펼친 frame으로 기억하고 접혀 있거나 움직이는 동안에는 왼쪽 끝을 다시 옮김
  // 자식 위치는 이 뷰 기준이라 다시 배치하지 않음
  override fun onLayout(
    changed: Boolean,
    l: Int,
    t: Int,
    r: Int,
    b: Int,
  ) {
    super.onLayout(changed, l, t, r, b)
    val animatingLeft = animatingLeft
    finalLeft = l
    finalTop = t
    finalRight = r
    finalBottom = b
    when {
      animatingLeft != null -> left = animatingLeft.coerceIn(l, r)
      isCollapsed -> left = r
    }
  }

  fun resetForRecycle() {
    generation += 1
    animator?.cancel()
    animator = null
    animatingLeft = null
    isFadeOut = false
    isExpand = false
    requestedIsPresented = false
    isPresented = false
    hasConfigured = false
    isCollapsed = false
  }

  override fun onDetachedFromWindow() {
    super.onDetachedFromWindow()
    generation += 1
    animator?.cancel()
    animator = null
    animatingLeft = null
  }

  private fun restingAlpha(isPresented: Boolean) = if (isFadeOut != isPresented) 1f else 0f

  private fun transition(isPresented: Boolean) {
    this.isPresented = isPresented
    val generation = ++generation
    val isAnimating = animator != null
    animator?.cancel()
    // 진행 중인 애니메이션을 되돌리면 현재 표시 값에서 이어감
    val startAlpha = if (isAnimating) alpha else restingAlpha(!isPresented)
    val targetAlpha = restingAlpha(isPresented)
    val startLeft =
      when {
        isAnimating -> left
        isPresented -> finalRight
        else -> finalLeft
      }
    val targetLeft = if (isPresented) finalLeft else finalRight
    isCollapsed = isExpand && !isPresented
    alpha = startAlpha
    val animator = ValueAnimator.ofFloat(0f, 1f)
    animator.duration = TRANSITION_DURATION
    // UIViewAnimationOptionCurveEaseInOut과 같은 곡선
    animator.interpolator = PathInterpolator(0.42f, 0f, 0.58f, 1f)
    animator.addUpdateListener {
      val fraction = it.animatedValue as Float
      alpha = startAlpha + (targetAlpha - startAlpha) * fraction
      if (isExpand) {
        val current = startLeft + ((targetLeft - startLeft) * fraction).toInt()
        animatingLeft = current
        left = current
      }
    }
    animator.addListener(
      object : AnimatorListenerAdapter() {
        private var isCancelled = false

        override fun onAnimationCancel(animation: Animator) {
          isCancelled = true
        }

        override fun onAnimationEnd(animation: Animator) {
          if (isCancelled || generation != this@PlystSearchTransitionView.generation) return
          this@PlystSearchTransitionView.animator = null
          animatingLeft = null
          emitTransitionEnd(isPresented)
        }
      },
    )
    this.animator = animator
    animator.start()
  }

  private fun emitTransitionEnd(isPresented: Boolean) {
    val context = context as ReactContext
    val surfaceID = UIManagerHelper.getSurfaceId(this)
    UIManagerHelper.getEventDispatcherForReactTag(context, id)
      ?.dispatchEvent(TransitionEndEvent(surfaceID, id, isPresented))
  }

  private class TransitionEndEvent(
    surfaceID: Int,
    viewID: Int,
    private val isPresented: Boolean,
  ) : Event<TransitionEndEvent>(surfaceID, viewID) {
    override fun getEventName() = EVENT_NAME

    override fun getEventData() = Arguments.createMap().apply { putBoolean("isPresented", isPresented) }
  }

  companion object {
    const val EVENT_NAME = "topTransitionEnd"
  }
}
