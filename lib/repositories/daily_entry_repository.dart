import 'package:uuid/uuid.dart';

import '../data/supa.dart';
import '../data/view_scope.dart';
import '../models/daily_entry.dart';
import '../models/daily_session.dart';
import '../models/enums.dart';
import '../models/room.dart';
import '../utils/deficiency_calculator.dart';

/// فلاتر البحث المتقدم في تبويب السجل.
class RecordSearchFilters {
  final String keyword;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? roomName;
  final String? carpenter;
  final String? installer;
  final String? supervisor;
  final String? wrapLocation;
  final RoomEntryStatus? status;

  /// شكل الغرفة: عادية / مواصفات / جزء من غرفة (null = الكل).
  final RoomShape? shape;

  /// ملكية الغرفة: داخلية / خارجية / أوردر (null = الكل).
  final RoomOwnership? ownership;

  /// يعرض سجلًا واحدًا فقط (الانتقال من إشعار إلى السجل المرتبط).
  final String? entryId;

  const RecordSearchFilters({
    this.keyword = '',
    this.dateFrom,
    this.dateTo,
    this.roomName,
    this.carpenter,
    this.installer,
    this.supervisor,
    this.wrapLocation,
    this.status,
    this.shape,
    this.ownership,
    this.entryId,
  });

  bool get isEmpty =>
      keyword.trim().isEmpty &&
      dateFrom == null &&
      dateTo == null &&
      (roomName == null || roomName!.isEmpty) &&
      (carpenter == null || carpenter!.isEmpty) &&
      (installer == null || installer!.isEmpty) &&
      (supervisor == null || supervisor!.isEmpty) &&
      (wrapLocation == null || wrapLocation!.isEmpty) &&
      status == null &&
      shape == null &&
      ownership == null &&
      entryId == null;

  RecordSearchFilters clear() => const RecordSearchFilters();
}

/// مسؤول عن إدخالات الغرف داخل اليوميات (المفتوحة والمغلقة) على الخادم.
/// ما يراه كل مستخدم وما يستطيع تعديله يحدده الخادم (RLS + حراس الصفوف)،
/// وليس الواجهة: الرصيص في يومية مغلقة لا يملك إلا تعديل 4 حقول.
class DailyEntryRepository {
  final _uuid = const Uuid();

  Future<List<DailyEntry>> fetchAllEntries() async {
    final owner = ViewScope.entryOwnerColumn;
    final rows = await fetchAll((from, to) {
      var q = supa.from('daily_entries').select();
      if (owner != null) q = q.eq(owner, ViewScope.targetId!);
      return q.order('created_at').order('id').range(from, to);
    });
    return rows.map((r) => DailyEntry.fromMap(fromServer(r))).toList();
  }

  Future<List<DailySession>> fetchAllSessions() async {
    final rows = await fetchAll((from, to) =>
        supa.from('daily_sessions').select().order('id').range(from, to));
    final all = rows.map((r) => DailySession.fromMap(fromServer(r))).toList();
    return ViewScope.filterSessions(all);
  }

  Future<List<DailyEntry>> _readAllEntries() => fetchAllEntries();
  Future<List<DailySession>> _readAllSessions() => fetchAllSessions();

  Future<List<DailyEntry>> getEntriesForSession(String sessionId) async {
    final owner = ViewScope.entryOwnerColumn;
    final rows = await fetchAll((from, to) {
      var q = supa.from('daily_entries').select().eq('daily_session_id', sessionId);
      if (owner != null) q = q.eq(owner, ViewScope.targetId!);
      return q.order('created_at').order('id').range(from, to);
    });
    return rows.map((r) => DailyEntry.fromMap(fromServer(r))).toList();
  }

  Future<DailyEntry> _getById(String id) async {
    final row = await supa.from('daily_entries').select().eq('id', id).maybeSingle();
    if (row == null) throw StateError('السجل غير موجود أو غير مصرح بالوصول إليه.');
    return DailyEntry.fromMap(fromServer(row));
  }

