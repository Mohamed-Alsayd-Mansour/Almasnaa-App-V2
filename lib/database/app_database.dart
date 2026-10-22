import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// طبقة تخزين محلية تعمل على كل المنصات (Android / iOS / Desktop / Web)
/// بدون أي اعتماد على مكوّنات أصلية (native plugins). تُخزَّن كل كيانات
/// التطبيق كقوائم JSON داخل SharedPreferences (والتي تُترجم إلى
/// localStorage تلقائيًا عند التشغيل على الويب).
///
/// هذه هي الطبقة الوحيدة في التطبيق التي "تعرف" آلية التخزين الفعلية،
/// وكل ما فوقها (الـ Repositories) يتعامل مع قوائم من Map فقط. هذا
/// يجعل استبدال آلية التخزين مستقبلًا (SQLite على الموبايل، أو مزامنة
/// سحابية) أسهل بكثير دون المساس ببقية طبقات التطبيق.
class AppDatabase {
  AppDatabase._internal();
  static final AppDatabase instance = AppDatabase._internal();

  static const String roomsKey = 'almasnaa_rooms';
  static const String sessionsKey = 'almasnaa_daily_sessions';
  static const String entriesKey = 'almasnaa_daily_entries';
  static const String peopleKey = 'almasnaa_people';

  SharedPreferences? _prefs;

  final List<void Function()> _changeListeners = [];

  /// يُستدعى بعد أي كتابة/حذف للبيانات (تستخدمه المزامنة اللحظية).
  void addChangeListener(void Function() l) => _changeListeners.add(l);

  void _notifyChanged() {
    for (final l in List.of(_changeListeners)) {
      l();
    }
  }

  Future<SharedPreferences> get _preferences async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<List<Map<String, Object?>>> readList(String key) async {
    final prefs = await _preferences;
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .cast<Map<String, dynamic>>()
        .map((m) => m.cast<String, Object?>())
        .toList();
  }

  Future<void> writeList(String key, List<Map<String, Object?>> items) async {
    final prefs = await _preferences;
    await prefs.setString(key, jsonEncode(items));
    _notifyChanged();
  }

  /// يحذف المفاتيح المحددة نهائيًا من التخزين المحلي.
  Future<void> clearKeys(Iterable<String> keys) async {
    final prefs = await _preferences;
    for (final key in keys) {
      await prefs.remove(key);
    }
    _notifyChanged();
  }
}
