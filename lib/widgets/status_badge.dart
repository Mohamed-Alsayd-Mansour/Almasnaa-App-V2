import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/enums.dart';

class StatusBadge extends StatelessWidget {
  final RoomEntryStatus status;
  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final isCompleted = status == RoomEntryStatus.completed;
    final bg = isCompleted ? AppColors.completedBg : AppColors.pendingBg;
    final fg = isCompleted ? AppColors.completedText : AppColors.pendingText;
    final icon = isCompleted ? Icons.check_circle : Icons.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// يُرجع لون خلفية الصف الكامل حسب الحالة (أخضر/أحمر شفاف) كما تنص
/// المواصفات، بحيث يبقى النص واضحًا فوقه.
Color rowColorForStatus(RoomEntryStatus status) {
  return status == RoomEntryStatus.completed
      ? AppColors.completedBg
      : AppColors.pendingBg;
}
