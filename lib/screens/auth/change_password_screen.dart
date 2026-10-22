import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/auth_controller.dart';
import 'auth_shell.dart';

/// تغيير كلمة المرور الإلزامي (الأدمن عند أول دخول).
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_a.text != _b.text) {
      setState(() => _error = 'كلمتا المرور غير متطابقتين');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context.read<AuthController>().changePassword(_a.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: 'تغيير كلمة المرور',
      subtitle: 'يجب تغيير كلمة المرور الأولية قبل المتابعة',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _a,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'كلمة المرور الجديدة (6 أحرف على الأقل)',
                prefixIcon: Icon(Icons.lock_outline)),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _b,
            obscureText: true,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
                labelText: 'تأكيد كلمة المرور', prefixIcon: Icon(Icons.lock_reset_outlined)),
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
                : const Text('حفظ ومتابعة'),
          ),
          TextButton(
            onPressed: _busy ? null : () => context.read<AuthController>().signOut(),
            child: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );
  }
}
