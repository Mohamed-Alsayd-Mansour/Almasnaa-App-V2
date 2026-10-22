import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../services/html_print_service.dart';
import '../services/print_template_store.dart';
import 'app_data_grid.dart';
import 'common_widgets.dart';

/// مسار الطباعة الموحّد في كل أنحاء التطبيق (اليومية، السجل، الغرف،
/// الاستعلامات): اختيار القالب أو تخصيصه ← معاينة ← فتح HTML للطباعة.
///
/// العنوان الرئيسي للتقرير يُشتق دائمًا من اسم القالب بالشكل
/// "سجل الغرف (اسم التقرير)" عبر [HtmlPrintService.reportTitle].
Future<void> runHtmlPrintFlow<T>(
  BuildContext context, {
  required PrintSpec<T> spec,
  required List<T> rows,
  required String fileNamePrefix,
  String? subtitle,
}) async {
  try {
    final template = await showPrintTemplateDialog<T>(context, spec: spec);
    if (template == null || !context.mounted) return;

    final title = HtmlPrintService.reportTitle(template.name);

    final preview = await showPrintPreviewDialog<T>(
      context,
      title: title,
      subtitle: subtitle,
      spec: spec,
      rows: rows,
      template: template,
    );
    if (preview != true || !context.mounted) return;

    final html = HtmlPrintService.buildHtml<T>(
      title: title,
      subtitle: subtitle,
      spec: spec,
      rows: rows,
      fieldKeys: template.fieldKeys,
      landscape: template.landscape,
    );
    await HtmlPrintService.openHtmlInBrowser(
      html: html,
      suggestedFileName: '$fileNamePrefix.html',
    );
  } catch (e) {
    if (!context.mounted) return;
    showErrorSnackBar(context, 'تعذّر تجهيز ملف HTML للطباعة.\n$e');
  }
}

Future<HtmlPrintTemplate?> showPrintTemplateDialog<T>(
  BuildContext context, {
  required PrintSpec<T> spec,
}) async {
  final custom = await PrintTemplateStore.loadCustom(spec.storageKey);
  if (!context.mounted) return null;
  return showDialog<HtmlPrintTemplate>(
    context: context,
    builder: (_) => _PrintTemplateDialog<T>(spec: spec, custom: custom),
  );
}

class _PrintTemplateDialog<T> extends StatefulWidget {
  final PrintSpec<T> spec;
  final List<HtmlPrintTemplate> custom;

  const _PrintTemplateDialog({
    required this.spec,
    required this.custom,
  });

  @override
  State<_PrintTemplateDialog<T>> createState() =>
      _PrintTemplateDialogState<T>();
}

class _PrintTemplateDialogState<T> extends State<_PrintTemplateDialog<T>> {
  late List<HtmlPrintTemplate> _custom;

  @override
  void initState() {
    super.initState();
    _custom = [...widget.custom];
  }

  Future<void> _customize({HtmlPrintTemplate? initial}) async {
    final result = await showDialog<HtmlPrintTemplate>(
      context: context,
      builder: (_) => _CustomizePrintDialog<T>(spec: widget.spec, initial: initial),
    );
    if (result == null || !mounted) return;
    await PrintTemplateStore.save(widget.spec.storageKey, result);
    setState(() {
      _custom = [..._custom.where((e) => e.id != result.id), result];
    });
    if (mounted) Navigator.of(context).pop(result);
  }

  Future<void> _delete(HtmlPrintTemplate template) async {
    await PrintTemplateStore.delete(widget.spec.storageKey, template.id);
    if (mounted) setState(() => _custom.removeWhere((e) => e.id == template.id));
  }

  Widget _tile(HtmlPrintTemplate template, {bool deletable = false}) {
    return ListTile(
      leading: const Icon(Icons.description_outlined),
      title: Text(template.name),
      subtitle: Text('${template.fieldKeys.length} حقلاً — ${template.landscape ? 'أفقي' : 'عمودي'}'),
      trailing: Wrap(
        children: [
          IconButton(
            tooltip: 'استخدام القالب',
            icon: const Icon(Icons.play_arrow),
            onPressed: () => Navigator.of(context).pop(template),
          ),
          if (deletable) ...[
            IconButton(
              tooltip: 'تعديل القالب',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _customize(initial: template),
            ),
            IconButton(
              tooltip: 'حذف القالب',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(template),
            ),
          ],
        ],
      ),
      onTap: () => Navigator.of(context).pop(template),
    );
  }