  /// يرسل للخادم الحقول التي تغيّرت فقط (فيتحقق الخادم من صلاحية كل حقل على حدة).
  Future<DailyEntry> _patch(DailyEntry before, DailyEntry after) async {
    final b = toServer(before.toMap());
    final a = toServer(after.toMap());
    const skip = {'id', 'created_at', 'updated_at', 'daily_session_id'};
    final diff = <String, Object?>{
      for (final k in a.keys)
        if (!skip.contains(k) && a[k] != b[k]) k: a[k],
    };
    if (diff.isEmpty) return before;
    final rows = await supa
        .from('daily_entries')
        .update(diff)
        .eq('id', before.id)
        .select();
    if (rows.isEmpty) throw StateError('لم يتم الحفظ: السجل غير موجود أو غير مصرح بتعديله.');
    return DailyEntry.fromMap(fromServer(Map<String, dynamic>.from(rows.first)));
  }

  /// يضيف غرفة جديدة إلى اليومية. يأخذ عدد القطع كـ Snapshot مستقل من
  /// بيانات الغرفة الأساسية وقت الإضافة (قاعدة العمل #3 و #4)، ويسمح
  /// بتكرار نفس [room] أكثر من مرة في نفس اليومية (قاعدة العمل #1، #2).
  Future<DailyEntry> addEntry({
    required String dailySessionId,
    Room? room,
    String externalRoomName = '',
    int externalPieceCount = 0,
    String merchantName = '',
    String customerName = '',
    bool isOrder = false,
    required String numbering,
    required String carpenter,
    required String service,
    String installer = '',
    String supervisor = '',
    required String repairer,
    required String deficiencies,
    String wrapLocation = '',
    bool hasSpecifications = false,
    String specificationsText = '',
    int specialPieceCount = 0,
    String problem = '',
    bool isPartial = false,
    String partName = '',
    int partialPieceCount = 0,
  }) async {
    final now = DateTime.now();
    final cleanPartName = partName.trim();
    final partial = isPartial && cleanPartName.isNotEmpty;
    final trimmedDeficiencies = deficiencies.trim();
    final missingCount = calculateMissingPiecesCount(trimmedDeficiencies);
    final baseRoomName = (room?.name ?? externalRoomName).trim();

    final entry = DailyEntry(
      id: _uuid.v4(),
      dailySessionId: dailySessionId,
      roomId: room?.id,
      // عند تسجيل جزء من غرفة يُكتب اسم الجزء قبل اسم الغرفة:
      // "[اسم الجزء] [اسم الغرفة]" ويُضاف العدد بين قوسين عند العرض.
      roomNameSnapshot:
          partial ? '$cleanPartName $baseRoomName' : baseRoomName,
      // Snapshot العدد القياسي للغرفة العادية دائمًا، بصرف النظر عن
      // تفعيل وسم "مواصفات" — يبقى مستقلًا تمامًا عن specialPieceCount.
      // العدد الكلي للغرفة (خشب + قواطيع + زجاج + رخام) كما في تبويب الغرف.
      pieceCountSnapshot: room?.totalPieceCount ?? externalPieceCount,
      isExternal: room == null && !isOrder,
      isOrder: isOrder,
      merchantName: merchantName.trim(),
      customerName: customerName.trim(),
      numbering: numbering.trim(),
      carpenter: carpenter.trim(),
      service: service.trim(),
      installer: installer.trim(),
      supervisor: supervisor.trim(),
      repairer: repairer.trim(),
      wrapLocation: wrapLocation.trim(),
      hasSpecifications: hasSpecifications,
      specificationsText: specificationsText.trim(),
      specialPieceCount: specialPieceCount,
      problem: problem.trim(),
      isPartial: partial,
      partName: partial ? cleanPartName : '',
      partialPieceCount: partial ? partialPieceCount : 0,
      originalDeficiencies: trimmedDeficiencies,
      currentDeficiencies: trimmedDeficiencies,
      originalMissingPiecesCount: missingCount,
      currentMissingPiecesCount: missingCount,
      createdAt: now,
      updatedAt: now,
      lastDeficiencyUpdateAt: null,
    );

    // المعرّف يُولَّد من العميل: إعادة المحاولة بعد انقطاع لا تكرّر الإدخال.
    // الخادم يفرض معرّفات الرصيص والمشرف من اليومية ويرفض اليوميات المغلقة/المعلّقة.
    await supa.from('daily_entries').upsert(
          toServer(entry.toMap())
            ..remove('created_at')
            ..remove('updated_at'),
          onConflict: 'id',
          ignoreDuplicates: true,
        );
    return _getById(entry.id);
  }

