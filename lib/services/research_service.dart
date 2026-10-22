import 'package:flutter/painting.dart' show Color;
import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';
import '../models/daily_entry.dart';
import '../models/daily_session.dart';
import '../models/enums.dart';
import '../models/person.dart';
import '../models/room.dart';
import '../utils/date_formatter.dart';
import '../utils/deficiency_calculator.dart';

/// توحيد النص العربي للبحث والمطابقة: يزيل التشكيل والتطويل، ويوحّد
/// الألف والياء والتاء المربوطة والأرقام الهندية، ويحوّل الإنجليزي لصغير.
String normalizeArabic(String input) {
  var s = input.trim().toLowerCase();
  if (s.isEmpty) return s;
  s = s.replaceAll(RegExp('[ً-ْـ]'), '');
  s = s
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll('ؤ', 'و')
      .replaceAll('ئ', 'ي');
  const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  for (var i = 0; i < arabicDigits.length; i++) {
    s = s.replaceAll(arabicDigits[i], '$i');
  }
  return s.replaceAll(RegExp(r'\s+'), ' ');
}

/// كل بيانات التطبيق المحفوظة (نفس محتوى ملف JSON): الغرف واليوميات
/// والإدخالات وقوائم الأسماء.
class ResearchData {
  final List<Room> rooms;
  final List<DailySession> sessions;
  final List<DailyEntry> entries;
  final List<Person> people;

  /// ملاحظات التدقيق التي اختار المستخدم تجاهلها (مفاتيح ثابتة).
  final Set<String> ignoredIssues;

  static const _kIgnored = 'almasnaa_audit_ignored';

  /// يتجاهل ملاحظة تدقيق نهائيًا (محليًا على هذا الجهاز).
  Future<void> ignoreIssue(String key) async {
    ignoredIssues.add(key);
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kIgnored, ignoredIssues.toList());
  }

  /// يعيد إظهار كل الملاحظات المتجاهَلة.
  Future<void> restoreIgnored() async {
    ignoredIssues.clear();
    final p = await SharedPreferences.getInstance();
    await p.remove(_kIgnored);
  }

  final Map<String, DailySession> _sessionsById;
  final Map<String, Room> _roomsById;

  ResearchData({
    required this.rooms,
    required this.sessions,
    required this.entries,
    required this.people,
    Set<String>? ignoredIssues,
  })  : ignoredIssues = ignoredIssues ?? <String>{},
        _sessionsById = {for (final s in sessions) s.id: s},
        _roomsById = {for (final r in rooms) r.id: r};

  DailySession? sessionOf(DailyEntry e) => _sessionsById[e.dailySessionId];
  Room? roomOf(DailyEntry e) => e.roomId == null ? null : _roomsById[e.roomId];

  DateTime dateOf(DailyEntry e) => sessionOf(e)?.date ?? e.createdAt;
  String dayNameOf(DailyEntry e) => sessionOf(e)?.dayName ?? '';

  /// اسم الغرفة الأساسي (من قاعدة الغرف إن وُجدت وإلا من النسخة المحفوظة).
  String roomNameOf(DailyEntry e) => (roomOf(e)?.name ?? e.baseRoomName).trim();

  static String fieldOf(DailyEntry e, PersonRole r) => switch (r) {
        PersonRole.service => e.service,
        PersonRole.carpenter => e.carpenter,
        PersonRole.installer => e.installer,
        PersonRole.supervisor => e.supervisor,
        PersonRole.repairer => e.repairer,
        PersonRole.wrapLocation => e.wrapLocation,
      };

  /// أسماء الغرف (قاعدة الغرف + ما ورد في الإدخالات) مرتبة.
  List<String> get roomNames {
    final set = <String>{
      for (final r in rooms) r.name.trim(),
      for (final e in entries) roomNameOf(e),
    }..remove('');
    return set.toList()..sort();
  }

  List<String> get dayNames {
    final set = <String>{
      for (final s in sessions) s.dayName.trim(),
    }..remove('');
    return set.toList()..sort();
  }

  /// أسماء دور معيّن: القائمة المسجلة + ما ورد في الإدخالات.
  List<String> namesFor(PersonRole role) {
    final set = <String>{
      for (final p in people)
        if (p.role == role) p.name.trim(),
      for (final e in entries) fieldOf(e, role).trim(),
    }..remove('');
    return set.toList()..sort();
  }

  static Future<ResearchData> load() async {
    final db = AppDatabase.instance;
    final rooms =
        (await db.readList(AppDatabase.roomsKey)).map(Room.fromMap).toList();
    final sessions = (await db.readList(AppDatabase.sessionsKey))
        .map(DailySession.fromMap)
        .toList();
    final entries = (await db.readList(AppDatabase.entriesKey))
        .map(DailyEntry.fromMap)
        .toList();
    final people =
        (await db.readList(AppDatabase.peopleKey)).map(Person.fromMap).toList();
    final prefs = await SharedPreferences.getInstance();
    return ResearchData(
        rooms: rooms,
        sessions: sessions,
        entries: entries,
        people: people,
        ignoredIssues: (prefs.getStringList(_kIgnored) ?? const <String>[]).toSet());
  }
}

enum ResearchView {
  overview('ملخص عام', 'مؤشرات شاملة عن الإنتاج والجودة وأفضل الأسماء.'),
  rooms('الغرف', 'كل غرفة مع عدد مرات إنتاجها ونسبة اكتمالها وآخر إنتاج.'),
  sessions('اليوميات', 'كل يومية: مدتها وعدد الغرف والقطع ونسبة الاكتمال.'),
  entries('السجلات', 'كل إدخال إنتاج بتفاصيله الكاملة. اضغط على أي صف لعرض تفاصيله.'),
  grouped('تجميع الإنتاج', 'إحصاءات مجمّعة حسب الغرفة أو الاسم أو التاريخ أو الشهر...'),
  deficiencies('النواقص المتكررة', 'كل قطعة ناقصة: كم مرة نقصت وكم تم استكماله ومن الأكثر ارتباطًا بها.'),
  problems('المشاكل', 'المشاكل المسجلة مجمّعة حسب النص مع الغرف المتأثرة.'),
  people('الأسماء', 'أداء كل اسم: إنتاجه ونسبة الاكتمال والنواقص المرتبطة به.'),
  audit('تدقيق البيانات', 'فحص آلي للتناقضات والبيانات الناقصة والتكرار في كل الجداول.');

  final String label;
  final String description;
  const ResearchView(this.label, this.description);
}

enum ResearchGroup {
  room('الغرفة'),
  carpenter('النجار'),
  service('الخدمة'),
  installer('الرصيص'),
  supervisor('المشرف'),
  repairer('الرميم'),
  wrapLocation('مكان اللف'),
  merchant('التاجر'),
  dayName('اليوم'),
  date('التاريخ'),
  month('الشهر'),
  status('الحالة'),
  shape('الشكل');

  final String label;
  const ResearchGroup(this.label);
}

enum ResearchShape {
  regular('عادية'),
  specs('مواصفات'),
  partial('جزء من غرفة');

  final String label;
  const ResearchShape(this.label);
}

class ResearchFilters {
  final String keyword;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final RoomEntryStatus? status;
  final ResearchShape? shape;

  /// ملكية الغرفة: داخلية / خارجية / أوردر.
  final RoomOwnership? ownership;

  /// اسم الغرفة الأساسي.
  final String? room;

  /// اسم اليوم (السبت، الأحد...).
  final String? dayName;

  /// فلتر لكل دور (نجار/مشرف/...): الاسم المطلوب.
  final Map<PersonRole, String> people;

  /// إدخالات لها مشكلة مسجلة فقط.
  final bool onlyWithProblem;

  /// إدخالات عُدّلت نواقصها بعد الإنتاج فقط.
  final bool onlyModified;

  const ResearchFilters({
    this.keyword = '',
    this.dateFrom,
    this.dateTo,
    this.status,
    this.shape,
    this.ownership,
    this.room,
    this.dayName,
    this.people = const {},
    this.onlyWithProblem = false,
    this.onlyModified = false,
  });

  ResearchFilters copyWith({
    String? keyword,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool clearFrom = false,
    bool clearTo = false,
    RoomEntryStatus? status,
    bool clearStatus = false,
    ResearchShape? shape,
    bool clearShape = false,
    RoomOwnership? ownership,
    bool clearOwnership = false,
    String? room,
    bool clearRoom = false,
    String? dayName,
    bool clearDayName = false,
    bool? onlyWithProblem,
    bool? onlyModified,
  }) {
    return ResearchFilters(
      keyword: keyword ?? this.keyword,
      dateFrom: clearFrom ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearTo ? null : (dateTo ?? this.dateTo),
      status: clearStatus ? null : (status ?? this.status),
      shape: clearShape ? null : (shape ?? this.shape),
      ownership: clearOwnership ? null : (ownership ?? this.ownership),
      room: clearRoom ? null : (room ?? this.room),
      dayName: clearDayName ? null : (dayName ?? this.dayName),
      people: people,
      onlyWithProblem: onlyWithProblem ?? this.onlyWithProblem,
      onlyModified: onlyModified ?? this.onlyModified,
    );
  }

  /// نسخة بعد ضبط (أو مسح عند null) فلتر دور معيّن.
  ResearchFilters withPerson(PersonRole role, String? name) {
    final next = {...people};
    if (name == null || name.isEmpty) {
      next.remove(role);
    } else {
      next[role] = name;
    }
    return ResearchFilters(
      keyword: keyword,
      dateFrom: dateFrom,
      dateTo: dateTo,
      status: status,
      shape: shape,
      ownership: ownership,
      room: room,
      dayName: dayName,
      people: next,
      onlyWithProblem: onlyWithProblem,
      onlyModified: onlyModified,
    );
  }