  @override
  Widget build(BuildContext context) {
    final builtIns = widget.spec.builtInTemplates.values.toList();
    return AlertDialog(
      title: const Text('اختر قالب الطباعة'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('قوالب جاهزة', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              ...builtIns.map(_tile),
              const Divider(height: 28),
              Row(
                children: [
                  const Expanded(child: Text('قوالبي المحفوظة', style: TextStyle(fontWeight: FontWeight.bold))),
                  FilledButton.icon(
                    onPressed: () => _customize(),
                    icon: const Icon(Icons.add),
                    label: const Text('تخصيص قالب'),
                  ),
                ],
              ),
              if (_custom.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(18),
                  child: Center(child: Text('لا توجد قوالب مخصصة محفوظة بعد.')),
                )
              else
                ..._custom.map((e) => _tile(e, deletable: true)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء')),
      ],
    );
  }
}

Future<bool?> showPrintPreviewDialog<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required PrintSpec<T> spec,
  required List<T> rows,
  required HtmlPrintTemplate template,
}) {
  final selected = spec.fieldsOf(template);

  // جدول المعاينة: عمود "م" + الحقول المختارة، بعرض مقدّر لكل عمود.
  final columns = <AppGridColumn>[
    const AppGridColumn('م', width: 56, numeric: true),
    for (final field in selected)
      AppGridColumn(
        field.label,
        width: estimateColumnWidth(field.label, rows.map(field.valueOf)),
      ),
  ];

  final screenWidth = MediaQuery.of(context).size.width;
  final dialogWidth = math.min(900.0, math.max(320.0, screenWidth - 96));

  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('معاينة: ${template.name}'),
      content: SizedBox(
        width: dialogWidth,
        height: 520,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(subtitle.trim(), style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
              const SizedBox(height: 8),
              Text('عدد السجلات: ${rows.length} — ${template.landscape ? 'A4 أفقي' : 'A4 عمودي'}'),
              const SizedBox(height: 12),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AppDataGrid(
                      columns: columns,
                      rowCount: rows.length,
                      rowHeight: 48,
                      rowBuilder: (i) => AppGridRow(cells: [
                        gridText('${i + 1}'),
                        for (final field in selected) gridText(field.valueOf(rows[i])),
                      ]),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('رجوع')),
        FilledButton.icon(
          onPressed: () => Navigator.pop(dialogContext, true),
          icon: const Icon(Icons.open_in_browser),
          label: const Text('فتح HTML والطباعة'),
        ),
      ],
    ),
  );
}

class _CustomizePrintDialog<T> extends StatefulWidget {
  final PrintSpec<T> spec;
  final HtmlPrintTemplate? initial;

  const _CustomizePrintDialog({required this.spec, this.initial});

  @override
  State<_CustomizePrintDialog<T>> createState() =>
      _CustomizePrintDialogState<T>();
}

class _CustomizePrintDialogState<T> extends State<_CustomizePrintDialog<T>> {
  late final TextEditingController _name;
  late Set<String> _selected;
  late List<String> _order;
  late bool _landscape;

  @override
  void initState() {
    super.initState();
    final spec = widget.spec;
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? 'تقرير مخصص');
    _order = spec.fields.map((f) => f.key).toList();
    if (initial != null) {
      final keys = initial.fieldKeys.where(spec.hasField).toList();
      final selected = keys.toSet();
      _order = [...keys, ..._order.where((k) => !selected.contains(k))];
      _selected = selected;
    } else {
      final base = spec.builtInTemplates[spec.defaultCustomBaseTemplateId] ??
          spec.builtInTemplates.values.first;
      _selected = {...base.fieldKeys.where(spec.hasField)};
    }
    _landscape = initial?.landscape ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تخصيص قالب الطباعة'),
      content: SizedBox(
        width: 650,
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'اسم القالب',
                  helperText: 'يظهر في عنوان التقرير: سجل الغرف (اسم القالب بدون كلمة تقرير)',
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('أفقي'), icon: Icon(Icons.crop_landscape)),
                  ButtonSegment(value: false, label: Text('عمودي'), icon: Icon(Icons.crop_portrait)),
                ],
                selected: {_landscape},
                onSelectionChanged: (v) => setState(() => _landscape = v.first),
              ),
              const SizedBox(height: 14),
              const Align(
                alignment: Alignment.centerRight,
                child: Text('اختر البيانات ورتّب الأعمدة بالسحب:', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 6),
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (oldIndex < newIndex) newIndex--;
                    final item = _order.removeAt(oldIndex);
                    _order.insert(newIndex, item);
                  });
                },
                children: [
                  for (final key in _order)
                    Builder(
                      key: ValueKey(key),
                      builder: (_) {
                        final field = widget.spec.fieldByKey(key);
                        final selected = _selected.contains(key);
                        return ListTile(
                          leading: Checkbox(
                            value: selected,
                            onChanged: (_) => setState(() {
                              if (selected) {
                                _selected.remove(key);
                              } else {
                                _selected.add(key);
                              }
                            }),
                          ),
                          title: Text(field.label, style: TextStyle(color: selected ? null : Colors.grey)),
                          trailing: const Icon(Icons.drag_handle),
                        );
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إلغاء')),
        FilledButton.icon(
          onPressed: _selected.isEmpty
              ? null
              : () {
                  final name = _name.text.trim().isEmpty ? 'تقرير مخصص' : _name.text.trim();
                  Navigator.of(context).pop(HtmlPrintTemplate(
                    id: widget.initial?.id ?? const Uuid().v4(),
                    name: name,
                    fieldKeys: _orderedKeys(),
                    landscape: _landscape,
                  ));
                },
          icon: const Icon(Icons.save),
          label: const Text('حفظ واستخدام'),
        ),
      ],
    );
  }

  List<String> _orderedKeys() => _order.where(_selected.contains).toList();
}
