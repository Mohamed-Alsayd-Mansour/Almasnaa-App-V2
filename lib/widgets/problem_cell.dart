import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// خلية "المشكلة": تعرض سبب القطع الناقصة بشكل مختصر، وبالضغط عليها
/// تُفتح نافذة لقراءة النص كاملًا وتعديله مباشرة (بنفس أسلوب خلية النواقص).
class ProblemCell extends StatelessWidget {
  final String text;
  final bool editable;
  final Future<void> Function(String newText)? onSave;

  /// نصوص الخلية ونافذتها (الافتراضي: "المشكلة"). تُستخدم الخلية نفسها
  /// لتعديل المواصفات ووصف الأوردر مباشرة من الجدول.
  final String title;
  final String emptyLabel;
  final String hint;

  const ProblemCell({
    super.key,
    required this.text,
    this.editable = false,
    this.onSave,
    this.title = 'المشكلة',
    this.emptyLabel = 'إضافة مشكلة',
    this.hint = 'اكتب سبب القطع الناقصة...',
  });

  @override
  Widget build(BuildContext context) {
    final isEmpty = text.trim().isEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => showDialog(
        context: context,
        builder: (_) => _ProblemDialog(
          initialText: text,
          editable: editable,
          onSave: onSave,
          title: title,
          hint: hint,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                isEmpty ? (editable ? emptyLabel : '') : text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isEmpty ? AppColors.textSecondary : AppColors.textPrimary,
                  fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
            if (editable) ...[
              const SizedBox(width: 4),
              const Icon(Icons.edit, size: 16, color: AppColors.textSecondary),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProblemDialog extends StatefulWidget {
  final String initialText;
  final bool editable;
  final Future<void> Function(String newText)? onSave;
  final String title;
  final String hint;

  const _ProblemDialog({
    required this.initialText,
    required this.editable,
    required this.onSave,
    required this.title,
    required this.hint,
  });

  @override
  State<_ProblemDialog> createState() => _ProblemDialogState();
}

class _ProblemDialogState extends State<_ProblemDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: _controller,
          maxLines: 6,
          minLines: 3,
          readOnly: !widget.editable,
          decoration: InputDecoration(
            hintText: widget.hint,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إغلاق'),
        ),
        if (widget.editable)
          ElevatedButton(
            onPressed: _saving
                ? null
                : () async {
                    setState(() => _saving = true);
                    await widget.onSave?.call(_controller.text);
                    if (context.mounted) Navigator.of(context).pop();
                  },
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('حفظ'),
          ),
      ],
    );
  }
}
