import '../data/supa.dart';
import '../data/view_scope.dart';
import '../models/daily_session.dart';
import '../models/enums.dart';

/// اليوميات على الخادم. الإنشاء (create_session) والتبديل (select_session) والإغلاق
/// (close_session) تتم عبر دوال الخادم فهي ذرّية ولا تُكرِّر اليوميات. اختيار المشرف
/// (change_supervisor) لا يُنشئ يومية.
class DailySessionRepository {
  Future<List<DailySession>> getAllVisible() async {
    final rows = await fetchAll((from, to) => supa
        .from('daily_sessions')
        .select()
        .order('date', ascending: false)
        .order('start_time', ascending: false)
        .range(from, to));
    final all = rows.map((r) => DailySession.fromMap(fromServer(r))).toList();
    return ViewScope.filterSessions(all);
  }

  /// اليوميات المفتوحة (مختارة + معلّقة) الظاهرة للمستخدم حسب RLS.
  Future<List<DailySession>> getOpenSessions() async {
    final all = await getAllVisible();
    return all.where((s) => s.isOpen).toList()
      ..sort((a, b) {
        if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
        return b.startTime.compareTo(a.startTime);
      });
  }

  Future<List<DailySession>> getClosedSessions() async {
    final all = await getAllVisible();
    return all.where((s) => s.isClosed).toList();
  }

  Future<DailySession?> getSessionById(String id) async {
    final row = await supa.from('daily_sessions').select().eq('id', id).maybeSingle();
    return row == null ? null : DailySession.fromMap(fromServer(row));
  }

  /// الرصيص: يجعل هذه اليومية المختارة ويعلّق السابقة.
  Future<void> selectSession(String id) async {
    await supa.rpc('select_session', params: {'p_session': id});
  }

  /// الرصيص/الأدمن: إنهاء صريح فقط. يحفظ كل التفاصيل ويصبح السجل تاريخيًا.
  Future<void> closeSession(String id) async {
    await supa.rpc('close_session', params: {'p_session': id});
  }

  /// إنشاء يومية جديدة صراحةً (الرصيص مع مشرفه الحالي، أو الأدمن لرصيص محدد).
  /// هذا هو المسار الوحيد لإنشاء يومية. الخادم يعيد اليومية المفتوحة لنفس الثنائي
  /// (رصيص + مشرف) إن وُجدت بدل تكرارها.
  Future<String> createSession({String? supervisorId, String? rassasId}) async {
    final res = await supa.rpc('create_session', params: {
      if (supervisorId != null) 'p_supervisor': supervisorId,
      if (rassasId != null) 'p_rassas': rassasId,
    });
    return res as String;
  }

  DailySessionStatus statusOf(DailySession s) => s.status;
}
