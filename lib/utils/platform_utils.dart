import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// true عند التشغيل كتطبيق أندرويد أصلي (APK). على الويب تكون القيمة
/// false حتى لو كان المتصفح على هاتف أندرويد.
bool get isAndroidApp =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// تبويب "الاستعلامات" متاح فقط في نسخة الويب ونسخة ويندوز.
/// (لا يظهر في أندرويد ولا iOS ولا macOS/Linux.)
bool get showResearchTab =>
    kIsWeb || defaultTargetPlatform == TargetPlatform.windows;

/// true عند التشغيل كتطبيق هاتف أصلي (أندرويد أو iOS) فقط.
/// على الويب والديسكتوب تكون القيمة false.
bool get isMobileApp =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// على الهاتف فقط: إخفاء الـ Status Bar مع إبقاء شريط التنقل. السحب من أعلى
/// الشاشة يظهر الشريط مؤقتًا ويفتح لوحة الإعدادات السريعة (Quick Settings).
Future<void> applyMobileSystemUi() async {
  if (!isMobileApp) return;
  // لون الـ header في التطبيق (يظهر خلف الشريط عند سحبه مؤقتًا).
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0xFF4D7280),
  ));
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.bottom],
  );
}
