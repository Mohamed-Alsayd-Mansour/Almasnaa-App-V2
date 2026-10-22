import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../models/daily_entry.dart';
import '../../providers/daily_provider.dart';
import '../../providers/rooms_provider.dart' show LoadStatus;
import '../../utils/platform_utils.dart';
import '../../services/html_print_service.dart';
import '../../utils/date_formatter.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/app_data_grid.dart';
import '../../widgets/deficiency_cell.dart';
import '../../widgets/problem_cell.dart';
import '../../widgets/print_template_dialog.dart';
import '../../widgets/status_badge.dart';
import 'add_entry_dialog.dart';
import 'edit_entry_dialog.dart';

class DailyScreen extends StatefulWidget {
  const DailyScreen({super.key});

  @override
  State<DailyScreen> createState() => _DailyScreenState();
}

class _DailyScreenState extends State<DailyScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DailyProvider>().load();
    });
  }

  Future<void> _startSession() async {
    final error = await context.read<DailyProvider>().startSession();
    if (!mounted) return;
    if (error != null) {
      showErrorSnackBar(context, error);
    } else {
      showSuccessSnackBar(context, 'تم بدء يومية جديدة.');
    }
  }

  Future<void> _addEntry() async {
    final ok = await showAddEntryDialog(context);
    if (ok == true && mounted) {
      showSuccessSnackBar(context, 'تمت إضافة الغرفة إلى اليومية.');
    }
  }

  Future<void> _editEntry(DailyEntry entry) async {
    final ok = await showEditEntryDialog(context, entry);
    if (ok == true && mounted) {
      showSuccessSnackBar(context, 'تم تعديل بيانات الغرفة.');
    }
  }

  Future<void> _deleteEntry(DailyEntry entry) async {
    final confirmed = await confirmDelete(
      context,
      title: 'حذف من اليومية',
      message: 'هل تريد حذف "${entry.displayName}" من اليومية الحالية؟',
    );
    if (!confirmed) return;
    final error = await context.read<DailyProvider>().deleteEntry(entry.id);
    if (!mounted) return;
    if (error != null) {
      showErrorSnackBar(context, error);
    } else {
      showSuccessSnackBar(context, 'تم الحذف.');
    }
  }

  Future<void> _printSession() async {
    final provider = context.read<DailyProvider>();
    final session = provider.activeSession;
    if (session == null) return;
    if (provider.entries.isEmpty) {
      showErrorSnackBar(context, 'لا توجد غرف في اليومية لطباعتها.');
      return;
    }

    final rows = provider.entries
        .map((e) => HtmlPrintRow(
              entry: e,
              dayName: session.dayName,
              date: session.date,
              sessionStatus: session.status,
            ))
        .toList();

    await runHtmlPrintFlow<HtmlPrintRow>(
      context,
      spec: HtmlPrintService.entriesSpec,
      rows: rows,
      subtitle: 'يومية ${session.dayName} - ${AppDateFormatter.date(session.date)}',
      fileNamePrefix:
          'يومية-${AppDateFormatter.date(session.date).replaceAll('/', '-')}',
    );
  }

  Future<void> _finishSession() async {
    final provider = context.read<DailyProvider>();
    final confirmed = await confirmDelete(
      context,
      title: 'إنهاء اليومية',
      message:
          'سيتم إغلاق اليومية الحالية وإضافتها إلى السجل. هل تريد المتابعة؟',
    );
    if (!confirmed) return;
    final error = await provider.finishSession();
    if (!mounted) return;
    if (error != null) {
      showErrorSnackBar(context, error);
    } else {
      showSuccessSnackBar(context, 'تم إنهاء اليومية وإضافتها إلى السجل.');
    }
  }

  static const List<AppGridColumn> _columns = [
    AppGridColumn('م', width: 56, numeric: true),
    AppGridColumn('الغرفة (القطع)', width: 260),
    AppGridColumn('الترقيم', width: 90),
    AppGridColumn('النجار', width: 120),
    AppGridColumn('الخدمة', width: 120),
    AppGridColumn('الرصيص', width: 120),
    AppGridColumn('المشرف', width: 120),
    AppGridColumn('الرميم', width: 120),
    AppGridColumn('التاجر', width: 120),
    AppGridColumn('اسم الزبون', width: 120),
    AppGridColumn('مكان اللف', width: 120),
    AppGridColumn('المواصفات', width: 180),
    AppGridColumn('وصف الأوردر', width: 180),
    AppGridColumn('النواقص', width: 220),
    AppGridColumn('المشكلة', width: 200),
    AppGridColumn('عدد الناقص', width: 100, numeric: true),
    AppGridColumn('إجراءات', width: 120),
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<DailyProvider>(
      builder: (context, provider, _) {
        if (provider.status == LoadStatus.loading ||
            provider.status == LoadStatus.initial) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!provider.hasActiveSession) {
          return EmptyState(
            icon: Icons.assignment_late_outlined,
            title: 'لا توجد يومية نشطة',
            subtitle: 'اضغط على الزر أدناه لبدء يومية عمل جديدة.',
            action: ElevatedButton.icon(
              onPressed: _startSession,
              icon: const Icon(Icons.play_arrow),
              label: const Text('بدء يومية'),
            ),
          );
        }

        final session = provider.activeSession!;
        final entries = provider.entries;

        return Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SessionHeader(
                dayName: session.dayName,
                date: AppDateFormatter.date(session.date),
                startTime: AppDateFormatter.time(session.startTime),
                endTime: AppDateFormatter.endTimeOrPending(session.endTime),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Text('غرف اليومية (${entries.length})',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  // أزرار الطباعة والتصدير لا تظهر في تطبيق أندرويد.
                  if (!isAndroidApp) ...[
                    OutlinedButton.icon(
                      onPressed: _printSession,
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('طباعة اليومية'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  ElevatedButton.icon(
                    onPressed: _addEntry,
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة غرفة'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: entries.isEmpty
                    ? const EmptyState(
                        icon: Icons.inbox_outlined,
                        title: 'لم تتم إضافة أي غرفة بعد',
                        subtitle: 'استخدم زر "إضافة غرفة" لتسجيل أول غرفة اليوم.',
                      )
                    : Card(
                        clipBehavior: Clip.antiAlias,
                        child: AppDataGrid(
                          columns: _columns,
                          rowCount: entries.length,
                          rowBuilder: (i) {
                            final e = entries[i];
                            return AppGridRow(
                              color: rowColorForStatus(e.status),
                              cells: [
                                gridText('${i + 1}'),
                                gridText(e.displayName, bold: true),
                                gridText(e.numbering),
                                gridText(e.carpenter),
                                gridText(e.service),
                                gridText(e.installer),
                                gridText(e.supervisor),
                                gridText(e.repairer),
                                gridText(e.merchantName),
                                gridText(e.customerName),
                                gridOneLine(e.wrapLocation),
                                e.hasSpecifications
                                    ? ProblemCell(
                                        text: e.specificationsText,
                                        editable: true,
                                        title: 'المواصفات',
                                        emptyLabel: 'إضافة مواصفات',
                                        hint:
                                            'اكتب المواصفات والتعديلات الشكلية...',
                                        onSave: (newText) => context
                                            .read<DailyProvider>()
                                            .updateEntrySpecifications(
                                              entryId: e.id,
                                              newText: newText,
                                            ),
                                      )
                                    : gridText(''),
                                e.isOrder
                                    ? ProblemCell(
                                        text: e.orderDescription,
                                        editable: true,
                                        title: 'وصف الأوردر',
                                        emptyLabel: 'إضافة وصف',
                                        hint: 'اكتب وصف الأوردر...',
                                        onSave: (newText) => context
                                            .read<DailyProvider>()
                                            .updateEntryOrderDescription(
                                              entryId: e.id,
                                              newText: newText,
                                            ),
                                      )
                                    : gridText(''),
                                DeficiencyCell(
                                  text: e.currentDeficiencies,
                                  missingCount: e.currentMissingPiecesCount,
                                  editable: true,
                                  onSave: (newText) => context
                                      .read<DailyProvider>()
                                      .updateEntryDeficiencies(
                                        entryId: e.id,
                                        newText: newText,
                                      ),
                                ),
                                ProblemCell(
                                  text: e.problem,
                                  editable: true,
                                  onSave: (newText) => context
                                      .read<DailyProvider>()
                                      .updateEntryProblem(
                                        entryId: e.id,
                                        newText: newText,
                                      ),
                                ),
                                gridText('${e.currentMissingPiecesCount}'),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'تعديل',
                                      icon: const Icon(Icons.edit, color: AppColors.primary),
                                      onPressed: () => _editEntry(e),
                                    ),
                                    IconButton(
                                      tooltip: 'حذف',
                                      icon: Icon(Icons.delete_outline, color: Colors.red.shade600),
                                      onPressed: () => _deleteEntry(e),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ),
              ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent),
                  onPressed: _finishSession,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('إنهاء اليومية وإضافة للسجل'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SessionHeader extends StatelessWidget {
  final String dayName;
  final String date;
  final String startTime;
  final String endTime;

  const _SessionHeader({
    required this.dayName,
    required this.date,
    required this.startTime,
    required this.endTime,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.primary.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm + 4),
        child: Wrap(
          spacing: 24,
          runSpacing: 8,
          children: [
            _HeaderItem(label: 'اليوم', value: dayName, icon: Icons.today),
            _HeaderItem(label: 'التاريخ', value: date, icon: Icons.calendar_today),
            _HeaderItem(label: 'بدء اليومية', value: startTime, icon: Icons.play_circle_outline),
            _HeaderItem(label: 'انتهاء اليومية', value: endTime, icon: Icons.stop_circle_outlined),
          ],
        ),
      ),
    );
  }
}

class _HeaderItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _HeaderItem({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 6),
        Text('$label: ', style: const TextStyle(color: AppColors.textSecondary)),
        Text(value,
            maxLines: 1,
            softWrap: false,
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }
}
