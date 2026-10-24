import 'package:flutter/foundation.dart';

import '../data/supa.dart';

/// إشعار واحد: صف من notifications مع حدث التدقيق المرتبط به.
class AppNotification {
  AppNotification({
    required this.id,
    required this.createdAt,
    required this.readAt,
    required this.op,
    required this.entity,
    required this.actorName,
    required this.actorRole,
    required this.changes,
    this.kind = 'audit',
    this.entityId,
    this.messageId,
    this.conversationId,
    this.summary,
    this.viewAsName,
    this.archivedAt,
    this.deletedAt,
  });

  final DateTime? archivedAt;
  final DateTime? deletedAt;

  /// مكان الإشعار: الوارد / الأرشيف / سلة المحذوفات.
  bool get inTrash => deletedAt != null;
  bool get inArchive => deletedAt == null && archivedAt != null;
  bool get inInbox => deletedAt == null && archivedAt == null;

  /// 'audit' (تغيير في البيانات) أو 'mention' (إشارة في محادثة).
  final String kind;
  final String? entityId;
  final String? messageId;
  final String? conversationId;
  final String? summary;
  final String? viewAsName;

  bool get isMention => kind == 'mention';

  final int id;
  final DateTime createdAt;
  final DateTime? readAt;
  final String op;
  final String entity;
  final String actorName;
  final String? actorRole;
  final Map<String, dynamic>? changes;

  bool get isRead => readAt != null;

  factory AppNotification.fromRow(Map<String, dynamic> r) {
    final a = Map<String, dynamic>.from((r['audit'] as Map?) ?? const {});
    return AppNotification(
      id: r['id'] as int,
      createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
      readAt: r['read_at'] == null ? null : DateTime.parse(r['read_at'] as String).toLocal(),
      op: a['op'] as String? ?? '',
      entity: a['entity'] as String? ?? '',
      actorName: (r['actor_name'] as String?) ?? a['actor_name'] as String? ?? '',
      actorRole: a['actor_role'] as String?,
      changes: a['changes'] is Map ? Map<String, dynamic>.from(a['changes'] as Map) : null,
      kind: r['kind'] as String? ?? 'audit',
      entityId: a['entity_id'] as String?,
      messageId: r['message_id'] as String?,
      conversationId: r['conversation_id'] as String?,
      summary: r['summary'] as String?,
      viewAsName: a['view_as_name'] as String?,
      archivedAt: r['archived_at'] == null ? null : DateTime.parse(r['archived_at'] as String).toLocal(),
      deletedAt: r['deleted_at'] == null ? null : DateTime.parse(r['deleted_at'] as String).toLocal(),
    );
  }

  static const _entities = {
    'daily_entries': 'غرفة في يومية',
    'daily_sessions': 'يومية',
    'rooms': 'غرفة في الكتالوج',
    'people': 'اسم في القوائم',
    'rassas_supervisor_links': 'ربط الرصيص بالمشرف',
    'profiles': 'حساب مستخدم',
    'app_settings': 'إعدادات',
    'backup': 'نسخة احتياطية',
    'operational_data': 'جميع البيانات',
  };
  static const _ops = {
    'INSERT': 'إضافة',
    'UPDATE': 'تعديل',
    'DELETE': 'حذف',
    'IMPORT': 'استيراد',
    'DELETE_ALL': 'حذف جماعي',
    'DELETE_NAMES': 'حذف الأسماء فقط',
  };
  static const _roles = {'admin': 'الأدمن', 'rassas': 'الرصيص', 'supervisor': 'المشرف'};

  static const _fields = {
    'problem': 'المشكلة',
    'current_deficiencies': 'النواقص الحالية',
    'specifications_text': 'المواصفات',
    'status': 'الحالة',
    'room_name_snapshot': 'اسم الغرفة',
    'carpenter': 'النجار',
    'service': 'الخدمة',
    'repairer': 'الرميم',
    'wrap_location': 'مكان اللف',
    'numbering': 'الترقيم',
    'supervisor_id': 'المشرف',
    'name': 'الاسم',
  };

  String get title {
    if (isMention) return '${actorName.isEmpty ? 'مستخدم' : actorName} أشار إليك في محادثة';
    final who = actorName.isEmpty ? 'النظام' : actorName;
    final role = _roles[actorRole];
    return '$who${role == null ? '' : ' ($role)'}: ${_ops[op] ?? op} — ${_entities[entity] ?? entity}';
  }

