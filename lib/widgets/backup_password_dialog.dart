import 'package:flutter/material.dart';

/// يطلب كلمة مرور النسخ الاحتياطي (مستقلة عن كلمة مرور الدخول). التحقق على الخادم.
/// لا تُحفظ ولا تُسجَّل.
Future<String?> askBackupPassword(BuildContext context, {required String action}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _Dialog(action: action),
  );
}

class _Dialog extends StatefulWidget {
  const _Dialog({required this.action});
  final String action;

  @override
  State<_Dialog> createState() => _DialogState();
}

class _DialogState extends State<_Dialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('كلمة مرور النسخ الاحتياطي'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('أدخل كلمة المرور المخصصة لـ ${widget.action}.'),
        const SizedBox(height: 12),
        TextField(
          controller: _c,
          obscureText: true,
          autofocus: true,
          onSubmitted: (v) => v.isEmpty ? null : Navigator.pop(context, v),
          decoration: const InputDecoration(labelText: 'كلمة المرور'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        ElevatedButton(
          onPressed: () => _c.text.isEmpty ? null : Navigator.pop(context, _c.text),
          child: const Text('متابعة'),
        ),
      ],
    );
  }
}
