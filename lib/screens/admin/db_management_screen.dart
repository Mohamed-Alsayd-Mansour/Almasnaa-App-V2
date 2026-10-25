import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme.dart';
import '../../data/supa.dart';
import '../../widgets/common_widgets.dart';
import 'orphan_records_view.dart';

/// «إدارة قاعدة البيانات» (للأدمن فقط): تصفّح وبحث وتعديل بيانات التطبيق من الواجهة.
///
/// الأمان: لا يوجد هنا أي مفتاح service_role ولا تجاوز لـ RLS. كل عملية تُنفَّذ بجلسة الأدمن نفسها،
/// فيفرض الخادم الصلاحيات (سياسات RLS + محفِّزات الحماية في قاعدة البيانات)، وتُسجَّل كل كتابة في
/// audit_log عبر المحفِّزات الموجودة مع هوية المنفّذ. ما لا تسمح به القاعدة يفشل ويظهر خطؤه الحقيقي.
/// عمليات صف واحد فقط: لا حذف شامل ولا تعديل جماعي.
class DbManagementScreen extends StatefulWidget {
  const DbManagementScreen({super.key});

  @override
  State<DbManagementScreen> createState() => _DbManagementScreenState();
}

enum _Kind { text, integer, boolean, choice }

class _Field {
  const _Field(this.key, this.label, this.kind, {this.required = false, this.choices});
  final String key;
  final String label;
  final _Kind kind;
  final bool required;
  final Map<String, String>? choices; // قيمة -> عنوان
}

class _TableSpec {
  const _TableSpec({
    required this.id,
    required this.label,
    required this.group,
    required this.columns,
    required this.searchColumns,
    this.orderBy = 'created_at',
    this.ascending = false,
    this.fields = const [],
    this.canInsert = false,
    this.canEdit = false,
    this.canDelete = false,
    this.filterColumn,
    this.filterChoices,
    this.note,
  });

  final String id; // اسم الجدول
  final String label;
  final String group;
  final Map<String, String> columns; // عمود -> عنوان (أول عمودين = عنوان الصف)
  final List<String> searchColumns;
  final String orderBy;
  final bool ascending;
  final List<_Field> fields; // الحقول القابلة للإضافة/التعديل
  final bool canInsert;
  final bool canEdit;
  final bool canDelete;
  final String? filterColumn;
  final Map<String, String>? filterChoices;
  final String? note;
}

const _kGroupOps = 'بيانات التشغيل';
const _kGroupLogs = 'السجلات والتدقيق';
const _kGroupReview = 'سجلات تحتاج إلى مراجعة';
const _kOrphans = '__orphans__';

// عناوين كل الأدوار (لعرض السجلات القديمة)، وخيارات الإضافة/التعديل بدون الرصيص والمشرف:
// أسماؤهما تأتي من حسابات المستخدمين فقط، ويرفض الخادم إدخالها هنا.
const _personRoles = {
  'service': 'خدمة',
  'carpenter': 'نجار',
  'installer': 'رصيص',
  'supervisor': 'مشرف',
  'repairer': 'رميم',
  'wrapLocation': 'مكان اللف',
};
const _editablePersonRoles = {
  'service': 'خدمة',
  'carpenter': 'نجار',
  'repairer': 'رميم',
  'wrapLocation': 'مكان اللف',
};

