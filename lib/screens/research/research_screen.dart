import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../models/enums.dart';
import '../../models/person.dart';
import '../../services/html_print_service.dart';
import '../../services/research_service.dart';
import '../../utils/date_formatter.dart';
import '../../utils/platform_utils.dart';
import '../../widgets/app_data_grid.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/print_template_dialog.dart';

/// التبويب الخامس: بحوث واستعلامات تفصيلية عن كل البيانات المحفوظة في
/// ملف JSON (الغرف، اليوميات، السجلات، الأسماء) مع ترتيب بالضغط على
/// العناوين وطباعة مخصصة بنفس منطق طباعة البرنامج.
class ResearchScreen extends StatefulWidget {
  const ResearchScreen({super.key});

  @override
  State<ResearchScreen> createState() => _ResearchScreenState();
}

class _ResearchScreenState extends State<ResearchScreen> {
  ResearchData? _data;
  String? _error;
  bool _loading = true;

  ResearchView _view = ResearchView.overview;
  ResearchGroup _group = ResearchGroup.room;
  ResearchFilters _filters = const ResearchFilters();

  ResearchTable? _table;
  List<ResearchRow> _rows = [];
  String? _sortKey;
  bool _sortAsc = true;

  final _keywordCtrl = TextEditingController();
  bool _showAdvanced = false;

  /// أعمدة التواريخ والأوقات: تُعرض على سطر واحد.
  static const _oneLineKeys = {
    'date', 'first', 'last', 'added', 'created', 'def_updated', 'start', 'end', 'wrap',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _keywordCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _data = await ResearchData.load();
      _recompute(resetSort: false);
    } catch (e) {
      _error = 'تعذر تحميل البيانات: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _recompute({bool resetSort = true}) {
    final data = _data;
    if (data == null) return;
    final table =
        ResearchService.build(_view, data, _filters, group: _group);
    if (resetSort) _sortKey = null;
    _table = table;
    _rows = _sorted(table.rows);
  }

  List<ResearchRow> _sorted(List<ResearchRow> rows) {
    final key = _sortKey;
    if (key == null) return rows;
    final copy = [...rows];
    copy.sort((a, b) {
      final na = a.sort[key];
      final nb = b.sort[key];
      final int c = (na != null && nb != null)
          ? na.compareTo(nb)
          : a.value(key).compareTo(b.value(key));
      return _sortAsc ? c : -c;
    });
    return copy;
  }

  void _onSort(int columnIndex) {
    final table = _table;
    if (table == null) return;
    final key = table.columns[columnIndex].key;
    setState(() {
      if (_sortKey == key) {
        _sortAsc = !_sortAsc;
      } else {
        _sortKey = key;
        _sortAsc = true;
      }
      _rows = _sorted(table.rows);
    });
  }

  void _update(void Function() change) {
    setState(() {
      change();
      _recompute();
    });
  }

  Future<void> _pickDate({required bool from}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (from ? _filters.dateFrom : _filters.dateTo) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    _update(() {
      _filters = from
          ? _filters.copyWith(dateFrom: picked)
          : _filters.copyWith(dateTo: picked);
    });
  }

  void _clearFilters() {
    _keywordCtrl.clear();
    _update(() => _filters = const ResearchFilters());
  }

  PrintSpec<ResearchRow> _specFor(ResearchTable table) {
    final fields = [
      for (final c in table.columns)
        HtmlPrintField<ResearchRow>(
          key: c.key,
          label: c.label,
          valueOf: (r) => r.value(c.key),
        ),
    ];
    return PrintSpec<ResearchRow>(
      storageKey: 'html_print_templates_research_${table.view.name}_v1',
      fields: fields,
      defaultCustomBaseTemplateId: 'full',
      builtInTemplates: {
        'full': HtmlPrintTemplate(
          id: 'full',
          name: 'تقرير ${table.view.label}',
          fieldKeys: fields.map((f) => f.key).toList(),
        ),
      },
    );
  }

  Future<void> _print() async {
    final table = _table;
    if (table == null || _rows.isEmpty) {
      showErrorSnackBar(context, 'لا توجد نتائج لطباعتها.');
      return;
    }
    final parts = <String>[_view.label];
    if (_view == ResearchView.grouped) parts.add('حسب ${_group.label}');
    final filterText = _filters.describe();
    if (filterText.isNotEmpty) parts.add(filterText);

    await runHtmlPrintFlow<ResearchRow>(
      context,
      spec: _specFor(table),
      rows: [..._rows, if (table.footer != null) table.footer!],
      subtitle: parts.join(' — '),
      fileNamePrefix:
          'استعلام-${_view.label}-${AppDateFormatter.date(DateTime.now()).replaceAll('/', '-')}',
    );
  }

