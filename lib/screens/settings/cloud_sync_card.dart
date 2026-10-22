import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../services/backup_service.dart';
import '../../services/github_sync_service.dart';
import '../../services/live_sync_service.dart';
import '../../utils/date_formatter.dart';
import '../../utils/platform_utils.dart';
import '../../widgets/common_widgets.dart';

/// قسم "المزامنة السحابية المجانية" في الإعدادات (عبر مستودع GitHub).
class CloudSyncCard extends StatefulWidget {
  /// يُستدعى بعد استعادة البيانات من السحابة لإعادة تحميل كل الشاشات.
  final Future<void> Function() onRestored;
  const CloudSyncCard({super.key, required this.onRestored});

  @override
  State<CloudSyncCard> createState() => _CloudSyncCardState();
}

class _CloudSyncCardState extends State<CloudSyncCard> {
  final _sync = GithubSyncService();
  final _backup = BackupService();
  final _userCtrl = TextEditingController();
  final _repoCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  bool _hideToken = true;
  bool _busy = false;
  bool _loaded = false;
  DateTime? _lastSync;

  final _live = LiveSyncService.instance;

  @override
  void initState() {
    super.initState();
    _live.addListener(_onLiveChanged);
    _load();
  }

  Future<void> _onLiveChanged() async {
    final c = await _sync.loadConfig();
    if (!mounted) return;
    setState(() => _lastSync = c.lastSyncAt);
  }

  Future<void> _toggleLive(bool value) async {
    if (value) {
      if (!_validate()) return;
      await _sync.saveConfig(
        user: _userCtrl.text,
        repo: _repoCtrl.text,
        token: _tokenCtrl.text,
      );
      if (await _sync.loadLastSha() == null) {
        if (!mounted) return;
        showErrorSnackBar(
          context,
          'نفّذ أولًا رفعًا أو تنزيلًا يدويًا واحدًا لتحديد النسخة المرجعية، ثم فعّل المزامنة اللحظية.',
        );
        return;
      }
    }
    await _live.setEnabled(value);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _live.removeListener(_onLiveChanged);
    _userCtrl.dispose();
    _repoCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final c = await _sync.loadConfig();
    if (!mounted) return;
    setState(() {
      _userCtrl.text = c.user;
      _repoCtrl.text = c.repo;
      _tokenCtrl.text = c.token;
      _lastSync = c.lastSyncAt;
      _loaded = true;
    });
  }

  GithubSyncConfig get _config => GithubSyncConfig(
        user: _userCtrl.text,
        repo: _repoCtrl.text,
        token: _tokenCtrl.text,
      );

