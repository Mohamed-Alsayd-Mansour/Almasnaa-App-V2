import 'package:flutter/material.dart';

/// كلمة المرور المطلوبة قبل التعديل الشامل على سجلات البيانات.
const String kRecordsEditPassword = '0000';

/// يعرض نافذة إدخال كلمة المرور ويعيد true عند إدخالها صحيحة.
Future<bool> askRecordsEditPassword(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => const _PasswordDialog(),
  );
  return result ?? false;
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.trim() == kRecordsEditPassword) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = 'كلمة المرور غير صحيحة');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('التعديل الشامل على السجل'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('أدخل كلمة المرور للمتابعة.'),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'كلمة المرور',
                errorText: _error,
                prefixIcon: const Icon(Icons.lock_outline),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(onPressed: _submit, child: const Text('تأكيد')),
      ],
    );
  }
}
