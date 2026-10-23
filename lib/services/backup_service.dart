import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/supa.dart';

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BackupFile {
  const BackupFile({required this.fileName, required this.json});
  final String fileName;
  final String json;
}

/// فحص مبدئي لملف النسخة قبل إرساله للخادم (التحقق الكامل من العلاقات يتم هناك).
class BackupPreview {
  const BackupPreview({
    required this.payload,
    required this.rooms,
    required this.people,
    required this.sessions,
    required this.entries,
    required this.exportedAt,
  });
  final Map<String, Object?> payload;
  final int rooms;
  final int people;
  final int sessions;
  final int entries;
  final String? exportedAt;
}

/// ملخص ما سيُدرج (أو ما أُدرج) عند الاستيراد. السجلات الموجودة تُتخطى ولا تُستبدل.
class ImportSummary {
  const ImportSummary({required this.rooms, required this.people, required this.sessions, required this.entries});
  final int rooms;
  final int people;
  final int sessions;
  final int entries;
}

/// النسخ الاحتياطي عبر دوال الخادم المحمية بكلمة مرور مستقلة. لا تُخزَّن كلمة المرور
/// ولا تُسجَّل، ولا يمكن تجاوز التحقق باستدعاء الجداول مباشرة (الدوال هي الطريق الوحيد
/// للتصدير الجماعي والاستيراد والحذف الجماعي).
class BackupService {
  static const String appId = 'almasnaa';
  static const int schemaVersion = 2;

  String _err(Object? code, [Object? detail]) {
    switch ('$code') {
      case 'invalid_password':
        return 'كلمة مرور النسخ الاحتياطي غير صحيحة (أو تجاوزت عدد المحاولات، انتظر 15 دقيقة).';
      case 'unsupported_file':
        return 'هذا الملف ليس نسخة احتياطية من الإصدار 2.0 (schemaVersion=2).';
      case 'bad_structure':
        return 'بنية الملف غير صحيحة: ${detail ?? ''}';
      case 'broken_relations':
        return 'علاقات الملف غير سليمة ولن يُكتب شيء:\n${(detail is List) ? detail.join('\n') : detail ?? ''}';
      default:
        return 'تعذرت العملية.';
    }
  }

  Map<String, dynamic> _asMap(Object? res) {
    if (res is Map) return Map<String, dynamic>.from(res);
    throw BackupException('استجابة غير متوقعة من الخادم.');
  }

  Future<BackupFile> export(String password) async {
    try {
      final r = _asMap(await supa.rpc('export_backup', params: {'p_password': password}));
      if (r['ok'] != true) throw BackupException(_err(r['error'], r['detail']));
      final name = r['fileName'] as String;
      return BackupFile(
        fileName: name,
        json: const JsonEncoder.withIndent('  ').convert(r['data']),
      );
    } on BackupException {
      rethrow;
    } on PostgrestException catch (e) {
      throw BackupException(friendlyError(e));
    } catch (e) {
      throw BackupException(friendlyError(e));
    }
  }

  BackupPreview parse(String source) {
    final text = source.startsWith('\uFEFF') ? source.substring(1) : source;
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw BackupException('الملف ليس بصيغة JSON صحيحة.');
    }
    if (decoded is! Map || decoded['app'] != appId) {
      throw BackupException('هذا الملف ليس نسخة احتياطية لتطبيق المصنع.');
    }
    final v = decoded['schemaVersion'];
    if (v == null && decoded['version'] == 1) {
      throw BackupException(
          'هذا ملف من الإصدار 1.0. بيانات 1.0 تُنقل مرة واحدة بسكربت الترحيل (scripts/migrate_v1.py) وليس من هنا.');
    }
    if (v is! int || v != schemaVersion) {
      throw BackupException('إصدار الملف غير مدعوم (المطلوب schemaVersion=$schemaVersion).');
    }
    final map = decoded;
    int count(String k) {
      final raw = map[k];
      if (raw is! List) throw BackupException('الملف ناقص أو تالف: "$k".');
      return raw.length;
    }

    return BackupPreview(
      payload: Map<String, Object?>.from(map),
      rooms: count('rooms'),
      people: count('people'),
      sessions: count('sessions'),
      entries: count('entries'),
      exportedAt: map['exportedAt'] as String?,
    );
  }

  ImportSummary _summary(Object? m) {
    final x = _asMap(m);
    int n(String k) => (x[k] as num?)?.toInt() ?? 0;
    return ImportSummary(rooms: n('rooms'), people: n('people'), sessions: n('sessions'), entries: n('entries'));
  }

  /// يتحقق من الملف على الخادم ويعيد ما سيُدرج فعلًا (دون أي كتابة).
  Future<ImportSummary> dryRun(String password, BackupPreview p) async {
    try {
      final r = _asMap(await supa.rpc('import_backup',
          params: {'p_password': password, 'p_payload': p.payload, 'p_apply': false}));
      if (r['ok'] != true) throw BackupException(_err(r['error'], r['detail']));
      return _summary(r['wouldInsert']);
    } on BackupException {
      rethrow;
    } catch (e) {
      throw BackupException(friendlyError(e));
    }
  }

  /// كتابة ذرّية: إما أن تنجح كلها أو لا يتغير شيء.
  Future<ImportSummary> apply(String password, BackupPreview p) async {
    try {
      final r = _asMap(await supa.rpc('import_backup',
          params: {'p_password': password, 'p_payload': p.payload, 'p_apply': true}));
      if (r['ok'] != true) throw BackupException(_err(r['error'], r['detail']));
      return _summary(r['inserted']);
    } on BackupException {
      rethrow;
    } catch (e) {
      throw BackupException(friendlyError(e));
    }
  }

  Future<void> deleteAll(String password) async {
    try {
      final r = _asMap(await supa.rpc('delete_all_data', params: {'p_password': password}));
      if (r['ok'] != true) throw BackupException(_err(r['error'], r['detail']));
    } on BackupException {
      rethrow;
    } catch (e) {
      throw BackupException(friendlyError(e));
    }
  }
}
