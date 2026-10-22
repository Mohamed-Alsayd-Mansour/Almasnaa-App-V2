import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// يعرض نص النواقص بشكل مختصر مع إمكانية فتحه في نافذة موسّعة لقراءة
/// النص الكامل أو تعديله مباشرة، وفق القاعدة رقم 11 في المواصفات.
class DeficiencyCell extends StatelessWidget {
  final String text;
  final int missingCount;
  final bool editable;
  final Future<void> Function(String newText)? onSave;

  const DeficiencyCell({
    super.key,
    required this.text,
    required this.missingCount,
    this.editable = false,
    this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final isEmpty = text.trim().isEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _openDetail(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                isEmpty ? 'لا يوجد نواقص' : text,
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

  void _openDetail(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _DeficiencyDialog(
        initialText: text,
        editable: editable,
        onSave: onSave,
      ),
    );
  }
}

class _DeficiencyDialog extends StatefulWidget {
  final String initialText;
  final bool editable;
  final Future<void> Function(String newText)? onSave;

  const _DeficiencyDialog({
    required this.initialText,
    required this.editable,
    required this.onSave,
  });

  @override
  State<_DeficiencyDialog> createState() => _DeficiencyDialogState();
}

class _DeficiencyDialogState extends State<_DeficiencyDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);
  bool _saving = false;

  int get _liveCount {
    final t = _controller.text.trim();
    if (t.isEmpty) return 0;
    return '-'.allMatches(t).length + 1;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('نواقص الغرفة'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              maxLines: 8,
              minLines: 4,
              readOnly: !widget.editable,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'مثال: باب - رف علوي - ضلفة يمين',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.info_outline, size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text('عدد القطع الناقصة المحسوب: $_liveCount',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ],
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
