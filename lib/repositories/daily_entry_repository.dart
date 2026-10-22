import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
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
      ownership == null;

  RecordSearchFilters clear() => const RecordSearchFilters();
}

/// مسؤول عن إدخالات الغرف داخل اليوميات (النشطة والمغلقة)، بما في ذلك
/// إنشاؤها، تعديل بياناتها، تعديل النواقص، وبحث السجل المتقدم.
class DailyEntryRepository {
  final AppDatabase _db;
  final _uuid = const Uuid();

  DailyEntryRepository({AppDatabase? db}) : _db = db ?? AppDatabase.instance;

  Future<List<DailyEntry>> _readAllEntries() async {
    final rows = await _db.readList(AppDatabase.entriesKey);
    return rows.map(DailyEntry.fromMap).toList();
  }

  Future<void> _writeAllEntries(List<DailyEntry> entries) async {
    await _db.writeList(
      AppDatabase.entriesKey,
      entries.map((e) => e.toMap()).toList(),
    );
  }

  Future<List<DailySession>> _readAllSessions() async {
    final rows = await _db.readList(AppDatabase.sessionsKey);
    return rows.map(DailySession.fromMap).toList();
  }

  Future<List<DailyEntry>> getEntriesForSession(String sessionId) async {
    final entries = await _readAllEntries();
    final filtered =
        entries.where((e) => e.dailySessionId == sessionId).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return filtered;
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
    required String installer,
    required String supervisor,
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

    final entries = await _readAllEntries();
    entries.add(entry);
    await _writeAllEntries(entries);
    return entry;
  }

  /// تعديل بيانات إدخال (غير النواقص) طالما اليومية ما زالت نشطة عادة،
  /// لكن الدالة لا تفرض ذلك؛ القرار يُترك لطبقة الحالة (Provider).
  Future<DailyEntry> updateEntryFields(DailyEntry entry) async {
    final entries = await _readAllEntries();
    final idx = entries.indexWhere((e) => e.id == entry.id);
    if (idx == -1) {
      throw StateError('السجل غير موجود.');
    }
    final updated = entry.copyWithFields();
    entries[idx] = updated;
    await _writeAllEntries(entries);
    return updated;
  }

  Future<void> deleteEntry(String id) async {
    final entries = await _readAllEntries();
    entries.removeWhere((e) => e.id == id);
    await _writeAllEntries(entries);
  }

  /// المسار الوحيد المعتمد لتعديل النواقص من تبويب السجل. يعيد حساب
  /// العدد تلقائيًا ويسجّل وقت آخر تعديل (قاعدة العمل #10، #11).
  Future<DailyEntry> updateCurrentDeficiencies({
    required String entryId,
    required String newDeficiencyText,
  }) async {
    final entries = await _readAllEntries();
    final idx = entries.indexWhere((e) => e.id == entryId);
    if (idx == -1) {
      throw StateError('السجل غير موجود.');
    }
    final updated = entries[idx].withUpdatedCurrentDeficiencies(newDeficiencyText);
    entries[idx] = updated;
    await _writeAllEntries(entries);
    return updated;
  }

  /// تعديل نص "المشكلة" (سبب القطع الناقصة) لإدخال واحد.
  Future<DailyEntry> updateProblem({
    required String entryId,
    required String newProblem,
  }) async {
    final entries = await _readAllEntries();
    final idx = entries.indexWhere((e) => e.id == entryId);
    if (idx == -1) {
      throw StateError('السجل غير موجود.');
    }
    final updated = entries[idx].withUpdatedProblem(newProblem.trim());
    entries[idx] = updated;
    await _writeAllEntries(entries);
    return updated;
  }

  /// تعديل نص المواصفات لإدخال واحد (من جدول السجل مباشرة).
  Future<DailyEntry> updateSpecificationsText({
    required String entryId,
    required String newText,
  }) async {
    final entries = await _readAllEntries();
    final idx = entries.indexWhere((e) => e.id == entryId);
    if (idx == -1) throw StateError('السجل غير موجود.');
    final updated = entries[idx].withUpdatedSpecifications(newText.trim());
    entries[idx] = updated;
    await _writeAllEntries(entries);
    return updated;
  }

  /// تعديل وصف الأوردر لإدخال واحد (من جدول السجل مباشرة).
  Future<DailyEntry> updateOrderDescription({
    required String entryId,
    required String newText,
  }) async {
    final entries = await _readAllEntries();
    final idx = entries.indexWhere((e) => e.id == entryId);
    if (idx == -1) throw StateError('السجل غير موجود.');
    final updated = entries[idx].withUpdatedOrderDescription(newText.trim());
    entries[idx] = updated;
    await _writeAllEntries(entries);
    return updated;
  }

  /// استبدال إدخال كامل بالنسخة المعدَّلة (التعديل الشامل من تبويب السجل).
  /// تُحفظ النسخة كما هي دون أي تعديل إضافي.
  Future<DailyEntry> replaceEntry(DailyEntry entry) async {
    final entries = await _readAllEntries();
    final idx = entries.indexWhere((e) => e.id == entry.id);
    if (idx == -1) {
      throw StateError('السجل غير موجود.');
    }
    entries[idx] = entry;
    await _writeAllEntries(entries);
    return entry;
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
