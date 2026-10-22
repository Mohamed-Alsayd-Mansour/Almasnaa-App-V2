import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../models/person.dart';
import '../../providers/people_provider.dart';
import '../../repositories/daily_entry_repository.dart';
import '../../utils/date_formatter.dart';
import '../../utils/platform_utils.dart';

/// يفتح ورقة سفلية (Bottom Sheet) لضبط فلاتر البحث المتقدم في السجل،
/// ويعيد الفلاتر الجديدة عند الضغط على "تطبيق"، أو null عند الإلغاء.
Future<RecordSearchFilters?> showAdvancedFiltersSheet(
  BuildContext context,
  RecordSearchFilters current,
) {
  return showModalBottomSheet<RecordSearchFilters>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _AdvancedFiltersSheet(current: current),
  );
}

class _AdvancedFiltersSheet extends StatefulWidget {
  final RecordSearchFilters current;
  const _AdvancedFiltersSheet({required this.current});

  @override
  State<_AdvancedFiltersSheet> createState() => _AdvancedFiltersSheetState();
}

class _AdvancedFiltersSheetState extends State<_AdvancedFiltersSheet> {
  DateTime? _from;
  DateTime? _to;
  late final TextEditingController _roomCtrl;
  late final TextEditingController _carpenterCtrl;
  late final TextEditingController _installerCtrl;
  late final TextEditingController _supervisorCtrl;
  String? _wrapLocation;
  RoomEntryStatus? _status;
  RoomShape? _shape;
  RoomOwnership? _ownership;

  @override
  void initState() {
    super.initState();
    _from = widget.current.dateFrom;
    _to = widget.current.dateTo;
    _roomCtrl = TextEditingController(text: widget.current.roomName ?? '');
    _carpenterCtrl = TextEditingController(text: widget.current.carpenter ?? '');
    _installerCtrl = TextEditingController(text: widget.current.installer ?? '');
    _supervisorCtrl = TextEditingController(text: widget.current.supervisor ?? '');
    final wl = widget.current.wrapLocation;
    _wrapLocation = (wl == null || wl.isEmpty) ? null : wl;
    _status = widget.current.status;
    _shape = widget.current.shape;
    _ownership = widget.current.ownership;
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _from : _to) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('بحث متقدم',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(isFrom: true),
                    icon: const Icon(Icons.date_range),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _from == null
                            ? 'من تاريخ'
                            : AppDateFormatter.date(_from!),
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(isFrom: false),
                    icon: const Icon(Icons.date_range),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _to == null ? 'إلى تاريخ' : AppDateFormatter.date(_to!),
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _roomCtrl,
              decoration: const InputDecoration(labelText: 'اسم الغرفة'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _carpenterCtrl,
              decoration: const InputDecoration(labelText: 'النجار'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _installerCtrl,
              decoration: const InputDecoration(labelText: 'الرصيص'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _supervisorCtrl,
              decoration: const InputDecoration(labelText: 'المشرف'),
            ),
            const SizedBox(height: 14),
            Builder(builder: (context) {
              final names = [
                ...context.watch<PeopleProvider>().namesFor(PersonRole.wrapLocation)
              ];
              if (_wrapLocation != null && !names.contains(_wrapLocation)) {
                names.add(_wrapLocation!);
              }
              return DropdownButtonFormField<String>(
                value: _wrapLocation,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'مكان اللف'),
                items: [
                  const DropdownMenuItem<String>(
                      value: null, child: Text('الكل')),
                  for (final n in names)
                    DropdownMenuItem<String>(value: n, child: Text(n)),
                ],
                onChanged: (v) => setState(() => _wrapLocation = v),
              );
            }),
            const SizedBox(height: 14),
            const Align(
              alignment: Alignment.centerRight,
              child: Text('حالة الغرفة', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('الكل'),
                  selected: _status == null,
                  onSelected: (_) => setState(() => _status = null),
                ),
                ChoiceChip(
                  label: const Text('مكتملة'),
                  selected: _status == RoomEntryStatus.completed,
                  onSelected: (_) =>
                      setState(() => _status = RoomEntryStatus.completed),
                ),
                ChoiceChip(
                  label: const Text('بها نواقص'),
                  selected: _status == RoomEntryStatus.pending,
                  onSelected: (_) =>
                      setState(() => _status = RoomEntryStatus.pending),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Align(
              alignment: Alignment.centerRight,
              child: Text('شكل الغرفة', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('الكل'),
                  selected: _shape == null,
                  onSelected: (_) => setState(() => _shape = null),
                ),
                ChoiceChip(
                  label: Text(RoomShape.specs.label),
                  selected: _shape == RoomShape.specs,
                  onSelected: (_) => setState(() => _shape = RoomShape.specs),
                ),
                ChoiceChip(
                  label: Text(RoomShape.regular.label),
                  selected: _shape == RoomShape.regular,
                  onSelected: (_) => setState(() => _shape = RoomShape.regular),
                ),
                ChoiceChip(
                  label: Text(isMobileApp ? 'جزء' : RoomShape.partial.label),
                  selected: _shape == RoomShape.partial,
                  onSelected: (_) => setState(() => _shape = RoomShape.partial),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Align(
              alignment: Alignment.centerRight,
              child: Text('ملكية الغرفة', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('الكل'),
                  selected: _ownership == null,
                  onSelected: (_) => setState(() => _ownership = null),
                ),
                for (final o in RoomOwnership.values)
                  ChoiceChip(
                    label: Text(o.label),
                    selected: _ownership == o,
                    onSelected: (_) => setState(() => _ownership = o),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).pop(const RecordSearchFilters());
                    },
                    child: const Text('مسح الفلاتر'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop(RecordSearchFilters(
                        keyword: widget.current.keyword,
                        dateFrom: _from,
                        dateTo: _to,
                        roomName: _roomCtrl.text.trim(),
                        carpenter: _carpenterCtrl.text.trim(),
                        installer: _installerCtrl.text.trim(),
                        supervisor: _supervisorCtrl.text.trim(),
                        wrapLocation: _wrapLocation ?? '',
                        status: _status,
                        shape: _shape,
                        ownership: _ownership,
                      ));
                    },
                    child: const Text('تطبيق'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
