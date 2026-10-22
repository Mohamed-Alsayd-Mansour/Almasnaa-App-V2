import 'package:flutter/foundation.dart';

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

  LoadStatus status = LoadStatus.initial;
  String? errorMessage;

  DailySession? activeSession;
  List<DailyEntry> entries = [];

  bool get hasActiveSession => activeSession != null;

  Future<void> load() async {
    status = LoadStatus.loading;
    notifyListeners();
    try {
      activeSession = await _sessionRepository.getActiveSession();
      if (activeSession != null) {
        entries = await _entryRepository.getEntriesForSession(activeSession!.id);
      } else {
        entries = [];
      }
      status = LoadStatus.loaded;
    } catch (e) {
      errorMessage = 'تعذر تحميل اليومية: $e';
      status = LoadStatus.error;
    }
    notifyListeners();
  }

  Future<String?> startSession() async {
    try {
      activeSession = await _sessionRepository.startNewSession();
      entries = [];
      notifyListeners();
      return null;
    } catch (e) {
      return 'تعذر بدء يومية جديدة: $e';
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
    if (activeSession == null) return 'لا توجد يومية نشطة حاليًا.';
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
      return 'تعذر إضافة الغرفة إلى اليومية: $e';
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
      return 'تعذر تعديل الغرفة: $e';
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
      return 'تعذر تعديل النواقص: $e';
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
      return 'تعذر تعديل المشكلة: $e';
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
      return 'تعذر تعديل المواصفات: $e';
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
      return 'تعذر تعديل وصف الأوردر: $e';
    }
  }

  Future<String?> deleteEntry(String entryId) async {
    try {
      await _entryRepository.deleteEntry(entryId);
      entries = entries.where((e) => e.id != entryId).toList();
      notifyListeners();
      return null;
    } catch (e) {
      return 'تعذر حذف الغرفة: $e';
    }
  }

  /// ينهي اليومية الحالية دون المساس بأي بيانات؛ تصبح بعدها متاحة في
  /// تبويب السجل كسجل تاريخي دائم (قاعدة العمل #15، #16).
  Future<String?> finishSession() async {
    if (activeSession == null) return 'لا توجد يومية نشطة لإنهائها.';
    try {
      await _sessionRepository.closeSession(activeSession!.id);
      activeSession = null;
      entries = [];
      notifyListeners();
      return null;
    } catch (e) {
      return 'تعذر إنهاء اليومية: $e';
    }
  }
}
