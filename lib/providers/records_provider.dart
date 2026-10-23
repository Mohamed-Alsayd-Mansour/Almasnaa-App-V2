import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/supa.dart';
import '../models/daily_entry.dart';
import '../repositories/daily_entry_repository.dart';
import 'rooms_provider.dart';

/// يدير حالة تبويب "السجل": البحث المتقدم الفوري، والتعديل المباشر
/// على النواقص من داخل الجدول.
class RecordsProvider extends ChangeNotifier {
  final DailyEntryRepository _repository;

  RecordsProvider({DailyEntryRepository? repository})
      : _repository = repository ?? DailyEntryRepository();

  LoadStatus status = LoadStatus.initial;
  String? errorMessage;

  List<RecordRow> results = [];
  RecordSearchFilters filters = const RecordSearchFilters();

  /// عند تسجيل الخروج: لا تبقى بيانات المستخدم السابق في الذاكرة.
  void reset() {
    results = [];
    filters = const RecordSearchFilters();
    status = LoadStatus.initial;
    errorMessage = null;
    notifyListeners();
  }

  Timer? _debounce;

  Future<void> load({bool silent = false}) => _runSearch(silent: silent);

  /// بحث فوري مع Debounce بسيط لتفادي إرهاق قاعدة البيانات أثناء الكتابة
  /// السريعة، مع الحفاظ على شعور "فوري" للمستخدم.
  void searchWithKeyword(String keyword) {
    filters = RecordSearchFilters(
      keyword: keyword,
      dateFrom: filters.dateFrom,
      dateTo: filters.dateTo,
      roomName: filters.roomName,
      carpenter: filters.carpenter,
      installer: filters.installer,
      supervisor: filters.supervisor,
      wrapLocation: filters.wrapLocation,
      status: filters.status,
      shape: filters.shape,
      ownership: filters.ownership,
    );
    notifyListeners();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _runSearch);
  }

  Future<void> applyFilters(RecordSearchFilters newFilters) async {
    filters = newFilters;
    await _runSearch();
  }

  Future<void> clearFilters() async {
    filters = const RecordSearchFilters();
    await _runSearch();
  }

  Future<void> _runSearch({bool silent = false}) async {
    if (!silent) {
      status = LoadStatus.loading;
      notifyListeners();
    }
    try {
      results = await _repository.searchRecords(filters);
      status = LoadStatus.loaded;
    } catch (e) {
      errorMessage = 'تعذر تنفيذ البحث: ${friendlyError(e)}';
      if (!silent || status != LoadStatus.loaded) status = LoadStatus.error;
    }
    notifyListeners();
  }

  /// المسار الوحيد لتعديل النواقص من داخل جدول السجل مباشرة.
  Future<String?> updateDeficiencies({
    required String entryId,
    required String newText,
  }) async {
    try {
      final updated = await _repository.updateCurrentDeficiencies(
        entryId: entryId,
        newDeficiencyText: newText,
      );
      results = results
          .map((r) => r.entry.id == entryId
              ? RecordRow(
                  entry: updated,
                  dayName: r.dayName,
                  date: r.date,
                  sessionStatus: r.sessionStatus,
                )
              : r)
          .toList();
      notifyListeners();
      return null;
    } catch (e) {
      return 'تعذر تحديث النواقص: ${friendlyError(e)}';
    }
  }

  /// تعديل نص "المشكلة" من داخل جدول السجل مباشرة.
  Future<String?> updateProblem({
    required String entryId,
    required String newText,
  }) async {
    try {
      final updated = await _repository.updateProblem(
        entryId: entryId,
        newProblem: newText,
      );
      results = results
          .map((r) => r.entry.id == entryId
              ? RecordRow(
                  entry: updated,
                  dayName: r.dayName,
                  date: r.date,
                  sessionStatus: r.sessionStatus,
                )
              : r)
          .toList();
      notifyListeners();
      return null;
    } catch (e) {
      return 'تعذر تحديث المشكلة: ${friendlyError(e)}';
    }
  }

  /// تعديل نص المواصفات من داخل جدول السجل مباشرة.
  Future<String?> updateSpecifications({
    required String entryId,
    required String newText,
  }) async {
    try {
      final updated = await _repository.updateSpecificationsText(
        entryId: entryId,
        newText: newText,
      );
      _replaceRow(updated);
      return null;
    } catch (e) {
      return 'تعذر تحديث المواصفات: ${friendlyError(e)}';
    }
  }

  /// تعديل وصف الأوردر من داخل جدول السجل مباشرة.
  Future<String?> updateOrderDescription({
    required String entryId,
    required String newText,
  }) async {
    if (newText.trim().isEmpty) return 'وصف الأوردر مطلوب.';
    try {
      final updated = await _repository.updateOrderDescription(
        entryId: entryId,
        newText: newText,
      );
      _replaceRow(updated);
      return null;
    } catch (e) {
      return 'تعذر تحديث وصف الأوردر: ${friendlyError(e)}';
    }
  }

  void _replaceRow(DailyEntry updated) {
    results = results
        .map((r) => r.entry.id == updated.id
            ? RecordRow(
                entry: updated,
                dayName: r.dayName,
                date: r.date,
                sessionStatus: r.sessionStatus,
              )
            : r)
        .toList();
    notifyListeners();
  }

  /// التعديل الشامل لسجل كامل (بعد التحقق من كلمة المرور في الواجهة).
  Future<String?> replaceEntry(DailyEntry updated) async {
    if (updated.roomNameSnapshot.trim().isEmpty) return 'اسم الغرفة مطلوب.';
    try {
      await _repository.replaceEntry(updated);
      await _runSearch();
      return null;
    } catch (e) {
      return 'تعذر حفظ التعديلات: ${friendlyError(e)}';
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
