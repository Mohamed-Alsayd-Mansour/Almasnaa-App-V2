import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/supa.dart';

enum SyncState { connecting, online, offline }

/// المزامنة اللحظية بين الأجهزة: تلقائية دائمًا ولا توجد لها أزرار.
/// الخادم هو المصدر؛ أي تغيير على الجداول (من أي جهاز) يُشغّل إعادة تحميل
/// هادئة للبيانات المعروضة. الحالة وآخر مزامنة وآخر خطأ تُعرض كمؤشر فقط.
class RealtimeHub extends ChangeNotifier {
  RealtimeHub._();
  static final RealtimeHub instance = RealtimeHub._();

  static const _tables = [
    'daily_entries',
    'daily_sessions',
    'rooms',
    'people',
    'rassas_supervisor_links',
    'app_settings',
    'notifications',
    'chat_messages',
    'chat_members',
    'chat_conversations',
  ];

  SyncState state = SyncState.connecting;
  DateTime? lastSyncAt;
  String? lastError;

  RealtimeChannel? _channel;
  Timer? _debounce;
  Timer? _heartbeat;
  Future<void> Function()? _onChange;
  bool _wasOffline = false;

  /// يبدأ الاشتراك بعد تسجيل الدخول. [onChange] يعيد تحميل مزودات البيانات.
  void start(Future<void> Function() onChange) {
    stop();
    _onChange = onChange;
    state = SyncState.connecting;
    notifyListeners();

    var ch = supa.channel('almasnaa-sync');
    for (final t in _tables) {
      ch = ch.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: t,
        callback: (_) => _scheduleRefresh(),
      );
    }
    ch.subscribe((status, [error]) {
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          final recovering = _wasOffline;
          _wasOffline = false;
          state = SyncState.online;
          lastError = null;
          notifyListeners();
          if (recovering) _scheduleRefresh(); // عودة الاتصال: نزامن ما فات
        case RealtimeSubscribeStatus.channelError:
        case RealtimeSubscribeStatus.timedOut:
          _wasOffline = true;
          state = SyncState.offline;
          lastError = 'تعذّر الاتصال بالمزامنة اللحظية. تتم إعادة المحاولة تلقائيًا.';
          notifyListeners();
        case RealtimeSubscribeStatus.closed:
          _wasOffline = true;
          state = SyncState.offline;
          notifyListeners();
      }
    });
    _channel = ch;

    // شبكة أمان: تحديث دوري هادئ إن فات حدث (مثلًا بعد نوم الجهاز).
    _heartbeat = Timer.periodic(const Duration(minutes: 2), (_) => _scheduleRefresh());
  }

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final cb = _onChange;
      if (cb == null) return;
      try {
        await cb();
        lastSyncAt = DateTime.now();
        lastError = null;
        if (state == SyncState.offline) state = SyncState.online;
      } catch (e) {
        lastError = friendlyError(e);
        state = SyncState.offline;
        _wasOffline = true;
      }
      notifyListeners();
    });
  }

  /// يُسجَّل عند نجاح أي تحميل/كتابة مؤكدة من الخادم.
  void markSynced() {
    lastSyncAt = DateTime.now();
    notifyListeners();
  }

  Future<void> stop() async {
    _debounce?.cancel();
    _heartbeat?.cancel();
    _onChange = null;
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      try {
        await supa.removeChannel(ch);
      } catch (_) {}
    }
  }
}
