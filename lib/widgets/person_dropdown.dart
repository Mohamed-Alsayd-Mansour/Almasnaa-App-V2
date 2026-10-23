import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/person.dart';
import '../providers/people_provider.dart';

/// قائمة منسدلة لاختيار اسم من قائمة دور معين (نجار، مشرف، ...) تُدار
/// من تبويب الإعدادات. إن كانت القيمة الحالية غير موجودة في القائمة
/// (اسم قديم أو محذوف) تبقى ظاهرة كخيار حتى لا تضيع عند التعديل.
class PersonDropdownField extends StatelessWidget {
  final PersonRole role;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool required;

  const PersonDropdownField({
    super.key,
    required this.role,
    required this.value,
    required this.onChanged,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    final names = context.watch<PeopleProvider>().namesFor(role);
    final current = (value == null || value!.isEmpty) ? null : value;
    final options = [...names];
    if (current != null && !options.contains(current)) options.add(current);

    return DropdownButtonFormField<String>(
      key: ValueKey(current),
      initialValue: current,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: required ? '${role.fieldLabel} *' : role.fieldLabel,
        helperText:
            names.isEmpty ? 'أضف أسماء ${role.label} من تبويب الإعدادات' : null,
      ),
      items: [
        if (!required)
          const DropdownMenuItem<String>(value: null, child: Text('— بدون —')),
        for (final n in options)
          DropdownMenuItem<String>(value: n, child: Text(n)),
      ],
      onChanged: onChanged,
      validator: required
          ? (v) => (v == null || v.isEmpty) ? '${role.fieldLabel} مطلوب' : null
          : null,
    );
  }
}
