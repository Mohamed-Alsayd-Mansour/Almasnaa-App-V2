import 'package:uuid/uuid.dart';

import '../data/supa.dart';
import '../models/room.dart';

/// كتالوج الغرف على الخادم. الصلاحيات (الأدمن والرصيص فقط يكتبان) مفروضة بـ RLS.
/// حذف غرفة لا يمس لقطات الاسم والعدد في الإدخالات (room_id يصبح فارغًا فقط).
class RoomRepository {
  final _uuid = const Uuid();

  Future<List<Room>> getAllRooms() async {
    final rows = await fetchAll((from, to) =>
        supa.from('rooms').select().order('name').range(from, to));
    final rooms = rows.map((r) => Room.fromMap(fromServer(r))).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return rooms;
  }

  Future<Room?> getRoomById(String id) async {
    final row = await supa.from('rooms').select().eq('id', id).maybeSingle();
    return row == null ? null : Room.fromMap(fromServer(row));
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
    // المعرّف يُولَّد من العميل: إعادة المحاولة بعد انقطاع لا تنشئ غرفة مكررة.
    await supa
        .from('rooms')
        .upsert(
            toServer(room.toMap())
              ..remove('created_at')
              ..remove('updated_at'),
            onConflict: 'id',
            ignoreDuplicates: true);
    return room;
  }

  Future<Room> updateRoom(Room room) async {
    final updated = room.copyWith(updatedAt: DateTime.now());
    final map = toServer(updated.toMap())
      ..remove('id')
      ..remove('created_at')
      ..remove('updated_at');
    final rows = await supa.from('rooms').update(map).eq('id', room.id).select('id');
    if (rows.isEmpty) throw StateError('الغرفة غير موجودة أو غير مصرح بتعديلها.');
    return updated;
  }

  Future<void> deleteRoom(String id) async {
    final rows = await supa.from('rooms').delete().eq('id', id).select('id');
    if (rows.isEmpty) throw StateError('تعذر حذف الغرفة (غير موجودة أو غير مصرح).');
  }

  Future<bool> isRoomNameTaken(String name, {String? excludingId}) async {
    final rooms = await getAllRooms();
    final target = name.trim().toLowerCase();
    return rooms.any((r) =>
        r.name.trim().toLowerCase() == target &&
        (excludingId == null || r.id != excludingId));
  }
}
