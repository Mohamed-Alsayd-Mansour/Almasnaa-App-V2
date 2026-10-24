import '../models/daily_session.dart';
import 'supa.dart';

/// وضع «عرض كمستخدم» للأدمن (المرحلة 4).
///
/// يغيّر **نطاق العرض فقط**: يُرسَل مع كل طلب ترويسة `x-view-as` ليسجّل الخادم في سجل
/// التدقيق المنفِّذ الحقيقي (الأدمن) والمستخدم المستهدف، وتُصفّى البيانات المعروضة بالمعرّف
/// كما تفعل سياسات RLS لذلك المستخدم. لا انتحال هوية: الصلاحيات الفعلية تبقى للأدمن
/// ولا تتأثر بالترويسة إطلاقًا في الخادم.
class ViewScope {
  ViewScope._();

  static const String header = 'x-view-as';

  /// المستخدم المستهدف (لإرسال الترويسة وتسجيله في التدقيق).
  static String? targetId;

  /// نطاق التصفية: 'rassas' أو 'supervisor' فقط (عرض الأدمن كأدمن لا يُصفّي شيئًا).
  static String? scopeRole;

  static bool get active => targetId != null;

  static void apply({String? id, String? role}) {
    targetId = id;
    scopeRole = (role == 'rassas' || role == 'supervisor') ? role : null;
    final h = {...supa.headers}..remove(header);
    if (id != null) h[header] = id;
    supa.headers = h;
  }

  static void clear() => apply();

  /// عمود الملكية في جدول الإدخالات لهذا النطاق (يطابق سياسة entries_select).
  static String? get entryOwnerColumn => switch (scopeRole) {
        'rassas' => 'rassas_id',
        'supervisor' => 'supervisor_id',
        _ => null,
      };

  /// يصفّي اليوميات كما تفعل sessions_select: الرصيص يرى يومياته، والمشرف يرى
  /// ما هو مشرفها أو فيها إدخالات باسمه.
  static Future<List<DailySession>> filterSessions(List<DailySession> all) async {
    final id = targetId;
    switch (scopeRole) {
      case 'rassas':
        return all.where((s) => s.rassasId == id).toList();
      case 'supervisor':
        final rows = await fetchAll((from, to) => supa
            .from('daily_entries')
            .select('daily_session_id')
            .eq('supervisor_id', id!)
            .order('id')
            .range(from, to));
        final ids = {for (final r in rows) r['daily_session_id'] as String};
        return all.where((s) => s.supervisorId == id || ids.contains(s.id)).toList();
      default:
        return all;
    }
  }
}
