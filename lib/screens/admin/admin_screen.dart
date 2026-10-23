import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/app_user.dart';
import '../../auth/auth_controller.dart';
import '../../core/app_theme.dart';
import '../../services/admin_api.dart';

/// تبويب الأدمن: الحسابات، إسناد الإدخالات القديمة بلا مالك، كلمة مرور النسخ الاحتياطي.
/// الصلاحيات مفروضة في الخادم؛ هذا التبويب لا يظهر لغير الأدمن.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!context.read<AuthController>().isAdmin) return const SizedBox.shrink();
    return const DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Material(
            color: Colors.white,
            child: TabBar(
              labelColor: AppColors.primary,
              tabs: [
                Tab(text: 'الحسابات'),
                Tab(text: 'إدخالات بلا مالك'),
                Tab(text: 'كلمة مرور النسخ'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(children: [
              _AccountsTab(),
              _OrphanEntriesTab(),
              _BackupPasswordTab(),
            ]),
          ),
        ],
      ),
    );
  }
}

SupabaseClient get _c => Supabase.instance.client;

void _snack(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

// ===================================================================== accounts

class _AccountsTab extends StatefulWidget {
  const _AccountsTab();

  @override
  State<_AccountsTab> createState() => _AccountsTabState();
}

class _AccountsTabState extends State<_AccountsTab> {
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _c
          .from('profiles')
          .select()
          .isFilter('deleted_at', null)
          .order('role')
          .order('display_name');
      if (!mounted) return;
      setState(() {
        _rows = (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = kOfflineError;
      });
    }
  }

  Future<void> _run(Future<void> Function() op, String ok) async {
    try {
      await op();
      if (mounted) _snack(context, ok);
      await _load();
    } on AdminApiException catch (e) {
      if (mounted) _snack(context, e.message);
    }
  }

  Future<void> _create() async {
    final r = await showDialog<_AccountForm>(context: context, builder: (_) => const _AccountDialog());
    if (r == null) return;
    await _run(
      () => AdminApi.instance.createAccount(
        username: r.username,
        displayName: r.displayName,
        role: r.role,
        password: r.password!,
        forceChange: r.forceChange,
      ),
      'تم إنشاء الحساب',
    );
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final r = await showDialog<_AccountForm>(
        context: context, builder: (_) => _AccountDialog(existing: row));
    if (r == null) return;
    await _run(
      () => AdminApi.instance.updateAccount(row['id'] as String,
          username: r.username, displayName: r.displayName, role: r.roleChanged ? r.role : null),
      'تم حفظ التعديل',
    );
  }

  Future<void> _resetPassword(Map<String, dynamic> row) async {
    final ctrl = TextEditingController();
    bool force = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('كلمة مرور جديدة: ${row['display_name']}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: ctrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'كلمة المرور (6 أحرف على الأقل)'),
            ),
            CheckboxListTile(
              value: force,
              onChanged: (v) => setS(() => force = v ?? false),
              title: const Text('إلزامه بتغييرها عند أول دخول'),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    final pw = ctrl.text;
    ctrl.dispose();
    if (ok != true) return;
    await _run(() => AdminApi.instance.setPassword(row['id'] as String, pw, forceChange: force),
        'تم تغيير كلمة المرور');
  }

  Future<void> _toggle(Map<String, dynamic> row) async {
    final active = row['status'] == 'active';
    final yes = await _confirm(
        active ? 'تعطيل ${row['display_name']}؟' : 'إعادة تفعيل ${row['display_name']}؟',
        active ? 'لن يستطيع الدخول ولن تُنقل بياناته. يمكن إعادة تفعيله لاحقًا.' : 'سيستطيع الدخول مجددًا.');
    if (!yes) return;
    await _run(() => AdminApi.instance.setStatus(row['id'] as String, !active),
        active ? 'تم التعطيل' : 'تم التفعيل');
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final yes = await _confirm('حذف ${row['display_name']}؟',
        'إن كان للحساب سجلات سابقة فسيُحذف منطقيًا (يُعطَّل وتبقى سجلاته كاملة). وإلا يُحذف نهائيًا. لا رجعة في الحذف النهائي.');
    if (!yes) return;
    try {
      final mode = await AdminApi.instance.deleteAccount(row['id'] as String);
      if (mounted) _snack(context, mode == 'physical' ? 'حُذف الحساب نهائيًا' : 'حُذف منطقيًا وسجلاته محفوظة');
      await _load();
    } on AdminApiException catch (e) {
      if (mounted) _snack(context, e.message);
    }
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final me = context.read<AuthController>().user?.id;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('حساب جديد'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!),
                  TextButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final r = _rows[i];
                      final active = r['status'] == 'active';
                      final isMe = r['id'] == me;
                      return Card(
                        child: ListTile(
                          leading: Icon(
                              r['role'] == 'admin'
                                  ? Icons.admin_panel_settings_outlined
                                  : r['role'] == 'rassas'
                                      ? Icons.construction_outlined
                                      : Icons.supervisor_account_outlined,
                              color: active ? AppColors.primary : Colors.grey),
                          title: Text('${r['display_name']}${isMe ? '  (أنت)' : ''}',
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text(
                              '${AppRole.fromDb(r['role'] as String).label} • ${r['username']} • ${active ? 'نشط' : 'معطّل'}'
                              '${r['last_login_at'] != null ? '\nآخر دخول: ${r['last_login_at'].toString().substring(0, 16).replaceFirst('T', ' ')}' : ''}'),
                          isThreeLine: r['last_login_at'] != null,
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) {
                              switch (v) {
                                case 'edit':
                                  _edit(r);
                                case 'pw':
                                  _resetPassword(r);
                                case 'toggle':
                                  _toggle(r);
                                case 'delete':
                                  _delete(r);
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                              const PopupMenuItem(value: 'pw', child: Text('كلمة مرور جديدة')),
                              if (!isMe)
                                PopupMenuItem(value: 'toggle', child: Text(active ? 'تعطيل' : 'إعادة تفعيل')),
                              if (!isMe) const PopupMenuItem(value: 'delete', child: Text('حذف')),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _AccountForm {
  _AccountForm(this.username, this.displayName, this.role, this.password, this.forceChange, this.roleChanged);
  final String username;
  final String displayName;
  final String role;
  final String? password;
  final bool forceChange;
  final bool roleChanged;
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({this.existing});
  final Map<String, dynamic>? existing;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late final _username = TextEditingController(text: widget.existing?['username'] as String? ?? '');
  late final _display = TextEditingController(text: widget.existing?['display_name'] as String? ?? '');
  final _password = TextEditingController();
  late String _role = widget.existing?['role'] as String? ?? 'supervisor';
  bool _force = false;
  String? _error;

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    _username.dispose();
    _display.dispose();
    _password.dispose();
    super.dispose();
  }

  void _ok() {
    if (_username.text.trim().isEmpty) {
      setState(() => _error = 'اسم المستخدم مطلوب');
      return;
    }
    if (_isNew && _password.text.length < 6) {
      setState(() => _error = 'كلمة المرور 6 أحرف على الأقل');
      return;
    }
    Navigator.pop(
      context,
      _AccountForm(
        _username.text.trim(),
        _display.text.trim().isEmpty ? _username.text.trim() : _display.text.trim(),
        _role,
        _isNew ? _password.text : null,
        _force,
        !_isNew && _role != widget.existing!['role'],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isNew ? 'حساب جديد' : 'تعديل الحساب'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              key: ValueKey(_role),
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'الدور'),
              items: [for (final r in AppRole.values) DropdownMenuItem(value: r.dbValue, child: Text(r.label))],
              onChanged: (v) => setState(() => _role = v ?? _role),
            ),
            if (!_isNew)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('لا يمكن تغيير الدور بعد أن يكون للحساب سجلات.', style: TextStyle(fontSize: 12)),
              ),
            const SizedBox(height: 12),
            TextField(controller: _username, decoration: const InputDecoration(labelText: 'اسم المستخدم')),
            const SizedBox(height: 12),
            TextField(controller: _display, decoration: const InputDecoration(labelText: 'الاسم المعروض')),
            if (_isNew) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'كلمة المرور (6 أحرف على الأقل)'),
              ),
              CheckboxListTile(
                value: _force,
                onChanged: (v) => setState(() => _force = v ?? false),
                title: const Text('إلزامه بتغييرها عند أول دخول'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        ElevatedButton(onPressed: _ok, child: const Text('حفظ')),
      ],
    );
  }
}

// ============================================================ owner-less entries

class _OrphanEntriesTab extends StatefulWidget {
  const _OrphanEntriesTab();

  @override
  State<_OrphanEntriesTab> createState() => _OrphanEntriesTabState();
}

class _OrphanEntriesTabState extends State<_OrphanEntriesTab> {
  List<Map<String, dynamic>> _rows = const [];
  List<DirectoryUser> _rassas = const [];
  List<DirectoryUser> _supervisors = const [];
  final Set<String> _selected = {};
  DirectoryUser? _r;
  DirectoryUser? _s;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _c
          .from('daily_entries')
          .select('id, room_name_snapshot, numbering, is_external, merchant_name, created_at')
          .isFilter('rassas_id', null)
          .isFilter('supervisor_id', null)
          .order('created_at');
      final dir = await _c.from('directory').select().order('display_name');
      final users = (dir as List).map((e) => DirectoryUser.fromMap(Map<String, dynamic>.from(e as Map))).toList();
      if (!mounted) return;
      setState(() {
        _rows = (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _rassas = users.where((u) => u.role == AppRole.rassas).toList();
        _supervisors = users.where((u) => u.role == AppRole.supervisor).toList();
        _selected.removeWhere((id) => !_rows.any((r) => r['id'] == id));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = kOfflineError;
      });
    }
  }

  Future<void> _assign() async {
    final r = _r, s = _s;
    if (_busy || r == null || s == null || _selected.isEmpty) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الإسناد'),
        content: Text('إسناد ${_selected.length} إدخال إلى الرصيص ${r.displayName} والمشرف ${s.displayName}؟\n'
            'يصبح الإدخال مرئيًا لهما، ولا يمكن تغيير مالكه بعد ذلك.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إسناد')),
        ],
      ),
    );
    if (yes != true) return;
    setState(() => _busy = true);
    try {
      final n = await _c.rpc('assign_entry_owner', params: {
        'p_entry_ids': _selected.toList(),
        'p_rassas': r.id,
        'p_supervisor': s.id,
      });
      if (mounted) _snack(context, 'تم إسناد $n إدخال');
      _selected.clear();
      await _load();
    } on PostgrestException catch (e) {
      if (mounted) _snack(context, e.message);
    } catch (_) {
      if (mounted) _snack(context, kOfflineError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!),
        TextButton(onPressed: _load, child: const Text('إعادة المحاولة')),
      ]));
    }
    if (_rows.isEmpty) {
      return const Center(child: Text('لا توجد إدخالات بلا مالك.'));
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          const Text(
            'هذه إدخالات من الإصدار 1.0 لم يُسجَّل فيها رصيص ولا مشرف، فلم تُنسب لأحد تلقائيًا. '
            'تظهر للأدمن فقط حتى تُسنَد.',
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<DirectoryUser>(
                key: ValueKey(_r),
                initialValue: _r,
                decoration: const InputDecoration(labelText: 'الرصيص'),
                items: [for (final u in _rassas) DropdownMenuItem(value: u, child: Text(u.displayName))],
                onChanged: (v) => setState(() => _r = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<DirectoryUser>(
                key: ValueKey(_s),
                initialValue: _s,
                decoration: const InputDecoration(labelText: 'المشرف'),
                items: [for (final u in _supervisors) DropdownMenuItem(value: u, child: Text(u.displayName))],
                onChanged: (v) => setState(() => _s = v),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            TextButton(
              onPressed: () => setState(() {
                if (_selected.length == _rows.length) {
                  _selected.clear();
                } else {
                  _selected.addAll(_rows.map((r) => r['id'] as String));
                }
              }),
              child: Text(_selected.length == _rows.length ? 'إلغاء تحديد الكل' : 'تحديد الكل'),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: (_busy || _selected.isEmpty || _r == null || _s == null) ? null : _assign,
              icon: const Icon(Icons.assignment_ind_outlined),
              label: Text('إسناد المحدد (${_selected.length})'),
            ),
          ]),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          itemCount: _rows.length,
          itemBuilder: (_, i) {
            final r = _rows[i];
            final id = r['id'] as String;
            final ext = r['is_external'] == true;
            return Card(
              child: CheckboxListTile(
                value: _selected.contains(id),
                onChanged: (v) => setState(() => v == true ? _selected.add(id) : _selected.remove(id)),
                title: Text('${r['room_name_snapshot']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                    '${ext ? 'غرفة خارجية${(r['merchant_name'] ?? '').toString().isNotEmpty ? ' • ${r['merchant_name']}' : ''} • ' : ''}'
                    'ترقيم: ${r['numbering'] ?? ''} • ${r['created_at'].toString().substring(0, 10)}'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            );
          },
        ),
      ),
    ]);
  }
}

