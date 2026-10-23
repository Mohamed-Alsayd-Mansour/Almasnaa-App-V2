import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/notifications_provider.dart';
import '../utils/date_formatter.dart';

/// جرس الإشعارات في شريط التطبيق مع عدّاد غير المقروء.
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

class _NotificationsSheet extends StatelessWidget {
  const _NotificationsSheet();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<NotificationsProvider>();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(children: [
              const Expanded(
                child: Text('الإشعارات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
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
            child: p.items.isEmpty
                ? const Center(child: Text('لا توجد إشعارات'))
                : ListView.separated(
                    itemCount: p.items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final n = p.items[i];
                      return ListTile(
                        tileColor: n.isRead ? null : Colors.amber.withValues(alpha: 0.12),
                        leading: Icon(n.isRead ? Icons.notifications_none : Icons.notifications_active_outlined),
                        title: Text(n.title, style: TextStyle(fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w800)),
                        subtitle: Text([
                          if (n.detail.isNotEmpty) n.detail,
                          AppDateFormatter.dateTime(n.createdAt),
                        ].join('\n')),
                        isThreeLine: n.detail.isNotEmpty,
                        onTap: () => p.markRead(n),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}