  bool _validate() {
    if (!_config.isComplete) {
      showErrorSnackBar(context, 'أدخل اسم المستخدم واسم المستودع والرمز أولًا.');
      return false;
    }
    return true;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on SyncException catch (e) {
      if (mounted) showErrorSnackBar(context, e.message);
    } on FormatException catch (e) {
      if (mounted) showErrorSnackBar(context, e.message);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, 'حدث خطأ غير متوقع: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_validate()) return;
    await _sync.saveConfig(
      user: _userCtrl.text,
      repo: _repoCtrl.text,
      token: _tokenCtrl.text,
    );
    if (mounted) showSuccessSnackBar(context, 'تم حفظ إعدادات المزامنة.');
  }

  Future<void> _checkAccess() async {
    if (!_validate()) return;
    await _run(() async {
      await _sync.saveConfig(
        user: _userCtrl.text,
        repo: _repoCtrl.text,
        token: _tokenCtrl.text,
      );
      await _sync.checkAccess(_config);
      if (mounted) {
        showSuccessSnackBar(context, 'تم الاتصال بـ GitHub والوصول إلى المستودع بنجاح.');
      }
    });
  }

  Future<void> _upload() async {
    if (!_validate()) return;
    await _run(() async {
      await _sync.saveConfig(
        user: _userCtrl.text,
        repo: _repoCtrl.text,
        token: _tokenCtrl.text,
      );
      await _sync.upload(_config, await _backup.buildJson());
      final c = await _sync.loadConfig();
      if (!mounted) return;
      setState(() => _lastSync = c.lastSyncAt);
      showSuccessSnackBar(context, 'تم رفع البيانات إلى السحابة.');
    });
  }

  Future<void> _download() async {
    if (!_validate()) return;
    await _run(() async {
      await _sync.saveConfig(
        user: _userCtrl.text,
        repo: _repoCtrl.text,
        token: _tokenCtrl.text,
      );
      final text = await _sync.download(_config);
      if (!mounted) return;
      if (text == null) {
        showErrorSnackBar(context, 'لا توجد نسخة سحابية بعد. ارفع بياناتك أولًا.');
        return;
      }
      final preview = _backup.parse(text);
      final confirmed = await confirmDelete(
        context,
        title: 'تنزيل من السحابة',
        confirmLabel: 'تنزيل واستبدال',
        message: 'سيتم استبدال جميع البيانات الحالية بالنسخة السحابية:\n'
            '• ${preview.rooms.length} غرفة\n'
            '• ${preview.sessions.length} يومية\n'
            '• ${preview.entries.length} إدخال في السجل\n\n'
            'لا يمكن التراجع عن هذه العملية.',
      );
      if (!confirmed || !mounted) return;
      await _backup.restore(preview);
      await widget.onRestored();
      await _sync.markSynced();
      await _sync.recordRemoteSha(_config);
      final c = await _sync.loadConfig();
      if (!mounted) return;
      setState(() => _lastSync = c.lastSyncAt);
      showSuccessSnackBar(context, 'تم تنزيل البيانات من السحابة.');
    });
  }

  Future<void> _signOut() async {
    await _live.setEnabled(false);
    await _sync.clearConfig();
    _tokenCtrl.clear();
    _userCtrl.text = GithubSyncService.defaultUser;
    _repoCtrl.text = GithubSyncService.defaultRepo;
    if (!mounted) return;
    setState(() => _lastSync = null);
    showSuccessSnackBar(context, 'تم مسح بيانات الاتصال من هذا الجهاز.');
  }

  /// ارتفاع موحَّد للحقول الثلاثة على الهاتف ليظهر حرف الياء كاملًا.
  EdgeInsetsGeometry? get _fieldPadding => isMobileApp
      ? const EdgeInsets.symmetric(horizontal: 16, vertical: 23)
      : null;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                            isMobileApp
                                ? 'المزامنة السحابية'
                                : 'المزامنة السحابية المجانية',
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'مزامنة لحظية عند توفر الإنترنت',
                        child: Switch(
                          value: _live.enabled,
                          onChanged: _busy ? null : _toggleLive,
                        ),
                      ),
                    ],
                  ),
                  if (_live.enabled) ...[
                    const SizedBox(height: 2),
                    Text(
                      _live.lastError != null
                          ? 'المزامنة اللحظية: بانتظار الاتصال — ${_live.lastError}'
                          : (_live.busy
                              ? 'المزامنة اللحظية: جارٍ التحديث...'
                              : 'المزامنة اللحظية مفعّلة'),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: _live.lastError != null
                            ? Colors.orange.shade800
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                  if (!isMobileApp) ...[
                    const SizedBox(height: 4),
                    const Text(
                      'احفظ نسخة من بياناتك في مستودع GitHub مجاني، واستعدها على أي جهاز. '
                      'ملاحظة: GitHub لا يقبل كلمة المرور العادية، فيُستخدم "رمز وصول شخصي" بدلًا منها '
                      '(Settings ← Developer settings ← Fine-grained tokens ← اختر هذا المستودع فقط ← Contents: Read and write).',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _userCtrl,
                    enabled: !_busy,
                    autocorrect: false,
                    decoration: InputDecoration(
                        labelText: 'اسم المستخدم (GitHub)',
                        contentPadding: _fieldPadding),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _repoCtrl,
                    enabled: !_busy,
                    autocorrect: false,
                    decoration: InputDecoration(
                        labelText: 'اسم المستودع', contentPadding: _fieldPadding),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _tokenCtrl,
                    enabled: !_busy,
                    obscureText: _hideToken,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      // على الهاتف عنوان أقصر لا يُقتطع بنقاط (...) فيظهر
                      // حرف الياء وغيره كاملًا دون قصّ.
                      labelText: isMobileApp
                          ? 'رمز الوصول الشخصي'
                          : 'رمز الوصول الشخصي (GitHub PAT)',
                      labelStyle: isMobileApp
                          ? const TextStyle(height: 1.7)
                          : null,
                      contentPadding: _fieldPadding,
                      suffixIcon: IconButton(
                        icon: Icon(_hideToken
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () =>
                            setState(() => _hideToken = !_hideToken),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _lastSync == null
                        ? 'لم تتم أي مزامنة بعد من هذا الجهاز.'
                        : 'آخر مزامنة: ${AppDateFormatter.dateTime(_lastSync!)}',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  if (!isMobileApp) ...[
                    const SizedBox(height: 4),
                    Text(
                      'تنبيه: إن كان المستودع عامًا (Public) فسيستطيع أي شخص قراءة البيانات المرفوعة. '
                      'يُفضَّل أن يكون المستودع خاصًا (Private). يُحفظ الرمز على هذا الجهاز فقط.',
                      style: TextStyle(color: Colors.orange.shade800, fontSize: 12.5),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  if (isMobileApp)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: (_busy || _live.enabled) ? null : _upload,
                                icon: const Icon(Icons.cloud_upload_outlined),
                                label: const Text('الرفع', textAlign: TextAlign.center),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: (_busy || _live.enabled) ? null : _download,
                                icon: const Icon(Icons.cloud_download_outlined),
                                label: const Text('التنزيل', textAlign: TextAlign.center),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _busy ? null : _checkAccess,
                                icon: const Icon(Icons.wifi_tethering_outlined),
                                label: const Text('الاختبار', textAlign: TextAlign.center),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _busy ? null : _save,
                                icon: const Icon(Icons.save_outlined),
                                label: const Text('الحفظ', textAlign: TextAlign.center),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextButton.icon(
                          onPressed: _busy ? null : _signOut,
                          icon: const Icon(Icons.logout),
                          label: const Text('مسح بيانات الاتصال',
                              textAlign: TextAlign.center),
                        ),
                      ],
                    )
                  else
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      ElevatedButton.icon(
                        onPressed: (_busy || _live.enabled) ? null : _upload,
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: const Text('رفع إلى السحابة'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _checkAccess,
                        icon: const Icon(Icons.wifi_tethering_outlined),
                        label: const Text('اختبار الاتصال'),
                      ),
                      OutlinedButton.icon(
                        onPressed: (_busy || _live.enabled) ? null : _download,
                        icon: const Icon(Icons.cloud_download_outlined),
                        label: const Text('تنزيل من السحابة'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _save,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('حفظ الإعدادات'),
                      ),
                      TextButton.icon(
                        onPressed: _busy ? null : _signOut,
                        icon: const Icon(Icons.logout),
                        label: const Text('مسح بيانات الاتصال'),
                      ),
                    ],
                  ),
                  if (_busy) ...[
                    const SizedBox(height: AppSpacing.sm),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
      ),
    );
  }
}
