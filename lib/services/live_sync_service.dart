import 'dart:async';

import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import 'backup_service.dart';
import 'github_sync_service.dart';

/// المزامنة اللحظية: عند تفعيلها يُرفع كل تغيير محلي تلقائيًا (بعد ثوانٍ
/// قليلة من آخر تعديل)، وتُفحص النسخة السحابية دوريًا فتُنزَّل أي تغييرات
/// جاءت من جهاز آخر. عند انقطاع الإنترنت تبقى التغييرات معلّقة وتُرسل
/// تلقائيًا فور عودة الاتصال. عند تعدد الأجهزة تسري قاعدة "آخر تعديل يفوز".
class LiveSyncService extends ChangeNotifier {
  LiveSyncService._();
  static final LiveSyncService instance = LiveSyncService._();

  static const _pollEvery = Duration(seconds: 20);
  static const _debounce = Duration(seconds: 3);

  final _sync = GithubSyncService();
  final _backup = BackupService();

  Timer? _poll;
  Timer? _debounceTimer;
  bool _enabled = false;
  bool _busy = false;
  bool _dirty = false;
  bool _applying = false;
  bool _listening = false;

  /// يُعيد تحميل شاشات التطبيق بعد تطبيق بيانات سحابية جديدة.
  Future<void> Function()? onRemoteApplied;

  /// آخر خطأ (null = المزامنة سليمة).
  String? lastError;

  bool get enabled => _enabled;
  bool get busy => _busy;

  Future<void> init() async {
    if (!_listening) {
      _listening = true;
      AppDatabase.instance.addChangeListener(_onLocalChange);
    }
    _dirty = await _sync.loadDirty();
    _enabled = await _sync.loadLive();
    if (_enabled) _startTimer(firstDelay: const Duration(seconds: 5));
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await _sync.saveLive(value);
    lastError = null;
    if (value) {
      _startTimer(firstDelay: Duration.zero);
    } else {
      _poll?.cancel();
      _debounceTimer?.cancel();
    }
    notifyListeners();
  }

  void _startTimer({required Duration firstDelay}) {
    _poll?.cancel();
    Timer(firstDelay, _tick);
    _poll = Timer.periodic(_pollEvery, (_) => _tick());
  }

  void _onLocalChange() {
    if (!_enabled || _applying) return;
    _dirty = true;
    unawaited(_sync.saveDirty(true));
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, _tick);
  }

  Future<void> _tick() async {
    if (!_enabled || _busy) return;
    _busy = true;
    notifyListeners();
    try {
      final cfg = await _sync.loadConfig();
      if (!cfg.isComplete) {
        lastError = 'أكمل بيانات الاتصال أولًا.';
        return;
      }
      if (_dirty) {
        _dirty = false;
        try {
          await _sync.upload(cfg, await _backup.buildJson());
          await _sync.saveDirty(false);
        } catch (_) {
          _dirty = true; // نعيد المحاولة في الدورة التالية
          rethrow;
        }
      } else {
        final remote = await _sync.fetchRemoteSha(cfg);
        final known = await _sync.loadLastSha();
        if (remote != null && remote != known && onRemoteApplied != null) {
          final text = await _sync.download(cfg);
          if (text != null) {
            final preview = _backup.parse(text);
            _applying = true;
            try {
              await _backup.restore(preview);
            } finally {
              _applying = false;
            }
            await _sync.saveLastSha(remote);
            await _sync.markSynced();
            await onRemoteApplied!.call();
          }
        }
      }
      lastError = null;
    } on SyncException catch (e) {
      lastError = e.message;
    } on FormatException catch (e) {
      lastError = e.message;
    } catch (e) {
      lastError = 'تعذرت المزامنة: $e';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