const _tables = <_TableSpec>[
  _TableSpec(
    id: 'rooms',
    label: 'الغرف',
    group: _kGroupOps,
    columns: {
      'name': 'الاسم',
      'piece_count': 'القطع',
      'glass_piece_count': 'زجاج',
      'partition_piece_count': 'قطع القواطيع',
      'partition_count': 'عدد القواطيع',
      'marble_piece_count': 'رخام',
    },
    searchColumns: ['name'],
    orderBy: 'name',
    ascending: true,
    fields: [
      _Field('name', 'اسم الغرفة', _Kind.text, required: true),
      _Field('piece_count', 'عدد القطع', _Kind.integer),
      _Field('glass_piece_count', 'قطع الزجاج', _Kind.integer),
      _Field('partition_piece_count', 'قطع القواطيع', _Kind.integer),
      _Field('partition_count', 'عدد القواطيع (للعرض فقط)', _Kind.integer),
      _Field('marble_piece_count', 'قطع الرخام', _Kind.integer),
    ],
    canInsert: true,
    canEdit: true,
    canDelete: true,
    note: 'حذف غرفة لا يمسح الإدخالات المرتبطة بها: تبقى بلقطة اسمها وعدد قطعها.',
  ),
  _TableSpec(
    id: 'people',
    label: 'قوائم الأسماء',
    group: _kGroupOps,
    columns: {'name': 'الاسم', 'role': 'الدور'},
    searchColumns: ['name'],
    orderBy: 'name',
    ascending: true,
    fields: [
      _Field('name', 'الاسم', _Kind.text, required: true),
      _Field('role', 'الدور', _Kind.choice, required: true, choices: _editablePersonRoles),
    ],
    canInsert: true,
    canEdit: true,
    canDelete: true,
    filterColumn: 'role',
    filterChoices: _personRoles,
    note: 'الأسماء في الإدخالات القديمة نصوص محفوظة، فلا يغيّرها تعديل القائمة. أسماء الرصيص والمشرف تأتي من الحسابات ولا تُضاف هنا (الصفوف القديمة منها للحذف فقط).',
  ),
  _TableSpec(
    id: 'daily_sessions',
    label: 'اليوميات',
    group: _kGroupOps,
    columns: {
      'day_name': 'اليوم',
      'date': 'التاريخ',
      'status': 'الحالة',
      'rassas_name_snapshot': 'الرصيص',
      'supervisor_name_snapshot': 'المشرف',
    },
    searchColumns: ['day_name', 'rassas_name_snapshot', 'supervisor_name_snapshot'],
    orderBy: 'date',
    filterColumn: 'status',
    filterChoices: {'active': 'مختارة', 'paused': 'معلّقة', 'closed': 'مغلقة'},
    canDelete: true,
    note: 'اليومية التي فيها إدخالات لا تُحذف (تمنعها قاعدة البيانات). الإنشاء والإغلاق من واجهة الرصيص؛ '
        'الملكية غير قابلة للتغيير.',
  ),
  _TableSpec(
    id: 'daily_entries',
    label: 'الإدخالات (الغرف المسجلة)',
    group: _kGroupOps,
    columns: {
      'room_name_snapshot': 'الغرفة',
      'numbering': 'الترقيم',
      'carpenter': 'النجار',
      'service': 'الخدمة',
      'installer': 'الرصيص',
      'supervisor': 'المشرف',
      'repairer': 'الرميم',
      'current_missing_count': 'الناقص',
      'created_at': 'أُنشئ',
    },
    searchColumns: ['room_name_snapshot', 'numbering', 'carpenter', 'service', 'installer', 'supervisor', 'repairer', 'merchant_name', 'customer_name'],
    fields: [
      _Field('room_name_snapshot', 'اسم الغرفة', _Kind.text, required: true),
      _Field('numbering', 'الترقيم', _Kind.text),
      _Field('carpenter', 'النجار', _Kind.text),
      _Field('service', 'الخدمة', _Kind.text),
      _Field('installer', 'اسم الرصيص (أدمن فقط)', _Kind.text),
      _Field('supervisor', 'اسم المشرف (أدمن فقط)', _Kind.text),
      _Field('repairer', 'الرميم', _Kind.text),
      _Field('wrap_location', 'مكان اللف', _Kind.text),
      _Field('merchant_name', 'التاجر', _Kind.text),
      _Field('customer_name', 'الزبون', _Kind.text),
      _Field('problem', 'المشكلة', _Kind.text),
      _Field('specifications_text', 'المواصفات', _Kind.text),
      _Field('piece_count_snapshot', 'عدد القطع', _Kind.integer),
      _Field('current_missing_count', 'عدد الناقص الحالي', _Kind.integer),
    ],
    canEdit: true,
    canDelete: true,
    filterColumn: 'is_external',
    filterChoices: {'true': 'خارجية', 'false': 'داخلية'},
    note: 'لا يمكن تغيير مالك الإدخال أو يوميته. الإضافة تتم من اليومية حتى يُحسب المالك صحيحًا.',
  ),
  _TableSpec(
    id: 'rassas_supervisor_links',
    label: 'روابط الرصيص بالمشرف',
    group: _kGroupLogs,
    columns: {'rassas_id': 'الرصيص (id)', 'supervisor_id': 'المشرف (id)', 'effective_from': 'من', 'effective_to': 'إلى'},
    searchColumns: [],
    orderBy: 'effective_from',
    note: 'للعرض فقط. التغيير يتم من «الإعدادات ← الربط» عبر دالة الخادم.',
  ),
  _TableSpec(
    id: 'app_settings',
    label: 'إعدادات التطبيق',
    group: _kGroupLogs,
    columns: {'key': 'المفتاح', 'value': 'القيمة', 'updated_at': 'آخر تحديث'},
    searchColumns: ['key'],
    orderBy: 'key',
    ascending: true,
    note: 'للعرض فقط في هذه النسخة.',
  ),
  _TableSpec(
    id: 'audit_log',
    label: 'سجل التدقيق',
    group: _kGroupLogs,
    columns: {'at': 'الوقت', 'actor_name': 'المنفّذ', 'op': 'العملية', 'entity': 'الجدول', 'entity_id': 'المعرّف'},
    searchColumns: ['actor_name', 'entity', 'entity_id'],
    orderBy: 'at',
    filterColumn: 'op',
    filterChoices: {'INSERT': 'إضافة', 'UPDATE': 'تعديل', 'DELETE': 'حذف'},
    note: 'للعرض فقط. يسجّل كل تغيير مع المنفّذ والقيم القديمة والجديدة.',
  ),
  _TableSpec(
    id: 'migration_review',
    label: 'قائمة مراجعة الترحيل',
    group: _kGroupReview,
    columns: {'entity': 'الجدول', 'entity_id': 'المعرّف', 'reason': 'السبب', 'created_at': 'التاريخ'},
    searchColumns: ['entity', 'reason', 'entity_id'],
    note: 'سجلات رُحِّلت من 1.0 وتحتاج نظرة بشرية (مالك غير معروف، غرفة محذوفة...). للعرض فقط.',
  ),
  _TableSpec(
    id: 'profiles',
    label: 'الحسابات (عرض فقط)',
    group: _kGroupLogs,
    columns: {'display_name': 'الاسم', 'username': 'اسم المستخدم', 'role': 'الدور', 'status': 'الحالة', 'last_login_at': 'آخر دخول'},
    searchColumns: ['display_name', 'username'],
    orderBy: 'display_name',
    ascending: true,
    note: 'للعرض فقط. إدارة الحسابات من تبويب «الحسابات» لأنها تمر بدالة خادم آمنة.',
  ),
];

