import 'package:flutter/material.dart';

import '../services/realtime_hub.dart';
import '../utils/date_formatter.dart';

/// مؤشر حالة المزامنة في شريط التطبيق: متصل / جارٍ الاتصال / غير متصل + آخر مزامنة.
class SyncIndicator extends StatelessWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: RealtimeHub.instance,
      builder: (context, _) {
        final hub = RealtimeHub.instance;
        final (IconData icon, Color color, String label) = switch (hub.state) {
          SyncState.online => (Icons.cloud_done_outlined, Colors.green.shade600, 'متصل'),
          SyncState.connecting => (Icons.cloud_sync_outlined, Colors.orange.shade700, 'جارٍ الاتصال'),
          SyncState.offline => (Icons.cloud_off_outlined, Colors.red.shade600, 'غير متصل'),
        };
        final last = hub.lastSyncAt == null
            ? 'لم تتم مزامنة بعد'
            : 'آخر مزامنة: ${AppDateFormatter.time(hub.lastSyncAt!)}';
        return Tooltip(
          message: '$label\n$last${hub.lastError != null ? '\n${hub.lastError}' : ''}',
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: color),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
            ]),
          ),
        );
      },
    );
  }
}
