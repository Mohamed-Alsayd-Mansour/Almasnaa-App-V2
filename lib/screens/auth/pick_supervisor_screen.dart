import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/app_user.dart';
import '../../auth/auth_controller.dart';
import 'auth_shell.dart';

/// بعد دخول الرصيص وقبل فتح التطبيق: اختيار المشرف المرتبط حاليًا (إلزامي).
/// المشرف الحالي يظهر محددًا مسبقًا؛ لا يمكن المتابعة دون مشرف صالح.
class PickSupervisorScreen extends StatefulWidget {
  const PickSupervisorScreen({super.key});

  @override
  State<PickSupervisorScreen> createState() => _PickSupervisorScreenState();
}

class _PickSupervisorScreenState extends State<PickSupervisorScreen> {
  List<DirectoryUser> _list = const [];
  DirectoryUser? _selected;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthController>();
    try {
      final list = await auth.activeSupervisors();
      if (!mounted) return;
      DirectoryUser? pre;
      for (final s in list) {
        if (s.id == auth.currentSupervisorId) pre = s;
      }
      setState(() {
        _list = list;
        _selected = pre;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = kOfflineError;
      });
    }
  }

  Future<void> _go() async {
    final s = _selected;
    if (_busy || s == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context.read<AuthController>().pickSupervisor(s);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final changing = auth.currentSupervisorId != null &&
        _selected != null &&
        _selected!.id != auth.currentSupervisorId;
    return AuthShell(
      title: 'مع أي مشرف تعمل الآن؟',
      subtitle: 'أهلًا ${auth.user?.displayName ?? ''}',
      child: _loading
          ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<DirectoryUser>(
                  key: ValueKey(_selected),
                  initialValue: _selected,
                  decoration: const InputDecoration(
                      labelText: 'المشرف', prefixIcon: Icon(Icons.supervisor_account_outlined)),
                  items: [
                    for (final s in _list)
                      DropdownMenuItem(value: s, child: Text(s.displayName)),
                  ],
                  onChanged: _busy ? null : (v) => setState(() => _selected = v),
                ),
                if (changing) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'عند تغيير المشرف تُعلَّق يوميتك الحالية دون إغلاقها، وتُستأنف يومية '
                    'المشرف الجديد إن كانت مفتوحة. لا تُنشأ يومية جديدة تلقائيًا؛ '
                    'تنشئها بنفسك من تبويب اليومية. اليوميات السابقة تبقى لأصحابها.',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
                if (_list.isEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('لا يوجد مشرف نشط. تواصل مع الأدمن.', textAlign: TextAlign.center),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w700)),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: (_busy || _selected == null) ? null : _go,
                  child: _busy
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('متابعة'),
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
