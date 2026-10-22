import 'package:intl/intl.dart';

import '../models/daily_entry.dart';
import '../models/enums.dart';
import '../models/room.dart';
import '../utils/date_formatter.dart';
import '../utils/browser_launcher.dart' as browser;

/// صف طباعة لإدخالات اليومية/السجل (الإدخال + بيانات يوميته).
class HtmlPrintRow {
  final DailyEntry entry;
  final String? dayName;
  final DateTime? date;
  final DailySessionStatus? sessionStatus;

  const HtmlPrintRow({
    required this.entry,
    this.dayName,
    this.date,
    this.sessionStatus,
  });
}

/// حقل قابل للطباعة من صف من النوع [T].
class HtmlPrintField<T> {
  final String key;
  final String label;
  final String Function(T row) valueOf;

  const HtmlPrintField({
    required this.key,
    required this.label,
    required this.valueOf,
  });
}

class HtmlPrintTemplate {
  final String id;
  final String name;
  final List<String> fieldKeys;
  final bool landscape;

  const HtmlPrintTemplate({
    required this.id,
    required this.name,
    required this.fieldKeys,
    this.landscape = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'fieldKeys': fieldKeys,
        'landscape': landscape,
      };

  factory HtmlPrintTemplate.fromJson(Map<String, dynamic> json) {
    return HtmlPrintTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      fieldKeys: (json['fieldKeys'] as List).cast<String>(),
      landscape: json['landscape'] as bool? ?? true,
    );
  }
}

/// وصف مجموعة بيانات قابلة للطباعة: حقولها، وقوالبها الجاهزة، ومفتاح
/// حفظ القوالب المخصصة الخاصة بها (لكل مجموعة قوالبها المستقلة).
class PrintSpec<T> {
  /// مفتاح التخزين المحلي للقوالب المخصصة.
  final String storageKey;
  final List<HtmlPrintField<T>> fields;
  final Map<String, HtmlPrintTemplate> builtInTemplates;

  /// القالب الذي تبدأ منه نافذة "تخصيص قالب" عند إنشاء قالب جديد.
  final String defaultCustomBaseTemplateId;

  const PrintSpec({
    required this.storageKey,
    required this.fields,
    required this.builtInTemplates,
    required this.defaultCustomBaseTemplateId,
  });

  bool hasField(String key) => fields.any((f) => f.key == key);

  HtmlPrintField<T> fieldByKey(String key) =>
      fields.firstWhere((field) => field.key == key);

  /// حقول القالب بترتيبه، مع تجاهل أي مفتاح لم يعد موجودًا (قالب قديم).
  List<HtmlPrintField<T>> fieldsOf(HtmlPrintTemplate template) => template
      .fieldKeys
      .where(hasField)
      .map(fieldByKey)
      .toList();
}

class HtmlPrintService {
  HtmlPrintService._();

  // ------------------------------------------------------------------
  // إدخالات اليومية والسجل
  // ------------------------------------------------------------------

