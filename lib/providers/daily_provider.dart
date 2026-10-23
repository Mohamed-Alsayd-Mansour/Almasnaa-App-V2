import 'package:flutter/foundation.dart';

import '../auth/app_user.dart';
import '../data/supa.dart';
import '../models/daily_entry.dart';
import '../models/daily_session.dart';
import '../models/room.dart';
import '../repositories/daily_entry_repository.dart';
import '../repositories/daily_session_repository.dart';
import 'rooms_provider.dart';

/// يدير حالة تبويب "اليومية": بدء/إنهاء اليومية، وإضافة/تعديل/حذف
/// الغرف المسجّلة فيها أثناء كونها نشطة.
class DailyProvider extends ChangeNotifier {
  final DailySessionRepository _sessionRepository;
  final DailyEntryRepository _entryRepository;

  DailyProvider({
    DailySessionRepository? sessionRepository,
    DailyEntryRepository? entryRepository,
  })  : _sessionRepository = sessionRepository ?? DailySessionRepository(),
        _entryRepository = entryRepository ?? DailyEntryRepository();

  /// دور المستخدم الحالي (يُضبط عند فتح التطبيق). الرصيص: الخادم يحدد يوميته
  /// المختارة. المشرف والأدمن: الاختيار محلي للعرض فقط.
  AppRole? role;

  LoadStatus status = LoadStatus.initial;
  String? errorMessage;

  /// كل اليوميات المفتوحة (مختارة + معلّقة) الظاهرة لهذا المستخدم.
  List<DailySession> openSessions = [];

  /// اليومية المعروضة حاليًا (المختارة).
  DailySession? activeSession;
  List<DailyEntry> entries = [];

  String? _selectedId;

  /// عند تسجيل الخروج: لا تبقى بيانات المستخدم السابق في الذاكرة.
  void reset() {
    openSessions = [];
    activeSession = null;
    entries = [];
    _selectedId = null;
    role = null;
    status = LoadStatus.initial;
    errorMessage = null;
    notifyListeners();
  }

  bool get hasActiveSession => activeSession != null;

  /// الإضافة مسموحة للرصيص والأدمن فقط، ولليومية المختارة (غير المعلّقة).
  bool get canAddEntries =>
      activeSession != null &&
      activeSession!.isActive &&
      (role == AppRole.rassas || role == AppRole.admin);

