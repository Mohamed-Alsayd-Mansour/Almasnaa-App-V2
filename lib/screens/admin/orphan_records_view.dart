import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/app_user.dart';
import '../../auth/auth_controller.dart';

SupabaseClient get _c => Supabase.instance.client;

void _snack(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

/// «سجلات بلا مالك» (كانت تبويب «إدخالات بلا مالك»): إدخالات v1 المرحَّلة دون رصيص/مشرف.
/// الإسناد يدوي وصريح عبر الدالة assign_entry_owner (أدمن فقط على الخادم، ومسجّل في التدقيق).
/// لا حذف ولا تخمين للمالك.
class OrphanRecordsView extends StatefulWidget {
  const OrphanRecordsView({super.key});

  @override
  State<OrphanRecordsView> createState() => _OrphanRecordsViewState();
}

class _OrphanRecordsViewState extends State<OrphanRecordsView> {
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
      return const Center(child: Text('لا توجد إدخالات بلا مالك. (السجلات لا تُحذف؛ هذه القائمة فارغة لأنه أُسند كل شيء.)'));
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          const Text(
            'سجلات بلا مالك: إدخالات من الإصدار 1.0 لم يُسجَّل فيها رصيص ولا مشرف، فلم تُنسب لأحد تلقائيًا '
            'ولا يخمّن النظام مالكها. لا تُنشأ إدخالات جديدة بهذه الصورة (الإدخال الجديد يأخذ مالكه من يوميته). '
            'تظهر للأدمن فقط ولا تُحذف، ويتم الإسناد يدويًا وصراحةً.',
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