  static final List<HtmlPrintField<HtmlPrintRow>> _entryFields = [
    HtmlPrintField(key: 'room_name', label: 'الغرفة (القطع)', valueOf: (r) => r.entry.displayName),
    HtmlPrintField(key: 'has_specifications', label: 'مواصفات', valueOf: (r) => r.entry.hasSpecifications ? 'نعم' : 'لا'),
    HtmlPrintField(key: 'is_partial', label: 'جزء من غرفة', valueOf: (r) => r.entry.isPartial ? 'نعم' : 'لا'),
    HtmlPrintField(key: 'part_name', label: 'اسم الجزء', valueOf: (r) => r.entry.isPartial ? r.entry.partName : ''),
    HtmlPrintField(key: 'piece_count', label: 'عدد القطع', valueOf: (r) => '${r.entry.effectivePieceCount}'),
    HtmlPrintField(key: 'standard_piece_count', label: 'العدد القياسي', valueOf: (r) => '${r.entry.pieceCountSnapshot}'),
    HtmlPrintField(key: 'specifications_piece_count', label: 'عدد قطع المواصفات', valueOf: (r) => r.entry.hasSpecifications ? '${r.entry.specialPieceCount}' : ''),
    HtmlPrintField(key: 'numbering', label: 'الترقيم', valueOf: (r) => r.entry.numbering),
    HtmlPrintField(key: 'carpenter', label: 'النجار', valueOf: (r) => r.entry.carpenter),
    HtmlPrintField(key: 'service', label: 'الخدمة', valueOf: (r) => r.entry.service),
    HtmlPrintField(key: 'installer', label: 'الرصيص', valueOf: (r) => r.entry.installer),
    HtmlPrintField(key: 'supervisor', label: 'المشرف', valueOf: (r) => r.entry.supervisor),
    HtmlPrintField(key: 'repairer', label: 'الرميم', valueOf: (r) => r.entry.repairer),
    HtmlPrintField(key: 'merchant', label: 'اسم التاجر', valueOf: (r) => r.entry.merchantName),
    HtmlPrintField(key: 'customer', label: 'اسم الزبون', valueOf: (r) => r.entry.customerName),
    HtmlPrintField(key: 'is_external', label: 'غرفة خارجية', valueOf: (r) => r.entry.isExternal ? 'نعم' : 'لا'),
    HtmlPrintField(key: 'wrap_location', label: 'مكان اللف', valueOf: (r) => r.entry.wrapLocation),
    HtmlPrintField(key: 'specifications_text', label: 'نص المواصفات', valueOf: (r) => r.entry.hasSpecifications ? r.entry.specificationsText : ''),
    HtmlPrintField(key: 'order_description', label: 'وصف الأوردر', valueOf: (r) => r.entry.orderDescription),
    HtmlPrintField(key: 'deficiencies', label: 'النواقص', valueOf: (r) => r.entry.currentDeficiencies),
    HtmlPrintField(key: 'problem', label: 'المشكلة', valueOf: (r) => r.entry.problem),
    HtmlPrintField(key: 'missing_count', label: 'عدد الناقص', valueOf: (r) => '${r.entry.currentMissingPiecesCount}'),
    HtmlPrintField(key: 'status', label: 'الحالة', valueOf: (r) => r.entry.status.label),
    HtmlPrintField(key: 'day_name', label: 'اليوم', valueOf: (r) => r.dayName ?? ''),
    HtmlPrintField(key: 'date', label: 'التاريخ', valueOf: (r) => r.date == null ? '' : AppDateFormatter.date(r.date!)),
    HtmlPrintField(key: 'session_status', label: 'حالة اليومية', valueOf: (r) => r.sessionStatus?.label ?? ''),
  ];

  static final PrintSpec<HtmlPrintRow> entriesSpec = PrintSpec<HtmlPrintRow>(
    // نفس المفتاح القديم حتى لا تضيع القوالب المخصصة المحفوظة سابقًا.
    storageKey: 'html_print_templates_v1',
    fields: _entryFields,
    defaultCustomBaseTemplateId: 'storage',
    builtInTemplates: {
      'full': HtmlPrintTemplate(
        id: 'full',
        name: 'التقرير الكامل',
        fieldKeys: _entryFields.map((e) => e.key).toList(),
      ),
      'storage': const HtmlPrintTemplate(
        id: 'storage',
        name: 'تقرير التخزين',
        fieldKeys: [
          'day_name',
          'date',
          'room_name',
          'numbering',
          'piece_count',
          'service',
          'wrap_location',
          'deficiencies',
          'missing_count',
          'status',
        ],
      ),
      'factory': const HtmlPrintTemplate(
        id: 'factory',
        name: 'تقرير المصنع',
        fieldKeys: [
          'day_name',
          'date',
          'room_name',
          'numbering',
          'carpenter',
          'service',
          'installer',
          'supervisor',
          'repairer',
          'wrap_location',
          'specifications_text',
          'deficiencies',
          'missing_count',
          'status',
        ],
      ),
    },
  );

  // ------------------------------------------------------------------
  // جدول الغرف (التبويب الأول)
  // ------------------------------------------------------------------

  static final List<HtmlPrintField<Room>> _roomFields = [
    HtmlPrintField(key: 'name', label: 'الغرفة', valueOf: (r) => r.name),
    HtmlPrintField(key: 'wood', label: 'قطع الخشب', valueOf: (r) => '${r.pieceCount}'),
    HtmlPrintField(key: 'partition', label: 'قطع القواطيع (عددها)', valueOf: (r) => r.partitionDisplay),
    HtmlPrintField(key: 'glass', label: 'قطع الزجاج', valueOf: (r) => '${r.glassPieceCount}'),
    HtmlPrintField(key: 'marble', label: 'قطع الرخام', valueOf: (r) => '${r.marblePieceCount}'),
    HtmlPrintField(key: 'total', label: 'عدد القطع الكلي', valueOf: (r) => '${r.totalPieceCount}'),
    HtmlPrintField(key: 'paper', label: 'عدد ورق الطباعة', valueOf: (r) => '${r.printPaperCount}'),
  ];

