import 'package:flutter/material.dart';

/// حقل عرض فقط لاسم الرصيص أو المشرف. القيمة تأتي من حساب المستخدم المرتبط باليومية
/// ويفرضها الخادم؛ لا يمكن تعديلها من هذه الواجهة (التعديل للأدمن فقط من «السجل»).
class ReadOnlyNameField extends StatelessWidget {
  final String label;
  final String value;
  const ReadOnlyNameField({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.lock_outline, size: 18),
        helperText: 'يُملأ تلقائيًا من الحساب',
      ),
      child: Text(value.isEmpty ? '—' : value),
    );
  }
}