  /// تفاصيل مختصرة آمنة: اسم الغرفة إن وُجد، والحقول المتغيرة (بأسمائها فقط).
  String get detail {
    if (isMention) return summary == null ? 'لا تملك صلاحية عرض هذه المحادثة' : summary!;
    final extra = viewAsName == null ? '' : '\nنُفِّذ أثناء عرضه التطبيق كـ $viewAsName';
    return _detailCore() + extra;
  }

  /// هل للإشعار هدف يمكن الانتقال إليه؟
  bool get canOpen => isMention ? conversationId != null : (entity == 'daily_entries' && entityId != null && op != 'DELETE');

  String _detailCore() {
    final c = changes;
    if (c == null) return '';
    if (op == 'UPDATE') {
      final names = c.keys.map((k) => _fields[k] ?? k).where((k) => k != 'updated_at').toList();
      return names.isEmpty ? '' : 'الحقول: ${names.join('، ')}';
    }
    final room = c['room_name_snapshot'] ?? c['name'];
    return room is String ? room : '';
  }
}

/// أقسام مركز الإشعارات.
enum NotifView { inbox, archive, trash }

/// مركز الإشعارات: بيانات خادم دائمة، تتحدث لحظيًا مع المزامنة.
/// الأرشفة والحذف (إلى السلة) والاستعادة والحذف النهائي كلها تُكتب في Supabase على صفوف المستلم نفسه
/// (RLS)، فتظهر على كل أجهزته. الحذف النهائي مسموح من الخادم فقط لما هو داخل السلة.
class NotificationsProvider extends ChangeNotifier {
  List<AppNotification> items = [];
  String? errorMessage;

  List<AppNotification> inView(NotifView v) => items
      .where((n) => switch (v) {
            NotifView.inbox => n.inInbox,
            NotifView.archive => n.inArchive,
            NotifView.trash => n.inTrash,
          })
      .toList();

  /// عدّاد الجرس: غير المقروء في الوارد فقط.
  int get unread => items.where((n) => n.inInbox && !n.isRead).length;

  void reset() {
    items = [];
    errorMessage = null;
    notifyListeners();
  }

  Future<void> load() async {
    try {
      final rows = await supa
          .from('notifications')
          .select('id, created_at, read_at, archived_at, deleted_at, kind, message_id, conversation_id, actor_name, summary, '
              'audit:audit_log(op, entity, entity_id, actor_name, actor_role, changes, view_as_name)')
          .order('id', ascending: false)
          .limit(300);
      items = rows.map((r) => AppNotification.fromRow(Map<String, dynamic>.from(r))).toList();
      errorMessage = null;
    } catch (e) {
      errorMessage = friendlyError(e);
    }
    notifyListeners();
  }

  static String _now() => DateTime.now().toUtc().toIso8601String();

  Future<void> _run(Future<void> Function() op) async {
    try {
      await op();
      errorMessage = null;
    } catch (e) {
      errorMessage = friendlyError(e);
    }
    await load();
  }

  Future<void> markRead(AppNotification n) async {
    if (n.isRead) return;
    await _run(() async {
      await supa.from('notifications').update({'read_at': _now()}).eq('id', n.id);
    });
  }

  Future<void> markAllRead() => _run(() async {
        await supa
            .from('notifications')
            .update({'read_at': _now()})
            .isFilter('read_at', null)
            .isFilter('archived_at', null)
            .isFilter('deleted_at', null);
      });

  Future<void> _patch(List<AppNotification> list, Map<String, Object?> values) async {
    if (list.isEmpty) return;
    await _run(() async {
      await supa.from('notifications').update(values).inFilter('id', list.map((n) => n.id).toList());
    });
  }

  /// أرشفة (قابلة للتراجع).
  Future<void> archive(List<AppNotification> list) => _patch(list, {'archived_at': _now()});

  Future<void> unarchive(List<AppNotification> list) => _patch(list, {'archived_at': null});

  /// «حذف» = نقل إلى سلة المحذوفات (لا حذف نهائي).
  Future<void> moveToTrash(List<AppNotification> list) => _patch(list, {'deleted_at': _now()});

  /// استعادة من السلة: يعود الإشعار إلى مكانه السابق (الوارد أو الأرشيف).
  Future<void> restore(List<AppNotification> list) => _patch(list, {'deleted_at': null});

  /// حذف نهائي: لا رجعة فيه، والخادم لا يسمح به إلا لإشعارات السلة.
  Future<void> deleteForever(List<AppNotification> list) async {
    final trashed = list.where((n) => n.inTrash).toList();
    if (trashed.isEmpty) return;
    await _run(() async {
      await supa.from('notifications').delete().inFilter('id', trashed.map((n) => n.id).toList());
    });
  }
}
