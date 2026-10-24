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
    final category = provider.category;
    final subtitleParts = [
      if (category != null) 'التصنيف: $category',
      if (query.isNotEmpty) 'نتائج البحث: $query',
    ];
    await runHtmlPrintFlow<Room>(
      context,
      spec: HtmlPrintService.roomsSpec,
      rows: rooms,
      subtitle: subtitleParts.isEmpty ? null : subtitleParts.join(' — '),
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
          const SizedBox(height: AppSpacing.sm),
          const _CategoryFilters(),
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
                    title: provider.query.isEmpty && provider.category == null
                        ? 'لا توجد غرف مسجّلة بعد'
                        : 'لا توجد نتائج مطابقة',
                    subtitle: provider.query.isEmpty && provider.category == null
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

/// أزرار التصنيف السريع: أطفال / سفرة / نوم. على الهاتف تمتد على عرض الصف بالكامل بعرض
/// ومسافات متساوية؛ على الشاشات الأكبر تبقى بحجم معتدل ولا تتمدد.
class _CategoryFilters extends StatelessWidget {
  const _CategoryFilters();

  static const _items = <({String word, Color color})>[
    (word: 'أطفال', color: Color(0xFFD9822B)), // برتقالي دافئ (من لون التمييز)
    (word: 'سفرة', color: Color(0xFF2E7D6B)), // أخضر مزرق
    (word: 'نوم', color: Color(0xFF3F5E9E)), // أزرق نيلي
  ];

  @override
  Widget build(BuildContext context) {
    final selected = context.select<RoomsProvider, String?>((p) => p.category);
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 700;
        final row = Row(
          children: [
            for (var i = 0; i < _items.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _CategoryButton(
                  word: _items[i].word,
                  color: _items[i].color,
                  selected: selected == _items[i].word,
                  onTap: () => context.read<RoomsProvider>().toggleCategory(_items[i].word),
                ),
              ),
            ],
          ],
        );
        if (narrow) return row;
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: row),
        );
      },
    );
  }
}

class _CategoryButton extends StatelessWidget {
  const _CategoryButton({required this.word, required this.color, required this.selected, required this.onTap});

  final String word;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // المحدد: لون أغمق + علامة ✓ + إطار أبيض وظل، حتى يُعرف أنه فعّال دون الاعتماد على اللون وحده.
    final bg = selected ? HSLColor.fromColor(color).withLightness((HSLColor.fromColor(color).lightness - 0.08).clamp(0.0, 1.0)).toColor() : color;
    return Semantics(
      button: true,
      selected: selected,
      label: 'عرض غرف $word',
      child: Material(
        color: bg,
        elevation: selected ? 4 : 0,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: selected ? Border.all(color: Colors.white, width: 2) : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  const Icon(Icons.check, size: 18, color: Colors.white),
                  const SizedBox(width: 4),
                ],
                Text(word, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
