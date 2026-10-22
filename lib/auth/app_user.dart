/// أدوار حسابات الدخول (ثلاثة فقط).
enum AppRole {
  admin,
  rassas,
  supervisor;

  String get dbValue => name;

  static AppRole fromDb(String v) =>
      AppRole.values.firstWhere((e) => e.name == v);

  String get label => switch (this) {
        AppRole.admin => 'الأدمن',
        AppRole.rassas => 'الرصيص',
        AppRole.supervisor => 'المشرف',
      };
}

/// الحساب المصادَق عليه (من جدول profiles). المعرّف ثابت؛ الاسم للعرض فقط.
class AppUser {
  final String id;
  final String username;
  final String displayName;
  final AppRole role;
  final bool mustChangePassword;

  const AppUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
    required this.mustChangePassword,
  });

  AppUser copyWith({bool? mustChangePassword}) => AppUser(
        id: id,
        username: username,
        displayName: displayName,
        role: role,
        mustChangePassword: mustChangePassword ?? this.mustChangePassword,
      );

  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser(
        id: m['id'] as String,
        username: m['username'] as String,
        displayName: m['display_name'] as String,
        role: AppRole.fromDb(m['role'] as String),
        mustChangePassword: (m['must_change_password'] as bool?) ?? false,
      );
}

/// عنصر في قائمة أسماء الدخول (قبل تسجيل الدخول).
class LoginOption {
  final String username;
  final String displayName;
  final String email; // هوية دخول داخلية غير معروضة للمستخدم

  const LoginOption({
    required this.username,
    required this.displayName,
    required this.email,
  });

  factory LoginOption.fromMap(Map<String, dynamic> m) => LoginOption(
        username: m['username'] as String,
        displayName: m['display_name'] as String,
        email: m['login_email'] as String,
      );
}

/// مستخدم نشط (للقوائم المنسدلة): من view الدليل directory.
class DirectoryUser {
  final String id;
  final String username;
  final String displayName;
  final AppRole role;

  const DirectoryUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
  });

  factory DirectoryUser.fromMap(Map<String, dynamic> m) => DirectoryUser(
        id: m['id'] as String,
        username: m['username'] as String,
        displayName: m['display_name'] as String,
        role: AppRole.fromDb(m['role'] as String),
      );
}
