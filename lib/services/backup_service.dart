import 'dart:convert';

import '../database/app_database.dart';
import '../models/daily_entry.dart';
import '../models/daily_session.dart';
import '../models/person.dart';
import '../models/room.dart';

/// محتوى ملف نسخة احتياطية بعد قراءته والتحقق منه (ولم يُطبَّق بعد).
class BackupPreview {
  final List<Map<String, Object?>> rooms;
  final List<Map<String, Object?>> sessions;
  final List<Map<String, Object?>> entries;

  /// null إذا كان الملف لا يحتوي على قوائم الأسماء (نسخ أقدم).
  final List<Map<String, Object?>>? people;
  final String? exportedAt;

  const BackupPreview({
    required this.rooms,
    required this.sessions,
    required this.entries,
    required this.people,
    required this.exportedAt,
  });
}

/// تصدير/استيراد/حذف كل بيانات التطبيق. لا تُطبَّق أي كتابة على
/// التخزين قبل نجاح التحقق الكامل من الملف.
class BackupService {
  final AppDatabase _db;

  BackupService({AppDatabase? db}) : _db = db ?? AppDatabase.instance;

  static const String appId = 'almasnaa';
  static const int formatVersion = 1;

  Future<String> buildJson() async {
    final payload = <String, Object?>{
      'app': appId,
      'version': formatVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'data': {
        'rooms': await _db.readList(AppDatabase.roomsKey),
        'sessions': await _db.readList(AppDatabase.sessionsKey),
        'entries': await _db.readList(AppDatabase.entriesKey),
        'people': await _db.readList(AppDatabase.peopleKey),
      },
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// يقرأ نص JSON ويتحقق من بنيته ومن إمكانية قراءة كل سجل فيه.
  /// يرمي [FormatException] برسالة عربية مفهومة عند أي مشكلة.
  BackupPreview parse(String source) {
    final text = source.startsWith('\uFEFF') ? source.substring(1) : source;

    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const FormatException('الملف ليس بصيغة JSON صحيحة.');
    }

    if (decoded is! Map || decoded['app'] != appId) {
      throw const FormatException('هذا الملف ليس نسخة احتياطية لتطبيق المصنع.');
    }
    final version = decoded['version'];
    if (version is! int || version > formatVersion) {
      throw const FormatException(
          'إصدار الملف أحدث من هذا التطبيق. حدّث التطبيق ثم أعد المحاولة.');
    }
    final data = decoded['data'];
    if (data is! Map) {
      throw const FormatException('الملف تالف: لا يحتوي على قسم البيانات.');
    }

    List<Map<String, Object?>>? readList(String key, {required bool required}) {
      final raw = data[key];
      if (raw == null) {
        if (required) {
          throw FormatException('الملف ناقص: لا يحتوي على "$key".');
        }
        return null;
      }
      if (raw is! List) {
        throw FormatException('الملف تالف: "$key" ليست قائمة.');
      }
      return raw.map((e) {
        if (e is! Map) {
          throw FormatException('الملف تالف: عنصر غير صالح داخل "$key".');
        }
        return Map<String, Object?>.from(e);
      }).toList();
    }

    final rooms = readList('rooms', required: true)!;
    final sessions = readList('sessions', required: true)!;
    final entries = readList('entries', required: true)!;
    final people = readList('people', required: false);

    try {
      for (final m in rooms) {
        Room.fromMap(m);
      }
      for (final m in sessions) {
        DailySession.fromMap(m);
      }
      for (final m in entries) {
        DailyEntry.fromMap(m);
      }
      for (final m in people ?? const <Map<String, Object?>>[]) {
        Person.fromMap(m);
      }
    } catch (_) {
      throw const FormatException('بيانات الملف تالفة أو غير متوافقة.');
    }

    return BackupPreview(
      rooms: rooms,
      sessions: sessions,
      entries: entries,
      people: people,
      exportedAt: decoded['exported_at'] as String?,
    );
  }

  /// يستبدل بيانات التطبيق الحالية بمحتوى النسخة الاحتياطية.
  Future<void> restore(BackupPreview preview) async {
    await _db.writeList(AppDatabase.roomsKey, preview.rooms);
    await _db.writeList(AppDatabase.sessionsKey, preview.sessions);
    await _db.writeList(AppDatabase.entriesKey, preview.entries);
    if (preview.people != null) {
      await _db.writeList(AppDatabase.peopleKey, preview.people!);
    }
  }

  /// يحذف الغرف واليوميات والسجل، وقوائم الأسماء اختياريًا.
  Future<void> deleteAll({required bool includePeople}) async {
    await _db.clearKeys([
      AppDatabase.roomsKey,
      AppDatabase.sessionsKey,
      AppDatabase.entriesKey,
      if (includePeople) AppDatabase.peopleKey,
    ]);
  }
}