class _DbManagementScreenState extends State<DbManagementScreen> {
  static const int _pageSize = 50;

  String _selected = _tables.first.id;

  // حالة الجدول الحالي
  List<Map<String, dynamic>> _rows = const [];
  int _page = 0;
  bool _hasNext = false;
  bool _loading = true;
  String? _error;
  String _search = '';
  String? _filter;
  final _searchCtrl = TextEditingController();

  _TableSpec get _spec => _tables.firstWhere((t) => t.id == _selected);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _select(String id) {
    if (id == _selected) return;
    setState(() {
      _selected = id;
      _page = 0;
      _search = '';
      _filter = null;
      _searchCtrl.clear();
      _rows = const [];
      _error = null;
    });
    if (id != _kOrphans) _load();
  }

  /// يمنع حقن صياغة PostgREST عبر نص البحث (الفواصل والأقواس).
  String _clean(String s) => s.replaceAll(RegExp(r'[,()*%\\"]'), ' ').trim();

  Future<void> _load() async {
    final spec = _spec;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var q = supa.from(spec.id).select();
      final term = _clean(_search);
      if (term.isNotEmpty && spec.searchColumns.isNotEmpty) {
        q = q.or(spec.searchColumns.map((c) => '$c.ilike.%$term%').join(','));
      }
      if (_filter != null && spec.filterColumn != null) {
        q = q.eq(spec.filterColumn!, _filter!);
      }
      final from = _page * _pageSize;
      // نطلب صفًّا زائدًا لمعرفة وجود صفحة تالية دون عدّ كلي مكلف.
      final rows = await q
          .order(spec.orderBy, ascending: spec.ascending)
          .range(from, from + _pageSize);
      if (!mounted || spec.id != _selected) return;
      final list = (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      setState(() {
        _hasNext = list.length > _pageSize;
        _rows = _hasNext ? list.sublist(0, _pageSize) : list;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[db-admin] load ${spec.id}: ${e.runtimeType}');
      if (!mounted || spec.id != _selected) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e);
      });
    }
  }

  void _reloadFirstPage() {
    _page = 0;
    _load();
  }

  // ------------------------------------------------------------------ writes

  Future<void> _insert() async {
    final spec = _spec;
    final values = await _showForm(spec, null);
    if (values == null) return;
    await _write(() async {
      await supa.from(spec.id).insert(values);
    }, 'تمت الإضافة.');
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final spec = _spec;
    final values = await _showForm(spec, row);
    if (values == null) return;
    // نرسل الحقول التي تغيّرت فقط.
    final changed = <String, Object?>{
      for (final e in values.entries)
        if ('${row[e.key] ?? ''}' != '${e.value ?? ''}') e.key: e.value,
    };
    if (changed.isEmpty) {
      if (mounted) _toast('لا يوجد تغيير.', error: false);
      return;
    }
    await _write(() async {
      final res = await supa.from(spec.id).update(changed).eq('id', row['id'] as Object).select('id');
      if ((res as List).isEmpty) throw StateError('no-rows');
    }, 'تم حفظ التعديل.');
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final spec = _spec;
    final ok = await confirmDelete(
      context,
      title: 'حذف من «${spec.label}»',
      message: 'سيُحذف هذا السجل نهائيًا:\n${_title(spec, row)}\n\n'
          'العملية تُسجَّل في سجل التدقيق باسمك، ولا يمكن التراجع عنها.',
    );
    if (!ok || !mounted) return;
    await _write(() async {
      final res = await supa.from(spec.id).delete().eq('id', row['id'] as Object).select('id');
      if ((res as List).isEmpty) throw StateError('no-rows');
    }, 'تم الحذف.');
  }

  Future<void> _write(Future<void> Function() op, String okMsg) async {
    try {
      await op();
      if (!mounted) return;
      _toast(okMsg, error: false);
      await _load();
    } on StateError {
      if (mounted) _toast('لم يتغيّر شيء: السجل غير موجود أو لا تسمح الصلاحيات بالعملية.', error: true);
    } catch (e) {
      // تفاصيل التشخيص دون أي بيانات: نوع الخطأ والرمز فقط.
      debugPrint('[db-admin] write ${_spec.id}: ${e.runtimeType} ${e is PostgrestException ? e.code : ''}');
      if (mounted) _toast(friendlyError(e), error: true);
    }
  }

  void _toast(String msg, {required bool error}) =>
      error ? showErrorSnackBar(context, msg) : showSuccessSnackBar(context, msg);

  // ------------------------------------------------------------------ form

  Future<Map<String, Object?>?> _showForm(_TableSpec spec, Map<String, dynamic>? row) {
    return showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _RowFormDialog(
        title: row == null ? 'إضافة إلى «${spec.label}»' : 'تعديل «${spec.label}»',
        fields: spec.fields,
        initial: row,
      ),
    );
  }

  // ------------------------------------------------------------------ view helpers

  String _fmt(Object? v) {
    if (v == null) return '—';
    if (v is bool) return v ? 'نعم' : 'لا';
    if (v is Map || v is List) return jsonEncode(v);
    final s = '$v';
    // قصّ الطوابع الزمنية لتاريخ/وقت مقروء
    if (RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(s)) {
      return DateTime.tryParse(s)?.toLocal().toString().substring(0, 16) ?? s;
    }
    return s;
  }

  String _label(_TableSpec spec, String col, Object? v) {
    if (col == 'role' && spec.id == 'people') return _personRoles['$v'] ?? '$v';
    return _fmt(v);
  }

  String _title(_TableSpec spec, Map<String, dynamic> row) {
    final cols = spec.columns.keys.toList();
    return cols.take(2).map((c) => _label(spec, c, row[c])).where((s) => s != '—').join(' • ');
  }

  String _subtitle(_TableSpec spec, Map<String, dynamic> row) {
    final cols = spec.columns.keys.toList();
    return cols.skip(2).map((c) => '${spec.columns[c]}: ${_label(spec, c, row[c])}').join(' | ');
  }

  void _details(Map<String, dynamic> row) {
    final spec = _spec;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(spec.label),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final e in row.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: SelectableText.rich(TextSpan(children: [
                    TextSpan(text: '${e.key}: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: e.value is Map || e.value is List ? const JsonEncoder.withIndent('  ').convert(e.value) : _fmt(e.value)),
                  ])),
                ),
            ]),
          ),
        ),
        actions: [
          if (spec.canEdit)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _edit(row);
              },
              child: const Text('تعديل'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<_TableSpec>>{};
    for (final t in _tables) {
      groups.putIfAbsent(t.group, () => []).add(t);
    }
    return Column(children: [
      Material(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final g in [_kGroupOps, _kGroupLogs, _kGroupReview]) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 2),
                child: Text(g, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
              ),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final t in groups[g] ?? const <_TableSpec>[])
                  ChoiceChip(label: Text(t.label), selected: _selected == t.id, onSelected: (_) => _select(t.id)),
                if (g == _kGroupReview)
                  ChoiceChip(
                    label: const Text('سجلات بلا مالك'),
                    selected: _selected == _kOrphans,
                    onSelected: (_) => _select(_kOrphans),
                  ),
              ]),
            ],
          ]),
        ),
      ),
      const Divider(height: 1),
      Expanded(child: _selected == _kOrphans ? const OrphanRecordsView() : _tableView()),
    ]);
  }

  Widget _tableView() {
    final spec = _spec;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (spec.note != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(spec.note!, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            ),
          Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (spec.searchColumns.isNotEmpty)
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(labelText: 'بحث', prefixIcon: Icon(Icons.search), isDense: true),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (v) {
                    _search = v;
                    _reloadFirstPage();
                  },
                ),
              ),
            if (spec.filterColumn != null)
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String?>(
                  key: ValueKey('${spec.id}-$_filter'),
                  initialValue: _filter,
                  isDense: true,
                  decoration: const InputDecoration(labelText: 'تصفية', isDense: true),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('الكل')),
                    for (final e in spec.filterChoices!.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) {
                    _filter = v;
                    _reloadFirstPage();
                  },
                ),
              ),
            IconButton(tooltip: 'تحديث', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
            if (spec.canInsert)
              ElevatedButton.icon(onPressed: _insert, icon: const Icon(Icons.add), label: const Text('إضافة')),
          ]),
        ]),
      ),
      Expanded(child: _body(spec)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          TextButton.icon(
            onPressed: (_loading || _page == 0) ? null : () {
              _page--;
              _load();
            },
            icon: const Icon(Icons.chevron_right),
            label: const Text('السابق'),
          ),
          Text('الصفحة ${_page + 1}'),
          TextButton.icon(
            onPressed: (_loading || !_hasNext) ? null : () {
              _page++;
              _load();
            },
            icon: const Icon(Icons.chevron_left),
            label: const Text('التالي'),
          ),
        ]),
      ),
    ]);
  }

  Widget _body(_TableSpec spec) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.all(12), child: Text(_error!, textAlign: TextAlign.center)),
          TextButton(onPressed: _load, child: const Text('إعادة المحاولة')),
        ]),
      );
    }
    if (_rows.isEmpty) return const Center(child: Text('لا توجد بيانات مطابقة.'));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      itemCount: _rows.length,
      itemBuilder: (_, i) {
        final row = _rows[i];
        return Card(
          child: ListTile(
            title: Text(_title(spec, row), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(_subtitle(spec, row), maxLines: 3, overflow: TextOverflow.ellipsis),
            onTap: () => _details(row),
            trailing: (spec.canEdit || spec.canDelete)
                ? PopupMenuButton<String>(
                    onSelected: (v) => v == 'edit' ? _edit(row) : (v == 'delete' ? _delete(row) : _details(row)),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'view', child: Text('تفاصيل')),
                      if (spec.canEdit) const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                      if (spec.canDelete) const PopupMenuItem(value: 'delete', child: Text('حذف')),
                    ],
                  )
                : const Icon(Icons.chevron_left),
          ),
        );
      },
    );
  }
}