  static final PrintSpec<Room> roomsSpec = PrintSpec<Room>(
    storageKey: 'html_print_templates_rooms_v1',
    fields: _roomFields,
    defaultCustomBaseTemplateId: 'full',
    builtInTemplates: {
      'full': HtmlPrintTemplate(
        id: 'full',
        name: 'التقرير الكامل',
        fieldKeys: _roomFields.map((e) => e.key).toList(),
      ),
      'pieces': const HtmlPrintTemplate(
        id: 'pieces',
        name: 'تقرير القطع',
        fieldKeys: ['name', 'wood', 'partition', 'glass', 'marble', 'total'],
      ),
      'paper': const HtmlPrintTemplate(
        id: 'paper',
        name: 'تقرير ورق الطباعة',
        fieldKeys: ['name', 'wood', 'partition', 'paper'],
      ),
    },
  );

  // ------------------------------------------------------------------
  // العنوان والبناء
  // ------------------------------------------------------------------

  /// العنوان الرئيسي لأي تقرير: "سجل الغرف (اسم التقرير)" بدون كلمة
  /// "تقرير". مثال: "تقرير النواقص" ← "سجل الغرف (النواقص)".
  static String reportTitle(String templateName) {
    final cleaned = templateName
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty && word != 'تقرير' && word != 'التقرير')
        .join(' ')
        .trim();
    return cleaned.isEmpty ? 'سجل الغرف' : 'سجل الغرف ($cleaned)';
  }

  static String buildHtml<T>({
    required String title,
    String? subtitle,
    required PrintSpec<T> spec,
    required List<T> rows,
    required List<String> fieldKeys,
    bool landscape = true,
  }) {
    final selected = spec.fieldsOf(
      HtmlPrintTemplate(id: '_', name: '_', fieldKeys: fieldKeys),
    );
    final generatedAt = DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now());
    final safeTitle = _escape(title);
    final safeSubtitle = (subtitle == null || subtitle.trim().isEmpty)
        ? ''
        : '<div class="subtitle">${_escape(subtitle.trim())}</div>';

    final header = selected.map((f) => '<th>${_escape(f.label)}</th>').join();
    final body = StringBuffer();
    for (var i = 0; i < rows.length; i++) {
      body.write('<tr><td class="index">${i + 1}</td>');
      for (final field in selected) {
        body.write('<td>${_escape(field.valueOf(rows[i]))}</td>');
      }
      body.write('</tr>');
    }

    final storageKey = _escape(selected.map((f) => f.label).join('|'));

    return '''<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$safeTitle</title>
<style>
@page { size: A4 ${landscape ? 'landscape' : 'portrait'}; margin: 10mm; }
$_pageCss
</style>
</head>
<body data-landscape="${landscape ? '1' : '0'}">
<div class="toolbar">
  <button onclick="window.print()">🖨️ طباعة</button>
  <button onclick="window.close()">إغلاق</button>
  <span class="sep"></span>
  <button class="alt" id="btnAuto" title="ملاءمة عرض كل عمود لمحتواه">↔ ملاءمة تلقائية</button>
  <button class="alt" id="btnFill" title="توزيع الأعمدة لتملأ عرض الصفحة">⇔ ملء العرض</button>
  <button class="alt" id="btnEqual" title="جعل كل الأعمدة بعرض متساوٍ">▥ تساوي الأعمدة</button>
  <span class="sep"></span>
  <button class="alt" id="btnFontMinus" title="تصغير الخط">A−</button>
  <button class="alt" id="btnFontPlus" title="تكبير الخط">A+</button>
  <button class="alt" id="btnPadMinus" title="تقليل ارتفاع الصفوف">▁ صفوف</button>
  <button class="alt" id="btnPadPlus" title="زيادة ارتفاع الصفوف">▇ صفوف</button>
</div>
<div class="hint">اسحب حافة عنوان أي عمود بالمؤشر لتغيير عرضه، ونقرتان على الحافة لملاءمة العمود لمحتواه. تُحفظ تخصيصاتك تلقائياً على هذا الجهاز.</div>
<div class="header">
  <h1>$safeTitle</h1>
  $safeSubtitle
  <div class="meta">تم إنشاء التقرير: ${_escape(generatedAt)} — عدد السجلات: ${rows.length}</div>
</div>
<div class="table-wrap" id="wrap">
<table id="grid" data-key="$storageKey">
<thead><tr><th>م</th>$header</tr></thead>
<tbody>$body</tbody>
</table>
</div>
<div class="footer">نظام المصنع — تقرير HTML قابل للطباعة</div>
<div id="probe"></div>
<script>
$_pageJs
</script>
</body>
</html>''';
  }

  static const String _pageCss = r'''
* { box-sizing: border-box; }
body { margin: 0; padding: 12px; font-family: Tahoma, Arial, sans-serif; color: #111; direction: rtl; background: #fff; }
.toolbar { display:flex; flex-wrap:wrap; gap:8px; align-items:center; justify-content:flex-start; margin-bottom:8px; }
.toolbar .sep { width:1px; height:26px; background:#ccc; margin:0 4px; }
button { border:0; border-radius:6px; padding:9px 16px; font-size:14px; cursor:pointer; background:#222; color:#fff; font-family:inherit; }
button.alt { background:#e9ecef; color:#222; border:1px solid #c9ced3; padding:8px 12px; }
button.alt:hover { background:#dde1e5; }
.hint { font-size:12px; color:#555; margin-bottom:12px; }
.header { text-align:center; margin-bottom:14px; }
h1 { margin:0 0 5px; font-size:23px; }
.subtitle { font-size:14px; font-weight:700; margin-bottom:4px; }
.meta { color:#555; font-size:12px; }
.table-wrap { width:100%; overflow-x:auto; padding-bottom:6px; }
table { border-collapse:collapse; table-layout:auto; width:100%; margin:0 auto; font-size:11px; --pad:10px; }
thead { display:table-header-group; }
tr { page-break-inside:avoid; }
th, td { border:1px solid #777; padding:var(--pad) 5px; text-align:center; vertical-align:middle; overflow-wrap:anywhere; }
th { position:relative; background:#e9ecef; font-weight:700; user-select:none; }
tbody tr:nth-child(2n - 1) { background-color: #f1f1f1a3; }
.rz { position:absolute; top:0; bottom:0; left:-4px; width:9px; cursor:col-resize; z-index:3; touch-action:none; }
.rz::after { content:""; position:absolute; top:20%; bottom:20%; left:4px; width:2px; background:#9aa3ab; opacity:0; border-radius:1px; }
th:hover .rz::after, .rz.active::after { opacity:1; }
.rz:hover::after, .rz.active::after { background:#0d6efd; }
body.resizing, body.resizing * { cursor:col-resize !important; user-select:none !important; }
.footer { margin-top:12px; font-size:10px; color:#666; text-align:left; }
#probe { position:absolute; visibility:hidden; height:0; pointer-events:none; }
@media print {
  body { padding:0; background:#fff; }
  .toolbar, .hint, .rz { display:none !important; }
  .table-wrap { overflow:visible; }
}
''';

  static const String _pageJs = r'''
(function () {
  var table = document.getElementById('grid');
  var wrap = document.getElementById('wrap');
  var probe = document.getElementById('probe');
  var ths = Array.prototype.slice.call(table.querySelectorAll('thead th'));
  var n = ths.length;
  var MIN = 36;
  var KEY = 'almasnaa-grid:' + (table.getAttribute('data-key') || '');
  var rtl = getComputedStyle(document.documentElement).direction === 'rtl';
  var state = { w: null, fs: 11, pad: 10 };

  var cg = document.createElement('colgroup');
  for (var i = 0; i < n; i++) cg.appendChild(document.createElement('col'));
  table.insertBefore(cg, table.firstChild);
  var cols = cg.children;

  function load() {
    try {
      var raw = localStorage.getItem(KEY);
      if (!raw) return;
      var o = JSON.parse(raw);
      if (o && o.w && o.w.length === n) state.w = o.w;
      if (o && o.fs) state.fs = o.fs;
      if (o && o.pad != null) state.pad = o.pad;
    } catch (e) {}
  }
  function save() {
    try { localStorage.setItem(KEY, JSON.stringify(state)); } catch (e) {}
  }
  function clearSaved() {
    try { localStorage.removeItem(KEY); } catch (e) {}
  }

  function sum(a) { var s = 0; for (var i = 0; i < a.length; i++) s += a[i]; return s; }
  function current() {
    var a = [];
    for (var i = 0; i < n; i++) a.push(ths[i].getBoundingClientRect().width);
    return a;
  }
  function apply(w) {
    state.w = w;
    for (var i = 0; i < n; i++) cols[i].style.width = w[i] + 'px';
    table.style.tableLayout = 'fixed';
    table.style.width = sum(w) + 'px';
  }
  function applyLook() {
    table.style.fontSize = state.fs + 'px';
    table.style.setProperty('--pad', state.pad + 'px');
  }
  // قياس العرض الطبيعي (توزيع المتصفح التلقائي) ثم تثبيته.
  function autoLayout() {
    for (var i = 0; i < n; i++) cols[i].style.width = '';
    table.style.tableLayout = 'auto';
    table.style.width = '100%';
    apply(current());
  }
  // ملاءمة كل عمود لأطول محتوى فيه.
  function fitColumn(i) {
    var rows = table.rows, max = MIN, r, c, old;
    for (r = 0; r < rows.length; r++) {
      c = rows[r].cells[i];
      if (!c) continue;
      old = c.style.whiteSpace;
      c.style.whiteSpace = 'nowrap';
      max = Math.max(max, c.scrollWidth + 2);
      c.style.whiteSpace = old;
    }
    return Math.min(Math.ceil(max), 700);
  }
  function fitAll() {
    var w = [];
    for (var i = 0; i < n; i++) w.push(fitColumn(i));
    apply(w);
  }
  function fillWidth() {
    var w = state.w.slice(), total = sum(w), target = wrap.clientWidth - 2;
    if (!total) return;
    var k = target / total;
    for (var i = 0; i < n; i++) w[i] = Math.max(MIN, w[i] * k);
    apply(w);
  }
  function equalWidth() {
    var each = Math.max(MIN, (wrap.clientWidth - 2) / n), w = [];
    for (var i = 0; i < n; i++) w.push(each);
    apply(w);
  }

  // مقابض السحب على حافة كل عنوان.
  ths.forEach(function (th, i) {
    var h = document.createElement('span');
    h.className = 'rz';
    th.appendChild(h);
    var startX = 0, startW = 0, dragging = false;
    h.addEventListener('pointerdown', function (e) {
      dragging = true; startX = e.clientX; startW = state.w[i];
      h.setPointerCapture(e.pointerId);
      h.classList.add('active'); document.body.classList.add('resizing');
      e.preventDefault();
    });
    h.addEventListener('pointermove', function (e) {
      if (!dragging) return;
      var dx = e.clientX - startX;
      var nw = Math.max(MIN, startW + (rtl ? -dx : dx));
      var w = state.w.slice(); w[i] = nw;
      apply(w);
    });
    function stop() {
      if (!dragging) return;
      dragging = false; h.classList.remove('active');
      document.body.classList.remove('resizing'); save();
    }
    h.addEventListener('pointerup', stop);
    h.addEventListener('pointercancel', stop);
    h.addEventListener('dblclick', function (e) {
      e.preventDefault();
      var w = state.w.slice(); w[i] = fitColumn(i); apply(w); save();
    });
  });

  function bind(id, fn) {
    document.getElementById(id).addEventListener('click', function () { fn(); save(); });
  }
  bind('btnFill', fillWidth);
  bind('btnEqual', equalWidth);
  document.getElementById('btnAuto').addEventListener('click', function () {
    clearSaved(); state.fs = 11; state.pad = 10; applyLook(); autoLayout(); fitAll(); save();
  });
  bind('btnFontPlus', function () { state.fs = Math.min(28, state.fs + 1); applyLook(); });
  bind('btnFontMinus', function () { state.fs = Math.max(7, state.fs - 1); applyLook(); });
  bind('btnPadPlus', function () { state.pad = Math.min(40, state.pad + 2); applyLook(); });
  bind('btnPadMinus', function () { state.pad = Math.max(1, state.pad - 2); applyLook(); });

  // عند الطباعة: إن كان الجدول أعرض من الصفحة يُصغَّر ليناسبها دون تغيير النسب.
  function beforePrint() {
    var land = document.body.getAttribute('data-landscape') === '1';
    probe.style.width = land ? '277mm' : '190mm';
    var avail = probe.offsetWidth, tw = table.offsetWidth;
    if (tw > avail && avail > 0) table.style.zoom = String(avail / tw);
  }
  function afterPrint() { table.style.zoom = ''; }
  window.addEventListener('beforeprint', beforePrint);
  window.addEventListener('afterprint', afterPrint);

  load();
  applyLook();
  function init() {
    if (state.w) apply(state.w); else autoLayout();
  }
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(init); else init();
})();
''';

  static Future<void> openHtmlInBrowser({
    required String html,
    required String suggestedFileName,
  }) async {
    await browser.openHtmlInBrowser(
      html: html,
      fileName: suggestedFileName,
    );
  }

  static String _escape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;')
        .replaceAll('\n', '<br>');
  }
}
