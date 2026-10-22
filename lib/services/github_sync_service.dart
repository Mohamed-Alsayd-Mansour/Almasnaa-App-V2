import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// خطأ مزامنة برسالة عربية جاهزة للعرض.
class SyncException implements Exception {
  final String message;
  const SyncException(this.message);
  @override
  String toString() => message;
}

/// إعدادات الاتصال بمستودع GitHub. تُحفظ محليًا على الجهاز فقط، وبمعزل
/// عن بيانات التطبيق (فلا تدخل في النسخ الاحتياطي ولا تُمسح بـ"حذف الكل").
class GithubSyncConfig {
  final String user;
  final String repo;
  final String token;
  final DateTime? lastSyncAt;

  const GithubSyncConfig({
    required this.user,
    required this.repo,
    required this.token,
    this.lastSyncAt,
  });

  bool get isComplete => user.trim().isNotEmpty &&
      repo.trim().isNotEmpty &&
      token.trim().isNotEmpty;
}

/// مزامنة سحابية مجانية عبر GitHub REST API: تُحفظ نسخة JSON كاملة من
/// البيانات داخل ملف في المستودع، ويمكن رفعها أو تنزيلها يدويًا.
///
/// يلزم Fine-grained Personal Access Token مع صلاحية Contents: Read and write
/// على المستودع المحدد. لا يحتاج التطبيق إلى صلاحيات GitHub أخرى.
class GithubSyncService {
  static const defaultUser = 'Mohamed-Alsayd-Mansour';
  static const defaultRepo = 'Almasnaa-App';
  static const filePath = 'cloud-sync/almasnaa-data.json';

  static const _kUser = 'almasnaa_sync_user';
  static const _kRepo = 'almasnaa_sync_repo';
  static const _kToken = 'almasnaa_sync_token';
  static const _kLastSync = 'almasnaa_sync_last';
  static const _kLastSha = 'almasnaa_sync_sha';
  static const _kLive = 'almasnaa_sync_live';
  static const _kDirty = 'almasnaa_sync_dirty';

  Future<bool> loadLive() async =>
      (await SharedPreferences.getInstance()).getBool(_kLive) ?? false;

  Future<void> saveLive(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_kLive, v);

  /// تغييرات محلية لم تُرفع بعد (تبقى محفوظة حتى بعد إغلاق التطبيق).
  Future<bool> loadDirty() async =>
      (await SharedPreferences.getInstance()).getBool(_kDirty) ?? false;

  Future<void> saveDirty(bool v) async =>
      (await SharedPreferences.getInstance()).setBool(_kDirty, v);

  /// SHA آخر نسخة سحابية تطابقت مع هذا الجهاز (null = لم تتم مزامنة بعد).
  Future<String?> loadLastSha() async =>
      (await SharedPreferences.getInstance()).getString(_kLastSha);

  Future<void> saveLastSha(String sha) async =>
      (await SharedPreferences.getInstance()).setString(_kLastSha, sha);

  Future<GithubSyncConfig> loadConfig() async {
    final p = await SharedPreferences.getInstance();
    final last = p.getString(_kLastSync);
    return GithubSyncConfig(
      user: p.getString(_kUser) ?? defaultUser,
      repo: p.getString(_kRepo) ?? defaultRepo,
      token: p.getString(_kToken) ?? '',
      lastSyncAt: last == null ? null : DateTime.tryParse(last),
    );
  }

  Future<void> saveConfig({
    required String user,
    required String repo,
    required String token,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUser, user.trim());
    await p.setString(_kRepo, repo.trim());
    await p.setString(_kToken, token.trim());
  }

  Future<void> clearConfig() async {
    final p = await SharedPreferences.getInstance();
    for (final k in [_kUser, _kRepo, _kToken, _kLastSync, _kLastSha, _kLive, _kDirty]) {
      await p.remove(k);
    }
  }