  /// هل توجد فلاتر تخص الإدخالات (غير التاريخ والكلمة المفتاحية)؟
  bool get hasEntryFilters =>
      status != null ||
      shape != null ||
      ownership != null ||
      room != null ||
      dayName != null ||
      people.isNotEmpty ||
      onlyWithProblem ||
      onlyModified;

  bool get isEmpty =>
      keyword.trim().isEmpty &&
      dateFrom == null &&
      dateTo == null &&
      !hasEntryFilters;

  /// عدد الفلاتر المفعّلة (للعرض على زر الفلاتر).
  int get activeCount =>
      (keyword.trim().isEmpty ? 0 : 1) +
      (dateFrom == null ? 0 : 1) +
      (dateTo == null ? 0 : 1) +
      (status == null ? 0 : 1) +
      (shape == null ? 0 : 1) +
      (ownership == null ? 0 : 1) +
      (room == null ? 0 : 1) +
      (dayName == null ? 0 : 1) +
      people.length +
      (onlyWithProblem ? 1 : 0) +
      (onlyModified ? 1 : 0);

  /// وصف نصي للفلاتر المطبّقة (للعنوان الفرعي في الطباعة).
  String describe() {
    final parts = <String>[];
    if (keyword.trim().isNotEmpty) parts.add('بحث: ${keyword.trim()}');
    if (dateFrom != null) parts.add('من ${AppDateFormatter.date(dateFrom!)}');
    if (dateTo != null) parts.add('إلى ${AppDateFormatter.date(dateTo!)}');
    if (status != null) parts.add('الحالة: ${status!.label}');
    if (shape != null) parts.add('الشكل: ${shape!.label}');
    if (ownership != null) parts.add('الملكية: ${ownership!.label}');
    if (room != null) parts.add('الغرفة: $room');
    if (dayName != null) parts.add('اليوم: $dayName');
    for (final r in PersonRole.values) {
      final n = people[r];
      if (n != null) parts.add('${r.label}: $n');
    }
    if (onlyWithProblem) parts.add('بمشكلة مسجلة');
    if (onlyModified) parts.add('نواقص معدّلة');
    return parts.join(' — ');
  }
}

class ResearchColumn {
  final String key;
  final String label;
  final double width;
  final bool numeric;
  final bool singleLine;

  const ResearchColumn(this.key, this.label,
      {this.width = 120, this.numeric = false, this.singleLine = false});
}

/// صف نتيجة: نص العرض لكل عمود، وقيمة رقمية اختيارية للترتيب.
class ResearchRow {
  final Map<String, String> text;
  final Map<String, num> sort;
  final Color? tint;

  /// معرّف ثابت اختياري (يُستخدم لتجاهل ملاحظة تدقيق).
  final String? id;

  const ResearchRow({
    required this.text,
    this.sort = const {},
    this.tint,
    this.id,
  });

  String value(String key) => text[key] ?? '';
}

class ResearchStat {
  final String label;
  final String value;
  const ResearchStat(this.label, this.value);
}

class ResearchTable {
  final ResearchView view;
  final List<ResearchColumn> columns;
  final List<ResearchRow> rows;
  final List<ResearchStat> stats;

  /// صف الإجماليات (يُعرض أسفل الجدول ولا يدخل في الترتيب).
  final ResearchRow? footer;

  const ResearchTable({
    required this.view,
    required this.columns,
    required this.rows,
    required this.stats,
    this.footer,
  });
}

class ResearchService {
  ResearchService._();

  static const Color _greenTint = Color(0x332E7D32);
  static const Color _redTint = Color(0x33C62828);
  static const Color _amberTint = Color(0x33FFA700);
  static const Color _footerTint = Color(0x261F4E5F);

  // ------------------------------------------------------------------
  // الفلترة
  // ------------------------------------------------------------------

  static bool _inDateRange(DateTime d, ResearchFilters f) {
    final day = DateTime(d.year, d.month, d.day);
    if (f.dateFrom != null) {
      final from = DateTime(f.dateFrom!.year, f.dateFrom!.month, f.dateFrom!.day);
      if (day.isBefore(from)) return false;
    }
    if (f.dateTo != null) {
      final to = DateTime(f.dateTo!.year, f.dateTo!.month, f.dateTo!.day);
      if (day.isAfter(to)) return false;
    }
    return true;
  }

  static ResearchShape _shapeOf(DailyEntry e) => e.isPartial
      ? ResearchShape.partial
      : (e.hasSpecifications ? ResearchShape.specs : ResearchShape.regular);

  /// بحث بكلمات متعددة (كل كلمة يجب أن تظهر في أي حقل) مع توحيد العربية.
  static bool _matchesKeyword(ResearchData data, DailyEntry e, String keyword) {
    final q = normalizeArabic(keyword);
    if (q.isEmpty) return true;
    final hay = normalizeArabic([
      e.roomNameSnapshot,
      data.roomNameOf(e),
      e.numbering,
      e.carpenter,
      e.service,
      e.installer,
      e.supervisor,
      e.repairer,
      e.wrapLocation,
      e.merchantName,
      e.customerName,
      e.ownership.label,
      e.specificationsText,
      e.partName,
      e.originalDeficiencies,
      e.currentDeficiencies,
      e.problem,
      data.dayNameOf(e),
      AppDateFormatter.date(data.dateOf(e)),
      e.status.label,
      _shapeOf(e).label,
      '${e.effectivePieceCount}',
    ].join(' | '));
    return q.split(' ').where((t) => t.isNotEmpty).every(hay.contains);
  }

  /// الإدخالات بعد تطبيق كل الفلاتر (والكلمة المفتاحية اختياريًا).
  static List<DailyEntry> filterEntries(
    ResearchData data,
    ResearchFilters f, {
    bool useKeyword = true,
  }) {
    return data.entries.where((e) {
      if (!_inDateRange(data.dateOf(e), f)) return false;
      if (f.status != null && e.status != f.status) return false;
      if (f.shape != null && _shapeOf(e) != f.shape) return false;
      if (f.ownership != null && e.ownership != f.ownership) return false;
      if (f.room != null && data.roomNameOf(e) != f.room) return false;
      if (f.dayName != null && data.dayNameOf(e).trim() != f.dayName) {
        return false;
      }
      for (final entry in f.people.entries) {
        if (ResearchData.fieldOf(e, entry.key).trim() != entry.value) {
          return false;
        }
      }
      if (f.onlyWithProblem && e.problem.trim().isEmpty) return false;
      if (f.onlyModified && !e.wasEverModified) return false;
      if (useKeyword && !_matchesKeyword(data, e, f.keyword)) return false;
      return true;
    }).toList();
  }

  // ------------------------------------------------------------------
  // أدوات مساعدة
  // ------------------------------------------------------------------

  static String _pct(num part, num whole) =>
      whole == 0 ? '0%' : '${(part * 100 / whole).toStringAsFixed(1)}%';

  static String _avg(num total, num count) =>
      count == 0 ? '0' : (total / count).toStringAsFixed(1);

  static ResearchRow _row(Map<String, String> text,
          {Map<String, num> sort = const {}, Color? tint, String? id}) =>
      ResearchRow(text: text, sort: sort, tint: tint, id: id);

  static ResearchRow _footer(Map<String, String> text) =>
      ResearchRow(text: text, tint: _footerTint);

  static Color _tintOf(RoomEntryStatus s) =>
      s == RoomEntryStatus.completed ? _greenTint : _redTint;

  static int _sumPieces(Iterable<DailyEntry> es) =>
      es.fold<int>(0, (a, e) => a + e.effectivePieceCount);
  static int _sumMissing(Iterable<DailyEntry> es) =>
      es.fold<int>(0, (a, e) => a + e.currentMissingPiecesCount);
  static int _sumOriginalMissing(Iterable<DailyEntry> es) =>
      es.fold<int>(0, (a, e) => a + e.originalMissingPiecesCount);
  static int _completed(Iterable<DailyEntry> es) =>
      es.where((e) => e.status == RoomEntryStatus.completed).length;
  static int _withProblem(Iterable<DailyEntry> es) =>
      es.where((e) => e.problem.trim().isNotEmpty).length;

  /// القطع التي تم استكمالها بعد الإنتاج (الأصلي − الحالي، بحد أدنى صفر لكل إدخال).
  static int _resolvedPieces(Iterable<DailyEntry> es) => es.fold<int>(0, (a, e) {
        final diff = e.originalMissingPiecesCount - e.currentMissingPiecesCount;
        return a + (diff > 0 ? diff : 0);
      });

  static String _dayDate(DateTime d) => AppDateFormatter.date(d);

