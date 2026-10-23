import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// نقطة الوصول الوحيدة لخادم Supabase من طبقة البيانات.
/// الخادم (PostgreSQL + RLS) هو المصدر الرسمي للبيانات؛ لا يُخزَّن شيء محليًا كمصدر.
SupabaseClient get supa => Supabase.instance.client;

const String kOfflineMessage =
    'لا يوجد اتصال بالخادم. لم يتم حفظ التغيير. تحقق من الإنترنت ثم أعد المحاولة.';

/// يحوّل أي خطأ إلى رسالة عربية مفهومة دون كشف تفاصيل داخلية.
String friendlyError(Object e) {
  if (e is PostgrestException) {
    switch (e.code) {
      case '42501':
        return 'غير مصرح لك بهذه العملية.';
      case '23503':
        return 'العملية مرتبطة ببيانات أخرى ولا يمكن تنفيذها.';
      case '23505':
        return 'هذا السجل موجود مسبقًا.';
      case 'P0001':
        return e.message;
    }
    final m = e.message;
    if (m.contains('closed') || m.contains('read-only')) {
      return 'اليومية مغلقة ولا يمكن تعديلها.';
    }
    if (m.contains('may not edit field')) {
      return 'غير مسموح لك بتعديل هذا الحقل بعد إغلاق اليومية.';
    }
    if (m.contains('paused')) {
      return 'اليومية معلّقة. اختَرها أولًا ثم أعد المحاولة.';
    }
    return m;
  }
  if (e is AuthException) return 'انتهت الجلسة. سجّل الدخول من جديد.';
  if (e is TimeoutException) return kOfflineMessage;
  final s = e.toString();
  if (s.contains('SocketException') ||
      s.contains('ClientException') ||
      s.contains('Failed host lookup') ||
      s.contains('XMLHttpRequest')) {
    return kOfflineMessage;
  }
  return 'حدث خطأ غير متوقع.';
}

/// يجلب كل الصفوف على دفعات (الحد الافتراضي للخادم 1000 صف لكل طلب).
Future<List<Map<String, dynamic>>> fetchAll(
  PostgrestTransformBuilder<PostgrestList> Function(int from, int to) page, {
  int pageSize = 1000,
}) async {
  final out = <Map<String, dynamic>>[];
  var from = 0;
  while (true) {
    final rows = await page(from, from + pageSize - 1);
    out.addAll(rows.map((e) => Map<String, dynamic>.from(e)));
    if (rows.length < pageSize) break;
    from += pageSize;
  }
  return out;
}

const List<String> _tsKeys = [
  'created_at',
  'updated_at',
  'date',
  'start_time',
  'end_time',
  'last_deficiency_update_at',
];

/// الخادم يعيد الأوقات بتوقيت UTC؛ التطبيق (كما في 1.0) يعمل بالتوقيت المحلي.
Map<String, Object?> fromServer(Map<String, dynamic> row) {
  final m = Map<String, Object?>.from(row);
  for (final k in _tsKeys) {
    final v = m[k];
    if (v is String) m[k] = DateTime.parse(v).toLocal().toIso8601String();
  }
  return m;
}

/// عند الكتابة: التواريخ المحلية (بلا منطقة زمنية) تُرسل بصيغة UTC صريحة.
Map<String, Object?> toServer(Map<String, Object?> row) {
  final m = Map<String, Object?>.from(row);
  for (final k in _tsKeys) {
    final v = m[k];
    if (v is String) m[k] = DateTime.parse(v).toUtc().toIso8601String();
  }
  return m;
}
