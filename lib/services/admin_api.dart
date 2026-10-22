import 'package:supabase_flutter/supabase_flutter.dart';

class AdminApiException implements Exception {
  AdminApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// واجهة إدارة الحسابات: كل العمليات تمر عبر Edge Function `admin-users`
/// (تتحقق من أن المنفّذ أدمن نشط). لا يوجد أي مفتاح سري في التطبيق.
class AdminApi {
  AdminApi._();
  static final AdminApi instance = AdminApi._();

  SupabaseClient get _c => Supabase.instance.client;

  Future<Map<String, dynamic>> _call(String action, Map<String, dynamic> args) async {
    try {
      final res = await _c.functions.invoke('admin-users', body: {'action': action, ...args});
      final data = res.data;
      if (data is Map && data['ok'] == true) return Map<String, dynamic>.from(data);
      throw AdminApiException(data is Map ? '${data['error']}' : 'استجابة غير متوقعة');
    } on FunctionException catch (e) {
      final d = e.details;
      throw AdminApiException(d is Map && d['error'] != null ? '${d['error']}' : 'فشل الطلب (${e.status})');
    } on AdminApiException {
      rethrow;
    } catch (_) {
      throw AdminApiException('تعذّر الاتصال بالخادم');
    }
  }

  Future<void> createAccount({
    required String username,
    required String displayName,
    required AppRoleName role,
    required String password,
    bool forceChange = false,
  }) =>
      _call('create', {
        'username': username,
        'display_name': displayName,
        'role': role,
        'password': password,
        'force_change': forceChange,
      });

  Future<void> updateAccount(String id, {String? username, String? displayName, AppRoleName? role}) =>
      _call('update', {
        'id': id,
        if (username != null) 'username': username,
        if (displayName != null) 'display_name': displayName,
        if (role != null) 'role': role,
      });

  Future<void> setPassword(String id, String password, {bool? forceChange}) => _call('set_password', {
        'id': id,
        'password': password,
        if (forceChange != null) 'force_change': forceChange,
      });

  Future<void> setStatus(String id, bool active) =>
      _call('set_status', {'id': id, 'status': active ? 'active' : 'disabled'});

  /// يعيد 'physical' أو 'logical'.
  Future<String> deleteAccount(String id) async {
    final r = await _call('delete', {'id': id, 'confirm': true});
    return '${r['mode']}';
  }
}

/// قيمة الدور كما تُرسل للخادم: admin | rassas | supervisor.
typedef AppRoleName = String;