// ============================================================== backup password

class _BackupPasswordTab extends StatefulWidget {
  const _BackupPasswordTab();

  @override
  State<_BackupPasswordTab> createState() => _BackupPasswordTabState();
}

class _BackupPasswordTabState extends State<_BackupPasswordTab> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  bool _busy = false;
  String? _msg;
  bool _ok = false;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_a.text.length < 6) {
      setState(() {
        _ok = false;
        _msg = 'كلمة المرور 6 أحرف على الأقل';
      });
      return;
    }
    if (_a.text != _b.text) {
      setState(() {
        _ok = false;
        _msg = 'كلمتا المرور غير متطابقتين';
      });
      return;
    }
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      await _c.rpc('set_backup_password', params: {'p_new': _a.text});
      _a.clear();
      _b.clear();
      setState(() {
        _ok = true;
        _msg = 'تم حفظ كلمة مرور النسخ الاحتياطي';
      });
    } on PostgrestException catch (e) {
      setState(() {
        _ok = false;
        _msg = e.message;
      });
    } catch (_) {
      setState(() {
        _ok = false;
        _msg = kOfflineError;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('كلمة مرور التصدير والاستيراد والحذف الجماعي',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 6),
                const Text(
                    'مستقلة عن كلمة مرور الدخول. تُحفظ مشفّرة على الخادم ولا يمكن استرجاعها، فقط استبدالها. '
                    'أعطها لمن تصرّح لهم فقط.'),
                const SizedBox(height: 14),
                TextField(
                    controller: _a,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة')),
                const SizedBox(height: 12),
                TextField(
                    controller: _b,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور')),
                if (_msg != null) ...[
                  const SizedBox(height: 10),
                  Text(_msg!,
                      style: TextStyle(
                          color: _ok ? Colors.green.shade700 : Colors.red.shade700,
                          fontWeight: FontWeight.w700)),
                ],
                const SizedBox(height: 14),
                ElevatedButton(
                    onPressed: _busy ? null : _save, child: const Text('حفظ')),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}
