import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../providers/notifications_provider.dart';
import '../services/app_navigator.dart';
import '../utils/date_formatter.dart';
import 'common_widgets.dart';

/// جرس الإشعارات في شريط التطبيق مع عدّاد غير المقروء (في الوارد فقط).
class NotificationsButton extends StatelessWidget {
  const NotificationsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<NotificationsProvider>();
    return IconButton(
      tooltip: 'الإشعارات',
      icon: Badge(
        isLabelVisible: p.unread > 0,
        label: Text('${p.unread > 99 ? '99+' : p.unread}'),
        child: const Icon(Icons.notifications_outlined),
      ),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const _NotificationsSheet(),
      ),
    );
  }
}

class _NotificationsSheet extends StatefulWidget {
  const _NotificationsSheet();

  @override
  State<_NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<_NotificationsSheet> {
  NotifView _view = NotifView.inbox;

  String get _title => switch (_view) {
        NotifView.inbox => 'الإشعارات',
        NotifView.archive => 'الأرشيف',
        NotifView.trash => 'سلة المحذوفات',
      };

  String get _emptyText => switch (_view) {
        NotifView.inbox => 'لا توجد إشعارات',
        NotifView.archive => 'لا توجد إشعارات مؤرشفة',
        NotifView.trash => 'سلة المحذوفات فارغة',
      };

  void _toast(String m) => showSuccessSnackBar(context, m);

  /// حذف الكل: يطبَّق على الإشعارات المعروضة في القسم الحالي، بعد تأكيد.
  Future<void> _deleteAll(NotificationsProvider p) async {
    final list = p.inView(_view);
    if (list.isEmpty) return;
    final ok = await confirmDelete(
      context,
      title: 'حذف الكل',
      message: 'سيتم نقل ${list.length} إشعار إلى سلة المحذوفات، ويمكنك استعادتها منها لاحقًا.',
      confirmLabel: 'نقل إلى السلة',
    );
    if (!ok || !mounted) return;
    await p.moveToTrash(list);
    if (mounted) _toast('تم نقل ${list.length} إشعار إلى سلة المحذوفات.');
  }

  Future<void> _foreverOne(NotificationsProvider p, AppNotification n) async {
    final ok = await confirmDelete(
      context,
      title: 'الحذف النهائي',
      message: 'سيتم حذف هذا الإشعار نهائيًا ولا يمكن استرجاعه.',
      confirmLabel: 'حذف نهائي',
    );
    if (!ok || !mounted) return;
    await p.deleteForever([n]);
  }

  Future<void> _foreverAll(NotificationsProvider p) async {
    final list = p.inView(NotifView.trash);
    if (list.isEmpty) return;
    final ok = await confirmDelete(
      context,
      title: 'الحذف النهائي',
      message: 'سيتم حذف ${list.length} إشعار نهائيًا من سلة المحذوفات ولا يمكن استرجاعها.',
      confirmLabel: 'حذف نهائي',
    );
    if (!ok || !mounted) return;
    await p.deleteForever(list);
    if (mounted) _toast('تم الحذف النهائي.');
  }

  List<Widget> _itemActions(NotificationsProvider p, AppNotification n) => switch (_view) {
        NotifView.inbox => [
            _MiniAction(icon: Icons.archive_outlined, label: 'أرشفة', onTap: () => p.archive([n])),
            _MiniAction(icon: Icons.delete_outline, label: 'حذف', color: Colors.red.shade600, onTap: () => p.moveToTrash([n])),
          ],
        NotifView.archive => [
            _MiniAction(icon: Icons.unarchive_outlined, label: 'إلغاء الأرشفة', onTap: () => p.unarchive([n])),
            _MiniAction(icon: Icons.delete_outline, label: 'حذف', color: Colors.red.shade600, onTap: () => p.moveToTrash([n])),
          ],
        NotifView.trash => [
            _MiniAction(icon: Icons.restore_from_trash_outlined, label: 'استعادة', onTap: () => p.restore([n])),
            _MiniAction(
                icon: Icons.delete_forever_outlined,
                label: 'حذف نهائي',
                color: Colors.red.shade700,
                onTap: () => _foreverOne(p, n)),
          ],
      };

  Widget _bottomBar(NotificationsProvider p) {
    final inboxCount = p.inView(NotifView.inbox).length;
    final archCount = p.inView(NotifView.archive).length;
    final trashCount = p.inView(NotifView.trash).length;
    final cur = p.inView(_view).length;

    Widget btn(String label, IconData icon, VoidCallback? onTap, {Color? color}) => Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: color,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              side: color == null ? null : BorderSide(color: color),
            ),
            onPressed: onTap,
            icon: Icon(icon, size: 18),
            label: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
          ),
        );
    const gap = SizedBox(width: AppSpacing.sm);

    final children = switch (_view) {
      NotifView.inbox => [
          btn('حذف الكل', Icons.delete_sweep_outlined, cur == 0 ? null : () => _deleteAll(p), color: Colors.red.shade700),
          gap,
          btn('الأرشيف ($archCount)', Icons.inventory_2_outlined, () => setState(() => _view = NotifView.archive)),
          gap,
          btn('سلة المحذوفات ($trashCount)', Icons.delete_outline, () => setState(() => _view = NotifView.trash)),
        ],
      NotifView.archive => [
          btn('حذف الكل', Icons.delete_sweep_outlined, cur == 0 ? null : () => _deleteAll(p), color: Colors.red.shade700),
          gap,
          btn('الوارد ($inboxCount)', Icons.inbox_outlined, () => setState(() => _view = NotifView.inbox)),
          gap,
          btn('سلة المحذوفات ($trashCount)', Icons.delete_outline, () => setState(() => _view = NotifView.trash)),
        ],
      NotifView.trash => [
          btn('استعادة الكل', Icons.restore_from_trash_outlined, cur == 0 ? null : () async {
            await p.restore(p.inView(NotifView.trash));
            if (mounted) _toast('تمت استعادة الإشعارات.');
          }),
          gap,
          btn('الوارد ($inboxCount)', Icons.inbox_outlined, () => setState(() => _view = NotifView.inbox)),
          gap,
          btn('الحذف النهائي', Icons.delete_forever_outlined, cur == 0 ? null : () => _foreverAll(p), color: Colors.red.shade700),
        ],
    };
    return Padding(padding: const EdgeInsets.fromLTRB(8, 8, 8, 4), child: Row(children: children));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<NotificationsProvider>();
    final list = p.inView(_view);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(children: [
              Expanded(
                child: Text('$_title${list.isEmpty ? '' : ' (${list.length})'}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              if (_view == NotifView.inbox)
                TextButton(
                  onPressed: p.unread == 0 ? null : () => p.markAllRead(),
                  child: const Text('تحديد الكل كمقروء'),
                ),
            ]),
          ),
          if (p.errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(p.errorMessage!, style: TextStyle(color: Colors.red.shade700)),
            ),
          const Divider(height: 1),
          Expanded(
            child: list.isEmpty
                ? Center(child: Text(_emptyText))
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final n = list[i];
                      final canOpen = n.canOpen && !n.inTrash;
                      return ListTile(
                        tileColor: n.inInbox && !n.isRead ? Colors.amber.withValues(alpha: 0.12) : null,
                        leading: Icon(n.isRead || !n.inInbox ? Icons.notifications_none : Icons.notifications_active_outlined),
                        title: Text(n.title, style: TextStyle(fontWeight: n.isRead || !n.inInbox ? FontWeight.w500 : FontWeight.w800)),
                        subtitle: Text([
                          if (n.detail.isNotEmpty) n.detail,
                          AppDateFormatter.dateTime(n.createdAt),
                        ].join('\n')),
                        isThreeLine: n.detail.contains('\n') || n.detail.length > 40,
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: _itemActions(p, n)),
                        onTap: () {
                          if (n.inInbox) p.markRead(n);
                          if (!canOpen) return;
                          Navigator.of(context).pop(); // أغلق الورقة ثم انتقل
                          AppNavigator.instance.request(n.isMention
                              ? NavRequest.chat(n.conversationId!, message: n.messageId)
                              : NavRequest.record(n.entityId!));
                        },
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          _bottomBar(p),
        ]),
      ),
    );
  }
}

/// زر صغير بجانب الإشعار: أيقونة + نص قصير.
class _MiniAction extends StatelessWidget {
  const _MiniAction({required this.icon, required this.label, required this.onTap, this.color});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 20, color: c),
            Text(label, style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}
