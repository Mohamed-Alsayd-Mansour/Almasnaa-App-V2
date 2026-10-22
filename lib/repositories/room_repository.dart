import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../models/room.dart';

/// مسؤول عن كل عمليات القراءة/الكتابة الخاصة بتبويب "الغرف".
class RoomRepository {
  final AppDatabase _db;
  final _uuid = const Uuid();

  RoomRepository({AppDatabase? db}) : _db = db ?? AppDatabase.instance;

  Future<List<Room>> _readAll() async {
    final rows = await _db.readList(AppDatabase.roomsKey);
    return rows.map(Room.fromMap).toList();
  }

  Future<void> _writeAll(List<Room> rooms) async {
    await _db.writeList(AppDatabase.roomsKey, rooms.map((r) => r.toMap()).toList());
  }

  Future<List<Room>> getAllRooms() async {
    final rooms = await _readAll();
    rooms.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return rooms;
  }

  Future<Room?> getRoomById(String id) async {
    final rooms = await _readAll();
    for (final r in rooms) {
      if (r.id == id) return r;
    }
    return null;
  }

  Future<Room> createRoom({
    required String name,
    required int pieceCount,
    required int glassPieceCount,
    int partitionPieceCount = 0,
    int partitionCount = 0,
    int marblePieceCount = 0,
  }) async {
    final now = DateTime.now();
    final room = Room(
      id: _uuid.v4(),
      name: name.trim(),
      pieceCount: pieceCount,
      glassPieceCount: glassPieceCount,
      partitionPieceCount: partitionPieceCount,
      partitionCount: partitionCount,
      marblePieceCount: marblePieceCount,
      createdAt: now,
      updatedAt: now,
    );
    final rooms = await _readAll();
    rooms.add(room);
    await _writeAll(rooms);
    return room;
  }

  /// تعديل بيانات الغرفة الأساسية فقط. لا يمس هذا أي Snapshot محفوظ
  /// مسبقًا داخل سجلات اليومية أو السجل التاريخي (قاعدة العمل #14).
  Future<Room> updateRoom(Room room) async {
    final updated = room.copyWith(updatedAt: DateTime.now());
    final rooms = await _readAll();
    final idx = rooms.indexWhere((r) => r.id == room.id);
    if (idx == -1) {
      throw StateError('الغرفة غير موجودة.');
    }
    rooms[idx] = updated;
    await _writeAll(rooms);
    return updated;
  }

  Future<void> deleteRoom(String id) async {
    final rooms = await _readAll();
    rooms.removeWhere((r) => r.id == id);
    await _writeAll(rooms);
  }

  Future<bool> isRoomNameTaken(String name, {String? excludingId}) async {
    final rooms = await _readAll();
    final target = name.trim().toLowerCase();
    return rooms.any((r) =>
        r.name.trim().toLowerCase() == target &&
        (excludingId == null || r.id != excludingId));
  }
}
