import 'package:flutter/material.dart';

import '../../utils/platform_utils.dart';
import '../../models/daily_entry.dart';
import '../../models/person.dart';
import '../../utils/deficiency_calculator.dart';
import '../../widgets/person_dropdown.dart';

/// نافذة التعديل الشامل على سجل واحد (بعد إدخال كلمة المرور). تُعدَّل كل
/// الحقول، وتُعاد النسخة المعدَّلة أو null عند الإلغاء.
Future<DailyEntry?> showFullEditDialog(BuildContext context, DailyEntry entry) {
  return showDialog<DailyEntry>(
    context: context,
    builder: (_) => _FullEditDialog(entry: entry),
  );
}

class _FullEditDialog extends StatefulWidget {
  final DailyEntry entry;
  const _FullEditDialog({required this.entry});

  @override
  State<_FullEditDialog> createState() => _FullEditDialogState();
}

class _FullEditDialogState extends State<_FullEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final DailyEntry e = widget.entry;

  late final _roomCtrl = TextEditingController(text: e.baseRoomName);
  late final _pieceCtrl =
      TextEditingController(text: e.pieceCountSnapshot.toString());
  late final _numberingCtrl = TextEditingController(text: e.numbering);
  late final _merchantCtrl = TextEditingController(text: e.merchantName);
  late final _customerCtrl = TextEditingController(text: e.customerName);
  late final _specTextCtrl = TextEditingController(text: e.specificationsText);
  late final _specCountCtrl =
      TextEditingController(text: e.specialPieceCount.toString());
  late final _partNameCtrl = TextEditingController(text: e.partName);
  late final _partCountCtrl =
      TextEditingController(text: e.partialPieceCount.toString());
  late final _originalCtrl =
      TextEditingController(text: e.originalDeficiencies);
  late final _currentCtrl = TextEditingController(text: e.currentDeficiencies);
  late final _problemCtrl = TextEditingController(text: e.problem);

  late String? _carpenter = _nullIfEmpty(e.carpenter);
  late String? _service = _nullIfEmpty(e.service);
  late String? _installer = _nullIfEmpty(e.installer);
  late String? _supervisor = _nullIfEmpty(e.supervisor);
  late String? _repairer = _nullIfEmpty(e.repairer);
  late String? _wrapLocation = _nullIfEmpty(e.wrapLocation);
  late bool _hasSpecs = e.hasSpecifications;
  late bool _isPartial = e.isPartial;

  static String? _nullIfEmpty(String v) => v.trim().isEmpty ? null : v;

  @override
  void dispose() {
    for (final c in [
      _roomCtrl,
      _pieceCtrl,
      _numberingCtrl,
      _merchantCtrl,
      _customerCtrl,
      _specTextCtrl,
      _specCountCtrl,
      _partNameCtrl,
      _partCountCtrl,
      _originalCtrl,
      _currentCtrl,
      _problemCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _requiredInt(String? v, {int min = 0}) {
    final n = int.tryParse((v ?? '').trim());
    if (n == null || n < min) return 'أدخل عددًا صحيحًا ($min فأكثر)';
    return null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final base = _roomCtrl.text.trim();
    final partial = _isPartial && !e.isOrder;
    final specs = _hasSpecs && !e.isOrder;
    final partName = _partNameCtrl.text.trim();
    final currentText = _currentCtrl.text.trim();
    final deficiencyChanged = currentText != e.currentDeficiencies.trim();

    final updated = e.copyWith(
      roomNameSnapshot: partial ? '$partName $base' : base,
      pieceCountSnapshot: int.parse(_pieceCtrl.text.trim()),
      merchantName: _merchantCtrl.text.trim(),
      customerName: _customerCtrl.text.trim(),
      numbering: _numberingCtrl.text.trim(),
      carpenter: _carpenter ?? '',
      service: _service ?? '',
      installer: _installer ?? '',
      supervisor: _supervisor ?? '',
      repairer: _repairer ?? '',
      wrapLocation: _wrapLocation ?? '',
      hasSpecifications: specs,
      specificationsText: _specTextCtrl.text.trim(),
      specialPieceCount: int.tryParse(_specCountCtrl.text.trim()) ?? 0,
      isPartial: partial,
      partName: partial ? partName : '',
      partialPieceCount:
          partial ? (int.tryParse(_partCountCtrl.text.trim()) ?? 0) : 0,
      originalDeficiencies: _originalCtrl.text,
      currentDeficiencies: _currentCtrl.text,
      problem: _problemCtrl.text.trim(),
      markDeficiencyUpdated: deficiencyChanged,
    );
    Navigator.of(context).pop(updated);
  }

  Widget _gap() => const SizedBox(height: 14);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // مسافة كافية بين العنوان وأول حقل ليظهر عنوان الحقل كاملًا.
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      title: isMobileApp
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text('تعديل شامل', textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  e.displayName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ],
            )
          : Text('تعديل شامل: ${e.displayName}'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _roomCtrl,
                  maxLines: e.isOrder ? 3 : 1,
                  minLines: 1,
                  decoration: InputDecoration(
                      labelText: e.isOrder
                          ? 'وصف الأوردر *'
                          : 'اسم الغرفة (بدون الجزء) *'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? (e.isOrder ? 'وصف الأوردر مطلوب' : 'اسم الغرفة مطلوب')
                      : null,
                ),
                _gap(),
                TextFormField(
                  controller: _pieceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: e.isOrder
                          ? 'عدد القطع *'
                          : 'العدد القياسي للقطع *'),
                  validator: (v) => _requiredInt(v),
                ),
                _gap(),
                TextFormField(
                  controller: _numberingCtrl,
                  decoration: const InputDecoration(labelText: 'الترقيم'),
                ),
                _gap(),
                ...[
                  TextFormField(
                    controller: _customerCtrl,
                    decoration: const InputDecoration(labelText: 'اسم الزبون'),
                    validator: (v) => (e.isOrder &&
                            (v ?? '').trim().isEmpty &&
                            _merchantCtrl.text.trim().isEmpty)
                        ? 'أدخل اسم الزبون أو اسم التاجر'
                        : null,
                  ),
                  _gap(),
                ],
                // اسم التاجر: إلزامي للخارجية، واختياري لباقي الأنواع.
                TextFormField(
                  controller: _merchantCtrl,
                  decoration: InputDecoration(
                      labelText: e.isExternal ? 'اسم التاجر *' : 'اسم التاجر'),
                  validator: (v) =>
                      (e.isExternal && (v == null || v.trim().isEmpty))
                          ? 'اسم التاجر مطلوب'
                          : null,
                ),
                _gap(),
                PersonDropdownField(
                  role: PersonRole.carpenter,
                  value: _carpenter,
                  onChanged: (v) => setState(() => _carpenter = v),
                ),
                _gap(),
                PersonDropdownField(
                  role: PersonRole.service,
                  value: _service,
                  onChanged: (v) => setState(() => _service = v),
                ),
                _gap(),
                PersonDropdownField(
                  role: PersonRole.repairer,
                  value: _repairer,
                  onChanged: (v) => setState(() => _repairer = v),
                ),
                _gap(),
                PersonDropdownField(
                  role: PersonRole.wrapLocation,
                  value: _wrapLocation,
                  onChanged: (v) => setState(() => _wrapLocation = v),
                ),
                const Divider(height: 28),
                if (!e.isOrder) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('جزء من غرفة',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  value: _isPartial,
                  onChanged: (v) => setState(() => _isPartial = v),
                ),
                if (_isPartial) ...[
                  TextFormField(
                    controller: _partNameCtrl,
                    decoration: const InputDecoration(
                        labelText: 'اسم الجزء أو الأجزاء *'),
                    validator: (v) => (_isPartial && (v ?? '').trim().isEmpty)
                        ? 'اسم الجزء مطلوب'
                        : null,
                  ),
                  _gap(),
                  TextFormField(
                    controller: _partCountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'عدد القطع الموجودة *'),
                    validator: (v) => _isPartial ? _requiredInt(v, min: 1) : null,
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('وسم "مواصفات"',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  value: _hasSpecs,
                  onChanged: (v) => setState(() => _hasSpecs = v),
                ),
                if (_hasSpecs) ...[
                  TextFormField(
                    controller: _specTextCtrl,
                    maxLines: 3,
                    minLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'المواصفات والتعديلات الشكلية',
                      alignLabelWithHint: true,
                    ),
                  ),
                  _gap(),
                  TextFormField(
                    controller: _specCountCtrl,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'عدد قطع المواصفات'),
                    validator: (v) => _hasSpecs ? _requiredInt(v) : null,
                  ),
                ],
                ],
                const Divider(height: 28),
                TextFormField(
                  controller: _originalCtrl,
                  maxLines: 4,
                  minLines: 2,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'النواقص الأصلية (وقت الإنتاج)',
                    helperText:
                        'العدد المحسوب: ${calculateMissingPiecesCount(_originalCtrl.text)}',
                    alignLabelWithHint: true,
                  ),
                ),
                _gap(),
                TextFormField(
                  controller: _currentCtrl,
                  maxLines: 4,
                  minLines: 2,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'النواقص الحالية',
                    helperText:
                        'العدد المحسوب: ${calculateMissingPiecesCount(_currentCtrl.text)}',
                    alignLabelWithHint: true,
                  ),
                ),
                _gap(),
                TextFormField(
                  controller: _problemCtrl,
                  maxLines: 3,
                  minLines: 1,
                  decoration: const InputDecoration(
                    labelText: 'المشكلة',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(onPressed: _submit, child: const Text('حفظ التعديلات')),
      ],
    );
  }
}
