import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/env.dart';
import '../data/view_scope.dart';
import 'app_user.dart';

/// مراحل الدخول قبل فتح التطبيق.
enum AuthStage {
  booting,
  notConfigured,
  signedOut,
  mustChangePassword,
  needsSupervisor, // للرصيص فقط: اختيار المشرف الحالي إلزامي
  ready,
}

class _AuthFail implements Exception {
  _AuthFail(this.message);
  final String message;
}

/// رسالة عامة لا تكشف هل اسم المستخدم موجود أم كلمة المرور خاطئة.
const String kGenericLoginError = 'بيانات الدخول غير صحيحة';
const String kOfflineError = 'تعذّر الاتصال بالخادم. تحقق من الإنترنت ثم أعد المحاولة.';

/// يدير الجلسة والهوية والدور. كل التحقق الفعلي يتم على خادم Supabase؛
/// هذا الكلاس يعكس نتيجته على الواجهة فقط.
class AuthController extends ChangeNotifier {
  AuthController({this.onSessionEnded});

  /// يُستدعى عند انتهاء الجلسة لأي سبب (خروج، تعطيل، انتهاء) لتفريغ بيانات الذاكرة.
  final VoidCallback? onSessionEnded;

  AuthStage stage = AuthStage.booting;
  AppUser? user;

  /// المشرف المرتبط حاليًا بالرصيص ويومية الرصيص المختارة (تستخدمها المرحلة 3).
  String? currentSupervisorId;
  String? currentSupervisorName;
  String? selectedSessionId;

  /// رسالة تظهر في شاشة الدخول بعد إنهاء الجلسة (حساب معطّل مثلًا).
  String? notice;

  StreamSubscription<AuthState>? _sub;
  Timer? _watchdog;

  SupabaseClient get _c => Supabase.instance.client;

  /// وضع «عرض كمستخدم» (الأدمن فقط): يغيّر نطاق العرض والواجهة لا الصلاحيات الفعلية.
  DirectoryUser? viewAs;

  /// الدور المعروض في الواجهة (دور المستخدم المستهدف أثناء وضع العرض).
  AppRole? get effectiveRole => viewAs?.role ?? user?.role;

  /// الأدمن الحقيقي المسجَّل دخوله (يتجاهل وضع العرض).
  bool get realIsAdmin => user?.role == AppRole.admin;

  bool get isAdmin => effectiveRole == AppRole.admin;
  bool get isRassas => effectiveRole == AppRole.rassas;
  bool get isSupervisor => effectiveRole == AppRole.supervisor;

  /// بدء عرض التطبيق كمستخدم آخر (للأدمن فقط؛ يُتحقق منه هنا وفي الخادم لأغراض التدقيق).
  void startViewAs(DirectoryUser target) {
    if (!realIsAdmin || target.id == user?.id) return;
    viewAs = target;
    ViewScope.apply(id: target.id, role: target.role.dbValue);
    notifyListeners();
  }

  void stopViewAs() {
    if (viewAs == null) return;
    viewAs = null;
    ViewScope.clear();
    notifyListeners();
  }

  /// كل المستخدمين النشطين (لاختيار المستخدم في وضع العرض).
  Future<List<DirectoryUser>> activeUsers() async {
    final rows = await _c.from('directory').select().order('display_name');
    return (rows as List)
        .map((e) => DirectoryUser.fromMap(Map<String, dynamic>.from(e as Map)))
        .where((u) => u.id != user?.id)
        .toList();
  }

  /// الغرف: الأدمن والرصيص يديران، المشرف قراءة فقط.
  bool get canManageRooms => isAdmin || isRassas;

  /// السجل: التعديل الشامل للمشرف والأدمن. الرصيص يعدّل 4 حقول مباشرة فقط
  /// (المواصفات، وصف الأوردر، النواقص الحالية، المشكلة) والخادم يفرض ذلك.
  bool get canFullEditRecords => isAdmin || isSupervisor;

