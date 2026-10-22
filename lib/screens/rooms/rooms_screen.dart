import 'package:flutter/material.dart';
import '../../auth/auth_controller.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../models/room.dart';
import '../../providers/rooms_provider.dart';
import '../../services/html_print_service.dart';
import '../../utils/date_formatter.dart';
import '../../utils/platform_utils.dart';
import '../../widgets/app_data_grid.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/print_template_dialog.dart';
import 'add_edit_room_dialog.dart';

class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key});

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RoomsProvider>().loadRooms();
    });
  }

  Future<void> _handleAdd() async {
    final ok = await showAddEditRoomDialog(context);
    if (ok == true && mounted) {
      showSuccessSnackBar(context, 'تمت إضافة الغرفة بنجاح.');
    }
  }

  Future<void> _handleEdit(Room room) async {
    final ok = await showAddEditRoomDialog(context, room: room);
    if (ok == true && mounted) {
      showSuccessSnackBar(context, 'تم تعديل بيانات الغرفة بنجاح.');
    }
  }

  Future<void> _handleDelete(Room room) async {
    final provider = context.read<RoomsProvider>();
    final confirmed = await confirmDelete(
      context,
      title: 'حذف الغرفة',
      message:
          'هل أنت متأكد من حذف "${room.name}"؟ لن يؤثر هذا على السجلات التاريخية المحفوظة سابقًا.',
    );
    if (!confirmed) return;
    final error = await provider.deleteRoom(room.id);
    if (!mounted) return;
    if (error != null) {
      showErrorSnackBar(context, error);
    } else {
      showSuccessSnackBar(context, 'تم حذف الغرفة.');
    }
  }

  /// طباعة جدول الغرف (نسخة سطح المكتب/الويب فقط) بنفس أسلوب طباعة السجل:
  /// قوالب جاهزة أو مخصصة ← معاينة ← فتح HTML للطباعة.
  Future<void> _printRooms(RoomsProvider provider) async {
    final rooms = provider.rooms;
    if (rooms.isEmpty) {
      showErrorSnackBar(context, 'لا توجد غرف لطباعتها.');
      return;
    }
    final query = provider.query.trim();
    await runHtmlPrintFlow<Room>(
      context,
      spec: HtmlPrintService.roomsSpec,
      rows: rooms,
      subtitle: query.isEmpty ? null : 'نتائج البحث: $query',
      fileNamePrefix: 'سجل-الغرف-${AppDateFormatter.date(DateTime.now()).replaceAll('/', '-')}',
    );
  }

  static const List<AppGridColumn> _columns = [
    AppGridColumn('م', width: 56, numeric: true),
    AppGridColumn('الغرفة', width: 240),
    AppGridColumn('قطع الخشب', width: 110, numeric: true),
    AppGridColumn('قطع القواطيع (عددها)',
        width: 175, numeric: true, singleLine: true),
    AppGridColumn('قطع الزجاج', width: 110, numeric: true),
    AppGridColumn('قطع الرخام', width: 110, numeric: true),
    AppGridColumn('عدد القطع الكلي', width: 130, numeric: true),
    AppGridColumn('عدد ورق الطباعة', width: 140, numeric: true),
    AppGridColumn('تعديل', width: 120),
  ];

  @override
  Widget build(BuildContext context) {
    final canManage = context.watch<AuthController>().canManageRooms;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Consumer<RoomsProvider>(
                  builder: (context, provider, _) => AppSearchField(
                    label: isMobileApp ? 'البحث' : 'البحث في الغرف',
                    hint: isMobileApp ? 'الغرفة' : 'اكتب اسم الغرفة...',
                    onChanged: provider.search,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // زر الطباعة لا يظهر في تطبيق أندرويد (مثل جدول السجل).
              if (!isAndroidApp) ...[
                Consumer<RoomsProvider>(
                  builder: (context, provider, _) => OutlinedButton.icon(
                    onPressed: () => _printRooms(provider),
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('طباعة الغرف'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              if (canManage)
              ElevatedButton.icon(
                onPressed: _handleAdd,
                icon: const Icon(Icons.add),
                label: const Text('إضافة غرفة'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: Consumer<RoomsProvider>(
              builder: (context, provider, _) {
                if (provider.status == LoadStatus.loading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (provider.status == LoadStatus.error) {
                  return EmptyState(
                    icon: Icons.error_outline,
                    title: 'حدث خطأ',
                    subtitle: provider.errorMessage,
                  );
                }
                final rooms = provider.rooms;
                if (rooms.isEmpty) {
                  return EmptyState(
                    icon: Icons.meeting_room_outlined,
                    title: provider.query.isEmpty
                        ? 'لا توجد غرف مسجّلة بعد'
                        : 'لا توجد نتائج مطابقة',
                    subtitle: provider.query.isEmpty
                        ? 'ابدأ بإضافة أول غرفة من زر "إضافة غرفة".'
                        : null,
                  );
                }
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: AppDataGrid(
                    columns: _columns,
                    rowCount: rooms.length,
                    rowBuilder: (i) {
                      final room = rooms[i];
                      return AppGridRow(cells: [
                        gridText('${i + 1}'),
                        gridText(room.name, bold: true),
                        gridText('${room.pieceCount}'),
                        gridText(room.partitionDisplay),
                        gridText('${room.glassPieceCount}'),
                        gridText('${room.marblePieceCount}'),
                        gridText('${room.totalPieceCount}', bold: true),
                        gridText('${room.printPaperCount}', bold: true),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (canManage) IconButton(
                              tooltip: 'تعديل',
                              icon: const Icon(Icons.edit, color: AppColors.primary),
                              onPressed: () => _handleEdit(room),
                            ),
                            if (canManage) IconButton(
                              tooltip: 'حذف',
                              icon: Icon(Icons.delete_outline, color: Colors.red.shade600),
                              onPressed: () => _handleDelete(room),
                            ),
                          ],
                        ),
                      ]);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
