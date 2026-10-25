import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../models/person.dart';
import '../../models/room.dart';
import '../../providers/daily_provider.dart';
import '../../providers/rooms_provider.dart';
import '../../utils/deficiency_calculator.dart';
import '../../utils/platform_utils.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/person_dropdown.dart';
import '../../widgets/read_only_name_field.dart';

/// نافذة Form احترافية لإضافة غرفة إلى اليومية النشطة. تعرض عدد القطع
/// تلقائيًا فور اختيار الغرفة من القائمة (قاعدة العمل #3)، وتحسب عدد
/// القطع الناقصة تلقائيًا من نص النواقص (قاعدة العمل #6، #7).
Future<bool?> showAddEntryDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const AddEntryDialog(),
  );
}

class AddEntryDialog extends StatefulWidget {
  const AddEntryDialog({super.key});

  @override
  State<AddEntryDialog> createState() => _AddEntryDialogState();
}

class _AddEntryDialogState extends State<AddEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  Room? _selectedRoom;

  /// الغرفة المختارة من تبويب "الغرف" عند الملكية "خارجية".
  Room? _externalRoom;

  /// هل الغرفة خارجية؟ (اسمها وعدد قطعها واسم التاجر تُدخل يدويًا).
  bool _isExternal = false;

  /// أوردر (طلب مخصوص): وصفه وعدد قطعه واسم الزبون تُدخل يدويًا، وله
  /// نفس حقول الفريق (النجار والخدمة...) مثل الغرفة الداخلية.
  bool _isOrder = false;

  /// غرفة تُدخل بياناتها يدويًا (خارجية أو أوردر) بدل اختيارها من الغرف.
  bool get _manual => _isExternal || _isOrder;

  /// حقل "عدد القطع" اليدوي: للأوردر وللخارجية الكاملة فقط. الخارجية
  /// "جزء منها" يُؤخذ عددها من "عدد القطع الموجودة".
  bool get _showManualCount => _isOrder || (_isExternal && _isComplete);
  final _extNameCtrl = TextEditingController();
  final _extCountCtrl = TextEditingController();
  final _merchantCtrl = TextEditingController();
  final _customerCtrl = TextEditingController();

  final _numberingCtrl = TextEditingController();
  String? _carpenter;
  String? _service;
  String? _repairer;
  String? _wrapLocation;
  final _deficienciesCtrl = TextEditingController();
  final _problemCtrl = TextEditingController();

  /// هل الغرفة كاملة؟ عند "لا" تُسجَّل أجزاء منها يدويًا.
  bool _isComplete = true;
  final _partNameCtrl = TextEditingController();
  final _partCountCtrl = TextEditingController();

  bool _hasSpecifications = false;
  final _specificationsCtrl = TextEditingController();
  final _specialPieceCountCtrl = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _extNameCtrl.dispose();
    _extCountCtrl.dispose();
    _merchantCtrl.dispose();
    _customerCtrl.dispose();
    _numberingCtrl.dispose();
    _deficienciesCtrl.dispose();
    _problemCtrl.dispose();
    _partNameCtrl.dispose();
    _partCountCtrl.dispose();
    _specificationsCtrl.dispose();
    _specialPieceCountCtrl.dispose();
    super.dispose();
  }

  int get _liveMissingCount =>
      calculateMissingPiecesCount(_deficienciesCtrl.text);

  void _onToggleSpecifications(bool value) {
    setState(() {
      _hasSpecifications = value;
      // عند التفعيل نملأ العدد تلقائيًا بالعدد القياسي الحالي للغرفة
      // كنقطة بداية مناسبة فقط؛ القيمة بعدها مستقلة تمامًا وقابلة
      // للتعديل بحرية دون أي تأثير على عدد القطع القياسي للغرفة.
      if (value && _specialPieceCountCtrl.text.trim().isEmpty) {
        _specialPieceCountCtrl.text = (_manual
                ? (int.tryParse(_extCountCtrl.text.trim()) ?? 0)
                : (_selectedRoom?.totalPieceCount ?? 0))
            .toString();
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_manual && _selectedRoom == null) {
      showErrorSnackBar(context, 'يرجى اختيار اسم الغرفة أولًا.');
      return;
    }
    setState(() => _saving = true);

    final error = await context.read<DailyProvider>().addEntry(
          room: _manual ? null : _selectedRoom,
          isOrder: _isOrder,
          externalRoomName: _extNameCtrl.text,
          externalPieceCount: _showManualCount
              ? (int.tryParse(_extCountCtrl.text.trim()) ?? 0)
              : (int.tryParse(_partCountCtrl.text.trim()) ?? 0),
          merchantName: _merchantCtrl.text,
          customerName: _customerCtrl.text,
          numbering: _numberingCtrl.text,
          carpenter: _isExternal ? '' : (_carpenter ?? ''),
          service: _isExternal ? '' : (_service ?? ''),
          repairer: _isExternal ? '' : (_repairer ?? ''),
          deficiencies: _deficienciesCtrl.text,
          wrapLocation: _wrapLocation ?? '',
          hasSpecifications: _hasSpecifications && !_isOrder,
          specificationsText: _specificationsCtrl.text,
          specialPieceCount: _hasSpecifications && !_isOrder
              ? (int.tryParse(_specialPieceCountCtrl.text.trim()) ?? 0)
              : 0,
          problem: _problemCtrl.text,
          isPartial: !_isComplete && !_isOrder,
          partName: _partNameCtrl.text,
          partialPieceCount: !_isComplete && !_isOrder
              ? (int.tryParse(_partCountCtrl.text.trim()) ?? 0)
              : 0,
        );

    if (!mounted) return;
    setState(() => _saving = false);

    if (error != null) {
      showErrorSnackBar(context, error);
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final rooms = context.watch<RoomsProvider>().rooms;

    return AlertDialog(
      title: isMobileApp
          ? const FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text('إضافة غرفة لليومية', maxLines: 1, softWrap: false),
            )
          : const Text('إضافة غرفة إلى اليومية'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ملكية الغرفة',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                SegmentedButton<RoomOwnership>(
                  segments: [
                    for (final o in RoomOwnership.values)
                      ButtonSegment(value: o, label: Text(o.label)),
                  ],
                  selected: {
                    _isOrder
                        ? RoomOwnership.order
                        : (_isExternal
                            ? RoomOwnership.external
                            : RoomOwnership.internal)
                  },
                  onSelectionChanged: (v) => setState(() {
                    _isExternal = v.first == RoomOwnership.external;
                    _isOrder = v.first == RoomOwnership.order;
                    // تفريغ الحقول اليدوية/المختارة عند تغيير الملكية.
                    _externalRoom = null;
                    _extNameCtrl.clear();
                    _extCountCtrl.clear();
                  }),
                ),
                const SizedBox(height: 14),
                if (_isExternal)
                  DropdownButtonFormField<Room>(
                    key: ValueKey(_externalRoom),
                    initialValue: _externalRoom,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'اسم الغرفة *'),
                    items: rooms
                        .map((r) => DropdownMenuItem(
                              value: r,
                              child: Text(r.name),
                            ))
                        .toList(),
                    onChanged: (r) => setState(() {
                      _externalRoom = r;
                      _extNameCtrl.text = r?.name ?? '';
                      // عدد القطع تلقائي من تبويب الغرف.
                      _extCountCtrl.text =
                          r == null ? '' : '${r.totalPieceCount}';
                    }),
                    validator: (v) =>
                        (_isExternal && v == null) ? 'اختر اسم الغرفة' : null,
                  )
                else if (_manual)
                  TextFormField(
                    controller: _extNameCtrl,
                    maxLines: _isOrder ? 3 : 1,
                    minLines: 1,
                    decoration: InputDecoration(
                        labelText: _isOrder ? 'وصف الأوردر *' : 'اسم الغرفة *'),
                    validator: (v) => (_manual && (v ?? '').trim().isEmpty)
                        ? (_isOrder ? 'وصف الأوردر مطلوب' : 'اسم الغرفة مطلوب')
                        : null,
                  )
                else
                DropdownButtonFormField<Room>(
                  key: ValueKey(_selectedRoom),
                  initialValue: _selectedRoom,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'اسم الغرفة *'),
                  items: rooms
                      .map((r) => DropdownMenuItem(
                            value: r,
                            child: Text(r.name),
                          ))
                      .toList(),
                  onChanged: (r) => setState(() => _selectedRoom = r),
                  validator: (v) =>
                      (!_manual && v == null) ? 'اختر اسم الغرفة' : null,
                ),
                if (!_manual) ...[
                  const SizedBox(height: 14),
                  _ReadonlyPieceCount(room: _selectedRoom),
                ],
                if (!_isOrder) ...[
                const SizedBox(height: 14),
                const Text('هل الغرفة كاملة؟',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('كاملة')),
                    ButtonSegment(value: false, label: Text('جزء منها')),
                  ],
                  selected: {_isComplete},
                  onSelectionChanged: (v) =>
                      setState(() => _isComplete = v.first),
                ),
                if (!_isComplete) ...[
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _partNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم الجزء أو الأجزاء *',
                      hintText: 'مثال: 2سرير وكمود',
                    ),
                    validator: (v) {
                      if (_isComplete) return null;
                      return (v == null || v.trim().isEmpty)
                          ? 'اكتب اسم الجزء أو الأجزاء'
                          : null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _partCountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'عدد القطع الموجودة *',
                    ),
                    validator: (v) {
                      if (_isComplete) return null;
                      final n = int.tryParse((v ?? '').trim());
                      if (n == null || n <= 0) {
                        return 'أدخل عددًا صحيحًا أكبر من صفر';
                      }
                      return null;
                    },
                  ),
                ],
                ],
                const SizedBox(height: 14),
                TextFormField(
                  controller: _numberingCtrl,
                  decoration: const InputDecoration(labelText: 'ترقيمها *'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'الترقيم مطلوب' : null,
                ),
                const SizedBox(height: 14),
                if (_showManualCount) ...[
                  TextFormField(
                    controller: _extCountCtrl,
                    keyboardType: TextInputType.number,
                    // الغرفة الخارجية: العدد تلقائي من تبويب الغرف (للقراءة فقط).
                    readOnly: _isExternal,
                    decoration: InputDecoration(
                      labelText: _isExternal
                          ? (isMobileApp
                              ? 'عدد القطع (تلقائي)'
                              : 'عدد القطع (تلقائي من بيانات الغرفة)')
                          : 'عدد القطع *',
                    ),
                    validator: (v) {
                      if (!_showManualCount) return null;
                      final n = int.tryParse((v ?? '').trim());
                      if (n == null || n <= 0) {
                        return 'أدخل عددًا صحيحًا أكبر من صفر';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                ],
                // اسم الزبون: إلزامي-بديل للأوردر (زبون أو تاجر)، واختياري للداخلية والخارجية.
                ...[
                  TextFormField(
                    controller: _customerCtrl,
                    decoration: InputDecoration(
                      labelText: 'اسم الزبون',
                      helperText: (_isOrder && !isMobileApp)
                          ? 'الأوردر يحمل اسم زبون أو اسم تاجر أو كليهما'
                          : null,
                    ),
                    validator: (v) => (_isOrder &&
                            (v ?? '').trim().isEmpty &&
                            _merchantCtrl.text.trim().isEmpty)
                        ? 'أدخل اسم الزبون أو اسم التاجر'
                        : null,
                  ),
                  const SizedBox(height: 14),
                ],
                // اسم التاجر: إلزامي للخارجية، واختياري لباقي الأنواع.
                TextFormField(
                  controller: _merchantCtrl,
                  decoration: InputDecoration(
                      labelText: _isExternal ? 'اسم التاجر *' : 'اسم التاجر'),
                  validator: (v) => (_isExternal && (v ?? '').trim().isEmpty)
                      ? 'اسم التاجر مطلوب'
                      : null,
                ),
                const SizedBox(height: 14),
                if (!_isExternal) ...[
                // الرصيص والمشرف: من حسابَي اليومية الحالية، للعرض فقط (يفرضهما الخادم).
                Builder(builder: (context) {
                  final s = context.watch<DailyProvider>().activeSession;
                  return Column(children: [
                    ReadOnlyNameField(label: PersonRole.installer.fieldLabel, value: s?.rassasName ?? ''),
                    const SizedBox(height: 14),
                    ReadOnlyNameField(label: PersonRole.supervisor.fieldLabel, value: s?.supervisorName ?? ''),
                    const SizedBox(height: 14),
                  ]);
                }),
                PersonDropdownField(
                  role: PersonRole.carpenter,
                  required: true,
                  value: _carpenter,
                  onChanged: (v) => setState(() => _carpenter = v),
                ),
                const SizedBox(height: 14),
                PersonDropdownField(
                  role: PersonRole.service,
                  value: _service,
                  onChanged: (v) => setState(() => _service = v),
                ),
                const SizedBox(height: 14),
                PersonDropdownField(
                  role: PersonRole.repairer,
                  value: _repairer,
                  onChanged: (v) => setState(() => _repairer = v),
                ),
                const SizedBox(height: 14),
                ],
                PersonDropdownField(
                  role: PersonRole.wrapLocation,
                  value: _wrapLocation,
                  onChanged: (v) => setState(() => _wrapLocation = v),
                ),
                const SizedBox(height: 14),
                if (!_isOrder) ...[
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('وسم "مواصفات"',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: isMobileApp
                      ? null
                      : const Text(
                          'غرفة بمواصفات وتعديلات شكلية خاصة، وعدد قطع مستقل تمامًا عن العدد القياسي للغرفة.'),
                  value: _hasSpecifications,
                  onChanged: _onToggleSpecifications,
                ),
                if (_hasSpecifications) ...[
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _specificationsCtrl,
                    maxLines: 4,
                    minLines: 2,
                    decoration: InputDecoration(
                      labelText: isMobileApp
                          ? 'المواصفات والتعديلات'
                          : 'المواصفات والتعديلات الشكلية',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _specialPieceCountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'عدد قطع غرفة المواصفات *',
                      helperText: isMobileApp
                          ? 'هذا العدد مستقل تماما'
                          : 'مستقل تمامًا عن عدد القطع القياسي للغرفة العادية.',
                    ),
                    validator: (v) {
                      if (!_hasSpecifications) return null;
                      final n = int.tryParse((v ?? '').trim());
                      if (n == null || n < 0) {
                        return 'أدخل عددًا صحيحًا غير سالب';
                      }
                      return null;
                    },
                  ),
                ],
                ],
                const SizedBox(height: 14),
                const Divider(),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _deficienciesCtrl,
                  maxLines: 5,
                  minLines: 3,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'نواقص الغرفة',
                    hintText: 'مثال: باب - رف علوي - ضلفة يمين',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.calculate_outlined, size: 18),
                    const SizedBox(width: 6),
                    // على الهاتف يصغَّر الخط تلقائيًا ليظهر النص كاملًا في سطر واحد.
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                            'عدد القطع الناقصة (محسوب تلقائيًا): $_liveMissingCount',
                            maxLines: 1,
                            softWrap: false,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _problemCtrl,
                  maxLines: 3,
                  minLines: 1,
                  decoration: const InputDecoration(
                    labelText: 'المشكلة',
                    hintText: 'سبب القطع الناقصة',
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
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('حفظ'),
        ),
      ],
    );
  }
}

class _ReadonlyPieceCount extends StatelessWidget {
  final Room? room;
  const _ReadonlyPieceCount({required this.room});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      readOnly: true,
      initialValue: room == null ? '' : '${room!.totalPieceCount}',
      key: ValueKey(room?.id),
      decoration: InputDecoration(
        labelText:
            isMobileApp ? 'عدد القطع الكلي (تلقائي)' : 'عدد القطع الكلي (تلقائي من بيانات الغرفة)',
        // ارتفاع أكبر قليلًا ليظهر حرف الياء كاملًا على الهاتف.
        contentPadding: isMobileApp
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 22)
            : null,
      ),
    );
  }
}
