import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../models/daily_session.dart';
import '../models/enums.dart';
import '../utils/date_formatter.dart';

/// مسؤول عن دورة حياة اليومية: البدء، القراءة، الإنهاء.
class DailySessionRepository {
  final AppDatabase _db;
  final _uuid = const Uuid();

  DailySessionRepository({AppDatabase? db}) : _db = db ?? AppDatabase.instance;

  Future<List<DailySession>> _readAll() async {
    final rows = await _db.readList(AppDatabase.sessionsKey);
    return rows.map(DailySession.fromMap).toList();
  }

  Future<void> _writeAll(List<DailySession> sessions) async {
    await _db.writeList(
      AppDatabase.sessionsKey,
      sessions.map((s) => s.toMap()).toList(),
    );
  }

  /// يعيد اليومية النشطة الحالية إن وجدت (يجب ألا يكون هناك أكثر من واحدة).
  Future<DailySession?> getActiveSession() async {
    final sessions = await _readAll();
    final active =
        sessions.where((s) => s.status == DailySessionStatus.active).toList()
          ..sort((a, b) => b.startTime.compareTo(a.startTime));
    return active.isEmpty ? null : active.first;
  }

  Future<List<DailySession>> getClosedSessions() async {
    final sessions = await _readAll();
    final closed =
        sessions.where((s) => s.status == DailySessionStatus.closed).toList()
          ..sort((a, b) {
            final byDate = b.date.compareTo(a.date);
            if (byDate != 0) return byDate;
            return b.startTime.compareTo(a.startTime);
          });
    return closed;
  }

  Future<DailySession?> getSessionById(String id) async {
    final sessions = await _readAll();
    for (final s in sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// ينشئ يومية جديدة تلقائيًا بالتاريخ والوقت الحاليين.
  /// يفشل إذا كانت هناك يومية نشطة بالفعل، لضمان عدم وجود أكثر من
  /// يومية نشطة واحدة في نفس الوقت.
  Future<DailySession> startNewSession() async {
    final existing = await getActiveSession();
    if (existing != null) {
      throw StateError('توجد يومية نشطة بالفعل، يجب إنهاؤها أولًا.');
    }
    final now = DateTime.now();
    final session = DailySession(
      id: _uuid.v4(),
      dayName: AppDateFormatter.dayName(now),
      date: now,
      startTime: now,
      status: DailySessionStatus.active,
    );
    final sessions = await _readAll();
    sessions.add(session);
    await _writeAll(sessions);
    return session;
  }

  /// يغلق اليومية ويسجّل وقت الانتهاء تلقائيًا، دون حذف أو تعديل أي
  /// من بيانات الإدخالات المرتبطة بها (قاعدة العمل #15 و #16).
  Future<DailySession> closeSession(String id) async {
    final sessions = await _readAll();
    final idx = sessions.indexWhere((s) => s.id == id);
    if (idx == -1) {
      throw StateError('اليومية غير موجودة.');
    }
    final closed = sessions[idx].copyWith(
      endTime: DateTime.now(),
      status: DailySessionStatus.closed,
    );
    sessions[idx] = closed;
    await _writeAll(sessions);
    return closed;
  }
}
