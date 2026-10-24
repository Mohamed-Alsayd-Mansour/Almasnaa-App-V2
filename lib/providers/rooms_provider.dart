import 'package:flutter/foundation.dart';

import '../data/supa.dart';
import '../models/room.dart';
import '../repositories/room_repository.dart';

enum LoadStatus { initial, loading, loaded, error }

/// يدير حالة تبويب "الغرف": التحميل، البحث الفوري، الإضافة والتعديل.
class RoomsProvider extends ChangeNotifier {
  final RoomRepository _repository;

  RoomsProvider({RoomRepository? repository})
      : _repository = repository ?? RoomRepository();

  LoadStatus status = LoadStatus.initial;
  String? errorMessage;

  List<Room> _allRooms = [];
  String _query = '';

  /// فلتر التصنيف السريع (أطفال / سفرة / نوم): الغرف التي يبدأ اسمها بهذه الكلمة. null = الكل.
  String? _category;

  /// توحيد بسيط للعربية للمقارنة: الهمزات على الألف، حذف التشكيل والتطويل.
  static String _norm(String s) => s
      .trim()
      .replaceAll(RegExp('[\u064B-\u0652\u0640]'), '')
      .replaceAll(RegExp('[أإآٱ]'), 'ا');

  /// الغرف بعد تطبيق الفلتر والبحث معًا (الشرطان يجتمعان).
  List<Room> get rooms {
    Iterable<Room> list = _allRooms;
    final cat = _category;
    if (cat != null) {
      final c = _norm(cat);
      list = list.where((r) => _norm(r.name).startsWith(c));
    }
    if (_query.trim().isNotEmpty) {
      final q = _query.trim();
      list = list.where((r) => r.name.contains(q));
    }
    return list.toList();
  }

  String get query => _query;
  String? get category => _category;

  /// الضغط على التصنيف المحدد مرة ثانية يلغيه ويعيد عرض كل الغرف.
  void toggleCategory(String word) {
    _category = _category == word ? null : word;
    notifyListeners();
  }

  /// عند تسجيل الخروج: لا تبقى بيانات المستخدم السابق في الذاكرة.
  void reset() {
    _allRooms = [];
    _query = '';
    _category = null;
    status = LoadStatus.initial;
    errorMessage = null;
    notifyListeners();
  }

  Future<void> loadRooms({bool silent = false}) async {
    if (!silent) {
      status = LoadStatus.loading;
      notifyListeners();
    }
    try {
      _allRooms = await _repository.getAllRooms();
      status = LoadStatus.loaded;
    } catch (e) {
      errorMessage = 'تعذر تحميل الغرف: ${friendlyError(e)}';
      if (!silent || status != LoadStatus.loaded) status = LoadStatus.error;
    }
    notifyListeners();
  }

  void search(String query) {
    _query = query;
    notifyListeners();
  }

  /// يُرجع رسالة خطأ نصية عند الفشل، أو null عند النجاح.
  Future<String?> addRoom({
    required String name,
    required int pieceCount,
    required int glassPieceCount,
    int partitionPieceCount = 0,
    int partitionCount = 0,
    int marblePieceCount = 0,
  }) async {
    if (name.trim().isEmpty) return 'اسم الغرفة مطلوب.';
    if (pieceCount <= 0) return 'عدد القطع يجب أن يكون أكبر من صفر.';
    if (glassPieceCount < 0) return 'عدد قطع الزجاج لا يمكن أن يكون سالبًا.';
    if (partitionPieceCount < 0) {
      return 'عدد قطع القواطيع لا يمكن أن يكون سالبًا.';
    }
    if (partitionCount < 0) {
      return 'عدد قواطيع الغرفة لا يمكن أن يكون سالبًا.';
    }
    if (marblePieceCount < 0) {
      return 'عدد قطع الرخام لا يمكن أن يكون سالبًا.';
    }

    try {
      final taken = await _repository.isRoomNameTaken(name);
      if (taken) {
        return 'يوجد بالفعل غرفة بنفس الاسم في قاعدة الغرف.';
      }
      final room = await _repository.createRoom(
        name: name,
        pieceCount: pieceCount,
        glassPieceCount: glassPieceCount,
        partitionPieceCount: partitionPieceCount,
        partitionCount: partitionCount,
        marblePieceCount: marblePieceCount,
      );
      _allRooms = [..._allRooms, room]
        ..sort((a, b) => a.name.compareTo(b.name));
      notifyListeners();
      return null;
    } catch (e) {
      return 'حدث خطأ أثناء حفظ الغرفة: ${friendlyError(e)}';
    }
  }

  Future<String?> updateRoom({
    required Room original,
    required String name,
    required int pieceCount,
    required int glassPieceCount,
    int partitionPieceCount = 0,
    int partitionCount = 0,
    int marblePieceCount = 0,
  }) async {
    if (name.trim().isEmpty) return 'اسم الغرفة مطلوب.';
    if (pieceCount <= 0) return 'عدد القطع يجب أن يكون أكبر من صفر.';
    if (glassPieceCount < 0) return 'عدد قطع الزجاج لا يمكن أن يكون سالبًا.';
    if (partitionPieceCount < 0) {
      return 'عدد قطع القواطيع لا يمكن أن يكون سالبًا.';
    }
    if (partitionCount < 0) {
      return 'عدد قواطيع الغرفة لا يمكن أن يكون سالبًا.';
    }
    if (marblePieceCount < 0) {
      return 'عدد قطع الرخام لا يمكن أن يكون سالبًا.';
    }

    try {
      final taken =
          await _repository.isRoomNameTaken(name, excludingId: original.id);
      if (taken) {
        return 'يوجد بالفعل غرفة أخرى بنفس الاسم.';
      }
      final updated = await _repository.updateRoom(original.copyWith(
        name: name,
        pieceCount: pieceCount,
        glassPieceCount: glassPieceCount,
        partitionPieceCount: partitionPieceCount,
        partitionCount: partitionCount,
        marblePieceCount: marblePieceCount,
      ));
      _allRooms = _allRooms
          .map((r) => r.id == updated.id ? updated : r)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      notifyListeners();
      return null;
    } catch (e) {
      return 'حدث خطأ أثناء تعديل الغرفة: ${friendlyError(e)}';
    }
  }

  Future<String?> deleteRoom(String id) async {
    try {
      await _repository.deleteRoom(id);
      _allRooms = _allRooms.where((r) => r.id != id).toList();
      notifyListeners();
      return null;
    } catch (e) {
      return 'حدث خطأ أثناء حذف الغرفة: ${friendlyError(e)}';
    }
  }
}
