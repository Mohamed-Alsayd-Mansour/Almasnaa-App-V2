import 'package:shared_preferences/shared_preferences.dart';

/// تنظيف بقايا الإصدار 1.0 من الجهاز.
/// يحذف فقط مفاتيح إعدادات المزامنة القديمة (ومنها رمز GitHub PAT المخزّن محليًا)،
/// ولا يمس بيانات 1.0 (الغرف/اليوميات/الإدخالات/الأسماء) فهي تبقى كنسخة للأمان.
class LegacyCleanup {
  LegacyCleanup._();

  static Future<void> wipeSecrets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('almasnaa_sync_')).toList();
      for (final k in keys) {
        await prefs.remove(k);
      }
    } catch (_) {
      // غير حرج
    }
  }
}