  Future<void> init() async {
    if (!Env.isConfigured) {
      stage = AuthStage.notConfigured;
      notifyListeners();
      return;
    }
    _sub = _c.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedOut && user != null) {
        _reset();
      }
    });
    if (_c.auth.currentSession == null) {
      stage = AuthStage.signedOut;
      notifyListeners();
      return;
    }
    try {
      await _afterSignIn();
    } on _AuthFail {
      await _safeSignOut();
      _reset();
    } catch (_) {
      // لا إنترنت عند الفتح: نبقى في شاشة الدخول ولا نفتح التطبيق دون تحقق.
      stage = AuthStage.signedOut;
      notice = kOfflineError;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- login

  Future<List<LoginOption>> loginOptions(AppRole role) async {
    final res = await _c.rpc('login_options', params: {'p_role': role.dbValue});
    return (res as List)
        .map((e) => LoginOption.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// يعيد null عند النجاح، أو رسالة خطأ مناسبة.
  Future<String?> signIn({
    required AppRole role,
    required LoginOption option,
    required String password,
  }) async {
    try {
      await _c.auth.signInWithPassword(email: option.email, password: password);
      await _afterSignIn(expectedRole: role);
      notice = null;
      return null;
    } on AuthException {
      await _safeSignOut();
      return kGenericLoginError;
    } on _AuthFail catch (e) {
      await _safeSignOut();
      return e.message;
    } catch (_) {
      await _safeSignOut();
      return kOfflineError;
    }
  }

  Future<void> _afterSignIn({AppRole? expectedRole}) async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) throw _AuthFail(kGenericLoginError);
    final row = await _c.from('profiles').select().eq('id', uid).maybeSingle();
    if (row == null) throw _AuthFail(kGenericLoginError);
    final status = row['status'] as String?;
    if (status != 'active' || row['deleted_at'] != null) {
      throw _AuthFail('هذا الحساب معطّل. تواصل مع الأدمن.');
    }
    final u = AppUser.fromMap(Map<String, dynamic>.from(row));
    if (expectedRole != null && u.role != expectedRole) {
      throw _AuthFail(kGenericLoginError);
    }
    user = u;
    try {
      await _c.rpc('touch_login');
    } catch (_) {/* غير حرج */}
    await _advance();
    _startWatchdog();
  }

  /// يحدد الشاشة التالية حسب الحالة.
  Future<void> _advance() async {
    final u = user!;
    if (u.mustChangePassword) {
      stage = AuthStage.mustChangePassword;
    } else if (u.role == AppRole.rassas) {
      await _loadLink();
      stage = AuthStage.needsSupervisor; // تُعرض دائمًا، والمشرف الحالي محدد مسبقًا
    } else {
      stage = AuthStage.ready;
    }
    notifyListeners();
  }

  // ------------------------------------------------------- password change

  Future<String?> changePassword(String newPassword) async {
    if (newPassword.length < 6) return 'كلمة المرور 6 أحرف على الأقل';
    try {
      await _c.auth.updateUser(UserAttributes(password: newPassword));
      await _c.rpc('password_changed');
      user = user!.copyWith(mustChangePassword: false);
      await _advance();
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (_) {
      return kOfflineError;
    }
  }

  // ---------------------------------------------------- supervisor linking

  Future<void> _loadLink() async {
    final link = await _c
        .from('rassas_supervisor_links')
        .select('supervisor_id')
        .eq('rassas_id', user!.id)
        .isFilter('effective_to', null)
        .maybeSingle();
    currentSupervisorId = link?['supervisor_id'] as String?;
    currentSupervisorName = null;
    if (currentSupervisorId != null) {
      final s = await _c
          .from('directory')
          .select('display_name')
          .eq('id', currentSupervisorId!)
          .maybeSingle();
      currentSupervisorName = s?['display_name'] as String?;
      // مشرف معطّل: لا يُعد ارتباطًا صالحًا.
      if (s == null) {
        currentSupervisorId = null;
      }
    }
  }

  Future<List<DirectoryUser>> activeSupervisors() async {
    final rows = await _c
        .from('directory')
        .select()
        .eq('role', 'supervisor')
        .order('display_name');
    return (rows as List)
        .map((e) => DirectoryUser.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// يربط الرصيص بالمشرف ويستأنف يوميته المفتوحة معه إن وُجدت. لا يُنشئ يومية أبدًا:
  /// إن لم توجد يومية مفتوحة يعيد الخادم null، وينشئها الرصيص صراحةً من تبويب اليومية.
  Future<String?> pickSupervisor(DirectoryUser supervisor) async {
    try {
      final sid = await _c.rpc('change_supervisor',
          params: {'p_supervisor': supervisor.id});
      selectedSessionId = sid as String?;
      currentSupervisorId = supervisor.id;
      currentSupervisorName = supervisor.displayName;
      stage = AuthStage.ready;
      notifyListeners();
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    } catch (_) {
      return kOfflineError;
    }
  }

  /// يعيد فتح شاشة اختيار المشرف (من قسم الربط في المرحلة 3).
  Future<void> requestSupervisorChange() async {
    if (!isRassas) return;
    await _loadLink();
    stage = AuthStage.needsSupervisor;
    notifyListeners();
  }

  // ------------------------------------------------------------- sign out

  Future<void> signOut() async {
    await _safeSignOut();
    _reset();
  }

  Future<void> _safeSignOut() async {
    try {
      await _c.auth.signOut();
    } catch (_) {}
  }

  void _reset({String? message}) {
    _watchdog?.cancel();
    onSessionEnded?.call();
    viewAs = null;
    ViewScope.clear();
    user = null;
    currentSupervisorId = null;
    currentSupervisorName = null;
    selectedSessionId = null;
    stage = AuthStage.signedOut;
    if (message != null) notice = message;
    notifyListeners();
  }

  /// كل دقيقة: إن عُطّل الحساب أو حُذف أثناء الجلسة تنتهي الجلسة فورًا.
  void _startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 60), (_) async {
      final uid = _c.auth.currentUser?.id;
      if (uid == null || user == null) return;
      try {
        final row = await _c
            .from('profiles')
            .select('status, deleted_at')
            .eq('id', uid)
            .maybeSingle();
        if (row == null || row['status'] != 'active' || row['deleted_at'] != null) {
          await _safeSignOut();
          _reset(message: 'تم تعطيل هذا الحساب. تواصل مع الأدمن.');
        }
      } catch (_) {
        // انقطاع مؤقت: لا نُنهي الجلسة بسببه.
      }
    });
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
