import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/person.dart';
import '../../providers/people_provider.dart';
import '../../widgets/common_widgets.dart';

/// نافذة إضافة اسم جديد أو تعديل اسم قائم (الاسم + دوره).
Future<bool?> showPersonDialog(
  BuildContext context, {
  Person? person,
  PersonRole? initialRole,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _PersonDialog(person: person, initialRole: initialRole),
  );
}

class _PersonDialog extends StatefulWidget {
  final Person? person;
  final PersonRole? initialRole;
  const _PersonDialog({this.person, this.initialRole});

  @override
  State<_PersonDialog> createState() => _PersonDialogState();
}

class _PersonDialogState extends State<_PersonDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.person?.name ?? '');
  late PersonRole _role =
      widget.person?.role ?? widget.initialRole ?? PersonRole.carpenter;
  bool _saving = false;

  bool get _isEdit => widget.person != null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final provider = context.read<PeopleProvider>();
    final error = _isEdit
        ? await provider.update(
            original: widget.person!, name: _nameCtrl.text, role: _role)
        : await provider.add(name: _nameCtrl.text, role: _role);
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      showErrorSnackBar(context, error);
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'تعديل الاسم' : 'إضافة اسم'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(labelText: 'الاسم *'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<PersonRole>(
                key: ValueKey(_role),
                initialValue: _role,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'الدور *'),
                items: [
                  for (final r in PersonRole.values)
                    DropdownMenuItem(value: r, child: Text(r.label)),
                ],
                onChanged: (r) => setState(() => _role = r ?? _role),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