  /// تعديل بيانات إدخال (التعديل من اليومية). الخادم هو من يقرر الصلاحية.
  Future<DailyEntry> updateEntryFields(DailyEntry entry) async {
    final before = await _getById(entry.id);
    return _patch(before, entry.copyWithFields());
  }

  Future<void> deleteEntry(String id) async {
    final rows = await supa.from('daily_entries').delete().eq('id', id).select('id');
    if (rows.isEmpty) throw StateError('تعذر الحذف (السجل غير موجود أو غير مصرح).');
  }

  /// المسار الوحيد لتعديل النواقص: يعيد حساب العدد ويسجّل وقت آخر تعديل.
  /// النواقص الأصلية لا تتغير أبدًا.
  Future<DailyEntry> updateCurrentDeficiencies({
    required String entryId,
    required String newDeficiencyText,
  }) async {
    final before = await _getById(entryId);
    return _patch(before, before.withUpdatedCurrentDeficiencies(newDeficiencyText));
  }

  Future<DailyEntry> updateProblem({
    required String entryId,
    required String newProblem,
  }) async {
    final before = await _getById(entryId);
    return _patch(before, before.withUpdatedProblem(newProblem.trim()));
  }

  Future<DailyEntry> updateSpecificationsText({
    required String entryId,
    required String newText,
  }) async {
    final before = await _getById(entryId);
    return _patch(before, before.withUpdatedSpecifications(newText.trim()));
  }

  Future<DailyEntry> updateOrderDescription({
    required String entryId,
    required String newText,
  }) async {
    final before = await _getById(entryId);
    return _patch(before, before.withUpdatedOrderDescription(newText.trim()));
  }

  /// التعديل الشامل (المشرف والأدمن فقط؛ يرفضه الخادم للرصيص).
  Future<DailyEntry> replaceEntry(DailyEntry entry) async {
    final before = await _getById(entry.id);
    return _patch(before, entry);
  }

