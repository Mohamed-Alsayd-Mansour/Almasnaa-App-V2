import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/app_user.dart';
import '../../auth/auth_controller.dart';
import '../../core/app_theme.dart';
import '../../data/supa.dart';
import '../../services/realtime_hub.dart';
import '../../utils/date_formatter.dart';

/// المزامنة: عرض حالة فقط. لا أزرار رفع/تنزيل/اختبار/تشغيل ولا حقول قابلة للتعديل.
/// اسم العامل يُملأ تلقائيًا من حساب الجلسة. إعدادات الخادم يديرها الأدمن خارج هذا التطبيق.
class SyncStatusCard extends StatelessWidget {
  const SyncStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: ListenableBuilder(
          listenable: RealtimeHub.instance,
          builder: (context, _) {
            final hub = RealtimeHub.instance;
            final stateLabel = switch (hub.state) {
              SyncState.online => 'متصل — المزامنة لحظية وتلقائية',
              SyncState.connecting => 'جارٍ الاتصال…',
              SyncState.offline => 'غير متصل — لن تُحفظ التغييرات حتى يعود الاتصال',
            };
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('المزامنة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                _row('الحالة', stateLabel),
                _row('آخر مزامنة',
                    hub.lastSyncAt == null ? '—' : AppDateFormatter.dateTime(hub.lastSyncAt!)),
                _row('اسم المستخدم (العامل)', auth.user?.displayName ?? '—'),
                _row('الخادم', 'Supabase (المصدر الرسمي للبيانات)'),
                if (hub.lastError != null) ...[
                  const SizedBox(height: 6),
                  Text(hub.lastError!, style: TextStyle(color: Colors.red.shade700)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 150, child: Text(k, style: const TextStyle(color: AppColors.textSecondary))),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );
}

/// قسم الربط: الرصيص يرى مشرفه الحالي ويغيّره (بتأكيد يوضح الأثر)، المشرف يرى رصيصيه
/// المرتبطين حاليًا للعرض فقط، والأدمن يرى كل الروابط. التعديل مرفوض في الخادم لغير الرصيص/الأدمن.
class LinksCard extends StatefulWidget {
  const LinksCard({super.key});

  @override
  State<LinksCard> createState() => _LinksCardState();
}

class _LinksCardState extends State<LinksCard> {
  List<Map<String, dynamic>> _links = const [];
  Map<String, String> _names = const {};
  bool _loading = true;
  String? _error;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    _load();
    RealtimeHub.instance.addListener(_maybeReload);
  }

  void _maybeReload() {
    // يُعاد التحميل عند تحديث المزامنة (آخر مزامنة تغيّرت)
    if (!mounted) return;
    final t = RealtimeHub.instance.lastSyncAt?.millisecondsSinceEpoch ?? 0;
    if (t != _tick) {
      _tick = t;
      _load();
    }
  }

  @override
  void dispose() {
    RealtimeHub.instance.removeListener(_maybeReload);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final links = await supa
          .from('rassas_supervisor_links')
          .select()
          .isFilter('effective_to', null);
      final dir = await supa.from('directory').select();
      if (!mounted) return;
      setState(() {
        _links = links.map((e) => Map<String, dynamic>.from(e)).toList();
        _names = {for (final d in dir) d['id'] as String: d['display_name'] as String};
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e);
      });
    }
  }

  String _n(Object? id) => _names[id] ?? 'غير متاح';

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('الربط', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
          else if (_error != null)
            Text(_error!, style: TextStyle(color: Colors.red.shade700))
          else if (auth.isRassas) ...[
            Text('المشرف الحالي: ${auth.currentSupervisorName ?? 'غير محدد'}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => auth.requestSupervisorChange(),
              icon: const Icon(Icons.swap_horiz),
              label: const Text('تغيير المشرف'),
            ),
          ] else if (auth.isSupervisor) ...[
            const Text('الرصيصون المرتبطون بك حاليًا (للعرض فقط):'),
            const SizedBox(height: 6),
            if (_links.isEmpty) const Text('لا يوجد'),
            for (final l in _links)
              ListTile(dense: true, leading: const Icon(Icons.construction_outlined), title: Text(_n(l['rassas_id']))),
          ] else ...[
            const Text('الروابط الحالية:'),
            const SizedBox(height: 6),
            if (_links.isEmpty) const Text('لا توجد روابط'),
            for (final l in _links)
              ListTile(
                dense: true,
                leading: const Icon(Icons.link),
                title: Text('${_n(l['rassas_id'])}  ←  ${_n(l['supervisor_id'])}'),
                trailing: TextButton(
                  onPressed: () => _adminChange(l['rassas_id'] as String),
                  child: const Text('تغيير'),
                ),
              ),
          ],
        ]),
      ),
    );
  }

  Future<void> _adminChange(String rassasId) async {
    final dir = await supa.from('directory').select().eq('role', 'supervisor').order('display_name');
    if (!mounted) return;
    final list = dir.map((e) => DirectoryUser.fromMap(Map<String, dynamic>.from(e))).toList();
    final chosen = await showDialog<DirectoryUser>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('مشرف جديد لـ ${_n(rassasId)}'),
        children: [for (final u in list) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, u), child: Text(u.displayName))],
      ),
    );
    if (chosen == null || !mounted) return;
    try {
      await supa.rpc('change_supervisor', params: {'p_supervisor': chosen.id, 'p_rassas': rassasId});
      await _load();
    } on PostgrestException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }
}
