import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'html_print_service.dart';

/// حفظ القوالب المخصصة محليًا. لكل مجموعة بيانات (السجل، الغرف، كل استعلام)
/// مفتاح تخزين مستقل يأتي من [PrintSpec.storageKey].
class PrintTemplateStore {
  PrintTemplateStore._();

  static Future<List<HtmlPrintTemplate>> loadCustom(String storageKey) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => HtmlPrintTemplate.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(String storageKey, HtmlPrintTemplate template) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await loadCustom(storageKey);
    final next = [...current.where((e) => e.id != template.id), template];
    await prefs.setString(storageKey, jsonEncode(next.map((e) => e.toJson()).toList()));
  }

  static Future<void> delete(String storageKey, String id) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await loadCustom(storageKey);
    await prefs.setString(
      storageKey,
      jsonEncode(current.where((e) => e.id != id).map((e) => e.toJson()).toList()),
    );
  }
}
