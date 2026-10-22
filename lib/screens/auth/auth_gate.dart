import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/auth_controller.dart';
import '../main_tabs_screen.dart';
import 'auth_shell.dart';
import 'change_password_screen.dart';
import 'login_screen.dart';
import 'pick_supervisor_screen.dart';

/// بوابة التطبيق: لا يُفتح شيء قبل مصادقة ناجحة.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final stage = context.select<AuthController, AuthStage>((a) => a.stage);
    switch (stage) {
      case AuthStage.booting:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case AuthStage.notConfigured:
        return const AuthShell(
          title: 'الإعدادات ناقصة',
          child: Text(
            'لم يُضبط عنوان الخادم. ابنِ التطبيق مع:\n'
            '--dart-define=SUPABASE_URL=...\n--dart-define=SUPABASE_ANON_KEY=...',
            textAlign: TextAlign.center,
          ),
        );
      case AuthStage.signedOut:
        return const LoginScreen();
      case AuthStage.mustChangePassword:
        return const ChangePasswordScreen();
      case AuthStage.needsSupervisor:
        return const PickSupervisorScreen();
      case AuthStage.ready:
        return const MainTabsScreen();
    }
  }
}