  /// بحث متقدم عبر كل الإدخالات، مع دمج بيانات اليومية التي ينتمي
  /// إليها كل إدخال (اليوم/التاريخ/الحالة) - يُنفَّذ بالكامل في الذاكرة
  /// حتى يعمل التطبيق على كل المنصات بما فيها الويب.
  Future<List<RecordRow>> searchRecords(RecordSearchFilters filters) async {
    final entries = await _readAllEntries();
    final sessions = await _readAllSessions();
    final sessionsById = {for (final s in sessions) s.id: s};

    final keyword = filters.keyword.trim().toLowerCase();
    bool contains(String? value) =>
        value != null && value.toLowerCase().contains(keyword);

    var rows = entries.map((entry) {
      final session = sessionsById[entry.dailySessionId];
      return RecordRow(
        entry: entry,
        dayName: session?.dayName ?? '',
        date: session?.date ?? entry.createdAt,
        sessionStatus: session?.status ?? DailySessionStatus.closed,
      );
    }).toList();

    if (keyword.isNotEmpty) {
      rows = rows.where((r) {
        final e = r.entry;
        return contains(e.roomNameSnapshot) ||
            contains(e.numbering) ||
            contains(e.carpenter) ||
            contains(e.service) ||
            contains(e.installer) ||
            contains(e.supervisor) ||
            contains(e.repairer) ||
            contains(e.wrapLocation) ||
            contains(e.specificationsText) ||
            contains(e.currentDeficiencies) ||
            contains(e.originalDeficiencies) ||
            contains(e.problem) ||
            contains(e.partName) ||
            contains(e.merchantName) ||
            contains(e.customerName) ||
            contains(r.dayName) ||
            contains('${e.pieceCountSnapshot}') ||
            contains('${e.effectivePieceCount}') ||
            contains('${e.currentMissingPiecesCount}');
      }).toList();
    }

    if (filters.dateFrom != null) {
      final from = DateTime(
          filters.dateFrom!.year, filters.dateFrom!.month, filters.dateFrom!.day);
      rows = rows.where((r) {
        final d = DateTime(r.date.year, r.date.month, r.date.day);
        return !d.isBefore(from);
      }).toList();
    }
    if (filters.dateTo != null) {
      final to =
          DateTime(filters.dateTo!.year, filters.dateTo!.month, filters.dateTo!.day);
      rows = rows.where((r) {
        final d = DateTime(r.date.year, r.date.month, r.date.day);
        return !d.isAfter(to);
      }).toList();
    }
    if (filters.roomName != null && filters.roomName!.trim().isNotEmpty) {
      final q = filters.roomName!.trim().toLowerCase();
      rows = rows
          .where((r) => r.entry.roomNameSnapshot.toLowerCase().contains(q))
          .toList();
    }
    if (filters.carpenter != null && filters.carpenter!.trim().isNotEmpty) {
      final q = filters.carpenter!.trim().toLowerCase();
      rows = rows.where((r) => r.entry.carpenter.toLowerCase().contains(q)).toList();
    }
    if (filters.installer != null && filters.installer!.trim().isNotEmpty) {
      final q = filters.installer!.trim().toLowerCase();
      rows =
          rows.where((r) => r.entry.installer.toLowerCase().contains(q)).toList();
    }
    if (filters.supervisor != null && filters.supervisor!.trim().isNotEmpty) {
      final q = filters.supervisor!.trim().toLowerCase();
      rows =
          rows.where((r) => r.entry.supervisor.toLowerCase().contains(q)).toList();
    }
    if (filters.wrapLocation != null && filters.wrapLocation!.trim().isNotEmpty) {
      final q = filters.wrapLocation!.trim().toLowerCase();
      rows = rows
          .where((r) => r.entry.wrapLocation.toLowerCase().contains(q))
          .toList();
    }
    if (filters.status == RoomEntryStatus.completed) {
      rows = rows.where((r) => r.entry.currentDeficiencies.trim().isEmpty).toList();
    } else if (filters.status == RoomEntryStatus.pending) {
      rows =
          rows.where((r) => r.entry.currentDeficiencies.trim().isNotEmpty).toList();
    }

    if (filters.shape == RoomShape.specs) {
      rows = rows.where((r) => r.entry.hasSpecifications).toList();
    } else if (filters.shape == RoomShape.regular) {
      rows = rows.where((r) => !r.entry.hasSpecifications).toList();
    } else if (filters.shape == RoomShape.partial) {
      rows = rows.where((r) => r.entry.isPartial).toList();
    }

    if (filters.ownership != null) {
      rows = rows.where((r) => r.entry.ownership == filters.ownership).toList();
    }
    if (filters.entryId != null) {
      rows = rows.where((r) => r.entry.id == filters.entryId).toList();
    }

    rows.sort((a, b) {
      final byDate = b.date.compareTo(a.date);
      if (byDate != 0) return byDate;
      return b.entry.createdAt.compareTo(a.entry.createdAt);
    });

    return rows;
  }

  /// إحصاءات بسيطة جاهزة للاستخدام في لوحة تحكم مستقبلية (بند 19 في
  /// المواصفات) دون الحاجة لإعادة بناء قاعدة البيانات.
  Future<Map<String, Object?>> getQuickStats() async {
    final entries = await _readAllEntries();
    final completed =
        entries.where((e) => e.currentDeficiencies.trim().isEmpty).length;
    final pending = entries.length - completed;
    final totalMissing =
        entries.fold<int>(0, (sum, e) => sum + e.currentMissingPiecesCount);

    return {
      'total': entries.length,
      'completed': completed,
      'pending': pending,
      'totalMissingPieces': totalMissing,
    };
  }
}