  Widget _statCard(ResearchStat s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s.value,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary)),
            Text(s.label,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  /// قائمة منسدلة عامة لفلتر نصي (تتحمّل غياب القيمة من الخيارات).
  Widget _dropdown({
    required String label,
    required List<String> options,
    required String? value,
    required ValueChanged<String?> onChanged,
    double width = 170,
  }) {
    final current = (value != null && options.contains(value)) ? value : null;
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String?>(
        value: current,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('الكل')),
          for (final o in options)
            DropdownMenuItem<String?>(
                value: o, child: Text(o, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _dateChip({required bool from}) {
    final f = _filters;
    final date = from ? f.dateFrom : f.dateTo;
    final base = from ? 'من تاريخ' : 'إلى تاريخ';
    return InputChip(
      avatar: const Icon(Icons.event, size: 18),
      label: Text(date == null
          ? base
          : '${from ? 'من' : 'إلى'} ${AppDateFormatter.date(date)}'),
      onPressed: () => _pickDate(from: from),
      onDeleted: date == null
          ? null
          : () => _update(() => _filters = from
              ? _filters.copyWith(clearFrom: true)
              : _filters.copyWith(clearTo: true)),
    );
  }

  Widget _advancedFilters() {
    final data = _data;
    if (data == null) return const SizedBox.shrink();
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _dropdown(
          label: 'الغرفة',
          options: data.roomNames,
          value: _filters.room,
          width: 220,
          onChanged: (v) => _update(() => _filters = v == null
              ? _filters.copyWith(clearRoom: true)
              : _filters.copyWith(room: v)),
        ),
        _dropdown(
          label: 'اليوم',
          options: data.dayNames,
          value: _filters.dayName,
          width: 140,
          onChanged: (v) => _update(() => _filters = v == null
              ? _filters.copyWith(clearDayName: true)
              : _filters.copyWith(dayName: v)),
        ),
        for (final role in PersonRole.values)
          _dropdown(
            label: role.label,
            options: data.namesFor(role),
            value: _filters.people[role],
            onChanged: (v) => _update(() => _filters = _filters.withPerson(role, v)),
          ),
        FilterChip(
          label: const Text('بمشكلة مسجلة فقط'),
          selected: _filters.onlyWithProblem,
          onSelected: (v) =>
              _update(() => _filters = _filters.copyWith(onlyWithProblem: v)),
        ),
        FilterChip(
          label: const Text('نواقص معدّلة بعد الإنتاج'),
          selected: _filters.onlyModified,
          onSelected: (v) =>
              _update(() => _filters = _filters.copyWith(onlyModified: v)),
        ),
      ],
    );
  }

  Widget _filtersBar() {
    final f = _filters;
    final advancedCount = f.activeCount -
        (f.keyword.trim().isEmpty ? 0 : 1) -
        (f.dateFrom == null ? 0 : 1) -
        (f.dateTo == null ? 0 : 1) -
        (f.status == null ? 0 : 1) -
        (f.shape == null ? 0 : 1) -
        (f.ownership == null ? 0 : 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: AppSearchField(
                controller: _keywordCtrl,
                label: 'بحث',
                hint: 'عدة كلمات للتضييق...',
                onChanged: (v) =>
                    _update(() => _filters = _filters.copyWith(keyword: v)),
              ),
            ),
            _dateChip(from: true),
            _dateChip(from: false),
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<RoomEntryStatus?>(
                value: f.status,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'الحالة'),
                items: [
                  const DropdownMenuItem<RoomEntryStatus?>(
                      value: null, child: Text('الكل')),
                  for (final s in RoomEntryStatus.values)
                    DropdownMenuItem<RoomEntryStatus?>(
                        value: s, child: Text(s.label)),
                ],
                onChanged: (v) => _update(() => _filters = v == null
                    ? _filters.copyWith(clearStatus: true)
                    : _filters.copyWith(status: v)),
              ),
            ),
            SizedBox(
              width: 160,
              child: DropdownButtonFormField<ResearchShape?>(
                value: f.shape,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'الشكل'),
                items: [
                  const DropdownMenuItem<ResearchShape?>(
                      value: null, child: Text('الكل')),
                  for (final s in ResearchShape.values)
                    DropdownMenuItem<ResearchShape?>(
                        value: s, child: Text(s.label)),
                ],
                onChanged: (v) => _update(() => _filters = v == null
                    ? _filters.copyWith(clearShape: true)
                    : _filters.copyWith(shape: v)),
              ),
            ),
            SizedBox(
              width: 160,
              child: DropdownButtonFormField<RoomOwnership?>(
                value: f.ownership,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'ملكية الغرفة'),
                items: [
                  const DropdownMenuItem<RoomOwnership?>(
                      value: null, child: Text('الكل')),
                  for (final o in RoomOwnership.values)
                    DropdownMenuItem<RoomOwnership?>(
                        value: o, child: Text(o.label)),
                ],
                onChanged: (v) => _update(() => _filters = v == null
                    ? _filters.copyWith(clearOwnership: true)
                    : _filters.copyWith(ownership: v)),
              ),
            ),
            if (_view == ResearchView.grouped)
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<ResearchGroup>(
                  value: _group,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'التجميع حسب'),
                  items: [
                    for (final g in ResearchGroup.values)
                      DropdownMenuItem<ResearchGroup>(
                          value: g, child: Text(g.label)),
                  ],
                  onChanged: (v) {
                    if (v != null) _update(() => _group = v);
                  },
                ),
              ),
            OutlinedButton.icon(
              onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
              icon: Icon(_showAdvanced ? Icons.expand_less : Icons.tune),
              label: Text(advancedCount > 0
                  ? 'فلاتر متقدمة ($advancedCount)'
                  : 'فلاتر متقدمة'),
            ),
            IconButton(
              tooltip: 'مسح الفلاتر',
              onPressed: _clearFilters,
              icon: const Icon(Icons.filter_alt_off_outlined),
            ),
            if (_view == ResearchView.audit &&
                (_data?.ignoredIssues.isNotEmpty ?? false))
              OutlinedButton.icon(
                onPressed: _restoreIgnored,
                icon: const Icon(Icons.restore),
                label: Text(
                    'استرجاع المتجاهَل (${_data!.ignoredIssues.length})'),
              ),
            IconButton(
              tooltip: 'تحديث البيانات',
              onPressed: _load,
              icon: const Icon(Icons.refresh),
            ),
            // زر الطباعة لا يظهر في تطبيق أندرويد (مثل بقية الجداول).
            if (!isAndroidApp)
              OutlinedButton.icon(
                onPressed: _print,
                icon: const Icon(Icons.print_outlined),
                label: const Text('طباعة النتائج'),
              ),
          ],
        ),
        if (_showAdvanced) ...[
          const SizedBox(height: AppSpacing.sm),
          _advancedFilters(),
        ],
      ],
    );
  }

  Future<void> _restoreIgnored() async {
    final data = _data;
    if (data == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استرجاع الملاحظات المتجاهَلة'),
        content: Text(
            'ستعود ${data.ignoredIssues.length} ملاحظة تم تجاهلها للظهور في تدقيق البيانات.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء')),
          ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('استرجاع')),
        ],
      ),
    );
    if (ok != true) return;
    await data.restoreIgnored();
    if (mounted) setState(() => _recompute(resetSort: false));
  }

  /// نافذة تعرض كل حقول الصف المختار (اسم الحقل وقيمته).
  void _showRowDetails(ResearchTable table, ResearchRow row) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تفاصيل — ${table.view.label}'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final c in table.columns)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: AppColors.border)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 150,
                          child: Text(
                            c.label,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SelectableText(
                            row.value(c.key).isEmpty ? '—' : row.value(c.key),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          if (table.view == ResearchView.audit && row.id != null)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
              onPressed: () async {
                final data = _data;
                if (data == null) return;
                await data.ignoreIssue(row.id!);
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (mounted) setState(() => _recompute(resetSort: false));
              },
              child: const Text('تجاهل'),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _table == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'حدث خطأ',
        subtitle: _error,
        action: ElevatedButton(onPressed: _load, child: const Text('إعادة المحاولة')),
      );
    }
    final table = _table;
    if (table == null) return const SizedBox.shrink();

    final sortIndex = table.columns.indexWhere((c) => c.key == _sortKey);
    final footer = table.footer;
    final rowCount = _rows.length + (footer == null ? 0 : 1);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              for (final v in ResearchView.values)
                ChoiceChip(
                  label: Text(v.label),
                  selected: _view == v,
                  onSelected: (_) => _update(() => _view = v),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _view.description,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: AppSpacing.sm),
          _filtersBar(),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [for (final s in table.stats) _statCard(s)],
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: _rows.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off,
                    title: 'لا توجد نتائج مطابقة',
                    subtitle: 'جرّب تعديل البحث أو الفلاتر.',
                  )
                : Card(
                    clipBehavior: Clip.antiAlias,
                    child: AppDataGrid(
                      columns: [
                        const AppGridColumn('م', width: 56, numeric: true),
                        for (final c in table.columns)
                          AppGridColumn(c.label,
              width: c.width, numeric: c.numeric, singleLine: c.singleLine),
                      ],
                      rowCount: rowCount,
                      rowHeight: 56,
                      // العمود الأول (م) ليس قابلًا للترتيب: نزيح الفهرس.
                      sortColumnIndex: sortIndex < 0 ? null : sortIndex + 1,
                      sortAscending: _sortAsc,
                      onSort: (i) {
                        if (i > 0) _onSort(i - 1);
                      },
                      onRowTap: (i) {
                        if (i < _rows.length) _showRowDetails(table, _rows[i]);
                      },
                      rowBuilder: (i) {
                        if (i >= _rows.length && footer != null) {
                          return AppGridRow(
                            color: footer.tint,
                            cells: [
                              gridText('', bold: true),
                              for (final c in table.columns)
                                gridText(footer.value(c.key), bold: true),
                            ],
                          );
                        }
                        final row = _rows[i];
                        return AppGridRow(
                          color: row.tint,
                          cells: [
                            gridText('${i + 1}'),
                            for (final c in table.columns)
                              _oneLineKeys.contains(c.key)
                                  ? gridOneLine(row.value(c.key))
                                  : gridText(row.value(c.key)),
                          ],
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