class _RowFormDialog extends StatefulWidget {
  const _RowFormDialog({required this.title, required this.fields, this.initial});
  final String title;
  final List<_Field> fields;
  final Map<String, dynamic>? initial;

  @override
  State<_RowFormDialog> createState() => _RowFormDialogState();
}

class _RowFormDialogState extends State<_RowFormDialog> {
  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, Object?> _values = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      final v = widget.initial?[f.key];
      switch (f.kind) {
        case _Kind.text:
        case _Kind.integer:
          _ctrls[f.key] = TextEditingController(text: v == null ? (f.kind == _Kind.integer && widget.initial == null ? '0' : '') : '$v');
        case _Kind.boolean:
          _values[f.key] = v == true;
        case _Kind.choice:
          // قيمة قديمة غير متاحة للاختيار (مثل رصيص/مشرف في قائمة الأسماء) تُترك فارغة ليختار الأدمن قيمة صالحة.
          _values[f.key] = (v is String && f.choices!.containsKey(v)) ? v : null;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final out = <String, Object?>{};
    for (final f in widget.fields) {
      switch (f.kind) {
        case _Kind.text:
          final t = _ctrls[f.key]!.text.trim();
          if (f.required && t.isEmpty) return setState(() => _error = '«${f.label}» مطلوب.');
          out[f.key] = t;
        case _Kind.integer:
          final n = int.tryParse(_ctrls[f.key]!.text.trim());
          if (n == null || n < 0) return setState(() => _error = '«${f.label}» يجب أن يكون رقمًا صحيحًا غير سالب.');
          out[f.key] = n;
        case _Kind.boolean:
          out[f.key] = _values[f.key] == true;
        case _Kind.choice:
          if (f.required && _values[f.key] == null) return setState(() => _error = 'اختر «${f.label}».');
          out[f.key] = _values[f.key];
      }
    }
    Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final f in widget.fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: switch (f.kind) {
                  _Kind.text => TextField(controller: _ctrls[f.key], decoration: InputDecoration(labelText: f.label)),
                  _Kind.integer => TextField(
                      controller: _ctrls[f.key],
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: f.label),
                    ),
                  _Kind.boolean => SwitchListTile(
                      title: Text(f.label),
                      value: _values[f.key] == true,
                      onChanged: (v) => setState(() => _values[f.key] = v),
                    ),
                  _Kind.choice => DropdownButtonFormField<String>(
                      initialValue: _values[f.key] as String?,
                      decoration: InputDecoration(labelText: f.label),
                      items: [for (final e in f.choices!.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                      onChanged: (v) => setState(() => _values[f.key] = v),
                    ),
                },
              ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        ElevatedButton(onPressed: _submit, child: const Text('حفظ')),
      ],
    );
  }
}
