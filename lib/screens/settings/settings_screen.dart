import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
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
import '../../auth/auth_controller.dart';
import '../../widgets/backup_password_dialog.dart';
import 'person_dialog.dart';
import 'sync_links_cards.dart';

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
    final password = await askBackupPassword(context, action: 'التصدير');
    if (password == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final file = await _backup.export(password);
      final bytes = Uint8List.fromList(utf8.encode(file.json));

      // الحفظ حسب المنصة (file_saver): تنزيل مباشر من المتصفح على الويب، ونافذة الحفظ
      // الأصلية على بقية المنصات. الاسم من الخادم: almasnaa-data-{الرصيص}-{المشرف}.json
      // أو اسم نسخة كاملة للأدمن.
      final result = await saveBytesAsFile(
        fileName: file.fileName,
        bytes: bytes,
        mimeType: 'application/json;charset=utf-8',
        dialogTitle: 'حفظ النسخة الاحتياطية',
      );
      if (!mounted) return;
      if (!result.saved) {
        showErrorSnackBar(context, 'تم إلغاء عملية الحفظ.');
        return;
      }
      showSuccessSnackBar(context, kIsWeb
          ? 'بدأ تنزيل النسخة الاحتياطية (${file.fileName}).'
          : 'تم حفظ النسخة الاحتياطية بنجاح.');
    } on BackupException catch (e) {
      if (mounted) showErrorSnackBar(context, e.message);
    } catch (e, st) {
      // التفاصيل للتشخيص فقط (نوع الخطأ ورسالته ومساره). لا يُسجَّل المحتوى ولا كلمة المرور.
      debugPrint('[export] ${e.runtimeType}: $e\n$st');
      if (mounted) {
        showErrorSnackBar(context,
            'تعذر تصدير الملف (${e.runtimeType}). تحقق من اتصالك ومن السماح للموقع بالتنزيلات ثم أعد المحاولة.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// استيراد (الأدمن فقط): فحص الملف ← كلمة المرور ← فحص الخادم وملخص ← تأكيد ← كتابة ذرّية.
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
      if (bytes == null) throw BackupException('تعذر قراءة الملف.');

      final preview = _backup.parse(utf8.decode(bytes));
      if (!mounted) return;

      final password = await askBackupPassword(context, action: 'الاستيراد');
      if (password == null || !mounted) return;

      final plan = await _backup.dryRun(password, preview);
      if (!mounted) return;

      final confirmed = await confirmDelete(
        context,
        title: 'استيراد البيانات',
        confirmLabel: 'استيراد',
        message: 'محتوى الملف: ${preview.rooms} غرفة، ${preview.people} اسم، '
            '${preview.sessions} يومية، ${preview.entries} إدخال.\n\n'
            'الجديد الذي سيُضاف فعلًا:\n'
            '• ${plan.rooms} غرفة\n• ${plan.people} اسم\n'
            '• ${plan.sessions} يومية\n• ${plan.entries} إدخال\n\n'
            'السجلات الموجودة بنفس المعرّف تُتخطى ولا تُستبدل. '
            'العملية ذرّية: إما أن تنجح كاملة أو لا يتغير شيء.',
      );
      if (!confirmed || !mounted) return;

      final done = await _backup.apply(password, preview);
      if (!mounted) return;
      await _reloadAll();
      if (!mounted) return;
      showSuccessSnackBar(
        context,
        'تم الاستيراد: ${done.entries} إدخال، ${done.sessions} يومية، ${done.rooms} غرفة، ${done.people} اسم.',
      );
    } on BackupException catch (e) {
      if (mounted) showErrorSnackBar(context, e.message);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'تعذر استيراد البيانات.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// حذف جميع البيانات التشغيلية (الأدمن فقط). الحسابات والإعدادات وسجل التدقيق تبقى.
  Future<void> _deleteAll() async {
    final confirmed = await confirmDelete(
      context,
      title: 'حذف جميع البيانات',
      message: 'سيتم حذف كل الغرف والأسماء واليوميات والإدخالات لجميع المستخدمين.\n'
          'الحسابات وسجل التدقيق لا يُحذفان. لا يمكن التراجع عن هذه العملية.',
    );
    if (!confirmed || !mounted) return;
    final password = await askBackupPassword(context, action: 'الحذف الجماعي');
    if (password == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _backup.deleteAll(password);
      if (!mounted) return;
      await _reloadAll();
      if (!mounted) return;
      showSuccessSnackBar(context, 'تم حذف جميع البيانات.');
    } on BackupException catch (e) {
      if (mounted) showErrorSnackBar(context, e.message);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'تعذر حذف البيانات.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// حذف قوائم الأسماء فقط (الأدمن). الغرف واليوميات والإدخالات تبقى كما هي.
  Future<void> _deletePeopleOnly() async {
    final confirmed = await confirmDelete(
      context,
      title: 'حذف الأسماء فقط',
      message: 'سيتم حذف جميع الأسماء من قوائم (الخدمة، النجار، الرصيص، المشرف، الرميم، مكان اللف).\n'
          'الغرف واليوميات والإدخالات المسجّلة تبقى كما هي. لا يمكن التراجع عن هذه العملية.',
    );
    if (!confirmed || !mounted) return;
    final password = await askBackupPassword(context, action: 'حذف الأسماء');
    if (password == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final n = await _backup.deletePeopleOnly(password);
      if (!mounted) return;
      await _reloadAll();
      if (!mounted) return;
      showSuccessSnackBar(context, 'تم حذف $n اسم من القوائم.');
    } on BackupException catch (e) {
      if (mounted) showErrorSnackBar(context, e.message);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'تعذر حذف الأسماء.');
    } finally {
      if (mounted) setState(() => _busy = false);
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
    final auth = context.watch<AuthController>();
    final isAdmin = auth.isAdmin;
    final canEditNames = auth.isAdmin || auth.isSupervisor;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        _SectionCard(
          title: 'البيانات والنسخ الاحتياطي',
          subtitle:
              isAdmin
              ? 'صدّر البيانات إلى ملف JSON، أو استورد/احذف بعد كلمة مرور النسخ الاحتياطي.'
              : 'صدّر بياناتك إلى ملف JSON بعد إدخال كلمة مرور النسخ الاحتياطي.',
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
                        if (isAdmin) const SizedBox(width: AppSpacing.sm),
                        if (isAdmin) Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _import,
                            icon: const Icon(Icons.file_upload_outlined),
                            label: const Text('استيراد', textAlign: TextAlign.center),
                          ),
                        ),
                      ],
                    ),
                    if (isAdmin) const SizedBox(height: AppSpacing.sm),
                    if (isAdmin) OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade700),
                      ),
                      onPressed: _busy ? null : _deletePeopleOnly,
                      icon: const Icon(Icons.person_remove_outlined),
                      label: const Text('حذف الأسماء فقط',
                          textAlign: TextAlign.center),
                    ),
                    if (isAdmin) const SizedBox(height: AppSpacing.sm),
                    if (isAdmin) OutlinedButton.icon(
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
                    if (isAdmin) OutlinedButton.icon(
                      onPressed: _busy ? null : _import,
                      icon: const Icon(Icons.file_upload_outlined),
                      label: const Text('استيراد JSON'),
                    ),
                    if (isAdmin) OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade700),
                      ),
                      onPressed: _busy ? null : _deletePeopleOnly,
                      icon: const Icon(Icons.person_remove_outlined),
                      label: const Text('حذف الأسماء فقط'),
                    ),
                    if (isAdmin) OutlinedButton.icon(
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
        const SyncStatusCard(),
        const SizedBox(height: AppSpacing.md),
        const LinksCard(),
        const SizedBox(height: AppSpacing.md),
        _SectionCard(
          title: 'قوائم الأسماء',
          subtitle: isAndroidApp
              ? null
              : 'هذه القوائم تظهر كخيارات عند تسجيل غرفة في اليومية. عدّل الاسم أو دوره، أو أضف اسمًا جديدًا.',
          trailing: canEditNames
              ? ElevatedButton.icon(
                  onPressed: () => _addPerson(),
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة اسم'),
                )
              : null,
          child: Consumer<PeopleProvider>(
            builder: (context, people, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // الرصيص والمشرف يأتيان من حسابات الدخول واليومية، فلا قائمة أسماء لهما.
                for (final role in PersonRole.values.where(
                    (r) => r != PersonRole.installer && r != PersonRole.supervisor))
                  _RoleSection(
                    role: role,
                    readOnly: !canEditNames,
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
  final bool readOnly;

  const _RoleSection({
    this.readOnly = false,
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
                if (!readOnly) IconButton(
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
                trailing: readOnly ? null : Row(
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