  Future<void> _markSynced() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLastSync, DateTime.now().toIso8601String());
  }

  Uri _repoUri(GithubSyncConfig c) => Uri.https(
        'api.github.com',
        '/repos/${c.user.trim()}/${c.repo.trim()}',
      );

  Uri _fileUri(GithubSyncConfig c) => Uri.https(
        'api.github.com',
        '/repos/${c.user.trim()}/${c.repo.trim()}/contents/$filePath',
      );

  Map<String, String> _headers(GithubSyncConfig c, {String? accept}) => {
        'Authorization': 'Bearer ${c.token.trim()}',
        'Accept': accept ?? 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'Almasnaa-App',
      };

  SyncException _httpError(http.Response r) {
    String? githubMessage;
    try {
      final decoded = jsonDecode(r.body);
      if (decoded is Map && decoded['message'] is String) {
        githubMessage = decoded['message'] as String;
      }
    } catch (_) {
      // نستخدم الرسالة العربية العامة إذا لم يكن رد GitHub بصيغة JSON.
    }

    switch (r.statusCode) {
      case 401:
        return const SyncException(
          'رمز الوصول غير صحيح أو منتهي الصلاحية. أنشئ رمزًا جديدًا.',
        );
      case 403:
        return const SyncException(
          'رفض GitHub الطلب. تأكد من صلاحية Contents: Read and write، ومن عدم انتهاء الرمز أو تجاوز حد الطلبات.',
        );
      case 404:
        return const SyncException(
          'لم يتم العثور على المستودع أو لا يملك رمز الوصول صلاحية الوصول إليه. تأكد من اسم المستخدم والمستودع واختيار المستودع عند إنشاء الرمز.',
        );
      case 409:
        return const SyncException(
          'حدث تعارض مع النسخة السحابية. أعد المحاولة للحصول على أحدث نسخة ثم ارفع من جديد.',
        );
      case 422:
        return SyncException(
          githubMessage == 'sha does not match'
              ? 'تغيرت النسخة السحابية أثناء الرفع. أعد المحاولة.'
              : 'رفض GitHub البيانات المرسلة (422). تحقق من إعدادات المستودع ثم أعد المحاولة.',
        );
      case 429:
        return const SyncException(
          'تم تجاوز حد الطلبات مؤقتًا. انتظر قليلًا ثم أعد المحاولة.',
        );
      default:
        return SyncException('خطأ من GitHub (رمز ${r.statusCode}).');
    }
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body().timeout(const Duration(seconds: 40));
    } on SyncException {
      rethrow;
    } on TimeoutException {
      throw const SyncException(
        'انتهت مهلة الاتصال بـ GitHub. تحقق من الإنترنت ثم أعد المحاولة.',
      );
    } on http.ClientException {
      throw const SyncException(
        'تعذر الاتصال بخادم GitHub. تحقق من الإنترنت ثم أعد المحاولة.',
      );
    } catch (_) {
      throw const SyncException(
        'تعذر الاتصال بالإنترنت أو بخادم GitHub.',
      );
    }
  }

  /// يتحقق من إمكانية الوصول إلى المستودع بالبيانات الحالية دون تعديل أي ملف.
  Future<void> checkAccess(GithubSyncConfig c) => _guard(() async {
        final res = await http.get(_repoUri(c), headers: _headers(c));
        if (res.statusCode != 200) {
          throw _httpError(res);
        }
      });

  /// يرفع [json] إلى المستودع (ينشئ الملف أو يحدّثه).
  Future<void> upload(GithubSyncConfig c, String json) => _guard(() async {
        // نجلب SHA الحالي للملف إن وُجد؛ يلزم SHA عند تحديث ملف قائم.
        String? sha;
        final meta = await http.get(_fileUri(c), headers: _headers(c));
        if (meta.statusCode == 200) {
          final decoded = jsonDecode(meta.body);
          if (decoded is Map) {
            sha = decoded['sha'] as String?;
          }
        } else if (meta.statusCode != 404) {
          throw _httpError(meta);
        }

        final body = jsonEncode({
          'message': 'Almasnaa cloud sync ${DateTime.now().toIso8601String()}',
          'content': base64Encode(utf8.encode(json)),
          if (sha != null) 'sha': sha,
        });
        final res = await http.put(
          _fileUri(c),
          headers: {..._headers(c), 'Content-Type': 'application/json'},
          body: body,
        );
        if (res.statusCode != 200 && res.statusCode != 201) {
          throw _httpError(res);
        }
        try {
          final d = jsonDecode(res.body);
          final sha = d is Map && d['content'] is Map
              ? (d['content'] as Map)['sha'] as String?
              : null;
          if (sha != null) await saveLastSha(sha);
        } catch (_) {}
        await _markSynced();
      });

  /// SHA الحالي للملف السحابي، أو null إن لم يوجد ملف بعد.
  Future<String?> fetchRemoteSha(GithubSyncConfig c) => _guard(() async {
        final res = await http.get(_fileUri(c), headers: _headers(c));
        if (res.statusCode == 404) return null;
        if (res.statusCode != 200) throw _httpError(res);
        final d = jsonDecode(res.body);
        return d is Map ? d['sha'] as String? : null;
      });

  /// يسجّل SHA النسخة السحابية الحالية كنسخة متطابقة مع هذا الجهاز
  /// (محاولة اختيارية لا ترمي أخطاء).
  Future<void> recordRemoteSha(GithubSyncConfig c) async {
    try {
      final sha = await fetchRemoteSha(c);
      if (sha != null) await saveLastSha(sha);
    } catch (_) {}
  }

  /// ينزّل نص JSON من المستودع، أو null إن لم يكن هناك ملف بعد.
  Future<String?> download(GithubSyncConfig c) => _guard(() async {
        final res = await http.get(
          _fileUri(c),
          headers: _headers(c, accept: 'application/vnd.github.raw+json'),
        );
        if (res.statusCode == 404) {
          // نفرّق بين "لا يوجد ملف" و"لا يوجد وصول" بفحص المستودع نفسه.
          final repo = await http.get(_repoUri(c), headers: _headers(c));
          if (repo.statusCode == 200) return null;
          throw _httpError(repo);
        }
        if (res.statusCode != 200) throw _httpError(res);
        return utf8.decode(res.bodyBytes);
      });

  /// يُسجّل وقت آخر مزامنة بعد نجاح العملية فعليًا.
  Future<void> markSynced() => _markSynced();
}
