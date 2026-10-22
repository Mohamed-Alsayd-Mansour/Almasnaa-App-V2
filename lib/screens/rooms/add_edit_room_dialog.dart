import 'package:flutter/material.dart';
import '../../utils/platform_utils.dart';
import 'package:provider/provider.dart';

import '../../models/room.dart';
import '../../providers/rooms_provider.dart';
import '../../widgets/common_widgets.dart';

/// يفتح نافذة Form احترافية لإضافة غرفة جديدة أو تعديل غرفة موجودة.
/// يعيد true إذا تمت العملية بنجاح.
Future<bool?> showAddEditRoomDialog(BuildContext context, {Room? room}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => AddEditRoomDialog(room: room),
  );
}

class AddEditRoomDialog extends StatefulWidget {
  final Room? room;
  const AddEditRoomDialog({super.key, this.room});

  @override
  State<AddEditRoomDialog> createState() => _AddEditRoomDialogState();
}

class _AddEditRoomDialogState extends State<AddEditRoomDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _pieceCtrl;
  late final TextEditingController _glassCtrl;
  late final TextEditingController _partitionCtrl;
  late final TextEditingController _partitionCountCtrl;
  late final TextEditingController _marbleCtrl;
  bool _saving = false;

  bool get isEditing => widget.room != null;

  int _n(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  /// عدد القطع الكلي = الخشب + القواطيع + الزجاج + الرخام.
  int get _liveTotal =>
      _n(_pieceCtrl) + _n(_partitionCtrl) + _n(_glassCtrl) + _n(_marbleCtrl);

  /// عدد ورق الطباعة = الخشب + القواطيع.
  int get _livePaper => _n(_pieceCtrl) + _n(_partitionCtrl);

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.room?.name ?? '');
    _pieceCtrl =
        TextEditingController(text: widget.room?.pieceCount.toString() ?? '');
    _glassCtrl = TextEditingController(
        text: widget.room?.glassPieceCount.toString() ?? '');
    _partitionCtrl = TextEditingController(
        text: widget.room?.partitionPieceCount.toString() ?? '0');
    _partitionCountCtrl = TextEditingController(
        text: widget.room?.partitionCount.toString() ?? '0');
    _marbleCtrl = TextEditingController(
        text: widget.room?.marblePieceCount.toString() ?? '0');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pieceCtrl.dispose();
    _glassCtrl.dispose();
    _partitionCtrl.dispose();
    _partitionCountCtrl.dispose();
    _marbleCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final provider = context.read<RoomsProvider>();
    final name = _nameCtrl.text.trim();
    final pieces = int.parse(_pieceCtrl.text.trim());
    final glass = int.parse(_glassCtrl.text.trim());
    final partitions = int.parse(_partitionCtrl.text.trim());
    final partitionCount = int.parse(_partitionCountCtrl.text.trim());
    final marble = int.parse(_marbleCtrl.text.trim());

    final error = isEditing
        ? await provider.updateRoom(
            original: widget.room!,
            name: name,
            pieceCount: pieces,
            glassPieceCount: glass,
            partitionPieceCount: partitions,
            partitionCount: partitionCount,
            marblePieceCount: marble,
          )
        : await provider.addRoom(
            name: name,
            pieceCount: pieces,
            glassPieceCount: glass,
            partitionPieceCount: partitions,
            partitionCount: partitionCount,
            marblePieceCount: marble,
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
    return AlertDialog(
      title: Text(isEditing ? 'تعديل غرفة' : 'إضافة غرفة'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'اسم الغرفة *'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'اسم الغرفة مطلوب' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _pieceCtrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'قطع الخشب *'),
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  if (n == null) return 'يرجى إدخال رقم صحيح';
                  if (n <= 0) return 'يجب أن يكون أكبر من صفر';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _glassCtrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration:
                    const InputDecoration(labelText: 'قطع الزجاج *'),
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  if (n == null) return 'يرجى إدخال رقم صحيح';
                  if (n < 0) return 'لا يمكن أن يكون سالبًا';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _partitionCtrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration:
                    const InputDecoration(labelText: 'قطع القواطيع *'),
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  if (n == null) return 'يرجى إدخال رقم صحيح';
                  if (n < 0) return 'لا يمكن أن يكون سالبًا';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              // رقم يُكتب فقط ولا يدخل في أي مجموع.
              TextFormField(
                controller: _partitionCountCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'عدد قواطيع الغرفة *',
                  helperText:
                      isMobileApp ? null : 'للعرض فقط — لا يؤثر على أي مجموع',
                ),
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  if (n == null) return 'يرجى إدخال رقم صحيح';
                  if (n < 0) return 'لا يمكن أن يكون سالبًا';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _marbleCtrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'قطع الرخام *'),
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  if (n == null) return 'يرجى إدخال رقم صحيح';
                  if (n < 0) return 'لا يمكن أن يكون سالبًا';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              if (isMobileApp)
                // على الهاتف: كل مجموع في سطر مستقل وفي المنتصف.
                Column(
                  children: [
                    const SizedBox(height: 6),
                    Text(
                      'عدد القطع الكلي: $_liveTotal',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'عدد ورق الطباعة: $_livePaper',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                  ],
                )
              else
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'عدد القطع الكلي: $_liveTotal    |    عدد ورق الطباعة: $_livePaper',
                    style: const TextStyle(fontWeight: FontWeight.w800),
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
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('حفظ'),
        ),
      ],
    );
  }
}
