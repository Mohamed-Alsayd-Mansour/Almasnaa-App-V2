import 'package:flutter/material.dart';

import '../../services/archive_api.dart';
import '../../utils/date_formatter.dart';

/// تبويب «الأرشفة على GitHub» (الأدمن فقط). لا يوجد حقل لرمز GitHub عمدًا:
/// الرمز سر من أسرار الـ Edge Function على الخادم (انظر docs/PHASE4_SETUP.md).
class ArchiveTab extends StatefulWidget {
  const ArchiveTab({super.key});

  @override
  State<ArchiveTab> createState() => _ArchiveTabState();
}

class _ArchiveTabState extends State<ArchiveTab> {
  final _repo = TextEditingController();
  final _branch = TextEditingController();
  final _path = TextEditingController();
  bool _enabled = false;
  bool _loading = true;
  bool _busy = false;
  String? _msg;
  bool _ok = false;
  List<ArchiveRun> _runs = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _repo.dispose();
    _branch.dispose();
    _path.dispose();
    super.dispose();
  }

  ArchiveConfig get _form => ArchiveConfig(
        enabled: _enabled,
        repo: _repo.text.trim(),
        branch: _branch.text.trim().isEmpty ? 'main' : _branch.text.trim(),
        path: _path.text.trim(),
      );

  Future<void> _load() async {
    try {
      final c = await ArchiveApi.instance.loadConfig();
      final runs = await ArchiveApi.instance.recentRuns();
      if (!mounted) return;
      setState(() {
        _repo.text = c.repo;
        _branch.text = c.branch;
        _path.text = c.path;
        _enabled = c.enabled;
        _runs = runs;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _ok = false;
          _msg = 'تعذر تحميل إعدادات الأرشفة.';
        });
      }
    }
  }

  void _say(String m, {bool ok = false}) => setState(() {
        _msg = m;
        _ok = ok;
      });

  String? _validate(ArchiveConfig c) {
    if (!RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(c.repo)) return 'اكتب المستودع بصيغة owner/repo';
    if (!RegExp(r'^[A-Za-z0-9._/-]+$').hasMatch(c.branch) || c.branch.contains('..')) return 'اسم الفرع غير صالح';
    if (!RegExp(r'^[A-Za-z0-9._/-]+\.json$').hasMatch(c.path) || c.path.contains('..') || c.path.startsWith('/')) {
      return 'مسار الملف غير صالح (يجب أن ينتهي بـ .json ولا يبدأ بـ /)';
    }
    return null;
  }

  /// يختبر الاتصال أولًا؛ لا يُعتمد الإعداد إلا إذا نجح الاختبار.
  Future<void> _save() async {
    if (_busy) return;
    final c = _form;
    final bad = _validate(c);
    if (bad != null) return _say(bad);
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final exists = await ArchiveApi.instance.test(c);
      await ArchiveApi.instance.saveConfig(c);
      _say(exists ? 'نجح الاتصال وتم حفظ الإعداد (الملف موجود وسيُحدَّث).' : 'نجح الاتصال وتم حفظ الإعداد (سيُنشأ الملف عند أول أرشفة).', ok: true);
    } on ArchiveException catch (e) {
      _say('لم يُحفظ الإعداد: ${e.message}');
    } catch (_) {
      _say('تعذّر الاتصال بالخادم');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runNow() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final r = await ArchiveApi.instance.runNow();
      _say(r, ok: true);
    } on ArchiveException catch (e) {
      _say(e.message);
    } catch (_) {
      _say('تعذّر الاتصال بالخادم');
    } finally {
      final runs = await ArchiveApi.instance.recentRuns().catchError((_) => _runs);
      if (mounted) setState(() {
            _runs = runs;
            _busy = false;
          });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(16), children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('الأرشفة التلقائية على GitHub', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 6),
                  const Text(
                    'تتم الأرشفة على الخادم فقط. رمز GitHub لا يظهر هنا ولا يُخزَّن في قاعدة البيانات أو الجهاز؛ '
                    'يُضبط كسر من أسرار الخادم (راجع docs/PHASE4_SETUP.md).',
                    style: TextStyle(fontSize: 12.5),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('تفعيل الأرشفة اليومية المجدولة'),
                    value: _enabled,
                    onChanged: _busy ? null : (v) => setState(() => _enabled = v),
                  ),
                  TextField(controller: _repo, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'المستودع (owner/repo)')),
                  const SizedBox(height: 10),
                  TextField(controller: _branch, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'الفرع')),
                  const SizedBox(height: 10),
                  TextField(controller: _path, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'مسار الملف (.json)')),
                  if (_msg != null) ...[
                    const SizedBox(height: 10),
                    Text(_msg!, style: TextStyle(color: _ok ? Colors.green.shade700 : Colors.red.shade700, fontWeight: FontWeight.w700)),
                  ],
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: ElevatedButton(onPressed: _busy ? null : _save, child: const Text('اختبار وحفظ'))),
                    const SizedBox(width: 8),
                    Expanded(child: OutlinedButton(onPressed: _busy ? null : _runNow, child: const Text('أرشفة الآن'))),
                  ]),
                  if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            const Text('آخر العمليات', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            if (_runs.isEmpty)
              const Padding(padding: EdgeInsets.all(8), child: Text('لا توجد عمليات أرشفة بعد.'))
            else
              for (final r in _runs)
                Card(
                  child: ListTile(
                    dense: true,
                    leading: Icon(
                      switch (r.status) {
                        'ok' => Icons.check_circle_outline,
                        'error' => Icons.error_outline,
                        'running' => Icons.sync,
                        _ => Icons.remove_circle_outline,
                      },
                      color: switch (r.status) {
                        'ok' => Colors.green.shade700,
                        'error' => Colors.red.shade700,
                        _ => Colors.grey.shade700,
                      },
                    ),
                    title: Text('${r.statusLabel} • ${r.trigger == 'manual' ? 'يدوية' : 'مجدولة'}'),
                    subtitle: Text([
                      AppDateFormatter.dateTime(r.startedAt),
                      if (r.error != null) r.error!,
                    ].join('\n')),
                  ),
                ),
          ]),
        ),
      ),
    ]);
  }
}