  static String _monthOf(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _duration(DateTime start, DateTime? end) {
    if (end == null) return '';
    final m = end.difference(start).inMinutes;
    if (m < 0) return 'غير منطقية';
    final h = m ~/ 60;
    final r = m % 60;
    if (h == 0) return '$r د';
    return r == 0 ? '$h س' : '$h س $r د';
  }

  /// أكثر اسم تكرارًا في القائمة بصيغة "الاسم (العدد)".
  static String _top(Iterable<String> names) {
    final counts = <String, int>{};
    for (final raw in names) {
      final n = raw.trim();
      if (n.isEmpty) continue;
      counts[n] = (counts[n] ?? 0) + 1;
    }
    if (counts.isEmpty) return '';
    final best = counts.entries.reduce((a, b) {
      if (a.value != b.value) return a.value > b.value ? a : b;
      return a.key.compareTo(b.key) <= 0 ? a : b;
    });
    return '${best.key} (${best.value})';
  }

  static DateTime? _maxDate(Iterable<DateTime> ds) {
    DateTime? m;
    for (final d in ds) {
      if (m == null || d.isAfter(m)) m = d;
    }
    return m;
  }

  static DateTime? _minDate(Iterable<DateTime> ds) {
    DateTime? m;
    for (final d in ds) {
      if (m == null || d.isBefore(m)) m = d;
    }
    return m;
  }

  /// يقسّم نص النواقص إلى عناصر مفردة (مفصولة بـ "-") بلا تكرار.
  static Map<String, String> _items(String text) {
    final out = <String, String>{};
    for (final raw in text.split('-')) {
      final item = raw.trim();
      if (item.isEmpty) continue;
      out.putIfAbsent(normalizeArabic(item), () => item);
    }
    return out;
  }

  // ------------------------------------------------------------------
  // بناء الجداول
  // ------------------------------------------------------------------

  static ResearchTable build(
    ResearchView view,
    ResearchData data,
    ResearchFilters filters, {
    ResearchGroup group = ResearchGroup.room,
  }) {
    switch (view) {
      case ResearchView.overview:
        return _overview(data, filters);
      case ResearchView.rooms:
        return _rooms(data, filters);
      case ResearchView.sessions:
        return _sessions(data, filters);
      case ResearchView.entries:
        return _entries(data, filters);
      case ResearchView.grouped:
        return _grouped(data, filters, group);
      case ResearchView.deficiencies:
        return _deficiencies(data, filters);
      case ResearchView.problems:
        return _problems(data, filters);
      case ResearchView.people:
        return _people(data, filters);
      case ResearchView.audit:
        return _audit(data, filters);
    }
  }

  // ---------------------------- الملخص العام ------------------------

  static ResearchTable _overview(ResearchData d, ResearchFilters f) {
    final es = filterEntries(d, f);
    final completed = _completed(es);
    final sessionsInRange = d.sessions.where((s) => _inDateRange(s.date, f)).toList();
    final closed =
        sessionsInRange.where((s) => s.status == DailySessionStatus.closed).length;
    final active = sessionsInRange.length - closed;
    final dates = es.map(d.dateOf).toList()..sort();
    int sumRooms(int Function(Room r) fn) => d.rooms.fold<int>(0, (a, r) => a + fn(r));

    // أفضل يوم من حيث القطع.
    final piecesByDay = <DateTime, int>{};
    for (final e in es) {
      final dt = d.dateOf(e);
      final day = DateTime(dt.year, dt.month, dt.day);
      piecesByDay[day] = (piecesByDay[day] ?? 0) + e.effectivePieceCount;
    }
    MapEntry<DateTime, int>? bestDay;
    MapEntry<DateTime, int>? worstDay;
    for (final en in piecesByDay.entries) {
      if (bestDay == null || en.value > bestDay.value) bestDay = en;
      if (worstDay == null || en.value < worstDay.value) worstDay = en;
    }
    final daysCount = piecesByDay.length;
    final totalPieces = _sumPieces(es);
    final issues = _auditIssues(d, f);
    final highIssues = issues.where((i) => i.severity == 1).length;

    final items = <List<String>>[
      // الغرف
      ['الغرف', 'الغرف المسجلة', '${d.rooms.length}', 'عدد الغرف في قاعدة الغرف'],
      ['الغرف', 'إجمالي قطع الخشب', '${sumRooms((r) => r.pieceCount)}', 'مجموع قطع الخشب لكل الغرف'],
      ['الغرف', 'إجمالي قطع القواطيع', '${sumRooms((r) => r.partitionPieceCount)}', ''],
      ['الغرف', 'إجمالي قطع الزجاج', '${sumRooms((r) => r.glassPieceCount)}', ''],
      ['الغرف', 'إجمالي قطع الرخام', '${sumRooms((r) => r.marblePieceCount)}', ''],
      ['الغرف', 'إجمالي القطع الكلي', '${sumRooms((r) => r.totalPieceCount)}', 'خشب + قواطيع + زجاج + رخام'],
      ['الغرف', 'إجمالي ورق الطباعة', '${sumRooms((r) => r.printPaperCount)}', 'خشب + قواطيع'],
      // الإنتاج
      ['الإنتاج', 'اليوميات', '${sessionsInRange.length}', 'مغلقة: $closed — نشطة: $active'],
      [
        'الإنتاج',
        'فترة الإنتاج',
        dates.isEmpty ? '-' : _dayDate(dates.first),
        dates.isEmpty ? '' : 'إلى ${_dayDate(dates.last)}',
      ],
      ['الإنتاج', 'أيام العمل الفعلية', '$daysCount', 'عدد الأيام التي سُجّل فيها إنتاج'],
      ['الإنتاج', 'إدخالات الإنتاج', '${es.length}', 'إجمالي الغرف المسجلة في اليوميات'],
      ['الإنتاج', 'إجمالي القطع المنتجة', '$totalPieces', 'مجموع عدد القطع الفعلي للإدخالات'],
      ['الإنتاج', 'متوسط الغرف في اليومية', _avg(es.length, sessionsInRange.length), ''],
      ['الإنتاج', 'متوسط القطع في اليوم', _avg(totalPieces, daysCount), 'على أيام العمل الفعلية'],
      [
        'الإنتاج',
        'أفضل يوم إنتاجًا',
        bestDay == null ? '-' : '${bestDay.value}',
        bestDay == null ? '' : '${AppDateFormatter.dayName(bestDay.key)} ${_dayDate(bestDay.key)}',
      ],
      [
        'الإنتاج',
        'أقل يوم إنتاجًا',
        worstDay == null ? '-' : '${worstDay.value}',
        worstDay == null ? '' : '${AppDateFormatter.dayName(worstDay.key)} ${_dayDate(worstDay.key)}',
      ],
      // الجودة
      ['الجودة', 'المكتملة', '$completed', 'نسبة الاكتمال ${_pct(completed, es.length)}'],
      ['الجودة', 'التي بها نواقص', '${es.length - completed}', 'نسبتها ${_pct(es.length - completed, es.length)}'],
      [
        'الجودة',
        'القطع الناقصة (الحالية)',
        '${_sumMissing(es)}',
        'الأصلية وقت الإنتاج: ${_sumOriginalMissing(es)} — تم استكمال: ${_resolvedPieces(es)}',
      ],
      [
        'الجودة',
        'نسبة القطع الناقصة',
        _pct(_sumMissing(es), totalPieces),
        'الناقص الحالي من إجمالي القطع المنتجة',
      ],
      ['الجودة', 'إدخالات بمشكلة مسجلة', '${_withProblem(es)}', ''],
      ['الجودة', 'إدخالات نواقصها معدّلة', '${es.where((e) => e.wasEverModified).length}', 'عُدّلت نواقصها بعد الإنتاج'],
      ['الجودة', 'إدخالات بمواصفات', '${es.where((e) => e.hasSpecifications).length}', ''],
      ['الجودة', 'إدخالات جزء من غرفة', '${es.where((e) => e.isPartial).length}', ''],
      // الأسماء
      [
        'الأسماء',
        'الأسماء المسجلة',
        '${d.people.length}',
        PersonRole.values
            .map((r) => '${r.label}: ${d.people.where((p) => p.role == r).length}')
            .join(' — '),
      ],
      for (final r in PersonRole.values)
        () {
          final names = es.map((e) => ResearchData.fieldOf(e, r));
          final top = _top(names);
          final withMissing = _top(es
              .where((e) => e.status == RoomEntryStatus.pending)
              .map((e) => ResearchData.fieldOf(e, r)));
          return [
            'الأسماء',
            'الأكثر إنتاجًا — ${r.label}',
            top.isEmpty ? '-' : top.split(' (').first,
            top.isEmpty
                ? ''
                : 'عدد الإدخالات: ${top.split(' (').last.replaceAll(')', '')}'
                    '${withMissing.isEmpty ? '' : ' — الأكثر نواقص: $withMissing'}',
          ];
        }(),
      [
        'الأسماء',
        'الغرفة الأكثر إنتاجًا',
        _top(es.map(d.roomNameOf)).isEmpty ? '-' : _top(es.map(d.roomNameOf)).split(' (').first,
        _top(es.map(d.roomNameOf)).isEmpty
            ? ''
            : 'مرات الإنتاج: ${_top(es.map(d.roomNameOf)).split(' (').last.replaceAll(')', '')}',
      ],
      // سلامة البيانات
      [
        'سلامة البيانات',
        'ملاحظات التدقيق',
        '${issues.length}',
        'عالية الأهمية: $highIssues — راجع تبويب «تدقيق البيانات»',
      ],
    ];

    return ResearchTable(
      view: ResearchView.overview,
      columns: const [
        ResearchColumn('section', 'القسم', width: 130),
        ResearchColumn('item', 'البند', width: 240),
        ResearchColumn('value', 'القيمة', width: 150, numeric: true),
        ResearchColumn('details', 'تفاصيل', width: 440),
      ],
      rows: [
        for (final i in items)
          _row({'section': i[0], 'item': i[1], 'value': i[2], 'details': i[3]}),
      ],
      stats: [
        ResearchStat('الغرف', '${d.rooms.length}'),
        ResearchStat('اليوميات', '${sessionsInRange.length}'),
        ResearchStat('الإدخالات', '${es.length}'),
        ResearchStat('القطع المنتجة', '$totalPieces'),
        ResearchStat('نسبة الاكتمال', _pct(completed, es.length)),
        ResearchStat('ملاحظات التدقيق', '${issues.length}'),
      ],
    );
  }

  // ------------------------------- الغرف ----------------------------

  static ResearchTable _rooms(ResearchData d, ResearchFilters f) {
    final used = filterEntries(d, f, useKeyword: false);
    final byRoom = <String, List<DailyEntry>>{};
    for (final e in used) {
      if (e.roomId != null) byRoom.putIfAbsent(e.roomId!, () => []).add(e);
    }
    final kw = normalizeArabic(f.keyword);
    final rooms = d.rooms
        .where((r) => f.room == null || r.name.trim() == f.room)
        .where((r) => kw.isEmpty || normalizeArabic(r.name).contains(kw))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final rows = <ResearchRow>[];
    var tWood = 0, tPart = 0, tGlass = 0, tMarble = 0, tTotal = 0, tPaper = 0;
    var tTimes = 0, tFull = 0, tPartial = 0, tMissing = 0, tPieces = 0, tDone = 0;
    for (final r in rooms) {
      final es = byRoom[r.id] ?? const <DailyEntry>[];
      final last = _maxDate(es.map(d.dateOf));
      final first = _minDate(es.map(d.dateOf));
      final done = _completed(es);
      final full = es.where((e) => !e.isPartial).length;
      final partial = es.length - full;
      final missing = _sumMissing(es);
      final pieces = _sumPieces(es);
      tWood += r.pieceCount;
      tPart += r.partitionPieceCount;
      tGlass += r.glassPieceCount;
      tMarble += r.marblePieceCount;
      tTotal += r.totalPieceCount;
      tPaper += r.printPaperCount;
      tTimes += es.length;
      tFull += full;
      tPartial += partial;
      tMissing += missing;
      tPieces += pieces;
      tDone += done;
      rows.add(_row({
        'name': r.name,
        'wood': '${r.pieceCount}',
        'partition': r.partitionDisplay,
        'glass': '${r.glassPieceCount}',
        'marble': '${r.marblePieceCount}',
        'total': '${r.totalPieceCount}',
        'paper': '${r.printPaperCount}',
        'times': '${es.length}',
        'full': '$full',
        'partial': '$partial',
        'done': '$done',
        'rate': es.isEmpty ? '' : _pct(done, es.length),
        'pieces': '$pieces',
        'missing': '$missing',
        'problems': '${_withProblem(es)}',
        'carpenter': _top(es.map((e) => e.carpenter)),
        'first': first == null ? '' : _dayDate(first),
        'last': last == null ? '' : _dayDate(last),
      }, sort: {
        'wood': r.pieceCount,
        'partition': r.partitionPieceCount,
        'glass': r.glassPieceCount,
        'marble': r.marblePieceCount,
        'total': r.totalPieceCount,
        'paper': r.printPaperCount,
        'times': es.length,
        'full': full,
        'partial': partial,
        'done': done,
        'rate': es.isEmpty ? -1 : done / es.length,
        'pieces': pieces,
        'missing': missing,
        'problems': _withProblem(es),
        'first': first?.millisecondsSinceEpoch ?? 0,
        'last': last?.millisecondsSinceEpoch ?? 0,
      }));
    }

    return ResearchTable(
      view: ResearchView.rooms,
      columns: const [
        ResearchColumn('name', 'الغرفة', width: 230),
        ResearchColumn('wood', 'قطع الخشب', width: 100, numeric: true),
        ResearchColumn('partition', 'قطع القواطيع (عددها)',
            width: 175, numeric: true, singleLine: true),
        ResearchColumn('glass', 'قطع الزجاج', width: 100, numeric: true),
        ResearchColumn('marble', 'قطع الرخام', width: 100, numeric: true),
        ResearchColumn('total', 'عدد القطع الكلي', width: 120, numeric: true),
        ResearchColumn('paper', 'عدد ورق الطباعة', width: 130, numeric: true),
        ResearchColumn('times', 'مرات الإنتاج', width: 110, numeric: true),
        ResearchColumn('full', 'كاملة', width: 80, numeric: true),
        ResearchColumn('partial', 'أجزاء', width: 80, numeric: true),
        ResearchColumn('done', 'مكتملة', width: 90, numeric: true),
        ResearchColumn('rate', 'نسبة الاكتمال', width: 110, numeric: true),
        ResearchColumn('pieces', 'القطع المنتجة', width: 110, numeric: true),
        ResearchColumn('missing', 'الناقص الحالي', width: 110, numeric: true),
        ResearchColumn('problems', 'بمشكلة', width: 90, numeric: true),
        ResearchColumn('carpenter', 'النجار الأكثر', width: 160),
        ResearchColumn('first', 'أول إنتاج', width: 125),
        ResearchColumn('last', 'آخر إنتاج', width: 125),
      ],
      rows: rows,
      footer: _footer({
        'name': 'الإجمالي (${rows.length})',
        'wood': '$tWood',
        'partition': '$tPart',
        'glass': '$tGlass',
        'marble': '$tMarble',
        'total': '$tTotal',
        'paper': '$tPaper',
        'times': '$tTimes',
        'full': '$tFull',
        'partial': '$tPartial',
        'done': '$tDone',
        'rate': tTimes == 0 ? '' : _pct(tDone, tTimes),
        'pieces': '$tPieces',
        'missing': '$tMissing',
      }),
      stats: [
        ResearchStat('عدد الغرف', '${rows.length}'),
        ResearchStat('إجمالي القطع', '$tTotal'),
        ResearchStat('إجمالي ورق الطباعة', '$tPaper'),
        ResearchStat('مرات الإنتاج', '$tTimes'),
        ResearchStat('غرف لم تُنتج', '${rows.where((r) => r.value('times') == '0').length}'),
      ],
    );
  }

  // ----------------------------- اليوميات ---------------------------

  static ResearchTable _sessions(ResearchData d, ResearchFilters f) {
    final kw = normalizeArabic(f.keyword);
    final filtered = filterEntries(d, f, useKeyword: false);
    final bySession = <String, List<DailyEntry>>{};
    for (final e in filtered) {
      bySession.putIfAbsent(e.dailySessionId, () => []).add(e);
    }

    final sessions = d.sessions.where((s) {
      if (!_inDateRange(s.date, f)) return false;
      if (f.dayName != null && s.dayName.trim() != f.dayName) return false;
      if (f.hasEntryFilters && !(bySession[s.id]?.isNotEmpty ?? false)) {
        return false;
      }
      if (kw.isEmpty) return true;
      final hay = normalizeArabic(
          '${s.dayName} ${AppDateFormatter.date(s.date)} ${s.status.label}');
      return kw.split(' ').every(hay.contains);
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final rows = <ResearchRow>[];
    var tRooms = 0, tDone = 0, tPieces = 0, tMissing = 0, tOriginal = 0;
    for (final s in sessions) {
      final es = bySession[s.id] ?? const <DailyEntry>[];
      final done = _completed(es);
      final pieces = _sumPieces(es);
      final missing = _sumMissing(es);
      final original = _sumOriginalMissing(es);
      tRooms += es.length;
      tDone += done;
      tPieces += pieces;
      tMissing += missing;
      tOriginal += original;
      final minutes = s.endTime?.difference(s.startTime).inMinutes;
      rows.add(_row({
        'day': s.dayName,
        'date': AppDateFormatter.date(s.date),
        'start': AppDateFormatter.time(s.startTime),
        'end': AppDateFormatter.endTimeOrPending(s.endTime),
        'duration': _duration(s.startTime, s.endTime),
        'status': s.status.label,
        'rooms': '${es.length}',
        'done': '$done',
        'pending': '${es.length - done}',
        'rate': es.isEmpty ? '' : _pct(done, es.length),
        'pieces': '$pieces',
        'missing': '$missing',
        'original': '$original',
        'problems': '${_withProblem(es)}',
        'specs': '${es.where((e) => e.hasSpecifications).length}',
        'partial': '${es.where((e) => e.isPartial).length}',
      }, sort: {
        'date': s.date.millisecondsSinceEpoch,
        'start': s.startTime.millisecondsSinceEpoch,
        'duration': minutes ?? -1,
        'rooms': es.length,
        'done': done,
        'pending': es.length - done,
        'rate': es.isEmpty ? -1 : done / es.length,
        'pieces': pieces,
        'missing': missing,
        'original': original,
        'problems': _withProblem(es),
        'specs': es.where((e) => e.hasSpecifications).length,
        'partial': es.where((e) => e.isPartial).length,
      }, tint: s.isActive ? _amberTint : null));
    }

    return ResearchTable(
      view: ResearchView.sessions,
      columns: const [
        ResearchColumn('day', 'اليوم', width: 100),
        ResearchColumn('date', 'التاريخ', width: 125),
        ResearchColumn('start', 'بدء اليومية', width: 110),
        ResearchColumn('end', 'انتهاء اليومية', width: 120),
        ResearchColumn('duration', 'المدة', width: 100),
        ResearchColumn('status', 'الحالة', width: 130),
        ResearchColumn('rooms', 'عدد الغرف', width: 100, numeric: true),
        ResearchColumn('done', 'مكتملة', width: 90, numeric: true),
        ResearchColumn('pending', 'بها نواقص', width: 100, numeric: true),
        ResearchColumn('rate', 'نسبة الاكتمال', width: 110, numeric: true),
        ResearchColumn('pieces', 'مجموع القطع', width: 110, numeric: true),
        ResearchColumn('missing', 'الناقص الحالي', width: 110, numeric: true),
        ResearchColumn('original', 'الناقص الأصلي', width: 110, numeric: true),
        ResearchColumn('problems', 'بمشكلة', width: 90, numeric: true),
        ResearchColumn('specs', 'مواصفات', width: 90, numeric: true),
        ResearchColumn('partial', 'أجزاء', width: 80, numeric: true),
      ],
      rows: rows,
      footer: _footer({
        'day': 'الإجمالي (${rows.length})',
        'rooms': '$tRooms',
        'done': '$tDone',
        'pending': '${tRooms - tDone}',
        'rate': tRooms == 0 ? '' : _pct(tDone, tRooms),
        'pieces': '$tPieces',
        'missing': '$tMissing',
        'original': '$tOriginal',
      }),
      stats: [
        ResearchStat('عدد اليوميات', '${rows.length}'),
        ResearchStat('الغرف المنتجة', '$tRooms'),
        ResearchStat('مجموع القطع', '$tPieces'),
        ResearchStat('متوسط الغرف/يومية', _avg(tRooms, rows.length)),
        ResearchStat('متوسط القطع/يومية', _avg(tPieces, rows.length)),
      ],
    );
  }

  // ----------------------------- السجلات ----------------------------

  static ResearchTable _entries(ResearchData d, ResearchFilters f) {
    final es = filterEntries(d, f)
      ..sort((a, b) {
        final byDate = d.dateOf(b).compareTo(d.dateOf(a));
        return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
      });

    final rows = [
      for (final e in es)
        _row({
          'day': d.dayNameOf(e),
          'date': AppDateFormatter.date(d.dateOf(e)),
          'room': e.displayName,
          'shape': _shapeOf(e).label,
          'numbering': e.numbering,
          'carpenter': e.carpenter,
          'service': e.service,
          'installer': e.installer,
          'supervisor': e.supervisor,
          'repairer': e.repairer,
          'merchant': e.merchantName,
          'customer': e.customerName,
          'external': e.isExternal ? 'نعم' : 'لا',
          'wrap': e.wrapLocation,
          'pieces': '${e.effectivePieceCount}',
          'standard': '${e.pieceCountSnapshot}',
          'specs': e.hasSpecifications ? e.specificationsText : '',
          'order_desc': e.orderDescription,
          'partial': e.isPartial ? e.partName : '',
          'original_def': e.originalDeficiencies,
          'current_def': e.currentDeficiencies,
          'problem': e.problem,
          'original_missing': '${e.originalMissingPiecesCount}',
          'missing': '${e.currentMissingPiecesCount}',
          'resolved': '${(e.originalMissingPiecesCount - e.currentMissingPiecesCount) > 0 ? e.originalMissingPiecesCount - e.currentMissingPiecesCount : 0}',
          'status': e.status.label,
          'session_status': d.sessionOf(e)?.status.label ?? 'غير موجودة',
          'modified': e.wasEverModified ? 'نعم' : 'لا',
          'created': AppDateFormatter.dateTime(e.createdAt),
          'def_updated': e.lastDeficiencyUpdateAt == null
              ? ''
              : AppDateFormatter.dateTime(e.lastDeficiencyUpdateAt!),
        }, sort: {
          'date': d.dateOf(e).millisecondsSinceEpoch,
          'pieces': e.effectivePieceCount,
          'standard': e.pieceCountSnapshot,
          'original_missing': e.originalMissingPiecesCount,
          'missing': e.currentMissingPiecesCount,
          'resolved': e.originalMissingPiecesCount - e.currentMissingPiecesCount,
          'created': e.createdAt.millisecondsSinceEpoch,
          'def_updated': e.lastDeficiencyUpdateAt?.millisecondsSinceEpoch ?? 0,
        }, tint: _tintOf(e.status)),
    ];

    return ResearchTable(
      view: ResearchView.entries,
      columns: const [
        ResearchColumn('day', 'اليوم', width: 90),
        ResearchColumn('date', 'التاريخ', width: 125),
        ResearchColumn('room', 'الغرفة (القطع)', width: 250),
        ResearchColumn('shape', 'الشكل', width: 100),
        ResearchColumn('numbering', 'الترقيم', width: 90),
        ResearchColumn('carpenter', 'النجار', width: 110),
        ResearchColumn('service', 'الخدمة', width: 110),
        ResearchColumn('installer', 'الرصيص', width: 110),
        ResearchColumn('supervisor', 'المشرف', width: 110),
        ResearchColumn('repairer', 'الرميم', width: 110),
        ResearchColumn('merchant', 'التاجر', width: 120),
        ResearchColumn('customer', 'اسم الزبون', width: 120),
        ResearchColumn('external', 'غرفة خارجية', width: 100),
        ResearchColumn('wrap', 'مكان اللف', width: 110),
        ResearchColumn('pieces', 'عدد القطع', width: 95, numeric: true),
        ResearchColumn('standard', 'العدد القياسي', width: 110, numeric: true),
        ResearchColumn('specs', 'المواصفات', width: 170),
        ResearchColumn('order_desc', 'وصف الأوردر', width: 170),
        ResearchColumn('partial', 'اسم الجزء', width: 140),
        ResearchColumn('original_def', 'النواقص الأصلية', width: 200),
        ResearchColumn('current_def', 'النواقص الحالية', width: 200),
        ResearchColumn('problem', 'المشكلة', width: 200),
        ResearchColumn('original_missing', 'الناقص الأصلي', width: 110, numeric: true),
        ResearchColumn('missing', 'الناقص الحالي', width: 110, numeric: true),
        ResearchColumn('resolved', 'تم استكماله', width: 100, numeric: true),
        ResearchColumn('status', 'الحالة', width: 130),
        ResearchColumn('session_status', 'حالة اليومية', width: 100),
        ResearchColumn('modified', 'نواقص معدّلة', width: 100),
        ResearchColumn('created', 'وقت التسجيل', width: 200),
        ResearchColumn('def_updated', 'آخر تعديل للنواقص', width: 200),
      ],
      rows: rows,
      footer: _footer({
        'day': 'الإجمالي (${es.length})',
        'pieces': '${_sumPieces(es)}',
        'original_missing': '${_sumOriginalMissing(es)}',
        'missing': '${_sumMissing(es)}',
        'resolved': '${_resolvedPieces(es)}',
      }),
      stats: _entryStats(es),
    );
  }

  static List<ResearchStat> _entryStats(List<DailyEntry> es) {
    final done = _completed(es);
    return [
      ResearchStat('الإدخالات', '${es.length}'),
      ResearchStat('مكتملة', '$done'),
      ResearchStat('بها نواقص', '${es.length - done}'),
      ResearchStat('نسبة الاكتمال', _pct(done, es.length)),
      ResearchStat('مجموع القطع', '${_sumPieces(es)}'),
      ResearchStat('الناقص الحالي', '${_sumMissing(es)}'),
      ResearchStat('الناقص الأصلي', '${_sumOriginalMissing(es)}'),
      ResearchStat('بمشكلة', '${_withProblem(es)}'),
    ];
  }

  // ------------------------------ التجميع ---------------------------

  static String _groupKey(ResearchData d, DailyEntry e, ResearchGroup g) {
    String clean(String v) => v.trim().isEmpty ? '(غير محدد)' : v.trim();
    switch (g) {
      case ResearchGroup.room:
        return clean(d.roomNameOf(e));
      case ResearchGroup.carpenter:
        return clean(e.carpenter);
      case ResearchGroup.service:
        return clean(e.service);
      case ResearchGroup.installer:
        return clean(e.installer);
      case ResearchGroup.supervisor:
        return clean(e.supervisor);
      case ResearchGroup.repairer:
        return clean(e.repairer);
      case ResearchGroup.wrapLocation:
        return clean(e.wrapLocation);
      case ResearchGroup.merchant:
        return clean(e.merchantName);
      case ResearchGroup.dayName:
        return clean(d.dayNameOf(e));
      case ResearchGroup.date:
        return AppDateFormatter.date(d.dateOf(e));
      case ResearchGroup.month:
        return _monthOf(d.dateOf(e));
      case ResearchGroup.status:
        return e.status.label;
      case ResearchGroup.shape:
        return _shapeOf(e).label;
    }
  }

  static ResearchTable _grouped(
      ResearchData d, ResearchFilters f, ResearchGroup g) {
    final es = filterEntries(d, f);
    final groups = <String, List<DailyEntry>>{};
    for (final e in es) {
      groups.putIfAbsent(_groupKey(d, e, g), () => []).add(e);
    }
    final chronological = g == ResearchGroup.date || g == ResearchGroup.month;
    int stamp(String k) {
      final dt = _minDate(groups[k]!.map(d.dateOf));
      return dt?.millisecondsSinceEpoch ?? 0;
    }

    final keys = groups.keys.toList()
      ..sort((a, b) => chronological ? stamp(a).compareTo(stamp(b)) : a.compareTo(b));
    final totalPieces = _sumPieces(es);

    final rows = [
      for (final k in keys)
        () {
          final list = groups[k]!;
          final done = _completed(list);
          final pieces = _sumPieces(list);
          final first = _minDate(list.map(d.dateOf));
          final last = _maxDate(list.map(d.dateOf));
          final distinctRooms = list.map(d.roomNameOf).toSet().length;
          return _row({
            'group': k,
            'count': '${list.length}',
            'done': '$done',
            'pending': '${list.length - done}',
            'rate': _pct(done, list.length),
            'pieces': '$pieces',
            'share': _pct(pieces, totalPieces),
            'avg': _avg(pieces, list.length),
            'missing': '${_sumMissing(list)}',
            'original': '${_sumOriginalMissing(list)}',
            'resolved': '${_resolvedPieces(list)}',
            'problems': '${_withProblem(list)}',
            'specs': '${list.where((e) => e.hasSpecifications).length}',
            'partial': '${list.where((e) => e.isPartial).length}',
            'rooms': '$distinctRooms',
            'first': first == null ? '' : _dayDate(first),
            'last': last == null ? '' : _dayDate(last),
          }, sort: {
            if (chronological) 'group': stamp(k),
            'count': list.length,
            'done': done,
            'pending': list.length - done,
            'rate': list.isEmpty ? 0 : done / list.length,
            'pieces': pieces,
            'share': totalPieces == 0 ? 0 : pieces / totalPieces,
            'avg': list.isEmpty ? 0 : pieces / list.length,
            'missing': _sumMissing(list),
            'original': _sumOriginalMissing(list),
            'resolved': _resolvedPieces(list),
            'problems': _withProblem(list),
            'specs': list.where((e) => e.hasSpecifications).length,
            'partial': list.where((e) => e.isPartial).length,
            'rooms': distinctRooms,
            'first': first?.millisecondsSinceEpoch ?? 0,
            'last': last?.millisecondsSinceEpoch ?? 0,
          });
        }(),
    ];

    final done = _completed(es);
    return ResearchTable(
      view: ResearchView.grouped,
      columns: [
        ResearchColumn('group', g.label, width: 230),
        const ResearchColumn('count', 'عدد الإدخالات', width: 120, numeric: true),
        const ResearchColumn('done', 'مكتملة', width: 90, numeric: true),
        const ResearchColumn('pending', 'بها نواقص', width: 100, numeric: true),
        const ResearchColumn('rate', 'نسبة الاكتمال', width: 120, numeric: true),
        const ResearchColumn('pieces', 'مجموع القطع', width: 110, numeric: true),
        const ResearchColumn('share', 'نسبة من الإجمالي', width: 130, numeric: true),
        const ResearchColumn('avg', 'متوسط القطع/إدخال', width: 140, numeric: true),
        const ResearchColumn('missing', 'الناقص الحالي', width: 110, numeric: true),
        const ResearchColumn('original', 'الناقص الأصلي', width: 110, numeric: true),
        const ResearchColumn('resolved', 'تم استكماله', width: 100, numeric: true),
        const ResearchColumn('problems', 'بمشكلة', width: 90, numeric: true),
        const ResearchColumn('specs', 'مواصفات', width: 90, numeric: true),
        const ResearchColumn('partial', 'أجزاء', width: 80, numeric: true),
        const ResearchColumn('rooms', 'عدد الغرف المختلفة', width: 140, numeric: true),
        const ResearchColumn('first', 'أول ظهور', width: 125),
        const ResearchColumn('last', 'آخر ظهور', width: 125),
      ],
      rows: rows,
      footer: _footer({
        'group': 'الإجمالي (${rows.length})',
        'count': '${es.length}',
        'done': '$done',
        'pending': '${es.length - done}',
        'rate': _pct(done, es.length),
        'pieces': '$totalPieces',
        'share': totalPieces == 0 ? '' : '100%',
        'avg': _avg(totalPieces, es.length),
        'missing': '${_sumMissing(es)}',
        'original': '${_sumOriginalMissing(es)}',
        'resolved': '${_resolvedPieces(es)}',
        'problems': '${_withProblem(es)}',
        'specs': '${es.where((e) => e.hasSpecifications).length}',
        'partial': '${es.where((e) => e.isPartial).length}',
      }),
      stats: [ResearchStat('عدد المجموعات', '${rows.length}'), ..._entryStats(es)],
    );
  }

  // --------------------------- النواقص المتكررة ----------------------

  static ResearchTable _deficiencies(ResearchData d, ResearchFilters f) {
    final es = filterEntries(d, f);

    final label = <String, String>{};
    final current = <String, int>{};
    final original = <String, int>{};
    final resolved = <String, int>{};
    final rooms = <String, Set<String>>{};
    final carpenters = <String, List<String>>{};
    final firstSeen = <String, DateTime>{};
    final lastSeen = <String, DateTime>{};
    final problems = <String, Set<String>>{};

    for (final e in es) {
      final cur = _items(e.currentDeficiencies);
      final org = _items(e.originalDeficiencies);
      final dt = d.dateOf(e);
      final all = <String, String>{...org, ...cur};
      for (final en in all.entries) {
        final k = en.key;
        label.putIfAbsent(k, () => en.value);
        if (!firstSeen.containsKey(k) || dt.isBefore(firstSeen[k]!)) {
          firstSeen[k] = dt;
        }
        if (!lastSeen.containsKey(k) || dt.isAfter(lastSeen[k]!)) {
          lastSeen[k] = dt;
        }
        rooms.putIfAbsent(k, () => {}).add(d.roomNameOf(e));
        carpenters.putIfAbsent(k, () => []).add(e.carpenter);
        if (e.problem.trim().isNotEmpty && cur.containsKey(k)) {
          problems.putIfAbsent(k, () => {}).add(e.problem.trim());
        }
      }
      for (final k in cur.keys) {
        current[k] = (current[k] ?? 0) + 1;
      }
      for (final k in org.keys) {
        original[k] = (original[k] ?? 0) + 1;
        if (!cur.containsKey(k)) resolved[k] = (resolved[k] ?? 0) + 1;
      }
    }

    final keys = label.keys.toList()
      ..sort((a, b) {
        final c = (current[b] ?? 0).compareTo(current[a] ?? 0);
        if (c != 0) return c;
        final o = (original[b] ?? 0).compareTo(original[a] ?? 0);
        return o != 0 ? o : label[a]!.compareTo(label[b]!);
      });

    final rows = [
      for (final k in keys)
        _row({
          'item': label[k]!,
          'count': '${current[k] ?? 0}',
          'original': '${original[k] ?? 0}',
          'resolved': '${resolved[k] ?? 0}',
          'rate': (original[k] ?? 0) == 0
              ? ''
              : _pct(resolved[k] ?? 0, original[k]!),
          'rooms': '${rooms[k]!.length}',
          'carpenter': _top(carpenters[k] ?? const <String>[]),
          'first': _dayDate(firstSeen[k]!),
          'last': _dayDate(lastSeen[k]!),
          'problems': (problems[k] ?? const <String>{}).take(3).join(' | '),
        }, sort: {
          'count': current[k] ?? 0,
          'original': original[k] ?? 0,
          'resolved': resolved[k] ?? 0,
          'rate': (original[k] ?? 0) == 0 ? -1 : (resolved[k] ?? 0) / original[k]!,
          'rooms': rooms[k]!.length,
          'first': firstSeen[k]!.millisecondsSinceEpoch,
          'last': lastSeen[k]!.millisecondsSinceEpoch,
        }, tint: (current[k] ?? 0) > 0 ? null : _greenTint),
    ];

    final totalCur = current.values.fold<int>(0, (a, b) => a + b);
    final totalOrg = original.values.fold<int>(0, (a, b) => a + b);
    final totalRes = resolved.values.fold<int>(0, (a, b) => a + b);

    return ResearchTable(
      view: ResearchView.deficiencies,
      columns: const [
        ResearchColumn('item', 'القطعة الناقصة', width: 250),
        ResearchColumn('count', 'ناقصة حاليًا', width: 110, numeric: true),
        ResearchColumn('original', 'نقصت وقت الإنتاج', width: 140, numeric: true),
        ResearchColumn('resolved', 'تم استكمالها', width: 110, numeric: true),
        ResearchColumn('rate', 'نسبة الاستكمال', width: 120, numeric: true),
        ResearchColumn('rooms', 'عدد الغرف', width: 100, numeric: true),
        ResearchColumn('carpenter', 'النجار الأكثر ارتباطًا', width: 180),
        ResearchColumn('first', 'أول ظهور', width: 125),
        ResearchColumn('last', 'آخر ظهور', width: 125),
        ResearchColumn('problems', 'المشاكل المسجلة', width: 340),
      ],
      rows: rows,
      footer: _footer({
        'item': 'الإجمالي (${rows.length})',
        'count': '$totalCur',
        'original': '$totalOrg',
        'resolved': '$totalRes',
        'rate': totalOrg == 0 ? '' : _pct(totalRes, totalOrg),
      }),
      stats: [
        ResearchStat('أنواع النواقص', '${rows.length}'),
        ResearchStat('ما زال ناقصًا', '${current.length}'),
        ResearchStat('إدخالات بنواقص حالية',
            '${es.where((e) => e.currentDeficiencies.trim().isNotEmpty).length}'),
        ResearchStat('إجمالي القطع الناقصة', '${_sumMissing(es)}'),
        ResearchStat('نسبة الاستكمال', totalOrg == 0 ? '-' : _pct(totalRes, totalOrg)),
      ],
    );
  }

  // ------------------------------ المشاكل ---------------------------

  static ResearchTable _problems(ResearchData d, ResearchFilters f) {
    final es = filterEntries(d, f)
        .where((e) => e.problem.trim().isNotEmpty)
        .toList();
    final label = <String, String>{};
    final groups = <String, List<DailyEntry>>{};
    for (final e in es) {
      final k = normalizeArabic(e.problem);
      label.putIfAbsent(k, () => e.problem.trim());
      groups.putIfAbsent(k, () => []).add(e);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) {
        final c = groups[b]!.length.compareTo(groups[a]!.length);
        return c != 0 ? c : label[a]!.compareTo(label[b]!);
      });

    final rows = [
      for (final k in keys)
        () {
          final list = groups[k]!;
          final pending = list.length - _completed(list);
          final last = _maxDate(list.map(d.dateOf));
          final roomsList = list.map(d.roomNameOf).toSet().toList()..sort();
          return _row({
            'problem': label[k]!,
            'count': '${list.length}',
            'pending': '$pending',
            'missing': '${_sumMissing(list)}',
            'rooms': roomsList.take(4).join('، ') +
                (roomsList.length > 4 ? ' … (${roomsList.length})' : ''),
            'carpenter': _top(list.map((e) => e.carpenter)),
            'supervisor': _top(list.map((e) => e.supervisor)),
            'last': last == null ? '' : _dayDate(last),
          }, sort: {
            'count': list.length,
            'pending': pending,
            'missing': _sumMissing(list),
            'last': last?.millisecondsSinceEpoch ?? 0,
          }, tint: pending > 0 ? _redTint : _greenTint);
        }(),
    ];

    return ResearchTable(
      view: ResearchView.problems,
      columns: const [
        ResearchColumn('problem', 'المشكلة', width: 320),
        ResearchColumn('count', 'مرات التسجيل', width: 110, numeric: true),
        ResearchColumn('pending', 'ما زالت بنواقص', width: 120, numeric: true),
        ResearchColumn('missing', 'الناقص الحالي', width: 110, numeric: true),
        ResearchColumn('rooms', 'الغرف المتأثرة', width: 300),
        ResearchColumn('carpenter', 'النجار الأكثر', width: 160),
        ResearchColumn('supervisor', 'المشرف الأكثر', width: 160),
        ResearchColumn('last', 'آخر تسجيل', width: 125),
      ],
      rows: rows,
      footer: _footer({
        'problem': 'الإجمالي (${rows.length})',
        'count': '${es.length}',
        'pending': '${es.length - _completed(es)}',
        'missing': '${_sumMissing(es)}',
      }),
      stats: [
        ResearchStat('أنواع المشاكل', '${rows.length}'),
        ResearchStat('إدخالات بمشكلة', '${es.length}'),
        ResearchStat('ما زالت بنواقص', '${es.length - _completed(es)}'),
        ResearchStat('الناقص الحالي', '${_sumMissing(es)}'),
      ],
    );
  }

  // ------------------------------ الأسماء ---------------------------

  static ResearchTable _people(ResearchData d, ResearchFilters f) {
    final kw = normalizeArabic(f.keyword);
    final scoped = filterEntries(d, f, useKeyword: false);

    // الأسماء المسجلة + أسماء وردت في الإدخالات ولم تُسجَّل في الإعدادات.
    final registered = {for (final p in d.people) '${p.role.name}|${p.name.trim()}': p};
    final seen = <String, (PersonRole, String)>{};
    for (final p in d.people) {
      seen['${p.role.name}|${p.name.trim()}'] = (p.role, p.name.trim());
    }
    for (final e in scoped) {
      for (final r in PersonRole.values) {
        final n = ResearchData.fieldOf(e, r).trim();
        if (n.isEmpty) continue;
        seen.putIfAbsent('${r.name}|$n', () => (r, n));
      }
    }
    final people = seen.entries.where((en) {
      final (role, name) = en.value;
      if (f.people[role] != null && f.people[role] != name) return false;
      if (kw.isEmpty) return true;
      final hay = normalizeArabic('$name ${role.label}');
      return kw.split(' ').every(hay.contains);
    }).toList()
      ..sort((a, b) {
        final c = a.value.$1.index.compareTo(b.value.$1.index);
        return c != 0 ? c : a.value.$2.compareTo(b.value.$2);
      });

    final rows = <ResearchRow>[];
    for (final en in people) {
      final (role, name) = en.value;
      final es = scoped
          .where((e) => ResearchData.fieldOf(e, role).trim() == name)
          .toList();
      final done = _completed(es);
      final pieces = _sumPieces(es);
      final person = registered[en.key];
      final last = _maxDate(es.map(d.dateOf));
      final days = es.map((e) {
        final dt = d.dateOf(e);
        return DateTime(dt.year, dt.month, dt.day);
      }).toSet().length;
      rows.add(_row({
        'role': role.label,
        'name': name,
        'registered': person == null ? 'غير مسجل' : 'مسجل',
        'count': '${es.length}',
        'done': '$done',
        'pending': '${es.length - done}',
        'rate': es.isEmpty ? '' : _pct(done, es.length),
        'pieces': '$pieces',
        'days': '$days',
        'missing': '${_sumMissing(es)}',
        'problems': '${_withProblem(es)}',
        'last': last == null ? '' : _dayDate(last),
        'added': person == null ? '' : AppDateFormatter.date(person.createdAt),
      }, sort: {
        'count': es.length,
        'done': done,
        'pending': es.length - done,
        'rate': es.isEmpty ? -1 : done / es.length,
        'pieces': pieces,
        'days': days,
        'missing': _sumMissing(es),
        'problems': _withProblem(es),
        'last': last?.millisecondsSinceEpoch ?? 0,
        'added': person?.createdAt.millisecondsSinceEpoch ?? 0,
      }, tint: person == null ? _amberTint : null));
    }

    return ResearchTable(
      view: ResearchView.people,
      columns: const [
        ResearchColumn('role', 'الدور', width: 110),
        ResearchColumn('name', 'الاسم', width: 220),
        ResearchColumn('registered', 'في الإعدادات', width: 110),
        ResearchColumn('count', 'عدد الإدخالات', width: 120, numeric: true),
        ResearchColumn('done', 'مكتملة', width: 90, numeric: true),
        ResearchColumn('pending', 'بها نواقص', width: 100, numeric: true),
        ResearchColumn('rate', 'نسبة الاكتمال', width: 120, numeric: true),
        ResearchColumn('pieces', 'مجموع القطع', width: 110, numeric: true),
        ResearchColumn('days', 'أيام العمل', width: 100, numeric: true),
        ResearchColumn('missing', 'الناقص الحالي', width: 110, numeric: true),
        ResearchColumn('problems', 'بمشكلة', width: 90, numeric: true),
        ResearchColumn('last', 'آخر نشاط', width: 125),
        ResearchColumn('added', 'تاريخ الإضافة', width: 125),
      ],
      rows: rows,
      stats: [
        ResearchStat('عدد الأسماء', '${rows.length}'),
        ResearchStat('غير مسجلة في الإعدادات',
            '${rows.where((r) => r.value('registered') == 'غير مسجل').length}'),
        ResearchStat('بلا أي إنتاج',
            '${rows.where((r) => r.value('count') == '0').length}'),
      ],
    );
  }

  // ---------------------------- تدقيق البيانات -----------------------

  static ResearchTable _audit(ResearchData d, ResearchFilters f) {
    final issues = _auditIssues(d, f);
    final kw = normalizeArabic(f.keyword);
    final shown = issues.where((i) {
      if (kw.isEmpty) return true;
      final hay = normalizeArabic('${i.type} ${i.room} ${i.who} ${i.details}');
      return kw.split(' ').every(hay.contains);
    }).toList()
      ..sort((a, b) {
        final c = a.severity.compareTo(b.severity);
        if (c != 0) return c;
        final t = a.type.compareTo(b.type);
        if (t != 0) return t;
        return (b.date ?? DateTime(2000)).compareTo(a.date ?? DateTime(2000));
      });

    String sevLabel(int s) => s == 1 ? 'عالية' : (s == 2 ? 'متوسطة' : 'منخفضة');
    final rows = [
      for (final i in shown)
        _row({
          'sev': sevLabel(i.severity),
          'type': i.type,
          'date': i.date == null ? '' : _dayDate(i.date!),
          'room': i.room,
          'who': i.who,
          'details': i.details,
        }, sort: {
          'sev': i.severity,
          'date': i.date?.millisecondsSinceEpoch ?? 0,
        }, tint: i.severity == 1 ? _redTint : (i.severity == 2 ? _amberTint : null),
            id: i.key),
    ];

    final byType = <String, int>{};
    for (final i in shown) {
      byType[i.type] = (byType[i.type] ?? 0) + 1;
    }

    return ResearchTable(
      view: ResearchView.audit,
      columns: const [
        ResearchColumn('sev', 'الأهمية', width: 90),
        ResearchColumn('type', 'نوع الملاحظة', width: 230),
        ResearchColumn('date', 'التاريخ', width: 125),
        ResearchColumn('room', 'الغرفة / العنصر', width: 230),
        ResearchColumn('who', 'الاسم / اليومية', width: 160),
        ResearchColumn('details', 'التفاصيل', width: 460),
      ],
      rows: rows,
      stats: [
        ResearchStat('إجمالي الملاحظات', '${shown.length}'),
        ResearchStat('عالية', '${shown.where((i) => i.severity == 1).length}'),
        ResearchStat('متوسطة', '${shown.where((i) => i.severity == 2).length}'),
        ResearchStat('منخفضة', '${shown.where((i) => i.severity == 3).length}'),
        ResearchStat('أنواع الملاحظات', '${byType.length}'),
      ],
    );
  }

  static List<_Issue> _auditIssues(ResearchData d, ResearchFilters f) {
    final out = <_Issue>[];
    final es = filterEntries(d, f);
    final today = DateTime.now();
    final today0 = DateTime(today.year, today.month, today.day);

    final registered = <PersonRole, Set<String>>{
      for (final r in PersonRole.values)
        r: {for (final p in d.people) if (p.role == r) p.name.trim()},
    };

    final fullKeys = <String, int>{};
    final numKeys = <String, int>{};

    for (final e in es) {
      final date = d.dateOf(e);
      final room = e.displayName;
      final who = d.dayNameOf(e);
      void add(int sev, String type, String details) => out.add(_Issue(
          severity: sev,
          type: type,
          date: date,
          room: room,
          who: who,
          details: details));

      final session = d.sessionOf(e);
      if (session == null) {
        add(1, 'يومية غير موجودة', 'الإدخال مرتبط بيومية محذوفة أو غير موجودة.');
      }
      final baseRoom = d.roomOf(e);
      if (e.isExternal) {
        if (e.merchantName.trim().isEmpty) {
          add(2, 'غرفة خارجية بلا تاجر', 'لم يُسجَّل اسم التاجر.');
        }
      } else if (baseRoom == null) {
        add(2, 'الغرفة الأساسية محذوفة',
            'الغرفة غير موجودة في قاعدة الغرف؛ تبقى النسخة المحفوظة فقط.');
      } else if (normalizeArabic(baseRoom.name) !=
          normalizeArabic(e.baseRoomName)) {
        add(3, 'اسم الغرفة لا يطابق الغرفة المرتبطة',
            'الاسم المسجّل «${e.baseRoomName}» بينما الغرفة المرتبطة في قاعدة الغرف «${baseRoom.name}».');
      } else if (!e.hasSpecifications &&
          !e.isPartial &&
          baseRoom.totalPieceCount != e.pieceCountSnapshot) {
        add(3, 'العدد القياسي تغيّر',
            'وقت الإنتاج: ${e.pieceCountSnapshot} — الحالي في تبويب الغرف (الكلي): ${baseRoom.totalPieceCount}.');
      }
      if (e.effectivePieceCount <= 0) {
        add(1, 'عدد القطع صفر', 'عدد القطع الفعلي للإدخال ${e.effectivePieceCount}.');
      }
      if (calculateMissingPiecesCount(e.currentDeficiencies) !=
          e.currentMissingPiecesCount) {
        add(1, 'عدد الناقص الحالي لا يطابق النص',
            'المخزّن ${e.currentMissingPiecesCount} والمحسوب من النص ${calculateMissingPiecesCount(e.currentDeficiencies)}.');
      }
      if (calculateMissingPiecesCount(e.originalDeficiencies) !=
          e.originalMissingPiecesCount) {
        add(1, 'عدد الناقص الأصلي لا يطابق النص',
            'المخزّن ${e.originalMissingPiecesCount} والمحسوب من النص ${calculateMissingPiecesCount(e.originalDeficiencies)}.');
      }
      if (e.currentMissingPiecesCount > e.originalMissingPiecesCount) {
        add(2, 'النواقص زادت عن الأصلية',
            'الأصلي ${e.originalMissingPiecesCount} ← الحالي ${e.currentMissingPiecesCount}.');
      }
      if (e.currentMissingPiecesCount > e.effectivePieceCount &&
          e.effectivePieceCount > 0) {
        add(2, 'الناقص أكبر من عدد القطع',
            'الناقص ${e.currentMissingPiecesCount} من ${e.effectivePieceCount} قطعة.');
      }
      if (e.status == RoomEntryStatus.completed && e.problem.trim().isNotEmpty) {
        add(2, 'مشكلة مسجلة على غرفة مكتملة', 'المشكلة: ${e.problem.trim()}');
      }
      if (e.status == RoomEntryStatus.pending && e.problem.trim().isEmpty) {
        add(3, 'نواقص بلا مشكلة مسجلة',
            'الناقص ${e.currentMissingPiecesCount} قطعة دون توضيح السبب.');
      }
      if (e.hasSpecifications && e.specificationsText.trim().isEmpty) {
        add(2, 'مواصفات بلا نص', 'وسم «مواصفات» مفعّل دون كتابة المواصفات.');
      }
      if (e.hasSpecifications && e.specialPieceCount <= 0) {
        add(2, 'مواصفات بلا عدد قطع', 'عدد قطع غرفة المواصفات ${e.specialPieceCount}.');
      }
      if (e.isPartial && e.partName.trim().isEmpty) {
        add(2, 'جزء بلا اسم', 'إدخال «جزء من غرفة» دون اسم للجزء.');
      }
      if (e.isPartial && e.partialPieceCount <= 0) {
        add(2, 'جزء بلا عدد قطع', 'عدد قطع الجزء ${e.partialPieceCount}.');
      }
      if (e.isPartial &&
          e.pieceCountSnapshot > 0 &&
          e.partialPieceCount > e.pieceCountSnapshot) {
        add(2, 'الجزء أكبر من الغرفة',
            'قطع الجزء ${e.partialPieceCount} أكبر من العدد القياسي ${e.pieceCountSnapshot}.');
      }

      final blanks = <String>[];
      final unknown = <String>[];
      for (final r in PersonRole.values) {
        // الغرفة الخارجية لا تُسجَّل لها أسماء النجار والخدمة وغيرهم.
        if (e.isExternal && r != PersonRole.wrapLocation) continue;
        final n = ResearchData.fieldOf(e, r).trim();
        if (n.isEmpty) {
          blanks.add(r.label);
        } else if (!registered[r]!.contains(n)) {
          unknown.add('${r.label}: $n');
        }
      }
      if (blanks.isNotEmpty) {
        add(3, 'بيانات ناقصة', 'حقول فارغة: ${blanks.join('، ')}.');
      }
      if (unknown.isNotEmpty) {
        add(3, 'اسم غير مسجل في الإعدادات', unknown.join(' — '));
      }

      final shape = _shapeOf(e).name;
      final fullKey =
          '${e.dailySessionId}|${normalizeArabic(e.roomNameSnapshot)}|${e.numbering.trim()}|$shape';
      fullKeys[fullKey] = (fullKeys[fullKey] ?? 0) + 1;
      if ((fullKeys[fullKey] ?? 0) > 1) {
        add(2, 'إدخال مكرر محتمل',
            'نفس الغرفة والترقيم والشكل مسجّلة أكثر من مرة في اليومية.');
      } else if (e.numbering.trim().isNotEmpty) {
        final nk = '${e.dailySessionId}|${e.numbering.trim()}';
        numKeys[nk] = (numKeys[nk] ?? 0) + 1;
        if ((numKeys[nk] ?? 0) > 1) {
          add(3, 'ترقيم مكرر في اليومية',
              'الترقيم «${e.numbering.trim()}» مستخدم لأكثر من غرفة.');
        }
      }
    }

    // اليوميات
    final perSession = <String, int>{};
    for (final e in d.entries) {
      perSession[e.dailySessionId] = (perSession[e.dailySessionId] ?? 0) + 1;
    }
    final byDate = <String, int>{};
    for (final s in d.sessions) {
      final key = AppDateFormatter.date(s.date);
      byDate[key] = (byDate[key] ?? 0) + 1;
    }
    for (final s in d.sessions) {
      if (!_inDateRange(s.date, f)) continue;
      if (f.dayName != null && s.dayName.trim() != f.dayName) continue;
      final label = '${s.dayName} ${AppDateFormatter.date(s.date)}';
      void add(int sev, String type, String details) => out.add(_Issue(
          severity: sev,
          type: type,
          date: s.date,
          room: 'يومية',
          who: label,
          details: details));
      final day0 = DateTime(s.date.year, s.date.month, s.date.day);
      if (s.isActive && day0.isBefore(today0)) {
        add(2, 'يومية نشطة لم تُغلق', 'اليومية ما زالت نشطة رغم مرور تاريخها.');
      }
      if (!s.isActive && s.endTime == null) {
        add(2, 'يومية مغلقة بلا وقت انتهاء', 'الحالة مغلقة لكن وقت الانتهاء فارغ.');
      }
      if (s.endTime != null && s.endTime!.isBefore(s.startTime)) {
        add(1, 'وقت الانتهاء قبل البدء',
            'البدء ${AppDateFormatter.time(s.startTime)} والانتهاء ${AppDateFormatter.time(s.endTime!)}.');
      }
      if ((perSession[s.id] ?? 0) == 0) {
        add(3, 'يومية بلا إدخالات', 'لم تُسجَّل أي غرفة في هذه اليومية.');
      }
      final expected = AppDateFormatter.dayName(s.date);
      if (expected.isNotEmpty && expected != s.dayName.trim()) {
        add(2, 'اسم اليوم لا يطابق التاريخ',
            'المسجّل «${s.dayName}» والتاريخ يوافق «$expected».');
      }
      if ((byDate[AppDateFormatter.date(s.date)] ?? 0) > 1) {
        add(2, 'أكثر من يومية في نفس التاريخ',
            'يوجد ${byDate[AppDateFormatter.date(s.date)]} يوميات بتاريخ ${AppDateFormatter.date(s.date)}.');
      }
    }

    // الغرف والأسماء (لا تتأثر بفلاتر التاريخ)
    final roomNames = <String, int>{};
    for (final r in d.rooms) {
      final k = normalizeArabic(r.name);
      roomNames[k] = (roomNames[k] ?? 0) + 1;
    }
    for (final r in d.rooms) {
      if (f.room != null && r.name.trim() != f.room) continue;
      void add(int sev, String type, String details) => out.add(_Issue(
          severity: sev,
          type: type,
          date: null,
          room: r.name,
          who: 'قاعدة الغرف',
          details: details));
      if ((roomNames[normalizeArabic(r.name)] ?? 0) > 1) {
        add(2, 'اسم غرفة مكرر', 'الاسم مسجّل أكثر من مرة في قاعدة الغرف.');
      }
      if (r.totalPieceCount <= 0) {
        add(2, 'غرفة بلا قطع', 'إجمالي قطع الغرفة صفر.');
      }
    }
    final peopleKeys = <String, int>{};
    for (final p in d.people) {
      final k = '${p.role.name}|${normalizeArabic(p.name)}';
      peopleKeys[k] = (peopleKeys[k] ?? 0) + 1;
    }
    for (final p in d.people) {
      if ((peopleKeys['${p.role.name}|${normalizeArabic(p.name)}'] ?? 0) > 1) {
        out.add(_Issue(
            severity: 3,
            type: 'اسم مكرر في الإعدادات',
            date: null,
            room: p.name,
            who: p.role.label,
            details: 'الاسم مسجّل أكثر من مرة ضمن نفس الدور.'));
      }
    }
    return out.where((i) => !d.ignoredIssues.contains(i.key)).toList();
  }
}

class _Issue {
  /// 1 = عالية، 2 = متوسطة، 3 = منخفضة.
  final int severity;
  final String type;
  final DateTime? date;
  final String room;
  final String who;
  final String details;

  /// مفتاح ثابت للملاحظة (يعتمد على نوعها وعناصرها ونصها).
  String get key =>
      '$type|$room|$who|$details|${date?.toIso8601String().substring(0, 10) ?? ''}';

  const _Issue({
    required this.severity,
    required this.type,
    required this.date,
    required this.room,
    required this.who,
    required this.details,
  });
}
