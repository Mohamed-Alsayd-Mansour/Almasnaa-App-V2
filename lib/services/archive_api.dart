import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/supa.dart';

class ArchiveException implements Exception {
  ArchiveException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ArchiveConfig {
  const ArchiveConfig({required this.enabled, required this.repo, required this.branch, required this.path});
  final bool enabled;
  final String repo;
  final String branch;
  final String path;

  factory ArchiveConfig.fromRow(Map<String, dynamic> r) => ArchiveConfig(
        enabled: r['enabled'] as bool? ?? false,
        repo: r['repo'] as String? ?? '',
        branch: r['branch'] as String? ?? 'main',
        path: r['path'] as String? ?? 'archive/almasnaa-backup.json',
      );
}

class ArchiveRun {
  const ArchiveRun({
    required this.startedAt,
    required this.finishedAt,
    required this.status,
    required this.trigger,
    required this.commitSha,
    required this.error,
  });
  final DateTime startedAt;
  final DateTime? finishedAt;
  final String status;
  final String trigger;
  final String? commitSha;
  final String? error;

  factory ArchiveRun.fromRow(Map<String, dynamic> r) => ArchiveRun(
        startedAt: DateTime.parse(r['started_at'] as String).toLocal(),
        finishedAt: r['finished_at'] == null ? null : DateTime.parse(r['finished_at'] as String).toLocal(),
        status: r['status'] as String,
        trigger: r['trigger'] as String,
        commitSha: r['commit_sha'] as String?,
        error: r['error'] as String?,
      );

  String get statusLabel => switch (status) {
        'ok' => 'نجحت',
        'error' => 'فشلت',
        'skipped' => 'لا تغيير',
        'running' => 'قيد التنفيذ',
        _ => status,
      };
}

/// أرشفة GitHub تتم بالكامل على الخادم (Edge Function `github-archive`).
/// التطبيق لا يرى رمز GitHub ولا يخزّنه ولا يرسله: يضبط فقط المستودع/الفرع/المسار.
class ArchiveApi {
  ArchiveApi._();
  static final ArchiveApi instance = ArchiveApi._();

  Future<ArchiveConfig> loadConfig() async {
    final row = await supa.from('archive_config').select().eq('id', 1).single();
    return ArchiveConfig.fromRow(Map<String, dynamic>.from(row));
  }

  Future<List<ArchiveRun>> recentRuns() async {
    final rows = await supa.from('archive_runs').select().order('id', ascending: false).limit(10);
    return rows.map((r) => ArchiveRun.fromRow(Map<String, dynamic>.from(r))).toList();
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final res = await supa.functions.invoke('github-archive', body: body);
      final d = res.data;
      if (d is Map) return Map<String, dynamic>.from(d);
      throw ArchiveException('استجابة غير متوقعة من الخادم');
    } on FunctionException catch (e) {
      final d = e.details;
      throw ArchiveException(d is Map && d['error'] != null ? '${d['error']}' : 'فشل الطلب (${e.status})');
    } on ArchiveException {
      rethrow;
    } catch (_) {
      throw ArchiveException('تعذّر الاتصال بالخادم');
    }
  }

  /// اختبار الاتصال بالمستودع قبل اعتماد الإعداد. يعيد true إن كان الملف موجودًا مسبقًا.
  Future<bool> test(ArchiveConfig c) async {
    final r = await _invoke({'action': 'test', 'config': {'repo': c.repo, 'branch': c.branch, 'path': c.path}});
    if (r['ok'] != true) throw ArchiveException('${r['error'] ?? 'فشل الاختبار'}');
    return r['fileExists'] == true;
  }

  Future<void> saveConfig(ArchiveConfig c) async {
    try {
      await supa
          .from('archive_config')
          .update({'enabled': c.enabled, 'repo': c.repo, 'branch': c.branch, 'path': c.path})
          .eq('id', 1);
    } catch (e) {
      throw ArchiveException(friendlyError(e));
    }
  }

  /// أرشفة فورية. تعيد وصفًا قصيرًا للنتيجة.
  Future<String> runNow() async {
    final r = await _invoke({'action': 'run'});
    if (r['ok'] != true) throw ArchiveException('${r['error'] ?? 'فشلت الأرشفة'}');
    if (r['skipped'] == 'unchanged') return 'لا توجد تغييرات منذ آخر أرشفة، لم يُنشأ commit جديد.';
    return 'تمت الأرشفة بنجاح.';
  }
}
