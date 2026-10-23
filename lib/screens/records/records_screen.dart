import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/auth_controller.dart';
import '../../core/app_theme.dart';
import '../../providers/records_provider.dart';
import '../../providers/rooms_provider.dart' show LoadStatus;
import '../../repositories/daily_entry_repository.dart' show RecordSearchFilters;
import '../../utils/platform_utils.dart';
import '../../services/html_print_service.dart';
import '../../utils/date_formatter.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/deficiency_cell.dart';
import '../../widgets/print_template_dialog.dart';
import '../../widgets/app_data_grid.dart';
import '../../widgets/problem_cell.dart';
import '../../providers/daily_provider.dart';
import '../../models/daily_entry.dart';
import 'full_edit_dialog.dart';
import '../../widgets/status_badge.dart';
import 'advanced_filters_sheet.dart';

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  final _keywordCtrl = TextEditingController();

  /// بعد إدخال كلمة المرور يبقى التعديل الشامل مفتوحًا حتى يُقفل يدويًا.

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RecordsProvider>().load();
    });
  }

  @override
  void dispose() {
    _keywordCtrl.dispose();
    super.dispose();
  }

  Future<void> _openFilters() async {
    final provider = context.read<RecordsProvider>();
    final result = await showAdvancedFiltersSheet(context, provider.filters);
    if (result == null) return;
    await provider.applyFilters(RecordSearchFilters(
      keyword: _keywordCtrl.text,
      dateFrom: result.dateFrom,
      dateTo: result.dateTo,
      roomName: result.roomName,
      carpenter: result.carpenter,
      installer: result.installer,
      supervisor: result.supervisor,
      wrapLocation: result.wrapLocation,
      status: result.status,
      shape: result.shape,
      ownership: result.ownership,
    ));
  }

  Future<void> _clearAll() async {
    _keywordCtrl.clear();
    await context.read<RecordsProvider>().clearFilters();
  }

  Future<void> _printRecords(RecordsProvider provider) async {
    if (provider.results.isEmpty) {
      showErrorSnackBar(context, 'لا توجد سجلات لطباعتها.');
      return;
    }

    final isFiltered = !provider.filters.isEmpty;
    final rows = provider.results
        .map((r) => HtmlPrintRow(
              entry: r.entry,
              dayName: r.dayName,
              date: r.date,
              sessionStatus: r.sessionStatus,
            ))
        .toList();

    await runHtmlPrintFlow<HtmlPrintRow>(
      context,
      spec: HtmlPrintService.entriesSpec,
      rows: rows,
      subtitle: isFiltered ? 'بعد تطبيق الفلاتر' : null,
      fileNamePrefix:
          'سجل-الغرف-${AppDateFormatter.date(DateTime.now()).replaceAll('/', '-')}',
    );
  }

  /// التعديل الشامل: للمشرف والأدمن فقط (الخادم يرفضه للرصيص أيضًا).
  Future<void> _fullEdit(DailyEntry entry) async {
    if (!context.read<AuthController>().canFullEditRecords) return;
    final updated = await showFullEditDialog(context, entry);
    if (updated == null || !mounted) return;
    final error = await context.read<RecordsProvider>().replaceEntry(updated);
    if (!mounted) return;
    if (error != null) {
      showErrorSnackBar(context, error);
      return;
    }
    // اليومية النشطة قد تحتوي نفس السجل، فنحدّثها.
    context.read<DailyProvider>().load(silent: true);
    showSuccessSnackBar(context, 'تم حفظ التعديلات على السجل.');
  }

  static const List<AppGridColumn> _columns = [
    AppGridColumn('م', width: 56, numeric: true),
    AppGridColumn('اليوم', width: 90),
    AppGridColumn('التاريخ', width: 125),
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
    AppGridColumn('الحالة', width: 150),
    AppGridColumn('تعديل', width: 80),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: AppSearchField(
                  controller: _keywordCtrl,
                  label: 'بحث شامل في السجل',
                  hint: isMobileApp
                      ? 'ابحث بأي كلمة'
                      : 'ابحث بأي كلمة: اسم، غرفة، ترقيم، نواقص...',
                  onChanged: (v) =>
                      context.read<RecordsProvider>().searchWithKeyword(v),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton.filled(
                tooltip: 'بحث متقدم',
                onPressed: _openFilters,
                icon: const Icon(Icons.tune),
              ),
              IconButton(
                tooltip: 'مسح الفلاتر',
                onPressed: _clearAll,
                icon: const Icon(Icons.filter_alt_off_outlined),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (!isAndroidApp)
          Consumer<RecordsProvider>(
            builder: (context, provider, _) {
              return Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _printRecords(provider),
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('طباعة السجل'),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Consumer<RecordsProvider>(
            builder: (context, provider, _) {
              if (provider.filters.isEmpty) return const SizedBox.shrink();
              return Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 6,
                  children: [
                    if (provider.filters.dateFrom != null)
                      Chip(label: Text('من ${AppDateFormatter.date(provider.filters.dateFrom!)}')),
                    if (provider.filters.dateTo != null)
                      Chip(label: Text('إلى ${AppDateFormatter.date(provider.filters.dateTo!)}')),
                    if ((provider.filters.roomName ?? '').isNotEmpty)
                      Chip(label: Text('الغرفة: ${provider.filters.roomName}')),
                    if ((provider.filters.carpenter ?? '').isNotEmpty)
                      Chip(label: Text('النجار: ${provider.filters.carpenter}')),
                    if ((provider.filters.installer ?? '').isNotEmpty)
                      Chip(label: Text('الرصيص: ${provider.filters.installer}')),
                    if ((provider.filters.supervisor ?? '').isNotEmpty)
                      Chip(label: Text('المشرف: ${provider.filters.supervisor}')),
                    if ((provider.filters.wrapLocation ?? '').isNotEmpty)
                      Chip(label: Text('مكان اللف: ${provider.filters.wrapLocation}')),
                    if (provider.filters.status != null)
                      Chip(label: Text('الحالة: ${provider.filters.status!.label}')),
                    if (provider.filters.shape != null)
                      Chip(label: Text('الشكل: ${provider.filters.shape!.label}')),
                    if (provider.filters.ownership != null)
                      Chip(label: Text('الملكية: ${provider.filters.ownership!.label}')),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: Consumer<RecordsProvider>(
              builder: (context, provider, _) {
                if (provider.status == LoadStatus.loading &&
                    provider.results.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (provider.status == LoadStatus.error) {
                  return EmptyState(
                    icon: Icons.error_outline,
                    title: 'حدث خطأ',
                    subtitle: provider.errorMessage,
                  );
                }
                if (provider.results.isEmpty) {
                  return const EmptyState(
                    icon: Icons.history_toggle_off,
                    title: 'لا توجد سجلات مطابقة',
                    subtitle: 'جرّب تعديل كلمة البحث أو الفلاتر المطبّقة.',
                  );
                }

                final rows = provider.results;
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: AppDataGrid(
                    columns: _columns,
                    rowHeight: isMobileApp ? 72 : 60,
                    cellVerticalPadding: isMobileApp ? 6 : 0,
                    rowCount: rows.length,
                    rowBuilder: (i) {
                      final r = rows[i];
                      final e = r.entry;
                      return AppGridRow(
                        color: rowColorForStatus(e.status),
                        cells: [
                          gridText('${i + 1}'),
                          gridText(r.dayName),
                          gridOneLine(AppDateFormatter.date(r.date)),
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
                                  hint: 'اكتب المواصفات والتعديلات الشكلية...',
                                  onSave: (newText) => context
                                      .read<RecordsProvider>()
                                      .updateSpecifications(
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
                                      .read<RecordsProvider>()
                                      .updateOrderDescription(
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
                                .read<RecordsProvider>()
                                .updateDeficiencies(
                                  entryId: e.id,
                                  newText: newText,
                                ),
                          ),
                          ProblemCell(
                            text: e.problem,
                            editable: true,
                            onSave: (newText) => context
                                .read<RecordsProvider>()
                                .updateProblem(
                                  entryId: e.id,
                                  newText: newText,
                                ),
                          ),
                          gridText('${e.currentMissingPiecesCount}'),
                          StatusBadge(status: e.status),
                          context.read<AuthController>().canFullEditRecords
                              ? IconButton(
                                  tooltip: 'تعديل شامل',
                                  icon: const Icon(Icons.edit, color: AppColors.primary),
                                  onPressed: () => _fullEdit(e),
                                )
                              : const SizedBox.shrink(),
                        ],
                      );
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