  /// إنهاء اليومية: الرصيص صاحبها أو الأدمن.
  bool get canFinish =>
      activeSession != null &&
      (role == AppRole.rassas || role == AppRole.admin);

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      status = LoadStatus.loading;
      notifyListeners();
    }
    try {
      final open = await _sessionRepository.getOpenSessions();
      DailySession? chosen;
      if (role == AppRole.rassas) {
        for (final s in open) {
          if (s.isActive) chosen = s;
        }
      } else {
        for (final s in open) {
          if (s.id == _selectedId) chosen = s;
        }
        chosen ??= open.isEmpty ? null : open.first;
        _selectedId = chosen?.id;
      }
      openSessions = open;
      activeSession = chosen;
      entries = chosen == null
          ? []
          : await _entryRepository.getEntriesForSession(chosen.id);
      status = LoadStatus.loaded;
      errorMessage = null;
    } catch (e) {
      errorMessage = 'تعذر تحميل اليومية: ${friendlyError(e)}';
      if (!silent || status != LoadStatus.loaded) status = LoadStatus.error;
    }
    notifyListeners();
  }

  /// تبديل اليومية المختارة (الرصيص: يعلّق السابقة على الخادم دون إغلاقها).
  Future<String?> selectSession(String id) async {
    try {
      if (role == AppRole.rassas) {
        await _sessionRepository.selectSession(id);
      } else {
        _selectedId = id;
      }
      await load(silent: true);
      return null;
    } catch (e) {
      return 'تعذر تبديل اليومية: ${friendlyError(e)}';
    }
  }

  /// الرصيص: فتح/استئناف يومية مع المشرف (لا تتكرر عند الضغط المتكرر).
  Future<String?> openWithSupervisor(String supervisorId) async {
    try {
      await _sessionRepository.openWithSupervisor(supervisorId);
      await load(silent: true);
      return null;
    } catch (e) {
      return 'تعذر فتح اليومية: ${friendlyError(e)}';
    }
  }

  Future<String?> addEntry({
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
    if (activeSession == null) return 'لا توجد يومية مختارة حاليًا.';
    if (!canAddEntries) return 'لا يمكن الإضافة إلى هذه اليومية.';
    if (numbering.trim().isEmpty) return 'حقل الترقيم مطلوب.';
    if (room == null) {
      if (externalRoomName.trim().isEmpty) {
        return isOrder ? 'وصف الأوردر مطلوب.' : 'اسم الغرفة مطلوب.';
      }
      if (externalPieceCount <= 0) {
        return 'عدد القطع يجب أن يكون أكبر من صفر.';
      }
      if (isOrder &&
          customerName.trim().isEmpty &&
          merchantName.trim().isEmpty) {
        return 'أدخل اسم الزبون أو اسم التاجر (أو كليهما).';
      }
      if (!isOrder && merchantName.trim().isEmpty) return 'اسم التاجر مطلوب.';
    }
    if (!(room == null && !isOrder) && carpenter.trim().isEmpty) {
      return 'اسم النجار مطلوب.';
    }
    if (hasSpecifications && specialPieceCount < 0) {
      return 'عدد قطع غرفة المواصفات لا يمكن أن يكون سالبًا.';
    }
    if (isPartial) {
      if (partName.trim().isEmpty) return 'اسم الجزء أو الأجزاء مطلوب.';
      if (partialPieceCount <= 0) {
        return 'عدد القطع الموجودة يجب أن يكون أكبر من صفر.';
      }
    }

    try {
      final entry = await _entryRepository.addEntry(
        dailySessionId: activeSession!.id,
        room: room,
        externalRoomName: externalRoomName,
        externalPieceCount: externalPieceCount,
        merchantName: merchantName,
        customerName: customerName,
        isOrder: isOrder,
        numbering: numbering,
        carpenter: carpenter,
        service: service,
        installer: installer,
        supervisor: supervisor,
        repairer: repairer,
        deficiencies: deficiencies,
        wrapLocation: wrapLocation,
        hasSpecifications: hasSpecifications,
        specificationsText: specificationsText,
        specialPieceCount: specialPieceCount,
        problem: problem,
        isPartial: isPartial,
        partName: partName,
        partialPieceCount: partialPieceCount,
      );
      entries = [...entries, entry];
      notifyListeners();
      return null;
    } catch (e) {
      return 'تعذر إضافة الغرفة إلى اليومية: ${friendlyError(e)}';
    }
  }

  Future<String?> updateEntry(DailyEntry updatedFields) async {
    try {
      final updated = await _entryRepository.updateEntryFields(updatedFields);
      entries =
          entries.map((e) => e.id == updated.id ? updated : e).toList();
      notifyListeners();
      return null;
    } catch (e) {
      return 'تعذر تعديل الغرفة: ${friendlyError(e)}';
    }
  }

  Future<String?> updateEntryDeficiencies({
    required String entryId,
    required String newText,
  }) async {
    try {
      final updated = await _entryRepository.updateCurrentDeficiencies(
        entryId: entryId,
        newDeficiencyText: newText,
      );
      entries =
          entries.map((e) => e.id == updated.id ? updated : e).toList();
      notifyListeners();
      return null;
    } catch (e) {
      return 'تعذر تعديل النواقص: ${friendlyError(e)}';
    }
  }

  Future<String?> updateEntryProblem({
    required String entryId,
    required String newText,
  }) async {
    try {
      final updated = await _entryRepository.updateProblem(
        entryId: entryId,
        newProblem: newText,
      );
      entries =
          entries.map((e) => e.id == updated.id ? updated : e).toList();
      notifyListeners();
      return null;
    } catch (e) {
      return 'تعذر تعديل المشكلة: ${friendlyError(e)}';
    }
  }

  /// تعديل نص المواصفات لإدخال واحد مباشرة من جدول اليومية.
  Future<String?> updateEntrySpecifications({
    required String entryId,
    required String newText,
  }) async {
    try {
      final updated = await _entryRepository.updateSpecificationsText(
        entryId: entryId,
        newText: newText,
      );
      entries =
          entries.map((e) => e.id == updated.id ? updated : e).toList();
      notifyListeners();
      return null;
    } catch (e) {
      return 'تعذر تعديل المواصفات: ${friendlyError(e)}';
    }
  }

  /// تعديل وصف الأوردر لإدخال واحد مباشرة من جدول اليومية.
  Future<String?> updateEntryOrderDescription({
    required String entryId,
    required String newText,
  }) async {
    if (newText.trim().isEmpty) return 'وصف الأوردر مطلوب.';
    try {
      final updated = await _entryRepository.updateOrderDescription(
        entryId: entryId,
        newText: newText,
      );
      entries =
          entries.map((e) => e.id == updated.id ? updated : e).toList();
      notifyListeners();
      return null;
    } catch (e) {
      return 'تعذر تعديل وصف الأوردر: ${friendlyError(e)}';
    }
  }

  Future<String?> deleteEntry(String entryId) async {
    try {
      await _entryRepository.deleteEntry(entryId);
      entries = entries.where((e) => e.id != entryId).toList();
      notifyListeners();
      return null;
    } catch (e) {
      return 'تعذر حذف الغرفة: ${friendlyError(e)}';
    }
  }

  /// إنهاء صريح لليومية المختارة دون المساس بأي بيانات؛ تصبح بعدها متاحة
  /// في السجل كسجل تاريخي دائم (قاعدة العمل #15، #16).
  Future<String?> finishSession() async {
    final session = activeSession;
    if (session == null) return 'لا توجد يومية مختارة لإنهائها.';
    try {
      await _sessionRepository.closeSession(session.id);
      await load(silent: true);
      return null;
    } catch (e) {
      return 'تعذر إنهاء اليومية: ${friendlyError(e)}';
    }
  }
}
