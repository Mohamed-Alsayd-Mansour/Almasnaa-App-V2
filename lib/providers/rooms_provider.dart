import 'package:flutter/foundation.dart';

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

  List<Room> get rooms {
    if (_query.trim().isEmpty) return _allRooms;
    final q = _query.trim();
    return _allRooms.where((r) => r.name.contains(q)).toList();
  }

  String get query => _query;

  Future<void> loadRooms() async {
    status = LoadStatus.loading;
    notifyListeners();
    try {
      _allRooms = await _repository.getAllRooms();
      status = LoadStatus.loaded;
    } catch (e) {
      errorMessage = 'تعذر تحميل الغرف: $e';
      status = LoadStatus.error;
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
      return 'حدث خطأ أثناء حفظ الغرفة: $e';
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
      return 'حدث خطأ أثناء تعديل الغرفة: $e';
    }
  }

  Future<String?> deleteRoom(String id) async {
    try {
      await _repository.deleteRoom(id);
      _allRooms = _allRooms.where((r) => r.id != id).toList();
      notifyListeners();
      return null;
    } catch (e) {
      return 'حدث خطأ أثناء حذف الغرفة: $e';
    }
  }
}
