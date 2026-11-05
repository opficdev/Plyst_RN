package opfic.plyst.host.app

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import opfic.plyst.host.model.AppLink

// 내용이 변하지 않는 위젯이므로 갱신 때 같은 화면과 링크만 설정
// 클립보드는 창 포커스를 가진 앱만 읽을 수 있어 위젯에서 저장하지 않고 앱을 염
class PlystWidgetProvider : AppWidgetProvider() {
  // 레이아웃은 앱 색을 참조해야 해서 앱 리소스에 있고 이름으로 찾음
  @SuppressLint("DiscouragedApi")
  override fun onUpdate(
    context: Context,
    manager: AppWidgetManager,
    ids: IntArray,
  ) {
    val packageName = context.packageName
    val views = RemoteViews(packageName, context.resources.getIdentifier("plyst_widget", "layout", packageName))
    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(AppLink.SAVE_CLIPBOARD.url)).setPackage(packageName)
    views.setOnClickPendingIntent(android.R.id.background, PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_IMMUTABLE))
    manager.updateAppWidget(ids, views)
  }
}
