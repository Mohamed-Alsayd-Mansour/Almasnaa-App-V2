import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/app_user.dart';
import '../../auth/auth_controller.dart';
import 'auth_shell.dart';

/// شاشة الدخول: الدور ← اسم المستخدم (حسب الدور، النشطون فقط) ← كلمة المرور ← دخول.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _password = TextEditingController();
  AppRole? _role;
  LoginOption? _user;
  List<LoginOption> _options = const [];
  bool _loadingOptions = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = context.read<AuthController>().notice;
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _onRole(AppRole? role) async {
    setState(() {
      _role = role;
      _user = null;
      _options = const [];
      _error = null;
      _loadingOptions = role != null;
    });
    if (role == null) return;
    try {
      final list = await context.read<AuthController>().loginOptions(role);
      if (!mounted || _role != role) return;
      setState(() {
        _options = list;
        _loadingOptions = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingOptions = false;
        _error = kOfflineError;
      });
    }
  }

  Future<void> _submit() async {
    if (_busy) return; // يمنع الضغط المتكرر
    final role = _role;
    final user = _user;
    if (role == null || user == null || _password.text.isEmpty) {
      setState(() => _error = 'اختر الدور واسم المستخدم وأدخل كلمة المرور');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context
        .read<AuthController>()
        .signIn(role: role, option: user, password: _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
      if (err != null) _password.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: 'المصنع',
      subtitle: 'تسجيل الدخول',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<AppRole>(
            initialValue: _role,
            decoration: const InputDecoration(
                labelText: 'الدور', prefixIcon: Icon(Icons.badge_outlined)),
            items: [
              for (final r in AppRole.values)
                DropdownMenuItem(value: r, child: Text(r.label)),
            ],
            onChanged: _busy ? null : _onRole,
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<LoginOption>(
            key: ValueKey(_role),
            initialValue: _user,
            decoration: InputDecoration(
              labelText: 'اسم المستخدم',
              prefixIcon: const Icon(Icons.person_outline),
              suffixIcon: _loadingOptions
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : null,
            ),
            items: [
              for (final o in _options)
                DropdownMenuItem(value: o, child: Text(o.displayName)),
            ],
            onChanged: (_busy || _role == null) ? null : (v) => setState(() => _user = v),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _password,
            obscureText: true,
            enabled: !_busy,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
                labelText: 'كلمة المرور', prefixIcon: Icon(Icons.lock_outline)),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('دخول'),
          ),
        ],
      ),
    );
  }
}
