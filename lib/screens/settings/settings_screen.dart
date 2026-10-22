import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../models/person.dart';
import '../../providers/daily_provider.dart';
import '../../providers/people_provider.dart';
import '../../providers/records_provider.dart';
import '../../providers/rooms_provider.dart';
import '../../services/backup_service.dart';
import '../../utils/file_saver.dart';
import '../../utils/platform_utils.dart';
import '../../widgets/common_widgets.dart';
import 'cloud_sync_card.dart';
import 'person_dialog.dart';

/// تبويب الإعدادات: النسخ الاحتياطي (تصدير/استيراد JSON)، حذف كل البيانات،
/// وإدارة قوائم الأسماء (الخدمة، النجار، الرصيص، المشرف، الرميم، مكان اللف).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _backup = BackupService();
  bool _busy = false;

  Future<void> _reloadAll() async {
    await Future.wait([
      context.read<RoomsProvider>().loadRooms(),
      context.read<DailyProvider>().load(),
      context.read<RecordsProvider>().load(),
      context.read<PeopleProvider>().load(),
    ]);
  }

  Future<void> _export() async {
    setState(() => _busy = true);

    try {
      final json = await _backup.buildJson();

      final bytes = Uint8List.fromList(
        utf8.encode(json),
      );

      final now = DateTime.now();

      String two(int n) => n.toString().padLeft(2, '0');

      final fileName =
          'almasnaa-backup-${now.year}-${two(now.month)}-${two(now.day)}.json';

      // فتح نافذة الحفظ الأصلية للنظام (تعمل على Android وiOS
      // وWindows وLinux وmacOS والويب).
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'حفظ النسخة الاحتياطية',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: bytes,
      );

      // على بعض المنصات (خصوصًا سطح المكتب) تُعيد النافذة المسار فقط
      // دون أن تكتب الملف فعليًا، فنكتبه هنا بأنفسنا لضمان نجاح الحفظ
      // في كل الحالات. لا تأثير لهذا على الويب (المسار يكون null هناك
      // لأن المتصفح هو من يتولى التنزيل مباشرة).
      if (path != null) {
        await writeBytesToPath(path, bytes);
      }

      if (!mounted) return;

      if (path == null) {
        showErrorSnackBar(
          context,
          'تم إلغاء عملية الحفظ.',
        );
        return;
      }

      showSuccessSnackBar(
        context,
        'تم حفظ النسخة الاحتياطية بنجاح.',
      );
    } catch (e, stackTrace) {
      debugPrint('EXPORT ERROR: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      showErrorSnackBar(
        context,
        'حدث خطأ أثناء التصدير:\n$e',
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final bytes = result.files.single.bytes;

      if (bytes == null) {
        throw const FormatException('تعذر قراءة الملف.');
      }

      final preview = _backup.parse(utf8.decode(bytes));

      if (!mounted) return;

      final confirmed = await confirmDelete(
        context,
        title: 'استيراد البيانات',
        confirmLabel: 'استيراد',
        message: 'سيتم استبدال جميع البيانات الحالية بمحتوى الملف:\n'
            '• ${preview.rooms.length} غرفة\n'
            '• ${preview.sessions.length} يومية\n'
            '• ${preview.entries.length} إدخال في السجل\n'
            '${preview.people == null ? '' : '• ${preview.people!.length} اسم في القوائم\n'}'
            '\nلا يمكن التراجع عن هذه العملية.',
      );

      if (!confirmed || !mounted) return;

      await _backup.restore(preview);

      if (!mounted) return;

      await _reloadAll();

      if (!mounted) return;

      showSuccessSnackBar(
        context,
        'تم استيراد البيانات بنجاح.',
      );
    } on FormatException catch (e) {
      if (mounted) {
        showErrorSnackBar(
          context,
          e.message,
        );
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(
          context,
          'تعذر استيراد البيانات: $e',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _deleteAll() async {
    final includePeople = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteAllDialog(),
    );

    if (includePeople == null || !mounted) return;

    setState(() => _busy = true);

    try {
      await _backup.deleteAll(
        includePeople: includePeople,
      );

      if (!mounted) return;

      await _reloadAll();

      if (!mounted) return;

      showSuccessSnackBar(
        context,
        'تم حذف جميع البيانات.',
      );
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(
          context,
          'تعذر حذف البيانات: $e',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _addPerson([PersonRole? role]) async {
    final ok = await showPersonDialog(
      context,
      initialRole: role,
    );

    if (ok == true && mounted) {
      showSuccessSnackBar(
        context,
        'تمت إضافة الاسم.',
      );
    }
  }

  Future<void> _editPerson(Person person) async {
    final ok = await showPersonDialog(
      context,
      person: person,
    );

    if (ok == true && mounted) {
      showSuccessSnackBar(
        context,
        'تم تعديل الاسم.',
      );
    }
  }

  Future<void> _deletePerson(Person person) async {
    final confirmed = await confirmDelete(
      context,
      title: 'حذف الاسم',
      message:
          'هل تريد حذف "${person.name}" من قائمة ${person.role.label}؟ لن يؤثر هذا على السجلات المسجّلة سابقًا.',
    );

    if (!confirmed || !mounted) return;

    final error = await context.read<PeopleProvider>().delete(person.id);

    if (!mounted) return;

    if (error != null) {
      showErrorSnackBar(
        context,
        error,
      );
    } else {
      showSuccessSnackBar(
        context,
        'تم حذف الاسم.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        _SectionCard(
          title: 'البيانات والنسخ الاحتياطي',
          subtitle:
              'صدّر كل بياناتك إلى ملف JSON للاحتفاظ بنسخة، أو استورد نسخة سابقة.',
          child: isMobileApp
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _busy ? null : _export,
                            icon: const Icon(Icons.file_download_outlined),
                            label: const Text('تصدير', textAlign: TextAlign.center),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _import,
                            icon: const Icon(Icons.file_upload_outlined),
                            label: const Text('استيراد', textAlign: TextAlign.center),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade700),
                      ),
                      onPressed: _busy ? null : _deleteAll,
                      icon: const Icon(Icons.delete_forever_outlined),
                      label: const Text('حذف جميع البيانات',
                          textAlign: TextAlign.center),
                    ),
                  ],
                )
              : Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _busy ? null : _export,
                      icon: const Icon(Icons.file_download_outlined),
                      label: const Text('تصدير JSON'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _import,
                      icon: const Icon(Icons.file_upload_outlined),
                      label: const Text('استيراد JSON'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade700),
                      ),
                      onPressed: _busy ? null : _deleteAll,
                      icon: const Icon(Icons.delete_forever_outlined),
                      label: const Text('حذف جميع البيانات'),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        CloudSyncCard(onRestored: _reloadAll),
        const SizedBox(height: AppSpacing.md),
        _SectionCard(
          title: 'قوائم الأسماء',
          subtitle: isAndroidApp
              ? null
              : 'هذه القوائم تظهر كخيارات عند تسجيل غرفة في اليومية. عدّل الاسم أو دوره، أو أضف اسمًا جديدًا.',
          trailing: ElevatedButton.icon(
            onPressed: () => _addPerson(),
            icon: const Icon(Icons.add),
            label: const Text('إضافة اسم'),
          ),
          child: Consumer<PeopleProvider>(
            builder: (context, people, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final role in PersonRole.values)
                  _RoleSection(
                    role: role,
                    people: people.byRole(role),
                    onAdd: () => _addPerson(role),
                    onEdit: _editPerson,
                    onDelete: _deletePerson,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            child,
          ],
        ),
      ),
    );
  }
}

class _RoleSection extends StatelessWidget {
  final PersonRole role;
  final List<Person> people;
  final VoidCallback onAdd;
  final ValueChanged<Person> onEdit;
  final ValueChanged<Person> onDelete;

  const _RoleSection({
    required this.role,
    required this.people,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(
        bottom: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border.all(
          color: AppColors.border,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.primary.withValues(
              alpha: 0.06,
            ),
            padding: const EdgeInsets.only(
              right: 14,
              left: 4,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${role.label} (${people.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'إضافة إلى قائمة ${role.label}',
                  icon: const Icon(
                    Icons.add_circle_outline,
                    color: AppColors.primary,
                  ),
                  onPressed: onAdd,
                ),
              ],
            ),
          ),
          if (people.isEmpty)
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'لا توجد أسماء بعد',
                style: TextStyle(
                  color: AppColors.textSecondary,
                ),
              ),
            )
          else
            for (final p in people)
              ListTile(
                dense: true,
                title: Text(p.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'تعديل',
                      icon: const Icon(
                        Icons.edit,
                        color: AppColors.primary,
                      ),
                      onPressed: () => onEdit(p),
                    ),
                    IconButton(
                      tooltip: 'حذف',
                      icon: Icon(
                        Icons.delete_outline,
                        color: Colors.red.shade600,
                      ),
                      onPressed: () => onDelete(p),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// تأكيد مشدّد لحذف كل البيانات: يتطلب كتابة كلمة "حذف".
/// يعيد قيمة "هل تُحذف قوائم الأسماء أيضًا"، أو null عند الإلغاء.
class _DeleteAllDialog extends StatefulWidget {
  const _DeleteAllDialog();

  @override
  State<_DeleteAllDialog> createState() => _DeleteAllDialogState();
}

class _DeleteAllDialogState extends State<_DeleteAllDialog> {
  final _ctrl = TextEditingController();
  bool _includePeople = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canDelete = _ctrl.text.trim() == 'حذف';

    return AlertDialog(
      title: const Text('حذف جميع البيانات'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'سيتم حذف كل الغرف واليوميات والسجل نهائيًا، ولا يمكن التراجع. '
              'يُنصح بتصدير نسخة JSON قبل المتابعة.',
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _includePeople,
              onChanged: (v) => setState(
                () => _includePeople = v ?? false,
              ),
              title: const Text(
                'حذف قوائم الأسماء أيضًا',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _ctrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'اكتب "حذف" للتأكيد',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade700,
          ),
          onPressed: canDelete
              ? () => Navigator.of(context).pop(
                    _includePeople,
                  )
              : null,
          child: const Text('حذف الكل'),
        ),
      ],
    );
  }
}
